# Phase 2 — cluster review: client stack (src/client, apps/client) + testing (reviewer report, as delivered)
# NOTE: delivery was truncated at the top; the HIGH findings preceding the first item below were requested again and are appended in phase2-claude-response.md once received.

### ISSUE: `CHAT_PRESENTER.pump` postconditions read poller state without the lock (`old pending_count`, `drained`)
- LOCATION: chat_presenter.e lines 162-163 (`shown_all`, `drained`), 56-62, body line 138
- SEVERITY: MEDIUM
- DESCRIPTION: `old pending_count` = 2; the worker appends a third before the drain → three shown → `shown_all` fails. Worker appends after `drain` and before the postcondition → `drained` fails. Both hold only in the single-threaded assault. `shown_all` is count-based: a skip and a double-show cancel out.
- SUGGESTION: `l_drained := p.drain` then `check shown_all … end` after the loop; postcondition `shown_some: view.shown_count >= old view.shown_count`; lift `shown_model` into deferred CHAT_VIEW and check `in_order`.

### ISSUE: `page_result` enforces only half of the server's since-contract — foreign-room events and statuses are accepted
- LOCATION: chat_client.e lines 255-256; chat_store.e line 111 (`all_after: … e.room_id = a_room_id`); chat_presenter.e 148-150 shows every status regardless of room
- SEVERITY: MEDIUM
- SUGGESTION: `page_result` takes `a_room_id`; refuse foreign events (502) and foreign statuses; `same_room` postcondition on `events_since` / `wait_for_events`.

### ISSUE: 401 mid-session has no contract; the token is kept and the poller has no backoff — a hot loop against the server
- LOCATION: chat_client.e 104-106, 124-126; event_poller.e 102-105
- SEVERITY: MEDIUM
- DESCRIPTION: An expired session answers 401 in ~1 ms; the Phase 4 loop calls again — thousands of requests per second into the server's rate limiter (which then locks the account). Same spin on connection refused.
- SUGGESTION: `backoff_seconds` (0 when healthy, doubling, `capped`); `session_lost` set on 401 with `poll_once require not session_lost`; decide by contract whether the client drops the token on 401.

### ISSUE: "Show the connection error once" is wrong in both directions
- LOCATION: chat_presenter.e 151-153 (`consecutive_failures = 1`)
- SEVERITY: MEDIUM
- DESCRIPTION: two fast failures between ticks → never shown; one failure then a 30 s blocked poll → shown every tick. `consecutive_failures`/`last_error` are two worker fields read non-atomically.
- SUGGESTION: presenter-owned latch `reported_outage` (or worker-owned `failure_episodes`).

### ISSUE: "`pending` is always ascending" is a stated law with no contract; `drain.ascending` asserts something else
- LOCATION: event_poller.e 9-10, 123 (`ascending: across Result as e all e.id <= cursor end`), invariant 147-151; chat_assault.e 335
- SEVERITY: MEDIUM
- SUGGESTION: `is_ascending_ids` helper; invariant `pending_ascending`; rename line 123 `at_or_below_cursor`, add `in_order`; test every position.

### ISSUE: Token shape is "64 characters", not "64 hex" — CRLF header injection from a hostile server
- LOCATION: chat_client.e 46, 279, 193; chat_json.e 300
- SEVERITY: MEDIUM
- DESCRIPTION: a 64-code-point token containing CR LF is accepted and injected into every subsequent request's headers; non-Latin-1 code points reach `to_string_8`.
- SUGGESTION: `is_hex_64` in CHAT_JSON; enforce in `login_from_bytes`, CHAT_CLIENT invariant.

### ISSUE: The decode path can raise on hostile fields despite "Decoding never raises on bad input"
- LOCATION: chat_json.e 167 (`make_from_iso8601 (t.to_string_8)`), 165, 314
- SEVERITY: MEDIUM (HIGH if either raises — verify against simple_datetime / EiffelBase)
- SUGGESTION: guard `is_valid_as_string_8` and an `is_iso8601` check before creation; same guards for `kind`, `code`, `username`, `mime`, `sha256`, `token`.

### ISSUE: `logout` forgets the token only after the exchange returns
- LOCATION: chat_client.e 84-86
- SEVERITY: MEDIUM
- SUGGESTION: capture headers, clear the token and `me`, then exchange.

### ISSUE: No `close_room`; `open_room` twice orphans a poller; `send`/`pump` after `logout` violate preconditions one level down
- LOCATION: chat_presenter.e 114-127, 171-178; chat_client.e 153
- SEVERITY: MEDIUM
- SUGGESTION: `close_room`, `open_room require not is_room_open`, `send`/`pump require client.is_logged_in`, invariant `open_implies_session`; `EVENT_POLLER.stop`.

### ISSUE: `SERVICE_LOCATOR.is_alive` is a side-effecting query filed under "contract support"; `last_probe_status` comment is wrong
- LOCATION: service_locator.e 81-100, 36
- SEVERITY: MEDIUM
- SUGGESTION: `probe` command + `last_probe_alive` query; fix the comment.

### ISSUE: `authorized_headers` is exported — the token leaves the class through a public query
- LOCATION: chat_client.e 185-196
- SEVERITY: MEDIUM
- SUGGESTION: move `authorized_headers`/`plain_headers` to `feature {NONE}`.

### ISSUE: The assault proves "token never in a URL" for one GET only; `requests_model` and `mentions` unused; ten missing tests
- LOCATION: chat_assault.e 301-303; memory_http_transport.e 34; http_request_record.e 54; chat_presenter.e 92
- SEVERITY: MEDIUM
- SUGGESTION: `across t.requests as r all not r.url.has_substring (hex64) and not r.body.has_substring (hex64) end` after login; ten listed tests (token across all requests; wait 0 → timeout 5; locator with no server; non-ascending page refused; foreground toggled mid-pump; foreground pump gets another's message → no notice; load_roster; login on non-JSON 200; post_message echo room 2; logout on transport failure).

### LOW: public mutable structures (`server_urls`, `requests`, `CHAT_PAGE.events` kept by reference, `base_url`, `body`, `shown_ids`) — CHAT_ENDPOINT lacks a `no_trailing_slash` invariant; system events count as unread and ring as "#0"; unbounded status queue, status line never cleared, badge on every tick; missing postconditions/frames (`members`, `page_result`, `error_of`, `room_path`, session frames on readers, `set_window`, `load`/`save`, `last_id`, `open_room`, `send`, `remember`/`load_roster`; `last_seen_id` comment); runner counts skeletal tests as PASS and prints no assertion tag, `p.drain` inside an `assert` argument; `set_server_url` discards standbys, `has_url` case-sensitive, `attached_result` tautology, 1xx allowed as final, no body cap; display-name collisions indistinguishable.

### INFO: `SERVICE_LOCATOR.is_alive` concatenates a path outside CHAT_ENDPOINT; CLIENT_CONFIG's DPAPI promise has no field; a 2xx without a page is a 502 (document "always 200 with a page"); SCOOP consumer never touches the client cluster; `drain` is an intentional CQS exception; `mentions` cannot serve as a leak oracle; dead guard `e.id > cursor` in `poll_once`.

Verified correct by the reviewer (no finding): `login.outcome` (because of `logged_out`); `me` stays Void on failure; `logout` forgets on a failed reply; login carries no bearer; `page_result`'s first-id check + CHAT_PAGE `ascending` implies `all_after`; object-test scopes in postconditions and tests are within the rules; wait timeout math; `unread` never counts own messages; `badge_matches` after clear/badge; `load_roster` cannot forget; `snippet_of` on an empty image caption is non-empty; `url_for` safe; duplicate URLs prevented.

(Coverage table: 25 classes; CHAT_CLIENT has no session/endpoint frame conditions on readers, login or logout; EVENT_POLLER's `older_kept` flagged wrong and `drain` racy; CHAT_PRESENTER's `pump` postconditions racy.)
