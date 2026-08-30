# Phase 2b — targeted re-review: domain + store + service + config (after the Phase 1b repair)

Reviewer: adversarial contract reviewer (OOSC2 / DbC / SCOOP). Read-only; nothing compiled.
Cluster: `src/domain/*.e`, `src/store/*.e`, `src/service/*.e` (address_parser.e / addressed_request.e belong to the participants reviewer and were skipped), `src/config/server_config.e`, `testing/store_assault.e`, `testing/chat_assault.e`.
Inputs: phase2-claude-response.md, phase2-part-domain-store.md, phase2-part-service-bus.md, approach.md §8, phase2-chain.txt (D1 SCOOP, D3 sandbox, D4 marker authenticates, D5 oracle twins).

Facts verified in the installed libraries (cited where a verdict leans on them):
- `READABLE_STRING_GENERAL.to_string_8` requires `is_valid_as_string_8` (base/elks/kernel/string/readable_string_general.e).
- `SIMPLE_JSON.parse_message (a_json_text: STRING_32)` **requires `not_empty: not a_json_text.is_empty`** (simple_json/src/core/simple_json.e:30-34); every `*_item` of SIMPLE_JSON_OBJECT only requires a non-empty key and returns 0/False/Void for a missing or mistyped field; SIMPLE_JSON_ARRAY.object_item requires `valid_index`.
- `SIMPLE_DATE_TIME.make_from_iso8601` → `make_from_string` → `SIMPLE_DATE.make_from_string` → `create internal_date.make (y, m, d)` on ISE `DATE`, whose `make` **requires `correct_date: is_correct_date (y, m, d)`** (library/time/date.e:56-59). SIMPLE_TIME clamps hour/minute/second; SIMPLE_DATE does not clamp month/day. simple_datetime.ecf compiles with `supplier_precondition="true"`.
- `SIMPLE_ENCRYPTION.hash_password` returns `salt$iterations$hash` with lowercase hex (`hex_chars = "0123456789abcdef"`), salt = `random_hex (16)` = 32 hex; `verify_password` requires both strings non-empty and never raises on a malformed stored hash.
- simple_mml `model_equals` uses `~` (object equality) for non-models, so STRING-keyed models and `|=|` behave as intended; `MML_RELATION.extended` adds a pair only if absent.
- `HASH_TABLE.remove` requires only `prunable` (no raise for an absent key); `HASH_TABLE` redefines `copy`, so `old sessions.twin` is an independent table.
- SCOOP: the error texts VUAR3 / VUTA3 / VFFD8 (studio/help/errors/short). CHAT_API is created on the service's processor with a **non-separate** `service: CHAT_SERVICE` (chat_api.e:30-42, 73) and every handler reaches it through `separate CHAT_API` formals with separate strings; so CHAT_SERVICE's non-separate formals are valid, and no CHAT_SERVICE / CHAT_STORE / RATE_LIMITER / CHAT_LOG postcondition ever calls a query on a separate object. The addendum records a clean compile of the merged tree (85/85), and chat_status.e has not changed since that compile, so `CHAT_STATUS.make_from_separate`'s postcondition on `a_other` (chat_status.e:43-44) is accepted by the compiler; it performs synchronous separate queries on a locked, immutable argument, which is sound. No `once ("PROCESS")` exists in this cluster; the `once` rule objects (`CHAT_USER.rules`, `CHAT_ATTACHMENT.rules`, `SERVER_CONFIG.hostname_rules/dns_rules`) are per-processor and non-separate — no VFFD8.

Verdict key: FIXED · DISSOLVED (the SCOOP restructuring makes the finding inapplicable) · PARTIAL · OPEN · NEW-HIGH / NEW-MEDIUM / NEW-LOW.

---

## A. Phase 2 HIGH findings located in this cluster

### [ISSUE 1]: Exact "+1" / "unchanged" postconditions on thread-shared state (service, store, limiter, log parts)
- LOCATION: CHAT_SERVICE.post_message/post_image/post_system/publish_status/authenticate (chat_service.e:115-118, 139-142, 159-161, 175-176, 73-75); CHAT_STORE.append_event (chat_store.e:125-127); MEMORY_CHAT_STORE frames (memory_chat_store.e:174-182, 273-289, 393-399, 443-447); RATE_LIMITER.record/set_limit/prune (rate_limiter.e:99-101, 110-113, 120-123); CHAT_LOG.info/warn/error (chat_log.e:30, 37, 44)
- VERDICT: DISSOLVED
- EVIDENCE: chat_service.e:10-15 "one processor - the API's - owns this service and the store, bus, limiter and log with it, so one request executes here at a time and every postcondition below is exact"; chat_api.e:30-42 `make (a_service: CHAT_SERVICE; …)` and chat_api.e:44-69 `make_from_shared` create the store, bus, limiter, log and service on the API's processor; every entry from another processor is `api_* (a_api: separate CHAT_API; …)` with copyable arguments (chat_api.e:98-360). `old x` and the postcondition are therefore evaluated by the only processor that can change `x`, with the caller's request holding that processor for the whole routine. `EVENT_BUS.ring` only increments its own `ring_count` and issues asynchronous separate commands (event_bus.e:100-112), so `bus.ring_count = old bus.ring_count + 1` is stable too. The memory store is used single-threaded by the assault. RATE_LIMITER's frames `others_unchanged`/`limits_unchanged` and CHAT_LOG's `lines_written = old lines_written + 1` are exact for the same reason (CHAT_LOG instances handed to other processors are separate instances, never shared).
- REMAINING/SUGGESTION: nothing for the contracts. Note that the still-stubbed bodies violate these exact clauses today (see NEW-5).

### [ISSUE 2]: Contract evaluation iterates shared collections without the lock (RATE_LIMITER part)
- LOCATION: RATE_LIMITER.counts_model (rate_limiter.e:36-45), invariant `never_over` (rate_limiter.e:142)
- VERDICT: DISSOLVED
- EVIDENCE: `counts` and `limits` are `feature {NONE}` attributes (rate_limiter.e:133-136) of an object that only the service's processor references (chat_api.e:60-63 creates it there). No other processor can be inside `record` while an assertion iterates `counts`. The remaining hazards of this class are the ones in [M-S6] (`set_limit` versus `never_over`, time-fragile `count`).
- REMAINING/SUGGESTION: none for concurrency.

### [ISSUE 6]: wait_for_events forbids the very thing it waits for
- LOCATION: former CHAT_SERVICE.wait_for_events
- VERDICT: DISSOLVED
- EVIDENCE: the feature no longer exists in chat_service.e; waiting moved to the request's processor (`POLL_WAIT.wait_for (a_waiter: separate POLL_WAITER)`, poll_wait.e:42) with `is_ready` as a wait condition; the service "never blocks" (chat_service.e:13-15). `Max_wait_seconds` (chat_service.e:396) survives as documentation only.
- REMAINING/SUGGESTION: none.

### [ISSUE 7]: RATE_LIMITER.record's precondition is a check-then-act race
- LOCATION: RATE_LIMITER.record (rate_limiter.e:104-114)
- VERDICT: DISSOLVED
- EVIDENCE: `require allowed: is_allowed (a_key)` (rate_limiter.e:107) is now a plain correctness precondition: the decision and the count happen in one routine on one processor, e.g. chat_api.e:474-489 `dispatcher_try_ask` ("decided and counted here, in one step, on the processor that owns the limiter") with `granted_when_allowed`, `recorded`, `nothing_when_refused` — exactly the `try_record` shape the finding asked for, one level up.
- REMAINING/SUGGESTION: none.

### [ISSUE 8]: add_user's `fresh_username` is check-then-act; no UNIQUE on usernames/memberships
- LOCATION: CHAT_STORE.add_user (chat_store.e:225-238); CHAT_SCHEMA note (chat_schema.e:7-14)
- VERDICT: FIXED (schema) / DISSOLVED (precondition)
- EVIDENCE: chat_schema.e:10-12 "UNIQUE on user.username and membership (room_id, user_id) so the store's `fresh_*' preconditions are also facts on disk"; chat_store.e:15-18 "The schema's UNIQUE constraints … back the `fresh_*' preconditions on disk". `has_username` then `add_user` inside `create_user` run on one processor, and CHAT_SERVICE.create_user reports the outcome (`duplicate_refused`, chat_service.e:253).
- REMAINING/SUGGESTION: Phase 4 must still make the CHAT_SCHEMA.migrate body match the note; nothing contractual remains.

### [ISSUE 11]: authenticate's `failure_counted` unsatisfiable at the lockout boundary; per-IP key uncontracted
- LOCATION: CHAT_SERVICE.authenticate (chat_service.e:58-79)
- VERDICT: FIXED
- EVIDENCE: chat_service.e:72-75
  `locked_out_stays_out: (old not limits.is_allowed (login_user_key (a_username))) implies not Result.is_success`
  `failure_counted: (not Result.is_success and old limits.is_allowed (login_user_key (a_username))) implies limits.count (login_user_key (a_username)) = old limits.count (login_user_key (a_username)) + 1`
  `ip_locked_out_stays_out: …`, `ip_failure_counted: …` (same shape on `login_ip_key (a_client_ip)`).
  Satisfiable at the boundary: counting is demanded only when the key was still allowed, so `record`'s precondition (rate_limiter.e:107) holds when the service records; when one key is locked and the other is not, the clauses demand the allowed key be counted and the locked one left alone — consistent with `record`. `login_ip_key` (chat_service.e:357-360) is now in two clauses. Exact form is right under SCOOP (Issue 1).
- REMAINING/SUGGESTION: none. (See NEW-5: the Phase 1 stub body records nothing, so `failure_counted` fails the first time any test calls `authenticate`; Phase 4 work.)

### [ISSUE 12]: create_user / create_bot `unique_or_error` is an equality
- LOCATION: CHAT_SERVICE.create_user, create_bot (chat_service.e:253-254, 284-285)
- VERDICT: FIXED
- EVIDENCE: `duplicate_refused: old store.has_username (a_username) implies not Result.is_success` and `success_is_fresh: Result.is_success implies not (old store.has_username (a_username))` in both features — implications, so a store error on a fresh name no longer violates the contract.
- REMAINING/SUGGESTION: none.

### [ISSUE 13]: One limiter window cannot express per-minute / per-10-minute / per-hour
- LOCATION: RATE_LIMITER.make (rate_limiter.e:20-32), set_limit (rate_limiter.e:92-102), window_seconds (rate_limiter.e:60); CHAT_API.make_from_shared (chat_api.e:60 `create l_limits.make (3600)`)
- VERDICT: OPEN
- EVIDENCE: `make (a_window_seconds: INTEGER)` still fixes one `window_seconds` for every key; `set_limit (a_prefix: READABLE_STRING_8; a_limit: INTEGER)` still carries no window; no `windows_model`, no `window_for`; nothing anywhere calls `set_limit` with the config's `posts_per_minute`, `login_failures_per_10_minutes`, `ai_requests_per_hour`. The addendum's sentence "RATE_LIMITER windows are per key" is not in the code. Under the one 3600 s window, 30 posts/minute becomes 30/hour and a login lockout lasts an hour.
- REMAINING/SUGGESTION:
  ```eiffel
  set_limit (a_prefix: READABLE_STRING_8; a_limit, a_window_seconds: INTEGER)
      require
          prefix_given: not a_prefix.is_empty
          positive: a_limit > 0
          window_positive: a_window_seconds > 0
      ensure
          set: limits_model |=| (old limits_model).updated (a_prefix.to_string_8, a_limit)
          window_set: windows_model |=| (old windows_model).updated (a_prefix.to_string_8, a_window_seconds)
          counts_unchanged: counts_model |=| old counts_model
  windows_model: MML_MAP [STRING_8, INTEGER]   -- pure, over a `windows: HASH_TABLE [INTEGER, STRING_8]'
  window_for (a_key: READABLE_STRING_8): INTEGER
      ensure positive: Result > 0
             by_prefix: attached matching_prefix (a_key) as p implies Result = windows_model [p]
  ```
  drop `make (a_window_seconds)` → `make` with a `Default_window_seconds`; and in CHAT_API.make_from_shared (or the facade's start) ensure `posts_limited: service.limits.limit_for ("post:x") = l_config.posts_per_minute and service.limits.window_for ("post:x") = 60`, likewise `login:user:`/`login:ip:` (10 min) and `ai:` (3600). Phase 5 tests `test_post_rate_limit_refuses_past_the_limit` and `test_login_lockout_boundary` remain to be written.

### [ISSUE 14]: A limiter that never limits passes every contract; no rate-limit test
- LOCATION: RATE_LIMITER.limit_for (rate_limiter.e:62-70); CHAT_SERVICE.post_message (chat_service.e:119-120); chat_assault.e (no lockout / limit test)
- VERDICT: PARTIAL
- EVIDENCE: `post_message` gained `recorded_on_success: Result.is_success implies limits.count (post_key (a_sender.id)) >= 1` (chat_service.e:120) — but `>= 1` is satisfied forever after the first successful post, so a body that records once and never again still passes; the exact form is available now (Issue 1). `limit_for` still ensures only `positive` and `configured_or_default: limits_model.is_empty implies Result = Default_limit` (rate_limiter.e:67-69): with any limit configured the clause says nothing, so `Result := Default_limit` remains a conforming body and `rate_limited` stays vacuous. No `matching_prefix`/`by_prefix`. No rate-limit or lockout test exists in chat_assault.e or store_assault.e.
- REMAINING/SUGGESTION:
  ```eiffel
  -- CHAT_SERVICE.post_message / post_image
  recorded_on_success: Result.is_success implies limits.count (post_key (a_sender.id)) = old limits.count (post_key (a_sender.id)) + 1
  not_recorded_on_failure: not Result.is_success implies limits.count (post_key (a_sender.id)) = old limits.count (post_key (a_sender.id))
  -- RATE_LIMITER
  matching_prefix (a_key: READABLE_STRING_8): detachable STRING_8
      -- The longest configured prefix `a_key' starts with.
      ensure matches: attached Result as p implies (a_key.starts_with (p) and limits_model.domain.has (p))
             longest: attached Result as p2 implies across limits as l all (a_key.starts_with (@l.key)) implies @l.key.count <= p2.count end
             none_when_unmatched: Result = Void implies across limits as l2 all not a_key.starts_with (@l2.key) end
  limit_for … ensure by_prefix: attached matching_prefix (a_key) as p implies Result = limits_model [p]
                     default_when_unmatched: matching_prefix (a_key) = Void implies Result = Default_limit
  ```

### [ISSUE 19]: events_since does not guarantee a gap-free page when the page is full
- LOCATION: CHAT_STORE.events_since (chat_store.e:149-163)
- VERDICT: FIXED
- EVIDENCE: chat_store.e:161-162 `contiguous: Result.count < a_limit implies Result.count = count_after (a_room_id, a_since_id)` and `gapless: Result.count > 0 implies count_after (a_room_id, a_since_id) - count_after (a_room_id, Result.last.id) = Result.count`. Checked against the finding's counter-example: events {1..5}, page [1,3,5] → 5 − 0 ≠ 3, refused; the correct [1,2,3] → 5 − 2 = 3. `Result.last` is guarded by `Result.count > 0 implies`. Exact under one processor. Memory body (memory_chat_store.e:195-205) walks `events` in id order → gapless by construction; store_assault.e:32-36 exercises both pages.
- REMAINING/SUGGESTION: none. (`count_after`'s `zero_iff_none` calls `events_since`, whose postcondition calls `count_after`: the ISE runtime suppresses assertion checking while evaluating an assertion, so this is not a recursion — worth a one-line note in the class.)

### [ISSUE 20]: events_before does not say which events — the oldest N satisfy it
- LOCATION: CHAT_STORE.events_before, count_before (chat_store.e:165-179, 193-202)
- VERDICT: FIXED
- EVIDENCE: chat_store.e:177-178 `newest: Result.count = a_limit.to_integer_64.min (count_before (a_room_id, a_before_id))` and `adjacent: Result.count > 0 implies count_before (a_room_id, a_before_id) - count_before (a_room_id, Result.first.id) = Result.count`. The oldest-2 page [1,2] for before = 6 over {1..5} gives 5 − 0 ≠ 2, refused; [4,5] gives 5 − 3 = 2. Memory body memory_chat_store.e:218-226 takes the last `a_limit` ascending; store_assault.e:37-41 checks 4,5 before 6 and 1 before 2.
- REMAINING/SUGGESTION: none.

### [ISSUE 21]: add_membership accepts duplicates but the relation model forbids them
- LOCATION: CHAT_STORE.add_membership (chat_store.e:357-370); MEMORY_CHAT_STORE invariant (memory_chat_store.e:517), models_consistent (520-522)
- VERDICT: FIXED
- EVIDENCE: `require … not_already: not is_member (a_membership.user_id, a_membership.room_id)` (chat_store.e:362); invariant `unique_pairs: across memberships as a all (across memberships as b all (a.user_id = b.user_id and a.room_id = b.room_id) implies a = b end) end`; `models_consistent` now includes `membership_model.count = memberships.count and attachments_model.count = attachments.count`; store_assault.e:86-88 proves the duplicate is refused.
- REMAINING/SUGGESTION: none.

### [ISSUE 23]: The memory oracle has reference semantics; SQLite has value semantics (D5)
- LOCATION: MEMORY_CHAT_STORE.add_user/update_user/user/user_by_username/users/room/membership/attachment/session_by_hash (memory_chat_store.e:268-318, 344-351, 381-388, 421-428, 449-456); CHAT_USER.make (chat_user.e:29-32); CHAT_EVENT.make (chat_event.e:41-45); MEMORY_CHAT_STORE.event/events_since/events_before (184-229)
- VERDICT: PARTIAL
- EVIDENCE: every user/room/membership/attachment/session is stored as `x.twin` and returned as `x.twin`; `user ensure then a_copy: attached Result as u2 implies u2 /= users_table [a_user_id]` (memory_chat_store.e:298); store_assault.e:44-58 proves `set_active` on a returned user does not reach the store. **But `twin` is a shallow copy and the domain constructors do not copy their strings**: `username := a_username.to_string_8` (chat_user.e:30) returns `Current` when the argument already is a STRING_8 (`READABLE_STRING_GENERAL.to_string_8`: "if attached {STRING_8} Current as s then Result := s"), the same for `display_name := a_display_name.to_string_32`. So the stored twin and the caller's copy share one `display_name` object, and `s.user (1).display_name.append ({STRING_32} "!")` changes the oracle with no command — the exact blindness D5 was meant to cure, now one level down. Events are worse: `event`, `events_since`, `events_before` return the stored CHAT_EVENT objects themselves (no twin), whose `body: STRING_32` and `payload: SIMPLE_JSON_OBJECT` are exported mutable (`payload_set: payload = a_payload` even demands sharing); `e.body.wipe_out` breaks the stored event's `message_has_body` invariant. The assault tests only a scalar (`is_active`).
- REMAINING/SUGGESTION: do not deepen `twin` (the models compare with `~`, and `CHAT_USER.is_equal` is field-by-reference, so `replaced: users_model |=| (old users_model).updated (a_user.id, a_user)` would fail on a deep copy). Instead close the hole at the interface, which also settles [M-D3]:
  ```eiffel
  -- CHAT_USER (same pattern for CHAT_ROOM.name, CHAT_MEMBER, CHAT_SESSION.token_hash, CHAT_ATTACHMENT.*, CHAT_EVENT.kind/body, CHAT_STATUS.*)
  username: IMMUTABLE_STRING_8
  display_name: IMMUTABLE_STRING_32
  password_hash: IMMUTABLE_STRING_8
  make … do create username.make_from_string (a_username.to_string_8)      -- copies
              create display_name.make_from_string (a_display_name.to_string_32) …
  -- CHAT_EVENT: keep `payload' private-by-copy
  payload: SIMPLE_JSON_OBJECT do Result := payload_storage.deep_twin end   -- or expose `payload_json: IMMUTABLE_STRING_32'
  ensure payload_set: payload.to_json_string.same_string (a_payload.to_json_string)   -- instead of `payload = a_payload'
  ```
  and add to store_assault.e `test_oracle_copies_strings`: mutate `display_name` of a returned user and `body` of a returned event, then read back.

### [ISSUE 24]: An image event can be appended with an unstored attachment (id 0)
- LOCATION: CHAT_STORE.append_event (chat_store.e:120); CHAT_EVENT invariant (chat_event.e:124) and CHAT_EVENT_DRAFT (chat_event_draft.e:27, 79); CHAT_JSON.attachment_from_json (chat_json.e:243)
- VERDICT: FIXED
- EVIDENCE: `attachment_stored: attached a_draft.attachment as a implies has_attachment (a.id)` (chat_store.e:120); `attachment_stored: attached attachment as a implies a.is_stored` in both invariants; the codec refuses `id <= 0` (`a_object.integer_item (Key_id) > 0`, chat_json.e:243) and store_assault.e:153 proves it.
- REMAINING/SUGGESTION: none.

### [ISSUE 25]: PASSWORD_HASHER.hash's `never_plaintext` is false for legal short passwords
- LOCATION: PASSWORD_HASHER.hash (password_hasher.e:28-40), Minimum_characters (password_hasher.e:83)
- VERDICT: PARTIAL
- EVIDENCE: `require long_enough: a_password.count >= Minimum_characters` (= 8, matching SERVER_CONFIG's `password_minimum_sane`, server_config.e:286) removes `hash ("0")`. The clause `never_plaintext: not Result.has_substring (utf8 (a_password))` (password_hasher.e:38) is still **deterministically false** for a legal password: the iterations field is the public constant `600000` and `$` is a legal password character, so `hash ("$600000$")` (exactly 8 characters) produces `<salt>$600000$<digest>`, which always contains the password; `hash ("0$600000")` fails whenever the salt ends in `0` (1 in 16). The comment "1-in-2^32 event" only holds for passwords that cannot straddle the field separators.
- REMAINING/SUGGESTION:
  ```eiffel
  never_plaintext: not utf8 (a_password).has ('$') implies not Result.has_substring (utf8 (a_password))
      -- A password without `$' can only match inside a random hex field (>= 8 characters of 96): probabilistic, ~2^-32.
  ```
  Passwords containing `$` are covered by `format`/`salted`/`floor` (the fields are hex, an iteration count and hex — none is the password).

### [ISSUE 28]: The decoder violates CHAT_ERROR.make's preconditions (codec half)
- LOCATION: CHAT_JSON.error_from_bytes (chat_json.e:363-382)
- VERDICT: FIXED
- EVIDENCE: `if a_http_status >= 400 and a_http_status <= 599 and then … attached ascii_item (o, Key_code) as c and then not c.is_empty and then attached o.string_item (Key_message) as m and then not m.is_empty` (368-370); an unknown code maps to `Code_unavailable` (372-376); `ensure only_error_statuses`, `status_kept` (380-381). Every precondition of `CHAT_ERROR.make` (chat_error.e:20-23: code_given, known, message_given, is_error_status) is established before the call. store_assault.e:154-156 covers the empty message, the 200 status and the unknown code. (`CHAT_CLIENT.error_of` is the client reviewer's.)
- REMAINING/SUGGESTION: see NEW-7 (the `is_known_code` probe object) and NEW-1 (an empty body reaches `parse_message`).

### [ISSUE 29]: Non-Latin-1 text reaches `to_string_8` in wire fields and on the login path
- LOCATION: CHAT_JSON.ascii_item (chat_json.e:432-438) and its uses (198-199, 235-236, 256, 354, 369); CHAT_SERVICE.login_user_key (chat_service.e:352-355), is_plausible_username (362-366), authenticate ensure (77-78)
- VERDICT: FIXED
- EVIDENCE: `ascii_item` returns Void unless `across s as c all c.natural_32_code < 128 end` and only then calls `to_string_8`; kind, created_at, mime, sha256, username, token and code all go through it. `login_user_key` builds the key with `{UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_username.as_lower)` (no precondition). `is_plausible_username: a_username.is_valid_as_string_8 and then …to_string_8` (short-circuit guard), and `bots_and_inactive_refused` guards its `to_string_8` with `is_plausible_username (a_username) and then` (chat_service.e:78). `login_ip_key` takes a READABLE_STRING_8 (to_string_8 always valid). store_assault.e:149 sends a Hebrew `kind`.
- REMAINING/SUGGESTION: none.

### [ISSUE 30]: `created_at` is parsed without validation
- LOCATION: CHAT_JSON.is_iso8601 (chat_json.e:404-428), event_from_json (chat_json.e:199, 204)
- VERDICT: PARTIAL
- EVIDENCE: the shape is now checked (`yyyy-mm-ddThh:mm:ss[Z]`, digits in the digit positions) before `create l_at.make_from_iso8601 (t)`, and "yesterday" is refused (store_assault.e:150). But the check is shape only: `2026-13-45T12:00:00`, `2026-00-10T00:00:00` and `2026-02-30T00:00:00` all pass `is_iso8601`, and `SIMPLE_DATE_TIME.make_from_string` → `SIMPLE_DATE.make_from_string` → `create internal_date.make (2026, 13, 45)` on ISE `DATE`, whose `make` requires `correct_date: is_correct_date (y, m, d)` (library/time/date.e:56-59) — a precondition violation raised from hostile bytes, on whichever processor decodes (with the checker off it is worse: a silently corrupt timestamp). The time part is safe (SIMPLE_TIME clamps).
- REMAINING/SUGGESTION: keep the shape check and add the range check that the date library itself uses:
  ```eiffel
  is_iso8601 (a_text: READABLE_STRING_8): BOOLEAN
      -- yyyy-mm-ddThh:mm:ss[Z], and a date that exists.
      do
          Result := has_iso8601_shape (a_text) and then
              (create {DATE_TIME_VALIDITY_CHECKER}).is_correct_date_time (
                  a_text.substring (1, 4).to_integer, a_text.substring (6, 7).to_integer, a_text.substring (9, 10).to_integer,
                  a_text.substring (12, 13).to_integer, a_text.substring (15, 16).to_integer, a_text.substring (18, 19).to_integer, False)
      ensure
          shape: Result implies has_iso8601_shape (a_text)
      end
  ```
  and a `time_kept` postcondition on the round trip (`e.created_at.to_iso8601.same_string (t)` for a decoded event) — SIMPLE_DATE.to_iso8601 zero-pads month/day but writes the year with `append_integer`, so a year below 1000 breaks the 19-character shape; the checker above makes that a refusal rather than a raise. Add `2026-13-45T…` and `2026-02-30T…` to `test_decoder_refuses_hostile_fields`.

### [ISSUE 34]: `sha256` and `stored_relpath` checked by length and prefix only — traversal
- LOCATION: CHAT_ATTACHMENT_RULES.is_sha256_hex/stored_path_for (chat_attachment_rules.e:19-25, 59-69); CHAT_ATTACHMENT.make/invariant (chat_attachment.e:27, 35, 102-103); CHAT_JSON.attachment_from_json (chat_json.e:236)
- VERDICT: FIXED
- EVIDENCE: `is_sha256_hex`: `a_text.count = 64 and then across a_text as ch all (ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f') end`; `stored_path_for` requires it and ensures `under_uploads` and `no_traversal: not Result.has_substring ("..")`; `stored_relpath := rules.stored_path_for (sha256, mime)` is computed in `make` (no caller names a path) and pinned by the invariant `path_pinned: stored_relpath.same_string (rules.stored_path_for (sha256, mime))`; the codec rebuilds through the same `make`. store_assault.e:114-127 covers the traversal hash, uppercase hex and separators in the name.
- REMAINING/SUGGESTION: `stored_relpath`/`sha256` remain exported mutable STRING_8 — closed by the [ISSUE 23]/[M-D3] change to IMMUTABLE_STRING_8.

### [ISSUE 35]: The bot flag is whatever the draft's creator passed (D4)
- LOCATION: CHAT_STORE.append_event (chat_store.e:119); CHAT_SERVICE.post_message (chat_service.e:117, 121-122); CHAT_JSON.event_from_json (chat_json.e:219)
- VERDICT: FIXED
- EVIDENCE: `bot_flag_truthful: a_draft.is_system or (attached user (a_draft.sender_id) as u and then u.is_bot = a_draft.is_bot_authored)`; `humans_unmarked: (Result.is_success and not a_sender.is_bot and then attached Result.value as e) implies not e.body.starts_with ({CHAT_EVENT_KINDS}.Bot_marker)`; `right_event: … e.is_bot_authored = a_sender.is_bot`; the codec refuses an unmarked `is_bot` message (chat_json.e:219; chat_assault.e:328) and store_assault.e:60-75 proves a person's bot-flagged draft is refused and a bot's accepted.
- REMAINING/SUGGESTION: a system draft (sender 0) may still carry `is_bot_authored = True` through store and codec (nothing checks it; clients would render a system notice as a bot) — add `system_unflagged: a_draft.is_system implies not a_draft.is_bot_authored` to CHAT_EVENT_DRAFT/CHAT_EVENT and the codec (LOW).

### [ISSUE 37]: Token revocation is uncontracted end to end
- LOCATION: CHAT_STORE.has_session_of/remove_sessions_of (chat_store.e:428-455); CHAT_SERVICE.revoke_bot_token, reset_password, revoke (chat_service.e:319-326, 301, 92-97)
- VERDICT: FIXED
- EVIDENCE: `remove_sessions_of ensure none_left: not has_session_of (a_user_id)`; `revoke_bot_token ensure revoked: not store.has_session_of (a_bot.id)`; `reset_password ensure sessions_revoked: Result.is_success implies not store.has_session_of (a_user.id)`; `revoke ensure gone: store.session_by_hash (a_session.token_hash) = Void` (the 64-character precondition of `session_by_hash` is met by CHAT_SESSION's invariant); memory body memory_chat_store.e:474-491 with `others_kept`; store_assault.e:92-110 proves it at the store. `CHAT_API.logout ensure revoked` closes the loop at the API.
- REMAINING/SUGGESTION: Phase 5 `test_revoke_bot_token_denies_the_next_request` (service level) is still to write.

---

## B. Phase 2 MEDIUM findings located in this cluster

### [M-S1]: wait_for_events cannot return the statuses the API promises; waiter lifetime unspecified
- LOCATION: former CHAT_SERVICE.wait_for_events
- VERDICT: DISSOLVED
- EVIDENCE: removed with Issue 6; statuses travel as the waiter's JSON (`page_to_json_merged`, chat_json.e:112-130; CHAT_API.events takes `a_statuses_json`).
- REMAINING/SUGGESTION: none.

### [M-S2]: Service room preconditions weaker than the store's
- LOCATION: CHAT_SERVICE.post_message/post_image (chat_service.e:103-109, 126-133) vs post_system/publish_status/events_since/events_before (150-151, 167-168, 183-184, 196-197)
- VERDICT: PARTIAL
- EVIDENCE: `room_known: store.has_room (a_room.id)` was added to post_system, publish_status, events_since and events_before, but not to post_message/post_image, which rely on `member: store.is_member (a_sender.id, a_room.id)`; CHAT_STORE never states `is_member implies has_room` (the memory invariant `memberships_reference` does, SQLite would need a foreign key). `append_event require room_exists` (chat_store.e:117) is therefore reachable from a service precondition that holds.
- REMAINING/SUGGESTION: add `room_known: store.has_room (a_room.id)` to both, or promise it once in CHAT_STORE: `is_member … ensure member_of_known: Result implies (has_room (a_room_id) and has_user (a_user_id))`.

### [M-S3]: post_message/post_image do not tie the event to their inputs; post_image bypasses the post limit; `e.attachment = a_attachment` is reference equality
- LOCATION: CHAT_SERVICE.post_message (chat_service.e:117-122), post_image (139-144)
- VERDICT: PARTIAL
- EVIDENCE: `right_event` (room, sender, kind, bot flag) was added to both and `rate_limited` to post_image. Still missing: any clause on the **body** (`e.body` versus `a_body` — a body that stores the caption of the previous message passes), `recorded_on_success` on post_image, and `image_kind: … e.attachment = a_attachment` (chat_service.e:141) is still reference equality, which the SQLite store cannot honour (it reads the row back) and the memory store honours only by accident.
- REMAINING/SUGGESTION:
  ```eiffel
  -- post_message
  body_kept: (Result.is_success and not a_sender.is_bot and then attached Result.value as e) implies e.body.same_string_general (a_body)
  bot_body_kept: (Result.is_success and a_sender.is_bot and then attached Result.value as e) implies e.body.ends_with (a_body.to_string_32)
  -- post_image
  same_attachment: (Result.is_success and then attached Result.value as e and then attached e.attachment as ea) implies ea.id = a_attachment.id
  caption_kept: (Result.is_success and then attached Result.value as e) implies e.body.same_string_general (a_caption)
  recorded_on_success / not_recorded_on_failure as in [ISSUE 14]
  ```
  The pre-existing LOW stands: `within_limit` counts `a_body` before the marker, so a bot body of exactly `message_characters` is stored two code points over.

### [M-S4]: post_system / publish_status under-contracted
- LOCATION: CHAT_SERVICE.post_system (chat_service.e:147-162), publish_status (164-177)
- VERDICT: FIXED
- EVIDENCE: `system_kind: … (e.is_system and e.sender_id = 0 and e.room_id = a_room.id)`; `room_known`, `from_stored`, `text_bounded` preconditions; `not_stored: store.last_event_id = old store.last_event_id`; `rung: bus.status_count = old bus.status_count + 1` (exact under SCOOP).
- REMAINING/SUGGESTION: none.

### [M-S5]: session_for_token lacks `right_one`; `now` moves between body and postcondition
- LOCATION: CHAT_SERVICE.session_for_token (chat_service.e:81-90), now (339-342), token_hash_of (344-350)
- VERDICT: PARTIAL
- EVIDENCE: `right_one: attached Result as s2 implies s2.token_hash.same_string (token_hash_of (a_token))` added with `token_hash_of` exported. `not_expired: attached Result as s implies not s.is_expired_at (now)` still calls `now` (a fresh `make_now`) in the postcondition: a session expiring in the second between the body's check and the postcondition's evaluation makes a correct body fail. Time-fragile.
- REMAINING/SUGGESTION: `not_expired: attached Result as s implies not s.is_expired_at (old now)` — the body's check happens at or after `old now`, so "not expired at old now" is implied by a correct body.

### [M-S6]: RATE_LIMITER.set_limit can break `never_over`; `count` purity is time-fragile
- LOCATION: RATE_LIMITER.set_limit (rate_limiter.e:92-102), invariant never_over (142), count (72-79), record ensure counted (111)
- VERDICT: OPEN
- EVIDENCE: unchanged. `set_limit ("post:", 1)` while `counts ["post:7"] = 5` ends the routine with `never_over` false → an exception from an administrative call. `count` is documented as "inside the current window" (rate_limiter.e:73) and the class note says Phase 4 keeps timestamps (134): if `count` evicts against the wall clock, `counted: count (a_key) = old count (a_key) + 1` can fail when an old entry expires between `old` and the postcondition.
- REMAINING/SUGGESTION: either `set_limit require would_hold: across counts as ic all (@ic.key.starts_with (a_prefix)) implies ic <= a_limit end`, or drop `never_over` (it is a consequence of `record`'s precondition) and keep it as a `check` in `record`. State the eviction rule in the class note and contract: `count` is pure over the current table; only `record` and `prune` evict (then `record ensure counted` holds exactly).

### [M-S7]: CHAT_LOG never promises what was written was redacted; the secret-field rule targets `password=` while the wire is JSON `"password":`
- LOCATION: CHAT_LOG.info/warn/error (chat_log.e:26-45), has_secret_field (83-87), redact (51-59)
- VERDICT: OPEN
- EVIDENCE: `info/warn/error` still ensure only `counted`; there is no `last_line` and no `redacted` clause, so a body that writes the raw text passes. `has_secret_field`'s header comment (84) still names `"password="`, `"token="`, `"hash="` — the JSON forms `"password":` / `"token":` are not in the rule as written; the body is a stub.
- REMAINING/SUGGESTION:
  ```eiffel
  last_line: detachable STRING_32   -- what was last handed to the logger, after redaction
  info … ensure counted: lines_written = old lines_written + 1
                 redacted: attached last_line as l and then (not has_hex_run (l, 64) and not has_secret_field (l))
                 is_redaction: attached last_line as l2 and then l2.same_string (redact (a_text))
  has_secret_field: -- "password" | "token" | "hash" [optional quote] [spaces] ( "=" | ":" ) followed by anything but the mask
  ```

### [M-S8]: update_user does not say the row now matches; reset_password's `verifiable` checks the in-memory user
- LOCATION: CHAT_STORE.update_user (chat_store.e:240-252); CHAT_SERVICE.reset_password (chat_service.e:290-302), change_password (304-317)
- VERDICT: PARTIAL
- EVIDENCE: store half fixed: `persisted: attached user (a_user.id) as u and then (u.is_active = a_user.is_active and u.password_hash.same_string (a_user.password_hash) and u.display_name.same_string (a_user.display_name) and u.is_admin = a_user.is_admin)`. Service half unchanged: `verifiable: Result.is_success implies hasher.verify (a_password, a_user.password_hash)` (300, 316) verifies against the argument object; under D5 a body that sets the hash on `a_user` and forgets `update_user` passes.
- REMAINING/SUGGESTION: `persisted: Result.is_success implies (attached store.user (a_user.id) as u and then hasher.verify (a_password, u.password_hash))` in both features (the `old hasher.verify` in change_password stays a 600k-iteration `old` — acceptable, noted LOW before).

### [M-S9]: User-facing rules as preconditions while promising never to raise (D6)
- LOCATION: CHAT_SERVICE.post_message/post_image/store_upload/create_user… preconditions (chat_service.e:103-109, 126-133, 226-228, 244-247); CHAT_API guards (chat_api.e:284-313, 507-540)
- VERDICT: PARTIAL
- EVIDENCE: D6 was never decided (phase2-chain.txt records D1, D3-D5). The rules stayed preconditions, and CHAT_API guards them where implemented: `user_for` ensures `active`, `member_room` ensures `member`, post_message checks empty and over-long bodies before calling the service. The guards do not yet exist for post_image (`not_yet`), change_password, admin_* (all stubs), and two service preconditions have no guard anywhere: `store_upload`'s file name (NEW-2) and `post_image`'s attachment (NEW-3).
- REMAINING/SUGGESTION: record D6 as "preconditions + a guard per handler" in the class note of CHAT_API and add a Phase 4 rule: every CHAT_SERVICE precondition that mentions an argument is either derived from the store (`user_for`, `member_room`) or checked in the API with a 4xx reply; or move the two user-controlled rules into outcomes (see NEW-2/NEW-3).

### [M-S10]: PASSWORD_HASHER.make never sets the iteration count it guarantees
- LOCATION: PASSWORD_HASHER.make (password_hasher.e:18-24)
- VERDICT: FIXED
- EVIDENCE: `crypto.set_pbkdf2_iterations (Minimum_iterations.max (crypto.pbkdf2_iterations))`, `ensure floor_applied`, invariant `crypto_at_floor`. `set_pbkdf2_iterations` requires `positive`; satisfied.
- REMAINING/SUGGESTION: none.

### [M-S11]: One CHAT_JSON with a mutable parser shared by every handler thread
- LOCATION: CHAT_JSON.parser (chat_json.e:26-29, 471)
- VERDICT: DISSOLVED
- EVIDENCE: under SCOOP a CHAT_JSON instance never crosses a processor: CHAT_API's `codec` is created on the service's processor and used by requests serialized there; `CHAT_EVENT.to_json` creates a fresh codec (chat_event.e:93); the client keeps its own. `SIMPLE_JSON`'s `last_errors` state is therefore per processor.
- REMAINING/SUGGESTION: none.

### [M-D1]: Password-hash shape is "two `$`"
- LOCATION: CHAT_USER_RULES.is_pbkdf2 (chat_user_rules.e:81-92); CHAT_USER.make/set_password_hash/invariant (chat_user.e:26, 92, 148)
- VERDICT: FIXED
- EVIDENCE: three parts, 32-hex lowercase salt, `is_integer and then >= Minimum_iterations`, 64-hex digest; simple_encryption writes lowercase hex, so `PASSWORD_HASHER.hash ensure format` is satisfiable; store_assault.e:138-141 covers the shapes.
- REMAINING/SUGGESTION: none.

### [M-D2]: `original_name` unconstrained
- LOCATION: CHAT_ATTACHMENT_RULES.is_valid_name (chat_attachment_rules.e:27-43); CHAT_ATTACHMENT.make/invariant (chat_attachment.e:24, 99); CHAT_JSON.attachment_from_json (243); CHAT_SERVICE.store_upload (223-239)
- VERDICT: PARTIAL
- EVIDENCE: domain and codec fixed (1..255 code points, no `/` `\`, no controls; Void on decode). The upload path is not: see NEW-2 — `store_upload` accepts any `a_original_name`, and nothing takes the basename.
- REMAINING/SUGGESTION: as NEW-2.

### [M-D3]: Exported mutable strings carry the invariants
- LOCATION: CHAT_USER (chat_user.e:52-58), CHAT_EVENT (63-67), CHAT_SESSION (41), CHAT_ATTACHMENT (49-53), CHAT_MEMBER (37-38), CHAT_ROOM (31), CHAT_ERROR (36-41), CHAT_STATUS (50-51), SERVER_CONFIG (95-99, 114-116)
- VERDICT: OPEN
- EVIDENCE: every text attribute is still `STRING_8`/`STRING_32`; constructors keep the caller's object when it already has the right type (`to_string_8`/`to_string_32` return `Current`); `payload` is shared by reference and `payload_set: payload = a_payload` requires it. `u.username.append ("x")` still breaks `username_shape`; `e.body.wipe_out` still breaks `message_has_body`/`marked_when_bot`.
- REMAINING/SUGGESTION: as in [ISSUE 23]: IMMUTABLE_STRING_* attributes created by copy; `payload` returned as a copy (or as JSON text).

### [M-D4]: SERVER_CONFIG exports its mutable lists
- LOCATION: SERVER_CONFIG.participants/validation_errors (server_config.e:121-147), participant_list/error_list (263-264)
- VERDICT: FIXED
- EVIDENCE: `feature {NONE}` lists; `participants: … do Result := participant_list.twin ensure a_copy: Result /= participant_list`; `participant_count`, `error_count`; `has_participant_handle` lowercases; ops_assault `config_lists_are_copies` registered (test_app.e:94).
- REMAINING/SUGGESTION: none.

### [M-D5]: make_from_file's postcondition is a tautology; invalid values silently become defaults
- LOCATION: SERVER_CONFIG.make_from_file (server_config.e:55-67), is_loaded (158-159), invariant (293-294); SIMPLE_CHAT_SERVER.set_config require valid (simple_chat_server.e:37)
- VERDICT: FIXED
- EVIDENCE: `loaded_or_explained: is_loaded = is_valid`, `errors_name_fields`, invariant `loaded_is_valid: is_loaded implies is_valid`, `valid_means_no_errors`; the facade refuses an invalid config by precondition. (The Phase 1 stub sets nothing after `make_defaults`, so `False = True` fails today — NEW-5.)
- REMAINING/SUGGESTION: none contractual.

### [M-D6]: `public_name` / DDNS fields spliced into generated files with no shape check
- LOCATION: SERVER_CONFIG.set_front_door (server_config.e:195-206), set_ddns (208-223), invariant (282, 287-289), is_hostname/is_valid_domains (243-252 via NO_DOOR_RULES/NO_DNS_RULES)
- VERDICT: FIXED
- EVIDENCE: `hostname_when_doored: not a_kind.same_string (Door_none) implies is_hostname (a_public_name)`; `domains_valid`, `token_given`, `at_least_a_minute`; invariants `public_when_doored`, `known_provider`, `ddns_needs_token`, `ddns_interval_sane`. FRONT_DOOR.is_hostname (labels of `[a-z0-9-]`, no leading/trailing dash, ≤ 253) and DYNAMIC_DNS.is_valid_domains (`[a-z0-9-]+(,…)*`) verified. Every setter re-establishes every invariant clause; `make_defaults` satisfies all thirteen.
- REMAINING/SUGGESTION: none.

### [M-D7]: Uniqueness stops at handles — bot usernames and aliases can collide
- LOCATION: SERVER_CONFIG invariant unique_handles (server_config.e:290-291), add_participant (225-234)
- VERDICT: OPEN
- EVIDENCE: still only `unique_handles`; `add_participant` requires only `fresh_handle`. Two entries with the same `bot_username` would make the second `create_bot` refuse (Issue 12) and the participant post as the wrong user; an alias equal to another entry's handle is not refused here.
- REMAINING/SUGGESTION:
  ```eiffel
  add_participant require … fresh_bot_username: not has_bot_username (a_participant.bot_username)
                             fresh_addresses: across a_participant.aliases_model as a all not has_address (a) end
  invariant unique_bot_usernames: across participant_list as p all (across participant_list as q all p.bot_username.same_string (q.bot_username) implies p = q end) end
            unique_addresses: -- handles and aliases, lowercased, pairwise distinct across entries
  ```

### [M-D8]: A database written by a newer build crashes `version_of` instead of being refused
- LOCATION: CHAT_SCHEMA.version_of/migrate (chat_schema.e:36-57); CHAT_STORE.open (chat_store.e:33-41)
- VERDICT: PARTIAL
- EVIDENCE: `never_ahead` is gone and `migrate require not_ahead: version_of (a_db) <= Current_version`; the schema note (12-14) says "refused by the store's `open'". But `CHAT_STORE.open ensure open: is_open; schema_current: schema_version = Current_version` leaves no way to refuse: an ahead database can only end in a violated `not_ahead` precondition inside `open` — a raise, not a refusal.
- REMAINING/SUGGESTION:
  ```eiffel
  open require not_open: not is_open
       ensure opened_or_explained: is_open xor (last_error /= Void)
              schema_current: is_open implies schema_version = {CHAT_SCHEMA}.Current_version
              ahead_refused: (attached last_error as e and then e.code.same_string ({CHAT_ERROR}.Code_unavailable)) implies not is_open
  last_error: detachable CHAT_ERROR   -- why the last `open' did not open
  ```
  and `SIMPLE_CHAT_SERVER.start` / `CHAT_API.make_from_shared` refuse on `not store.is_open`.

### [M-D9]: Deferred CHAT_STORE commands carry no frames and the class has no invariant
- LOCATION: CHAT_STORE (chat_store.e:59-109 counts; 135-136, 235-237, 250-251, 300-301, 367-369, 384, 416, 443, 453-454; invariant 457-458)
- VERDICT: FIXED
- EVIDENCE: scalar `event_count/user_count/room_count/session_count/attachment_count` with `*_untouched` frames on every command (append_event, add_user, update_user, add_room, add_membership, add_attachment, put_session, remove_session, remove_sessions_of) and the invariant `count_within_ids: is_open implies event_count <= last_event_id` (guarded, so `event_count`'s `open` precondition is not hit after `make`).
- REMAINING/SUGGESTION: frames are uneven (append_event says nothing about sessions/attachments/memberships; add_attachment nothing about users/rooms) — cheap to complete, not blocking.

### [M-D10]: `user`/`room`/`attachment`/`event` lack `consistent`; `users` promises nothing
- LOCATION: chat_store.e:259-262, 268-271, 278-281, 308-311, 328-331, 352-355, 397-400
- VERDICT: FIXED
- EVIDENCE: `consistent: (Result /= Void) = has_user (a_user_id)` and the same for username, room, default_room, membership, attachment; `users ensure complete: Result.count = user_count; each_stored`. `event` keeps `right_one`/`within_ids` only — right, since SQLite ids need not be contiguous.
- REMAINING/SUGGESTION: none.

### [M-D11]: `update_user` lets a username change bypass `fresh_username`
- LOCATION: CHAT_STORE.update_user (chat_store.e:245)
- VERDICT: FIXED
- EVIDENCE: `same_username: attached user (a_user.id) as u and then u.username.same_string (a_user.username)`; memory invariant `unique_usernames` (memory_chat_store.e:516).
- REMAINING/SUGGESTION: none.

### [M-D12]: `default_room` has no contract
- LOCATION: CHAT_STORE.default_room_id/default_room (chat_store.e:313-331), add_room ensure first_room_is_default (299)
- VERDICT: FIXED
- EVIDENCE: `exists_when_set`, `set_when_any`, `consistent`, `right_one`, `first_room_is_default`; memory invariants `default_room_exists`/`default_when_any`; store_assault.e:84.
- REMAINING/SUGGESTION: none.

### [M-D13]: Membership role is write-only
- LOCATION: CHAT_STORE.membership (chat_store.e:347-355), add_membership ensure role_kept (366)
- VERDICT: FIXED
- EVIDENCE: `membership (a_user_id, a_room_id): detachable CHAT_MEMBERSHIP ensure consistent, right_one`; `role_kept`; store_assault.e:85.
- REMAINING/SUGGESTION: none.

### [M-D14]: append_event forgets `kind`, `attachment`, `payload`
- LOCATION: CHAT_STORE.append_event (chat_store.e:126-134); MEMORY_CHAT_STORE ensure next_id (181)
- VERDICT: FIXED
- EVIDENCE: `same_kind`, `same_body`, `same_author`, `same_attachment` (presence equality and id equality), `same_payload` (by JSON text), stronger `persisted` (id, kind, body), `next_id: Result.id = old last_event_id + 1` in the oracle.
- REMAINING/SUGGESTION: none.

### [M-D15]: The oracle has no referential-integrity invariants
- LOCATION: MEMORY_CHAT_STORE invariant (memory_chat_store.e:504-522)
- VERDICT: FIXED
- EVIDENCE: `ids_never_exceed_last`, `count_matches`, `events_ascending`, `events_reference`, `keyed_by_id`, `rooms_keyed_by_id`, `attachments_keyed_by_id`, `keyed_by_hash`, `memberships_reference`, `sessions_reference`, `attachments_reference`, `unique_usernames`, `unique_pairs`, `default_room_exists`, `default_when_any`, `models_consistent`. Each command re-establishes them: ids are assigned from private counters; every `add_*`/`put_session` precondition names the referenced row; `remove_*` only shrink. All six model queries are pure (build a fresh MML value from the private table) and are compared with `|=|`.
- REMAINING/SUGGESTION: none.

### [M-D16]: System events accept a negative `sender_id`
- LOCATION: CHAT_EVENT.make/invariant (chat_event.e:31, 119-120), CHAT_EVENT_DRAFT (chat_event_draft.e:23, 74-75), CHAT_JSON.event_from_json (chat_json.e:216)
- VERDICT: FIXED
- EVIDENCE: `sender_or_system: a_sender_id > 0 or (a_sender_id = 0 and a_kind.same_string (Kind_system))`; codec `(l_sender > 0 or (l_sender = 0 and …Kind_system))`; store_assault.e:151.
- REMAINING/SUGGESTION: none.

### [M-D17]: Display names may be invisible, multi-line, or contain controls
- LOCATION: CHAT_USER_RULES.is_valid_display_name/is_forbidden_in_name (chat_user_rules.e:40-79)
- VERDICT: FIXED
- EVIDENCE: rejects `< 0x20`, `0x7F-0x9F`, `U+200B-200F`, `U+2028-202E`, `U+2060-206F`, `U+FEFF`, requires a visible character; one implementation, CHAT_USER and CHAT_MEMBER delegate; tests in chat_assault.e:41-52 and store_assault.e:134-137.
- REMAINING/SUGGESTION: none.

(Not in this cluster's file list: "kind-specific engine requirements are not invariants" lives in participant_config.e, where `complete: is_complete_for_kind` and `shapers_known` now exist — left to the participants reviewer.)

---

## C. New defects found in the repaired code

### [NEW-1]: An empty body raises inside the decoder — `SIMPLE_JSON.parse_message` requires a non-empty text
- LOCATION: CHAT_JSON.object_from_bytes (chat_json.e:164-170), array_from_bytes (172-178); reachable from page_from_bytes, event_from_bytes, members_from_bytes, login_from_bytes, error_from_bytes and CHAT_API.events (chat_api.e:167 `codec.array_from_bytes (local_8 (a_statuses_json))`)
- VERDICT: NEW-HIGH
- EVIDENCE: chat_json.e:167 `if attached parser.parse_message ({UTF_CONVERTER}.utf_8_string_8_to_string_32 (a_bytes)) as v and then v.is_object then` — no emptiness check; simple_json/src/core/simple_json.e:30-34 `parse_message (a_json_text: STRING_32) … require not_empty: not a_json_text.is_empty`. CHAT_JSON is compiled with `supplier_precondition="true"` (simple_chat.ecf:16), so the client's `error_from_bytes ("", 502)` (a front door answering 502 with an empty body), a `200` with an empty body on login, or a handler passing `""` instead of `"[]"` as `a_statuses_json` ends in a PRECONDITION_VIOLATION — the class note's "Decoding never raises on bad input" (chat_json.e:9) is false on the simplest hostile input. Neither assault sends an empty body.
- REMAINING/SUGGESTION:
  ```eiffel
  object_from_bytes (a_bytes: READABLE_STRING_8): detachable SIMPLE_JSON_OBJECT
      do
          if not a_bytes.is_empty and then attached parser.parse_message ({UTF_CONVERTER}.utf_8_string_8_to_string_32 (a_bytes)) as v and then v.is_object then
              Result := v.as_object
          end
      ensure
          empty_is_void: a_bytes.is_empty implies Result = Void
      end
  ```
  the same in `array_from_bytes`; add `j.error_from_bytes ("", 502) = Void`, `j.page_from_bytes ("") = Void`, `j.login_from_bytes ("") = Void` to `test_decoder_refuses_hostile_fields`.

### [NEW-2]: `store_upload` can raise on a user-chosen file name, and ties its result neither to the store nor to the bytes
- LOCATION: CHAT_SERVICE.store_upload (chat_service.e:223-239) versus CHAT_ATTACHMENT.make require valid_name (chat_attachment.e:24)
- VERDICT: NEW-MEDIUM
- EVIDENCE: `store_upload (a_uploader: CHAT_USER; a_original_name: READABLE_STRING_GENERAL; a_bytes: SPECIAL [NATURAL_8])` has no precondition and no outcome clause on `a_original_name`, yet the only way to produce its result is `create {CHAT_ATTACHMENT}.make (…, a_original_name, …)` whose precondition `valid_name: rules.is_valid_name (a_original_name)` refuses `..\evil.png`, `a/b`, an empty name, a 256-character name or a name with a control character. Phase 4's `CHAT_API.post_image` receives `a_file_name` from the multipart part — attacker-controlled. So the service that "never raises for a user's mistake" (chat_service.e:5) raises here, and the MEDIUM's "basename on upload" is nowhere. Also nothing ties the result to the store or to the bytes: `stored_on_success` says `a.id > 0` (an unstored object with a made-up id passes) and no clause says `a.sha256` is the SHA-256 of `a_bytes` — "stored under its content hash" is contractually a promise about a field, not about the bytes.
- REMAINING/SUGGESTION: either an outcome
  ```eiffel
  bad_name_refused: not (create {CHAT_ATTACHMENT_RULES}).is_valid_name (a_original_name) implies not Result.is_success
  ```
  or a precondition `valid_name` plus `CHAT_API.post_image` taking `basename_of (a_file_name)` and answering 400 otherwise; and in either case
  ```eiffel
  in_store: (Result.is_success and then attached Result.value as a5) implies (store.has_attachment (a5.id) and store.attachment_count = old store.attachment_count + 1)
  content_hashed: (Result.is_success and then attached Result.value as a6) implies a6.sha256.same_string (sha256_hex_of (a_bytes))
  name_kept: (Result.is_success and then attached Result.value as a7) implies a7.original_name.same_string_general (a_original_name)
  ```
  with `sha256_hex_of (a_bytes: SPECIAL [NATURAL_8]): STRING_8` as contract support over `crypto`.

### [NEW-3]: `post_image`'s precondition is weaker than `append_event`'s — a forged attachment id reaches a store precondition
- LOCATION: CHAT_SERVICE.post_image require attachment_stored (chat_service.e:131) versus CHAT_STORE.append_event require attachment_stored (chat_store.e:120)
- VERDICT: NEW-MEDIUM
- EVIDENCE: the service requires only `a_attachment.id > 0`; the store requires `has_attachment (a.id)`. A CHAT_ATTACHMENT built with `make (7, …)` for an id the store never assigned satisfies the service and violates the store inside the service body. CHAT_API's future `post_image` builds the attachment through `store_upload`, so the honest path is safe — but the contract does not say so, and the dispatcher's `feature {PARTICIPANT_DISPATCHER}` section will grow an image-posting entry (D3 fences `image_path`; the answer must be posted as an image event).
- REMAINING/SUGGESTION: `attachment_known: store.has_attachment (a_attachment.id)` (and keep `own_upload`; consider `own_upload_in_store: attached store.attachment (a_attachment.id) as sa and then sa.uploader_id = a_sender.id`, since the argument's `uploader_id` is caller-supplied).

### [NEW-4]: RATE_LIMITER still creates a MUTEX and describes a lock order the design forbids
- LOCATION: RATE_LIMITER note (rate_limiter.e:5-6), make (27 `create lock.make`), record comment (109 "under `lock'"), lock (138 `lock: MUTEX`); SQLITE_CHAT_STORE.append_event comment (sqlite_chat_store.e:77 "INSERT under `lock'")
- VERDICT: NEW-LOW
- EVIDENCE: approach.md §8 "No MUTEX, no CONDITION_VARIABLE, no lock order anywhere in simple_chat"; the addendum repeats it. The limiter's note still says "Guarded by its own lock (middle of the order: store < limiter < bus)". Dead, misleading, and it spawns an OS mutex per limiter.
- REMAINING/SUGGESTION: delete `lock`, its creation and the two comments; rewrite the note: "Lives on the API's processor (D1); one caller at a time by construction."

### [NEW-5]: Phase 1 stubs that violate their own new postconditions the first time they are reached
- LOCATION: CHAT_SERVICE.authenticate (chat_service.e:66 versus 73/75), RATE_LIMITER.record (108-111), CHAT_LOG.info/warn/error/redact (26-59), SERVER_CONFIG.make_from_file (60-65: after `make_defaults`, `is_loaded = False` and `is_valid = True`, so `loaded_or_explained` is `False = True`), SQLITE_CHAT_STORE.open/append_event (46-49, 73-81)
- VERDICT: NEW-LOW
- EVIDENCE: as cited; none of the registered tests calls these features, so the suite is green. The addendum §4 lists most of them; `authenticate` and `make_from_file` are not in its list.
- REMAINING/SUGGESTION: keep them out of every test until Phase 4; add `authenticate` and `SERVER_CONFIG.make_from_file` to the addendum's "still-stubbed bodies whose postconditions will fail" list so a Phase 3 task owns each.

### [NEW-6]: `create_first_admin` does not refuse an existing username
- LOCATION: CHAT_SERVICE.create_first_admin (chat_service.e:259-272)
- VERDICT: NEW-LOW
- EVIDENCE: `refused_when_admin_exists` and `admin_on_success` only; when no admin exists but a person of that name does, the body is documented as `create_user (…, True)` (267), which refuses — but a body that calls `store.add_user` directly would violate `fresh_username`, and the contract does not forbid it.
- REMAINING/SUGGESTION: `duplicate_refused: old store.has_username (a_username) implies not Result.is_success`.

### [NEW-7]: `error_from_bytes` creates a throw-away CHAT_ERROR to ask whether a code is known
- LOCATION: CHAT_JSON.error_from_bytes (chat_json.e:372 `(create {CHAT_ERROR}.make ({CHAT_ERROR}.Code_unavailable, "probe", 503)).is_known_code (c)`)
- VERDICT: NEW-LOW
- EVIDENCE: `is_known_code` depends on nothing in the instance (chat_error.e:49-56). The probe runs CHAT_ERROR's four-clause invariant per decode and reads as a workaround.
- REMAINING/SUGGESTION: make `is_known_code` a class feature (`ensure instance_free: class`) and call `{CHAT_ERROR}.is_known_code (c)`; or move the codes and the query to a CHAT_ERROR_CODES class like CHAT_EVENT_KINDS.

### [NEW-8]: Failed logins are counted under attacker-chosen keys
- LOCATION: CHAT_SERVICE.authenticate ensure failure_counted (chat_service.e:73) with login_user_key (352-355)
- VERDICT: NEW-LOW
- EVIDENCE: `failure_counted` demands a count for every failure, including an implausible or non-existent username, under `"login:user:" + utf8 (lower (a_username))` — one table entry per distinct name an attacker types. Growth is bounded only by the IP rule (ten failures per IP per window) and by `prune`; the class has no maximum on distinct keys.
- REMAINING/SUGGESTION: count implausible names only under the IP key — `failure_counted: (not Result.is_success and is_plausible_username (a_username) and old limits.is_allowed (…)) implies …` — and give RATE_LIMITER a `Maximum_keys` with `prune` evicting oldest-first.

---

## Summary

49 Phase 2 items re-reviewed (21 HIGH, 28 MEDIUM) and 8 new items.

| Verdict | Count | Items |
|---|---|---|
| FIXED | 27 | HIGH 8, 11, 12, 19, 20, 21, 24, 28, 29, 34, 35, 37 · MEDIUM M-S4, M-S10, M-D1, M-D4, M-D5, M-D6, M-D9, M-D10, M-D11, M-D12, M-D13, M-D14, M-D15, M-D16, M-D17 |
| DISSOLVED | 6 | HIGH 1, 2, 6, 7 · MEDIUM M-S1, M-S11 |
| PARTIAL | 11 | HIGH 14, 23, 25, 30 · MEDIUM M-S2, M-S3, M-S5, M-S8, M-S9, M-D2, M-D8 |
| OPEN | 5 | HIGH 13 · MEDIUM M-S6, M-S7, M-D3, M-D7 |
| NEW-HIGH | 1 | NEW-1 (empty bytes raise in the decoder) |
| NEW-MEDIUM | 2 | NEW-2 (store_upload file name; no store or content-hash tie), NEW-3 (post_image attachment not known to the store) |
| NEW-LOW | 5 | NEW-4 (MUTEX leftover), NEW-5 (stubs versus their new postconditions), NEW-6 (create_first_admin duplicate), NEW-7 (is_known_code probe), NEW-8 (attacker-chosen limiter keys) |

**Assessment: PASS WITH CONDITIONS.** The SCOOP restructuring does what §8 claims for this cluster: the service, store, limiter and log are owned by one processor, the API reaches them only through same-processor calls, and no contract here touches a separate object, so the exact `= old + 1` forms and the MML frames are correct and the ten concurrency findings are gone rather than papered over. The store contract is now strong (gap-free pages, newest-N history, a relation with unique pairs, referential-integrity invariants, revocation, D4's `bot_flag_truthful`), the codec refuses non-ASCII, unstored, negative-sender and mis-flagged input, and the configuration's invariants are established by every constructor and setter. Four things must be done before Phase 3 tasks are cut: (1) NEW-1 — guard the two `parse_message` calls, because an empty reply is the most ordinary hostile input there is; (2) ISSUE 13 — the limiter still has one window, so none of the configured per-minute/per-10-minute/per-hour limits is expressible and a login lockout would last an hour; (3) ISSUE 30 — validate the date range, not only the shape, or the decoder raises on `2026-13-45`; (4) ISSUE 23/M-D3 — D5 is shallow: the domain classes hand out the very strings and payloads the oracle stores, so "a change to a returned object reaches the store only through a command" is true for scalars only. The remaining PARTIAL/OPEN items (`limit_for`'s vacuity, the in-memory `verifiable`, `old now`, `set_limit` versus `never_over`, the log's redaction promise, bot-username/alias uniqueness, `open` unable to refuse, NEW-2/NEW-3) are Phase 3 task material, none of them a design flaw.
