# Phase 2: Claude Review Response
# STATUS: COMPLETE
# Date: 2026-08-29
# Model: Claude Fable 5 — adversarial self-review run as four parallel cluster reviewers (each read every file in its cluster against the Phase 2 checklist and cited exact lines); the orchestrator re-read the cited source for every HIGH before accepting it
# Project: D:\prod\simple_chat — 86 classes, 8,818 lines (Phase 1 + 1m + thick-client amendment)
# Cluster reports (verbatim/condensed): phase2-part-domain-store.md, phase2-part-service-bus.md, phase2-part-participants.md, phase2-part-client.md

Verdict key — **CONFIRMED**: orchestrator re-read the cited lines; **ACCEPTED**: consistent with the reviewer's quoted lines, not independently re-read.

Totals: **38 HIGH · 53 MEDIUM · ~30 LOW · INFO**. Four root causes account for most of the HIGHs; they are the themes below.

---

## Theme A — The concurrency model was never written down, so the contracts were written for one thread

The server runs a thread per connection (simple_web over EWF's standalone connector). Every `old x` is captured before a body takes its lock and every postcondition runs after the lock is released. Exact arithmetic (`= old + 1`), "unchanged" frames, and any assertion that iterates a shared collection are therefore wrong *for correct code* the moment two handlers overlap — and assertion monitoring turns those races into crashes.

### ISSUE 1: Exact "+1" / "unchanged" postconditions on thread-shared state (systemic)
- **LOCATION**: CHAT_SERVICE.post_message (chat_service.e 105-108: `appended_on_success … = old store.last_event_id + 1`, `rung_on_success … = old bus.ring_count + 1`, `nothing_on_failure`), post_image 126-129, publish_status 153-154, authenticate 69; EVENT_BUS.ring 83 / ring_status 92; CHAT_LOG.info/warn/error 30/37/44; RATE_LIMITER.record 111, set_limit 101, prune 121-122; STREAM_SINK.write 35; CHAT_STORE.append_event 84/88 (`is_last`, `one_more`), events_since 113 (`contiguous … = count_after`); MEMORY_CHAT_STORE frames 148-153, 203-206
- **SEVERITY**: HIGH — **CONFIRMED**
- **DESCRIPTION**: Poster A captures `old last_event_id = 7`, B appends 8, A appends 9 → `9 = 7 + 1` fails. `contiguous` fails whenever an append lands between the page query and `count_after`. The memory store's `|=| old` frames fire spuriously under the planned 8-posters/4-streams assault. CHAT_SERVICE holds no lock and its postconditions span three locks; the only way both `appended_on_success` and `rung_on_success` could hold is a service-wide lock across `bus.ring` — which the lock order forbids and which would not help anyway.
- **SUGGESTION**: Decide the model once (synopsis decision D1) and write it into the class notes. Under threads: monotone forms — `appended_on_success: (Result.is_success and then attached Result.value as e) implies (e.id > old store.last_event_id and store.last_event_id >= e.id)`; `rung_on_success: … bus.ring_count > old bus.ring_count`; drop `nothing_on_failure`; `EVENT_BUS.ring counted: ring_count > old ring_count`; CHAT_LOG `lines_written > old`; CHAT_STORE `is_last: last_event_id >= Result.id`, `one_more: event_count > old event_count`, `contiguous: Result.count < a_limit implies Result.count <= count_after (…)`; RATE_LIMITER frames stated single-threaded only. Keep the exact forms as `ensure then` in MEMORY_CHAT_STORE and prove them in single-threaded Phase 5 tests. Alternative: declare EVENT_BUS, RATE_LIMITER, POLL_WAITER, CHAT_LOG and the stores `separate` and let SCOOP serialize — then the exact forms stand.

### ISSUE 2: Contract evaluation iterates shared collections without the lock
- **LOCATION**: RATE_LIMITER.counts_model (rate_limiter.e 40-42), invariant 142 `never_over: across counts …`; EVENT_BUS.subscribers_model 34-36, invariant 106, subscribe precondition 58; POLL_WAITER invariant 154; EVENT_POLLER.pending_model 43-47 ("a snapshot; not locked"), pending_count 67-70, invariant 149-151, drain postconditions 121-122
- **SEVERITY**: HIGH — **CONFIRMED**
- **DESCRIPTION**: Every long-poll subscribes and unsubscribes, so `subscribe`'s `not_yet` precondition iterates the list on one handler while another handler's `extend` reallocates it — a torn read caused by assertion monitoring. On the client the GUI evaluates EVENT_POLLER's invariant on every qualified call while the worker is inside `pending.extend`.
- **SUGGESTION**: Rule: a model or contract-support query of a locked object acquires that object's lock; invariants keep scalar clauses only; the "never over" / "consistent" laws become `check`s inside the locked region. Bodies that hold the lock never call the locking queries (EiffelBase MUTEX is not documented re-entrant).

### ISSUE 3: POLL_WAITER's postconditions are evaluated after the lock is released
- **LOCATION**: poll_waiter.e 96-99 (`Result := wakes_since_arm > 0` / `lock.unlock` / `definition: Result = (wakes_since_arm > 0)`), wake 124 `mine_counted`, inherited `counted` (event_subscriber.e 38), receive_status 137-138
- **SEVERITY**: HIGH — **CONFIRMED**
- **DESCRIPTION**: A wake between the unlock and the postcondition makes `False = (1 > 0)`; two posters ringing the same room both capture `old = 0` and the second fails `2 = 0 + 1`. A wake that raises is unsubscribed by the bus — one race kills the poller for the request. The body's lost-/spurious-wakeup handling is correct; only the contracts are wrong.
- **SUGGESTION**: `definition: Result implies wakes_since_arm > 0`; `counted: wake_count > old wake_count`; drop `mine_counted`, `others_ignored`, `kept_when_mine` (single-threaded Phase 5 tests keep them).

### ISSUE 4: EVENT_POLLER.poll_once `older_kept` compares two snapshots taken under two lock acquisitions
- **LOCATION**: event_poller.e 109
- **SEVERITY**: HIGH — **CONFIRMED**
- **SUGGESTION**: delete; `check queued: pending.count = l_before + l_accepted end` inside the locked region; keep only worker-owned facts in the postcondition.

### ISSUE 5: EVENT_POLLER extends `pending` before advancing `cursor`
- **LOCATION**: event_poller.e 92-93 (`pending.extend (e)` then `cursor := e.id`) vs invariant `pending_at_or_below_cursor`
- **SEVERITY**: HIGH — **CONFIRMED**
- **SUGGESTION**: swap the two lines (cursor only grows, so every instant satisfies the invariant); `pending_model` and `pending_count` take the lock; `drain` proves `handed_over`/`emptied` as `check`s under the lock and keeps postconditions on `Result` alone (`in_order`, `at_or_below_cursor`).

### ISSUE 6: wait_for_events forbids the very thing it waits for
- **LOCATION**: chat_service.e 189 `nothing_appended: store.last_event_id = old store.last_event_id`
- **SEVERITY**: HIGH — **CONFIRMED** (wrong by construction: satisfiable only on the timeout path)
- **SUGGESTION**: delete.

### ISSUE 7: RATE_LIMITER.record's precondition is a check-then-act race and forbids the atomic form
- **LOCATION**: rate_limiter.e 104-114 (`require allowed: is_allowed (a_key)`), invariant 142
- **SEVERITY**: HIGH — **CONFIRMED**
- **SUGGESTION**: `try_record (a_key): BOOLEAN` deciding and counting under the lock (`granted_counted`, `refused_at_limit`); `is_allowed` advisory only; CHAT_SERVICE uses `if limits.try_record (…)`.

### ISSUE 8: CHAT_STORE.add_user's `fresh_username` is check-then-act, and the schema has no UNIQUE on usernames or memberships
- **LOCATION**: chat_store.e 158; chat_schema.e 7-10 (UNIQUE only on `session.token_hash`)
- **SEVERITY**: HIGH — **ACCEPTED**
- **SUGGESTION**: `user.username UNIQUE`, `membership (room_id, user_id) UNIQUE` in the schema; `add_user` becomes outcome-reporting (`CHAT_RESULT [CHAT_USER]`) or the service serializes registration — a precondition cannot serialize.

### ISSUE 9: Subscribers do real work on the ringing thread — the dispatcher re-enters itself through the doorbell; SSE_STREAM does client I/O on the poster's thread with no lock
- **LOCATION**: participant_dispatcher.e 57, 70 (`unseen: a_event.id > cursor`), 72; event_bus.e 81 ("snapshot under lock, release, wake each"), 7-8; sse_stream.e 81-87, 73-79, 94-102, 129-133
- **SEVERITY**: HIGH — **CONFIRMED** (deterministic, not a race)
- **DESCRIPTION**: `ring` wakes subscribers synchronously on the poster's thread. The dispatcher's answer is a post → `ring` → `wake` re-entered on the same thread mid-loop → the outer loop resumes and `handle_event` fires `unseen` → the bus unsubscribes the dispatcher and every participant goes silent. Two rooms posting at once give two concurrent wakes over one global cursor. SSE: two concurrent wakes deliver the same page twice; a heartbeat interleaves bytes; a slow client's TCP back-pressure stalls every poster — snapshotting the subscriber list avoids the bus lock, not the synchronous call-out (intent Q2's promise is false as written).
- **SUGGESTION** (synopsis decision D2): `wake` only records the room and broadcasts (`pending_rooms_model: MML_SET [INTEGER_64]`; for SSE embed a POLL_WAITER); a worker per dispatcher and the owning handler thread per SSE stream do the work; per-room cursors (`cursors_model: MML_MAP`); `handle_event` idempotent (drop `unseen`, ensure `skipped_when_seen`); `answered_model: MML_SET` with `seen_once`.

### ISSUE 10: EVENT_BUS.ring's frame contradicts its own raise-handling rule and the long-poll subscribe pattern; unsubscribe's precondition turns that into a second exception
- **LOCATION**: event_bus.e 7, 84 (`subscribers_unchanged`), 93, 67 (`present`); chat_service.e 185
- **SEVERITY**: HIGH — **CONFIRMED**
- **SUGGESTION**: drop the frame; idempotent `subscribe`/`unsubscribe` (`added: subscribers_model.has (…)`, `removed: not …`); give the bus a CHAT_LOG; catch only non-assertion exceptions from subscribers.

## Theme B — Contracts that are wrong by construction (unsatisfiable, vacuous, or naming the wrong thing)

### ISSUE 11: authenticate's `failure_counted` is unsatisfiable at the lockout boundary; the per-IP key is promised but uncontracted
- **LOCATION**: chat_service.e 69 vs rate_limiter.e 107 and invariant 142; `login_ip_key` 324 used nowhere in a clause
- **SEVERITY**: HIGH — **CONFIRMED**
- **SUGGESTION**: `failure_counted: (not Result.is_success and old limits.is_allowed (…)) implies limits.count (…) > old …`; add `ip_locked_out_stays_out`, `ip_failure_counted`.

### ISSUE 12: create_user / create_bot `unique_or_error` is an equality
- **LOCATION**: chat_service.e 248, 263
- **SEVERITY**: HIGH — **CONFIRMED** (a fresh username must succeed; a store error or the Phase 1 stub violates it; two concurrent admins both capture `old has_username = False`)
- **SUGGESTION**: `duplicate_refused: old store.has_username (…) implies not Result.is_success`; `success_is_fresh: Result.is_success implies not old store.has_username (…)`.

### ISSUE 13: One limiter window cannot express per-minute / per-10-minute / per-hour
- **LOCATION**: rate_limiter.e 20-24 (`make (a_window_seconds)`), 92; simple_chat_server.e 23 `create limits.make (3600)`; server_config.e 97-99
- **SEVERITY**: HIGH — **CONFIRMED**
- **SUGGESTION**: `set_limit (a_prefix, a_limit, a_window_seconds)`, `windows_model`, `window_for`; the facade's `start` ensures each configured pair.

### ISSUE 14: A limiter that never limits passes every contract; there is no rate-limit or lockout test
- **LOCATION**: rate_limiter.e 67-69; chat_service.e 109; chat_assault.e 414-453
- **SEVERITY**: HIGH — **CONFIRMED**
- **SUGGESTION**: `matching_prefix (a_key)` + `limit_for ensure by_prefix`; `post_message ensure recorded_on_success`; Phase 5 `test_post_rate_limit_refuses_past_the_limit`, `test_login_lockout_boundary`.

### ISSUE 15: The dispatcher's contract never mentions the rate limit; `always_answers` counts a self-incremented integer
- **LOCATION**: participant_dispatcher.e 74-80; spec 05 lines 192-195 had `rate_limited_not_asked` / `asked_once`
- **SEVERITY**: HIGH — **CONFIRMED**
- **SUGGESTION**: pure `target_of (a_event)`; `rate_limited_not_asked`, `asked_once`, `limit_recorded`, store-observed `always_answers`, `via_charged`.

### ISSUE 16: The dispatcher starts at `cursor = 0` — a restart re-answers history
- **LOCATION**: participant_dispatcher.e 35
- **SEVERITY**: HIGH — **CONFIRMED**
- **SUGGESTION**: `make (…; a_start_after)` ensure `starts_where_told`; the facade passes `store.last_event_id`.

### ISSUE 17: SSE_STREAM.deliver_pending compares a per-room cursor with the store-wide id
- **LOCATION**: sse_stream.e 78 `caught_up_or_closed: last_delivered_id >= store.last_event_id or else not is_open`
- **SEVERITY**: HIGH — **CONFIRMED** (false for every correct implementation once a second room exists)
- **SUGGESTION**: drop; `delivered_model: MML_SEQUENCE [INTEGER_64]` with `strictly_increasing`, `starts_after_since`, `extended` (prefix preserved) on EVENT_SOURCE — which also gives "each exactly once" a contract it lacks today.

### ISSUE 18: SSE_STREAM.open's documented plan (replay inside open) violates the inherited `starts_at_since`
- **LOCATION**: sse_stream.e 64 vs event_source.e 42
- **SEVERITY**: HIGH — **ACCEPTED**
- **SUGGESTION**: `open` sets state and writes the preamble; the handler calls `deliver_pending`.

### ISSUE 19: events_since does not guarantee a gap-free page when the page is full
- **LOCATION**: chat_store.e 113 (`contiguous` is vacuous for a full page: {1,2,3,4,5} → [1,3,5] passes; the client's cursor moves to 5 and 2 and 4 are lost forever)
- **SEVERITY**: HIGH — **CONFIRMED**
- **SUGGESTION**: `gapless: Result.count > 0 implies count_after (a_room_id, a_since_id) - count_after (a_room_id, Result.last.id) = Result.count` (monotone-safe since events are never deleted).

### ISSUE 20: events_before does not say which events — the oldest N satisfy it
- **LOCATION**: chat_store.e 116-128
- **SEVERITY**: HIGH — **CONFIRMED** (a `WHERE id < ? ORDER BY id LIMIT ?` without DESC passes everything)
- **SUGGESTION**: `count_before`; `newest: Result.count = a_limit.min (count_before (…))`; `adjacent: … count_before (a_room_id, a_before_id) - count_before (a_room_id, Result.first.id) = Result.count`.

### ISSUE 21: add_membership accepts duplicates but `membership_model.same_count` forbids them
- **LOCATION**: memory_chat_store.e 76-79 (`MML_RELATION.extended` adds if absent; `count` = distinct pairs) vs chat_store.e 243-251 (no `not is_member` precondition)
- **SEVERITY**: HIGH — **CONFIRMED** (two calls → the model query fails its own postcondition)
- **SUGGESTION**: `require not_already: not is_member (…)`; `unique_pairs` invariant; memberships and attachments added to `models_consistent`; schema UNIQUE.

### ISSUE 22: CHAT_CLIENT.post_message `echoed` asserts the server's honesty
- **LOCATION**: chat_client.e 163, 169 (the body never checks `e.room_id`; a 201 echo for room 2 → POSTCONDITION_VIOLATION on the GUI thread)
- **SEVERITY**: HIGH — **CONFIRMED**
- **SUGGESTION**: check `e.room_id = a_room_id and e.is_message` in the body and answer 502 otherwise; keep `echoed`, add `message_kind`.

### ISSUE 23: The memory oracle has reference semantics; SQLite has value semantics
- **LOCATION**: memory_chat_store.e 213, 223; chat_user.e 78-83 (`set_active`), chat_session.e 56-64 (`touch`)
- **SEVERITY**: HIGH — **ACCEPTED**
- **DESCRIPTION**: `u.set_active (False)` on an object from the memory store changes the store with no command; a service body that forgets `update_user` passes every oracle test and loses the deactivation against SQLite. The oracle is blind on exactly the paths that matter.
- **SUGGESTION** (synopsis decision D5): the oracle stores and returns twins; `update_user ensure persisted: attached user (a_user.id) as u and then (u.is_active = a_user.is_active and …)` in the deferred class — or remove the domain setters and add explicit store commands.

### ISSUE 24: An image event can be appended with an unstored attachment (id 0) — a dangling row and an invariant violation on read-back
- **LOCATION**: chat_store.e 76-79; chat_event.e 30, 113; chat_attachment.e 76 (`id_non_negative`)
- **SEVERITY**: HIGH — **CONFIRMED**
- **SUGGESTION**: `attachment_stored: attached a_draft.attachment as a implies (a.id > 0 and attached attachment (a.id))` on `append_event`; `attachment_stored` in CHAT_EVENT's invariant; `> 0` in the codec.

### ISSUE 25: PASSWORD_HASHER.hash's `never_plaintext` is false for legal short passwords
- **LOCATION**: password_hasher.e 29-30, 37 (`hash ("0")`: the iterations field "600000" contains "0")
- **SEVERITY**: HIGH — **CONFIRMED**
- **SUGGESTION**: precondition `Minimum_characters = 8` (matches `password_minimum_sane`) or condition the clause; note it stays probabilistic.

### ISSUE 26: No runtime bound on the Ollama participant and shaper; the Claude participant's `timeout_seconds` has no contract
- **LOCATION**: ollama_participant.e 16, 41-46; ollama_shaper.e 16, 41-45; claude_code_participant.e 47, 54-59
- **SEVERITY**: HIGH — **ACCEPTED**
- **SUGGESTION**: `timeout_seconds`, `elapsed_seconds`, `last_timed_out` on every engine; `bounded_runtime`, `timeout_is_error`; state that the bound is advisory until simple_process can kill — no clamp may make it true by construction.

### ISSUE 27: `no_orphan` is satisfiable by forgetting the child
- **LOCATION**: caddy_front_door.e 68-71 (`Result := process /= Void`), 87-92 (`process := Void`); front_door.e 72
- **SEVERITY**: HIGH — **CONFIRMED**
- **SUGGESTION**: `has_child_process = attached process as p and then p.is_running`; `stop ensure child_gone`; invariant `serving_has_child`; `start ensure caddyfile_written`.

## Theme C — "Never raises on bad input" is broken by hostile input

### ISSUE 28: The decoder violates CHAT_ERROR.make's preconditions — a server reply becomes an exception
- **LOCATION**: chat_client.e 269-275 (`error_of`'s else branch passes `a_reply.status`), chat_json.e 311-314 (`error_from_bytes`: message may be empty; status unchecked); chat_error.e 21-22 (`message_given`, `is_error_status: 400..599`)
- **SEVERITY**: HIGH — **CONFIRMED**
- **DESCRIPTION**: A captive-portal `200 <html>` on login, a `302` on post, a `200 {"code","message"}` for `members`, or a 4xx `{"code":"x","message":""}` each end in a PRECONDITION_VIOLATION — on the Phase 4 worker thread, with no rescue.
- **SUGGESTION**: `error_of`: `elseif a_reply.status < 400 then 502 "not what was expected"`; ensure `error_status: 400..599`; `error_from_bytes` requires an error status and demands a non-empty message.

### ISSUE 29: Non-Latin-1 text in "ASCII" wire fields reaches `to_string_8`; so does a username on the login path
- **LOCATION**: chat_json.e 162, 165, 167, 199-200, 219, 303, 314; chat_service.e 321 (`login_user_key: … .as_lower.to_string_8`, evaluated inside `old` at 68-69)
- **SEVERITY**: HIGH — **CONFIRMED** (EiffelBase `READABLE_STRING_GENERAL.to_string_8` requires `is_valid_as_string_8` — verified in the installed library)
- **SUGGESTION**: a private `ascii_item (obj, key): detachable STRING_8` (Void unless all codes < 128) for kind, created_at, mime, sha256, username, token, code; `login_user_key` via `{UTF_CONVERTER}.utf_32_string_to_utf_8_string_8`; `authenticate` refuses invalid usernames with a 401 result before any lookup and adds `bots_and_inactive_refused`.

### ISSUE 30: `created_at` is parsed without validation
- **LOCATION**: chat_json.e 167 (`make_from_iso8601` → `make_from_string`, no validation — verified in simple_datetime)
- **SEVERITY**: HIGH — **CONFIRMED**
- **SUGGESTION**: an `is_iso8601` shape check before construction (Void otherwise); `time_kept` postcondition if the round trip is exact.

## Theme D — Security contracts missing

### ISSUE 31: The argv gate has no postcondition on the shaped path — vacuous whenever a query shaper is configured
- **LOCATION**: tool_participant.e 67 (`… and query_shaper.cost_tier = {SHAPER}.Tier_none) implies not Result.is_success`), 77 (`all_safe` is a precondition of a deferred feature)
- **SEVERITY**: HIGH — **CONFIRMED**
- **SUGGESTION**: `executed_arguments` + `executed_model: MML_SEQUENCE`; `run_tool ensure recorded`; `answer ensure only_safe_ran: across executed_arguments as a all is_safe_argument (a) end`, `raw_gate`, `shaped_gate`.

### ISSUE 32: `refused_when_unsafe` / `phrasing_disclosed` bind to the configured shapers and ignore `via`
- **LOCATION**: tool_participant.e 67, 70; participant_request.e 41
- **SEVERITY**: HIGH — **CONFIRMED** (`… via @qwen` on a plain tool is contractually refused; `… via plain` on a `@qwen` tool must carry a false "phrased by" footer)
- **SUGGESTION**: `effective_query_shaper (a_request)` / `effective_response_shaper (a_request)`, `last_response_shaped`; `no_false_disclosure`, `shaper_failure_is_error`.

### ISSUE 33: `@claude` runs `claude -p` in the vault with tools and memory; `image_path` is a model-chosen path the dispatcher will read and post
- **LOCATION**: claude_code_participant.e 3-7, 22-23, 58; participant_answer.e 17, 43
- **SEVERITY**: HIGH — **CONFIRMED** — **synopsis decision D3**
- **DESCRIPTION**: The prompt is one argv element, but that argument drives an agent that can run Bash and read MEMORY.md; nothing pins its tool policy. `image_path` is whatever the model returns and `store_upload` accepts any PNG/JPEG: a prompt-injected `C:\Users\…\Pictures\x.png` is exfiltrated to the room. The vault as working directory exposes private notes to anyone who can type `@claude`.
- **SUGGESTION**: `PARTICIPANT_ANSWER.is_safe_image_path` (relative, no `..`, no drive/UNC, `.png`/`.jpg`, ≤ 200) as precondition + invariant; the dispatcher resolves only under `<data_dir>/participants/<handle>/`; `tools_disabled` invariant; a dedicated working directory with a curated CLAUDE.md — not the vault, not MEMORY.md.

### ISSUE 34: `sha256` and `stored_relpath` are checked by length and prefix only — `uploads/../../x.png` satisfies the invariant on the server and in the rebuilt client path
- **LOCATION**: chat_attachment.e 24-25, 80-81; chat_json.e 206-207
- **SEVERITY**: HIGH — **CONFIRMED**
- **SUGGESTION**: `is_sha256_hex` (64 × `0-9a-f`) in CHAT_ATTACHMENT_RULES, used in `hash_shape` and the codec; `path_pinned: stored_relpath.same_string (Uploads_prefix + sha256 + extension_of (mime))` as invariant; compute the path in `make` so no caller can choose a name.

### ISSUE 35: The bot flag is whatever the draft's creator passed — unmarked bot messages are possible, and the marker is forgeable by humans
- **LOCATION**: chat_store.e 79 (`sender_exists` only), chat_event.e 9-10 ("no path through the system can post one without it"), 114 (`marked_when_bot` conditioned on `is_bot_authored`); chat_service.e 107 (`marker_enforced` for bots only)
- **SEVERITY**: HIGH — **CONFIRMED** — **synopsis decision D4**
- **SUGGESTION**: `append_event require bot_flag_truthful: system or (attached user (a_draft.sender_id) as u and then u.is_bot = a_draft.is_bot_authored)`; `post_message ensure humans_unmarked: (Result.is_success and not a_sender.is_bot …) implies not e.body.starts_with (Bot_marker)`; clients render bot-ness from `is_bot_authored`, never from the glyph.

### ISSUE 36: The loopback test is a prefix match — `http://localhost@evil.example` gets the token in clear; no contract forbids a Bearer header on an insecure endpoint
- **LOCATION**: client_config.e 95-96; chat_endpoint.e 21, 52, 57; chat_client.e 21-30, 246
- **SEVERITY**: HIGH — **CONFIRMED** (also `http://127.0.0.1.evil.example`, `https://user:pw@host`, a base with `?` — and `is_secure` derives from the `is_local` flag, so a loopback reached via the server list is "insecure")
- **SUGGESTION**: `is_loopback_url` that parses the authority (host ∈ {127.0.0.1, localhost, [::1]}, digits-only port, nothing before the first `/`); `is_acceptable_url` = https with an authority containing no `@`/whitespace/`?`/`#`, or loopback; `CHAT_ENDPOINT.is_secure` from the URL; `CHAT_CLIENT.make require secure`, invariant `never_plaintext`, `exchange require token_over_tls`; `SERVICE_LOCATOR.locate ensure secure`.

### ISSUE 37: Token revocation is uncontracted end to end
- **LOCATION**: chat_service.e 296-301 (`revoke_bot_token`, no ensure), 275; chat_store.e 305-310 (`remove_sessions_of`, no ensure); memory_chat_store.e 344 states `none_left` privately
- **SEVERITY**: HIGH — **CONFIRMED** (a no-op passes everything; no revocation test)
- **SUGGESTION**: `CHAT_STORE.has_session_of`; `none_left`, `revoked`, `sessions_revoked`; Phase 5 `test_revoke_bot_token_denies_the_next_request`.

### ISSUE 38: Chat text can still reach a tool through paths the argv rule does not see, and the rule itself is unspecified
- **LOCATION**: tool_participant.e 36-39 (`is_safe_argument` deferred, no postcondition; whole-text use at 67 vs per-element use at 77); bible_tool_participant.e 48-53, shape_tool_participant.e 47-51 (rules as comments)
- **SEVERITY**: HIGH — **ACCEPTED** (raised from the reviewer's MEDIUM because it is the rule the whole design leans on: nothing forbids empty text, controls, NUL, a leading `-` — option injection needs no shell)
- **SUGGESTION**: `is_safe_argument ensure never_empty, bounded, printable (32..126), no_option (item (1) /= '-')`; SHAPE's rule as a `definition`; `arguments_of (a_text)` pure with `all_safe`, used in both places.

---

## MEDIUM (53) — fix during the repair pass where cheap, otherwise during Phase 4

**Service / bus / web**: STREAM_SINK.write's `open` precondition and exact byte count cannot survive a peer disconnect (`counted_when_open`, `closed_stays_closed`; heartbeat without `open`) · POLL_WAITER.wait deducts a full 250 ms slice regardless and ignores the statuses it is broadcast for (clock-based deadline; exit on statuses; drop `l_slept`) · wait_for_events cannot return the statuses the API promises; per-call waiter and cleanup unspecified (return a page; unsubscribe in a rescue) · POLL_WAITER.statuses exported mutable, read across threads, unmodeled (`{NONE}` + locked snapshot + model) · service room preconditions weaker than the store's (`room_known: store.has_room`) · post_message/post_image do not tie the returned event to their inputs; post_image bypasses the post limit; `e.attachment = a_attachment` is reference equality (`right_event`, `same_attachment` by id) · post_system/publish_status under-contracted (`right_room`, `from_stored`, `EVENT_BUS.last_status`) · session_for_token lacks `right_one` (export `token_hash_of`; `old now`) · `last_error` never cleared → `is_running xor (last_error /= Void)` fails on a second start (clear on start) · set_limit can break `never_over`; `count` purity time-fragile (prune only in commands) · CHAT_LOG never promises what was written was redacted; secret-field rule keyed on `password=` while the wire is JSON `"password":` (`last_line` + `redacted`; rule covers `=`/`:` with optional quote) · client_ip / trusts_forwarded_headers have no trust contract; XFF list handling and header `to_string_8` unspecified (`peer_when_untrusted`, `rightmost_when_trusted`, `definition`, `is_valid_as_string_8` guard, case-insensitive `Bearer`, hex-64 token) · SERVER_CONFIG exports mutable lists; handle uniqueness case-sensitive vs a case-insensitive parser (`{NONE}` lists, `as_lower`) · door and DNS never tied to the config (`door_matches_config`, `dns_matches_config`) · update_user does not say the row now matches; reset_password's `verifiable` checks the in-memory user (`written`/`persisted`) · user-facing rules as preconditions while promising never to raise for a user mistake — synopsis decision D6 · ADDRESS_PARSER `via train`, `@claude,`, `@claudette`, bare `@claude` (`via_shape`, `handle_lowercase`, `handle_no_blank`, `via_known`, `empty_is_plain`) · PASSWORD_HASHER.make never sets the iteration count it guarantees (pin it) · one CHAT_JSON with a mutable `parser` shared by every handler (parser as a local; class stateless).

**Domain / store / config**: password-hash shape is "two `$`" (`is_pbkdf2`) · `original_name` unconstrained (`name_shape`; basename on upload) · exported mutable strings carry the invariants (`e.body.wipe_out` after append; IMMUTABLE_STRING_* or copies; `payload` by copy) · `make_from_file`'s postcondition is a tautology and invalid values silently become defaults (`loaded`, `loaded_or_explained`; the facade refuses `not is_valid`) · `public_name`/DDNS fields spliced into generated files with no shape check (`is_hostname`, `known_provider`) · uniqueness stops at handles — bot usernames and aliases can collide (`unique_bot_usernames`, `unique_addresses`) · kind-specific engine requirements are not invariants (`engine_for_kind`) · a newer database crashes `version_of` (`never_ahead`) instead of being refused · deferred CHAT_STORE commands carry no frames and the class has no invariant (scalar `*_count` queries + scalar frames; `count_vs_last`) · `user`/`room`/`attachment`/`event` lack `consistent`; `users` promises nothing · `update_user` lets a username change bypass `fresh_username` (`same_username`) · `default_room` has no contract though the service's join invariant depends on it (`default_room_id`, `first_room_is_default`) · membership role is write-only (`membership (u, r)`, `role_kept`) · append_event forgets `kind`, `attachment`, `payload` (`same_kind`, `same_attachment`, `same_payload`, stronger `persisted`; `next_id` in the oracle) · the oracle has no referential-integrity invariants (`keyed_by_id`, `keyed_by_hash`, `events_ascending`, `events_reference`, `unique_usernames`) · system events accept a negative `sender_id` (`= 0` exactly) · display names may be invisible, multi-line, or contain C0 controls (reject < 0x20, 0x7F-0x9F, U+200B-U+200F, U+2028-U+202E, U+2060-U+206F, U+FEFF; one implementation).

**Participants / ops**: handle alphabet/case unconstrained; `limit_key`'s `to_string_8` on non-Latin-1 handles (`is_valid_handle` = `@[a-z0-9_-]{1,32}`) · `parse` untied to the body, no boundary rule, handle-only body contradictory (`leading_handle`, `boundary`, `text_in_body`, `via_in_body`) · aliases have no home (registry `aliases_model`, `alias_targets_exist`, `aliases_are_not_handles`; alias shape) · `via` has no runtime home (`shapers_model`, `unknown_via_refused`) · `max_concurrent`/bounded FIFO unstated (`in_flight`, `Max_queue_depth = 8`, `refused_when_full`) · `always_answers` forces a count when the post cannot happen; non-message events reach `limit_key` with asker 0 (`answers_posted`/`answer_failures`, `ignores_non_messages`, `only_member_rooms`) · echo/footer self-reported, jointly unsatisfiable for small limits (`echo_recorded`, `ran_when_success`, `Minimum_reply_characters`) · tool output unbounded (`Output_maximum`) · PARTICIPANT does not require its bot user stored/active (`bot_stored`, `bot_active`, `bot_marked`) · PARTICIPANT_CONFIG invariants vs constructors (`is_complete_for_kind`; `requests_per_hour = 0`) · NO_FRONT_DOOR.check_health resurrects a stopped door (`last_error` from `stop`; `no_silent_start`) · Caddyfile: `public_name` unescaped, `caddy.exe`/`Caddyfile` relative to CWD, no `admin off` (`single_site`, `loopback_only`, `admin_off`, absolute paths under `data_dir`) · `--create-admin` has no contract home (`CHAT_STORE.has_admin`, `create_first_admin`, usage on unknown flags) · one `last_session_id` for all rooms.

**Client**: `pump` postconditions read poller state without the lock (locked `check`s; `shown_some`; lift `shown_model` into CHAT_VIEW) · `page_result` accepts foreign-room events and statuses (`same_room`) · 401 mid-session uncontracted; no backoff — a hot loop against the server (`backoff_seconds`, `session_lost`) · "show the error once" wrong in both directions (a presenter-owned latch) · "`pending` is always ascending" has no contract; `drain.ascending` asserts something else (`pending_ascending`, `in_order`) · token shape is "64 characters", not "64 hex" — CRLF header injection from a hostile server (`is_hex_64`) · `logout` forgets the token only after the exchange (clear first) · no `close_room`; `open_room` twice orphans a poller; `send`/`pump` after `logout` (`close_room`, `open_implies_session`, `EVENT_POLLER.stop`) · `SERVICE_LOCATOR.is_alive` is a side-effecting query (`probe` command + `last_probe_alive`) · `authorized_headers` exported — the token leaves the class through a public query (`{NONE}`) · the assault proves "token never in a URL" for one GET only; `requests_model`/`mentions` unused; ten missing tests · one CHAT_CLIENT/transport shared by worker and GUI (`last_status`, parser, `token`, `exchange_count` race; `logout` during a poll violates a precondition on the worker) — one client per thread (`for_worker`), `EVENT_POLLER.stop`, drop `last_status`.

## LOW (~30) — polish, listed in the cluster files
`update_url.no_token` predicate; `limit_key` prefix collision; PARTICIPANT_REQUEST looser than ADDRESSED_REQUEST; SHAPING_BRIEF frame and exported `examples`; missing frames on small commands; mutable STRING_32 registry keys; NO_FRONT_DOOR.make accepts a doored config; `bounded_runtime`/`timed` restate the invariant; dispatcher postconditions reference `{NONE}` features; EVENT_BUS models subscribers with `~`; SSE record shape (`"id: 1"` prefix of `"id: 10"`); store_upload's 4-of-8 PNG bytes; duplicated username/display rules; health conflates unconfigured with failing; config edge values (`ai_requests_per_hour = 0`, `Door_eiffel`, `Door_none` needing a door object); `store_open` invariant after stop; bot marker prepended after `within_limit`; three PBKDF2 runs per `change_password` with assertions on; `SESSION_ISSUER.issue`'s derivable argument; `has_hex_run` masks sha256 in upload logs; `POLL_WAITER.wait` as a blocking query; `count` vs `counts_model [k]`; attachment on a message/system event; CHAT_EVENT_DRAFT's 2-of-6 invariant; creation postconditions omitting arguments; domain setters without frames; uneven memory-store frames and an invariant calling `event_count` whose precondition does not hold after `make`; constants aliased into mutable attributes (`Door_none`, `Shaper_none`); `lock_attached` tautology and MUTEX-recursion assumption; wire attachment id 0 and fabricated uploader/time; `page_from_bytes` ignores `last_id`; `CHAT_ERROR.code` unrestricted; weak postconditions on `mention`, `ai_enabled`, `has_participant_handle`, `allows_via`, `has_alias`, `count_after`; CHAT_STATUS unbounded; session flags/ownership untied; room names by count only; `has_participant_handle` case; display-name length vs bytes on read-back; CHAT_RESULT for detachable/expanded G; public mutable client structures; system events counted as unread ("#0"); unbounded status queue; missing client postconditions/frames; runner counts skeletal tests as PASS, no assertion tag; `set_server_url` discards standbys; display-name collisions.

## INFO
No `MML_MAP.has` misuse anywhere; model kinds are right except `aliases_model`/`allow_via_model` (sequences with set semantics) and `membership_model` (relation vs a list that may hold duplicates — Issue 21); `models_consistent` invariants are tautologies over the builders; `PARTICIPANT.answer`, `SHAPER.shape`, `EVENT_POLLER.drain`, `POLL_WAITER.wait` and every CHAT_RESULT-returning command are CQS hybrids by design — record for the Phase 4.5 audit; CHAT_API's twenty handlers carry no contracts and are where the precondition guards will live; the SSE catch-up loop is unbounded under sustained posting; CHAT_SERVICE.make creates three SIMPLE_ENCRYPTION instances; the SCOOP consumer test never touches the client cluster; a human quoting "Claude: …" at line start triggers the alias; design choices to confirm at the gate: a bot may be admin, `CHAT_MEMBER` carries no `is_active`, no attachment dedup by sha256, `localhost_only` is effectively a constant.

## Assault gaps named by the reviewers (Phase 5)
Rate limit past the limit; login lockout boundary; token revocation denies the next request; mixed-case/prefix-spoof handles; handle-only body; `via` unknown / `via plain` disclosure; restart cursor; re-entrant wake (two threads); a human message starting with 🤖; `stop` after a real child; `image_path` outside the output directory; `kind = bible_tool` with empty `executable`; uppercase/non-hex sha256 and `../` inside it; empty error message; non-error status into `error_from_bytes`; unparseable `created_at`; non-Latin-1 in kind/username/token; attachment on a message event; negative `sender_id`; duplicate memberships; gaplessness of `events_since` on a full page; recency of `events_before`; `update_user` with a changed username; mutation of a store-returned user; token never in URL/body across all requests; wait 0 → timeout 5; locator with no server; non-ascending page; foreground toggled mid-pump; foreground pump receiving another's message; `load_roster`; login on a non-JSON 200; post echo for another room; logout on a transport failure; `page_from_bytes` with a foreign-room event; the retained-wake property with two threads.
