# Phase 2b — targeted re-review: bus + web + facade + ops (+ door, apps/server, tests)
# Date: 2026-08-31 · main 5188754 · reviewer: adversarial contract re-review after passes 1b/1c
# Scope: src/bus/*, src/web/*, src/facade/simple_chat_server.e, src/participants/dispatcher_host.e,
#        src/door/*, apps/server/*, apps/server/ops/*, testing/ops_assault.e, test_scoop_consumer.e,
#        bus/SSE tests of chat_assault.e. Issue numbers = phase2-claude-response.md; M-* = cluster-file MEDIUMs.

## The question the re-review was ordered for

**Does `CHAT_REQUEST_HANDLER.handle_wait` hold the API while blocking? NO.**
chat_request_handler.e 240 subscribes via `api_subscribe (shared_api, t, l_room, l_waiter)` (API + waiter
locked only for that call), 244 reads via `api_events (shared_api, ...)` (ditto), 249 blocks in
`l_wait.wait_for (l_waiter)` — POLL_WAIT.wait_for (poll_wait.e 42-53) has exactly one separate formal,
the waiter; `shared_api` is not an argument of any blocking call, so the API processor serves other
requests throughout the wait. The wait condition `ready: a_waiter.is_ready` is satisfied by the bus's
async `wake` or by POLL_ALARM (which sleeps holding nothing — poll_alarm.e 47-51 — and locks the waiter
only inside `expire`, 61-65). Matches approach.md §8 / addendum §2 exactly.

---

## Adjudicated findings (orchestrator HIGHs whose LOCATION is in this cluster)

### Issue 1: exact "+1"/"unchanged" postconditions on shared state (bus/web portion)
- LOCATION: event_bus.e 83-85, 94-95, 110-111, 122-123; chat_api.e (every `counted`); poll_waiter.e
- VERDICT: **FIXED**. One processor owns each object (bus+limiter+store inside the API processor,
  chat_shared.e 21-25; waiter on its own), every cross-processor entry is a separate formal, so exact
  arithmetic is sound again.

### Issue 2: contract evaluation iterates shared collections without the lock
- LOCATION: event_bus.e 156-160 (invariant), 37-46 (model); poll_waiter.e statuses
- VERDICT: **DISSOLVED**. Only the owning processor ever evaluates these assertions; there is no
  second thread to tear the collection.

### Issue 3: POLL_WAITER postconditions evaluated after the lock is released
- LOCATION: poll_waiter.e 94-97, 104-107; event_subscriber.e 44
- VERDICT: **DISSOLVED**. No lock exists; `wake`/`time_out`/`receive_status` are serialized on the
  waiter's processor, so `mine_counted`, `counted`, `kept_when_mine` are exact and satisfiable.

### Issue 9: subscribers do real work on the ringing thread; SSE I/O on the poster's thread
- VERDICT: **FIXED**. event_bus.e 143-149: `wake_one` is an asynchronous command to a `separate`
  subscriber — posters never stall. SSE_STREAM is an EVENT_SOURCE driven only by the request's
  handler (sse_stream.e 3-9); it is never subscribed to the bus.

### Issue 10: ring's frame vs the raise-rule; unsubscribe's precondition
- VERDICT: **FIXED**. No raise-unsubscribe rule survives (event_bus.e 10-13); `unsubscribe` has no
  precondition and its `removed` post is MML-idempotent (94); `subscribers_unchanged` (111) is now
  truthful because nothing can mutate the map mid-ring on one processor. Tickets are never reused
  (`last_ticket` strictly increases, 78-83; overflow horizon ~decades at pool rate).

### Issue 16: dispatcher restart re-answers history (API/host side)
- VERDICT: **FIXED**. chat_api.e 393-400 `dispatcher_start_after = store.last_event_id`;
  dispatcher_host.e 59 passes it into `make (a_api, a_api.dispatcher_start_after)`
  (participant_dispatcher.e 50 confirms the signature); facade launches before the web face starts
  (simple_chat_server.e 95-103), so nothing can land between the snapshot and the subscription.

### Issue 17: SSE deliver_pending compares a per-room cursor with the store-wide id
- VERDICT: **FIXED**. `deliver_pending` and `caught_up_or_closed` are gone; delivery is
  `delivered_model` + the inherited `extended`/`prefix_kept`/`advanced` (event_source.e 68-72),
  exercised by test_sse_stream_delivers_in_order (chat_assault.e 259-282).

### Issue 18: open's replay plan violates `starts_at_since`
- VERDICT: **FIXED**. sse_stream.e 70-79: open writes only the preamble; `nothing_yet` and
  `starts_at_since` hold; the handler drives catch-up through `deliver`.

### Issue 27: `no_orphan` satisfiable by forgetting the child
- LOCATION: caddy_front_door.e 90-94, 135-145, 147-158, 177-183
- VERDICT: **PARTIAL**. `has_child_process` is now the maintained liveness flag `child_is_alive`
  (not the reference test), and `serving_has_child` (180), `child_when_serving` (132),
  `serving_means_alive` (157), `child_gone` (144) exist. But `stop` still proves the kill by flipping
  the flag it is judged by — honest only because the class note (13-16) declares the simple_process
  wait/kill dependency and promises `last_error`; the current body does not set `last_error` on an
  unprovable kill. Condition for Phase 4: when the real kill lands, derive `child_is_alive` from the
  process handle (`attached process as p and then p.is_running`) and have `stop` set `last_error`
  when the wait cannot confirm exit.

### Issue 29: non-Latin-1 input reaches `to_string_8` (web/app side)
- VERDICT: **FIXED**. Handler passes login credentials as STRING_32 end to end (chat_request_handler.e
  179; chat_api.e 98-107 copies with `local_32`); admin usernames pass `ascii_of` (557-565); SERVER_APP
  gates `--create-admin` on `is_valid_as_string_8` first (server_app.e 82-85).

### Issue 37 (API surface only): revocation
- VERDICT: **FIXED at this layer**. `logout` ensures `revoked: session_for (...) = Void`
  (chat_api.e 135-138); the store/service half was the domain cluster's re-review.

---

## Cluster-file MEDIUM/LOW items in this cluster

### M-A: STREAM_SINK.write exact byte count cannot survive a mid-stream disconnect
- VERDICT: **PARTIAL**. stream_sink.e 29-36 still promises `counted: bytes_written = old + a_text.count`;
  WEB_STREAM_SINK counts unconditionally (40-44) — satisfiable today (counting accepted bytes) and in
  Phase 4 only under a "bytes accepted into the buffer" reading. Condition: when the real streaming
  write lands, either document that reading in STREAM_SINK or weaken to
  `counted_when_open: is_open implies bytes_written = old bytes_written + a_text.count` with
  `closed_stays_closed: not old is_open implies not is_open`.

### M-B: POLL_WAITER.wait mis-accounts time and ignores statuses
- VERDICT: **DISSOLVED**. The polling `wait` is gone; POLL_WAIT's wait condition + POLL_ALARM replace
  it, and statuses ride out as `statuses_json` (poll_waiter.e 59-65, poll_wait.e 48) into
  `api_events (..., l_wait.statuses_json)` (handler 250).

### M-C: waiter lifetime / unsubscribe in a rescue
- VERDICT: **PARTIAL**. Per-request waiter: yes (handler 239). Idempotent unsubscribe: yes. But
  handle_wait (241-253) has **no rescue**: an exception between `api_subscribe` and `api_unsubscribe`
  (a store failure inside the second `api_events`, an assertion violation) leaks the subscription
  forever — the bus then wakes a dead waiter on every ring and the waiter's processor never collects.
  SUGGESTION (Phase 4, exact shape):
  `rescue if l_ticket > 0 then api_unsubscribe (shared_api, l_ticket) end` with a local retry-guard
  so the handler answers 500 rather than dying subscribed.

### M-D: POLL_WAITER.statuses exported mutable — **FIXED** (now `{NONE}`, poll_waiter.e 118-122;
  only the JSON snapshot is exported).

### M-E: `last_error` never cleared — **FIXED** (chat_web_app.e 58 clears on start;
  simple_chat_server.e 111-115; front_door.e 68 `cleared_on_success`).

### M-F: client_ip / forwarded-header trust contracts
- VERDICT: **PARTIAL**. `peer_when_untrusted` exists (handler 88) and `trusts_forwarded_headers` is
  hard False until simple_web exposes the peer (91-95) — conservative and honest. Still missing:
  the `definition` clause on trust and `rightmost_when_trusted` once the peer lands. Consequence
  worth naming: until then every client is `127.0.0.1` (84), so the per-IP login lockout is one
  shared bucket — ten failures by anyone lock login for everyone in the window. Acceptable for a
  Phase-1 skeleton; must be re-verified when simple_web's peer-address task closes.

### M-G: door and DNS never tied to the config they must agree with
- VERDICT: **OPEN** (small). CADDY_FRONT_DOOR.make requires kind+hostname (caddy_front_door.e 30-34)
  but the facade accepts any FRONT_DOOR against any config: `set_front_door` (simple_chat_server.e
  48-57) has no consistency clause and `start` never asserts `door_matches_config`. SUGGESTION:
  on `start`, `ensure door_agrees: (attached config as c and attached front_door as d) implies
  (c.is_public = d.is_public)` — or a require on `set_front_door` once SERVER_CONFIG exposes the kind.

### M-H: CHAT_API had no contracts / handler guards — **FIXED**. Twenty routes registered and counted
  (handler 30-58, `Route_count = 20`), every handler funnels through `reply` (522-528) which sets
  nosniff on every response; CHAT_API now carries per-answer postconditions (counted / needs_session /
  bounded / token_only_on_success ...).

### M-I: NO_FRONT_DOOR.check_health resurrects a stopped door — **FIXED**
  (no_front_door.e 77-84 `unchanged: is_serving = old is_serving`; test_null_door_stays_stopped).

### M-J: Caddyfile injection / CWD-relative paths / admin off
- VERDICT: **PARTIAL** (injection and admin: fixed; paths: half). `caddyfile_text` (61-79) is
  provably one site (`occurrences ('{') = 3` is sound because `public_name` is invariant-validated
  as a lowercase hostname — front_door.e 88-120 rejects `{`, space, uppercase), `admin off` leads,
  upstream is literal `127.0.0.1`, exactly one `reverse_proxy`, and ops_assault covers the injection
  attempt (45). Remaining: `executable := cwd + "caddy.exe"` (41) is absolute-ized CWD — it still
  runs whatever caddy.exe sits in the working directory. Fine when the service's CWD is the install
  dir; `set_executable` (112-121, requires absolute) is the escape hatch. Condition: SERVER_APP's
  Phase-4 wiring should set the executable from config or the install dir explicitly, not inherit CWD.

### M-K: `--create-admin` rules — **FIXED** (server_app.e 27-39 argument discipline: flag-with-name,
  unknown `--flag` → usage, validation before to_string_8; the has-admin refusal lives in
  CHAT_SERVICE.create_first_admin per 1c).

### M-L: SERVER_CONFIG exported mutable lists — **FIXED** as observed from this cluster
  (test_config_lists_are_copies, ops_assault.e 81-91, proves the copy).

### LOW sweep
- EVENT_BUS `~`-equality on subscribers — **FIXED** (integer tickets; the bus never compares
  subscribers, event_bus.e 10-13).
- SSE record shape / injection — **FIXED** (`terminated`, `carries_id`, `one_record`,
  sse_stream.e 118-135; JSON escaping keeps newlines out of `data:`).
- `update_url.no_token` wrong predicate — **FIXED** (duckdns_updater.e 52 `not Result.has_substring
  (token)` + invariant 79; exact-string test ops_assault.e 72). One satisfiability nit: a pathological
  token that is a substring of the URL text (e.g. a 1-2 character token, or `"****"`) falsifies the
  invariant at creation. SUGGESTION: `require token_plausible: a_token.count >= 8` on make.
- NO_FRONT_DOOR.make accepts a doored config — **FIXED** (require `none_configured`, 23-25).
- Door edge values (`Door_eiffel` with no class; `Door_none` needs an object) — **FIXED**
  (EIFFEL_FRONT_DOOR answers 503 honestly; NO_FRONT_DOOR exists and serves).

---

## NEW defects found in this pass

### NEW-1 (MEDIUM): facade restart launches a second dispatcher and can violate its own postcondition
- LOCATION: simple_chat_server.e 95-100, 120-121, 135-149
- EVIDENCE: `shared_api` is `once ("PROCESS")` — the API, bus and the first dispatcher's subscription
  survive `stop` (stop only drops the web face and door, 135-149; `dispatcher_host` is never cleared).
  A second `start` in the same process creates a fresh DISPATCHER_HOST and launches a **second**
  dispatcher subscribed to the same bus → every `@handle` answered twice. And if the config toggles
  `ai_enabled` off between runs, the stale `dispatcher_host` attribute falsifies
  `no_dispatcher_unasked` (121) — a wrong-for-correct-code postcondition.
- SUGGESTION: in `start`, launch only when not already launched:
  `if c.ai_enabled and then dispatcher_host = Void and then attached api as a then ...`;
  weaken 121 to `(... not c3.ai_enabled and old dispatcher_host = Void) implies dispatcher_host = Void`
  — or have DISPATCHER_HOST keep the ticket and add `retire (a_api: separate CHAT_API)` called from `stop`.

### NEW-2 (MEDIUM): no request-body size bound before parsing
- LOCATION: chat_request_handler.e 116-120 (json_body), 283-295 (handle_post_image passes
  `a_request.body` whole)
- EVIDENCE: `message_characters` is enforced only after the full body is read and parsed on the API
  processor; nothing in the handler caps `a_request.body.count`. CHAT_JSON's empty/deep guards (1c)
  do not bound length. A 100 MB POST is parsed at full cost; for images the cap is wherever
  simple_web or Phase-4 `store_upload` puts it — neither is contracted here.
- SUGGESTION: first line of `json_body`: `if a_request.body.count > Max_body_bytes then Result := Void end`
  (Max_body_bytes: INTEGER = 65_536) and in handle_post_image refuse
  `a_request.body.count > config-derived upload maximum` with 413 before calling the API.

### NEW-3 (LOW): CHAT_WEB_APP.start claims running before anything is bound
- LOCATION: chat_web_app.e 46-62
- EVIDENCE: `is_running := True` after mere object creation; the port is first touched inside `run`
  (`s.start`, blocking), so a port conflict can never surface through `outcome`/`last_error` — the
  postcondition is satisfied by construction, vacuously honest. Known Phase-4 shape (simple_web must
  report bind failure); record so it is not forgotten.

### NEW-4 (LOW): time-fragile session clauses in CHAT_API postconditions
- LOCATION: chat_api.e 149, 183, 219, 315, 633
- EVIDENCE: `needs_session` / `ticket_when_allowed` re-evaluate `user_for` (wall-clock expiry via
  `session_for_token`) after the body; a session expiring in the microseconds between body and
  postcondition falsifies them for correct code. Vanishingly narrow on one processor, but it is the
  one survivor of the old "now moves" family. SUGGESTION where cheap:
  `needs_session: old (user_for (local_8 (a_token)) = Void) implies Result.status = 401`.

### Observations (no verdict)
- Alarm/waiter processor lifetime is bounded, not zero: an early wake leaves the POLL_ALARM sleeping
  up to 25 s holding the waiter reference — two idle processors per answered poll until the alarm
  fires. At Max_connections = 64 that is bounded and fine; worth a line in approach.md S3.
- The bus's `subscribe` does a synchronous `name_of` query on the new subscriber (event_bus.e 80,
  128-134). It is deadlock-free today only because every subscriber is freshly created and idle when
  subscribed (waiter: handler 239-240; dispatcher: launch's lock chain). Document that rule on
  `subscribe` — a future caller subscribing a busy subscriber while it sync-queries the API would cycle.
- `POLL_ALARM.start`'s precondition `once_only: not has_fired` is a wait condition on an async call —
  a second `start` would deadlock its processor silently rather than fail. Only called once (handler
  247); note for Phase 5's assault.
- test_scoop_consumer builds everything on one processor (compile-compat only); the cross-processor
  long-poll (subscribe → wake → wait_for) has no test yet — the Phase 5 TODOs
  (`test_long_poll_returns_within_deadline`, `test_doorbell_no_loss_under_concurrency`) are the right
  ones and remain mandatory.
- CHAT_REPLY.make_from_separate (chat_reply.e 62-73) is a correct field copy: queries on the locked
  formal, `make_from_separate` for both strings, invariant re-established. Clean.
- EVENT_SOURCE.is_strictly_increasing is total on empty/singleton sequences (event_source.e 76-89);
  invariants hold vacuously at make. Clean.

---

## Verdict count

| Verdict   | Count | Items |
|-----------|-------|-------|
| FIXED     | 18    | Issues 1, 9, 10, 16, 17, 18, 29, 37(API); M-D, M-E, M-H, M-I, M-K, M-L; LOW ×4 (bus ~, SSE shape, update_url, no-door config) |
| DISSOLVED | 3     | Issues 2, 3; M-B |
| PARTIAL   | 5     | Issue 27 (child liveness = flag until simple_process kill/wait); M-A (sink byte count); M-C (no rescue → subscription leak); M-F (trust contract minimal; shared-IP lockout until peer address); M-J (CWD-anchored caddy.exe) |
| OPEN      | 1     | M-G (door/DNS-vs-config consistency clause) |
| NEW       | 2 MEDIUM (NEW-1 restart double-dispatcher, NEW-2 body-size bound) + 2 LOW (NEW-3, NEW-4) |

## Cluster assessment: **PASS WITH CONDITIONS**

The restructuring did what it claimed: the long-poll blocks holding only its waiter (the API is
provably never held across a wait), the bus is fan-out by asynchronous command with idempotent
integer tickets, SSE is handler-driven with a real delivery model, the dispatcher starts after the
store's last id through a clean lock-passing chain, and the ops surface (Caddyfile, DuckDNS masking,
null door, argument handling) is contract-honest with tests behind it. No SCOOP validity error was
found anywhere in the cluster — every separate call goes through a formal or a fresh creation.
Conditions before Phase 3 closes: fix NEW-1 (guard the second launch — three lines) and add the
handle_wait rescue (M-C) now; carry NEW-2, M-A, M-F, M-G, M-J and the Issue-27 kill-proof as named
Phase-4 tasks tied to their dependency items (simple_web peer address + body cap, simple_process
kill/wait); keep the Phase 5 cross-processor doorbell tests mandatory.
