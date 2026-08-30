# Phase 2b - targeted re-review: client cluster (src/client, apps/client, chat_json.e as consumed by the client, testing/client_assault.e)
# Reviewer: Claude Fable 5 (adversarial contract review, read-only; no compile)
# Date: 2026-08-29
# Inputs: phase2-claude-response.md, phase2-part-client.md, approach.md section 8, spec/10-ADDENDUM-THICK-CLIENT.md, phase2-chain.txt; current source (22:24-22:28 timestamps)
# Library facts verified on disk: SIMPLE_DATE_TIME.make_from_iso8601 -> make_from_string -> SIMPLE_DATE.make (EiffelBase DATE.make requires `correct_date: is_correct_date (y, m, d)'; SIMPLE_TIME clamps out-of-range fields); SIMPLE_JSON.parse_message requires `not_empty'; SIMPLE_JSON_OBJECT.*_item answer Void/0/False on a wrong type; UTF_CONVERTER.utf_8_string_8_to_string_32 never raises (bounds-guarded); STRING_8/STRING_32.make_from_separate exist; EXECUTION_ENVIRONMENT.sleep (nanoseconds: INTEGER_64); MML_SEQUENCE `<=' is prefix; ISE JSON_PARSER is recursive descent with no depth bound; ECF: every assertion kind on, SCOOP use="scoop".

Line numbers are those of the current files.

---

## A. Phase-2 HIGH findings located in this cluster

### [ISSUE 4]: EVENT_POLLER.poll_once `older_kept' compares two snapshots taken under two lock acquisitions
- LOCATION: event_poller.e (whole class; formerly line 109)
- VERDICT: DISSOLVED
- EVIDENCE: There is no `pending', no `drain', no MUTEX and no `older_kept' anywhere in event_poller.e. The page leaves the poller as bytes: `deliver (inbox, p.bytes)' (line 128) -> `a_inbox.put (a_bytes)' (line 188). Every postcondition of `poll_once' (lines 139-148) names only processor-owned scalars (`polls', `cursor', `consecutive_failures', `last_error', `delivered', `session_lost', `room_id'). Under SCOOP the poller is the only writer of those, so the exact forms (`polled: polls = old polls + 1', `moved_only_by_delivery: cursor > old cursor implies delivered = old delivered + 1') are correct, not racy. The drain laws moved to EVENT_INBOX (`take', event_inbox.e 112-125), single-processor by construction.
- REMAINING/SUGGESTION: none.

### [ISSUE 5]: EVENT_POLLER extends `pending' before advancing `cursor'
- LOCATION: event_poller.e lines 127-130
- VERDICT: DISSOLVED
- EVIDENCE: `if not p.is_empty then deliver (inbox, p.bytes); cursor := cursor.max (p.last_id) end' - the inbox copy happens first, then the cursor moves, and no invariant relates the two any more (`pending_at_or_below_cursor' is gone). `cursor_monotonic: cursor >= old cursor' (line 141) is proved by `cursor.max (...)' and `p.last_id' (chat_page.e 57-67: `the_highest: across events as e all e.id <= Result end'). Ordering across processors is guaranteed by the inbox's FIFO (`oldest', event_inbox.e 122).
- REMAINING/SUGGESTION: none - but see NEW-2: the cursor moves even when the inbox refused the page.

### [ISSUE 22]: CHAT_CLIENT.post_message `echoed' asserts the server's honesty
- LOCATION: chat_client.e lines 216-227
- VERDICT: FIXED
- EVIDENCE: lines 216-221: `if l_reply.is_success and then attached codec.event (l_reply.body) as e then if e.room_id = a_room_id and e.is_message then create Result.make_success (e) else create Result.make_error (unexpected_answer) end'. Postconditions `echoed: ... e.room_id = a_room_id' (226) and `message_kind: ... e.is_message' (227) are now established by the body; `unexpected_answer' is a 502 (`gateway: Result.http_status = 502', 391). Test `test_post_message_echo_for_another_room_is_refused' (client_assault.e 144) fires a room-2 echo, a system-kind echo, a non-event 201 and a 429, and checks the true echo is accepted.
- REMAINING/SUGGESTION: none.

### [ISSUE 28]: The decoder violates CHAT_ERROR.make's preconditions - a server reply becomes an exception
- LOCATION: chat_client.e lines 365-408 (`error_of', `salvaged_code'); chat_json.e lines 363-382 (`error_from_bytes'); client_codec.e lines 100-115
- VERDICT: PARTIAL (the three named seams are closed; the repair introduced a fourth - NEW-1)
- EVIDENCE: `error_of' (365-384) has the branches the review asked for: `not a_reply.is_exchanged' -> 503 with `a_reply.error' (non-empty by HTTP_REPLY's invariant `failed_is_explained', http_reply.e 76); `a_reply.status < 400' -> `unexpected_answer' (502); else `codec.error (a_reply.body, a_reply.status)', whose precondition `error_status: 400..599' (client_codec.e 102-103) is satisfied by the branch order plus HTTP_REPLY's `status_range' (77). `error_from_bytes' (chat_json.e 368-377) demands an error status, an ASCII non-empty code and a non-empty message before `CHAT_ERROR.make', and maps an unknown code to `Code_unavailable' (372-376), so `known' and `message_given' hold. The captive-portal 200, the 302, the error-body-under-200 and the empty message are tested (`test_login_never_raises_on_hostile_replies', client_assault.e 98). HOWEVER the fallback at line 377 - `create Result.make (salvaged_code (a_reply.body), "HTTP " + a_reply.status.out, a_reply.status)' - passes a code that `salvaged_code' (394-408) checks for length and printability only, never for `is_known_code'. `CHAT_ERROR.make' requires `known: is_known_code (a_code)' (chat_error.e 21). A 4xx/5xx whose body has a printable unknown code and no usable message (`429 {"code":"throttled"}', `503 {"code":"maintenance","message":""}', a non-string message) is a PRECONDITION_VIOLATION signalled in `error_of', which has no rescue (CLIENT_CODEC's rescue is one frame below and cannot help). Detailed as NEW-1.
- REMAINING/SUGGESTION: see NEW-1.

### [ISSUE 29]: Non-Latin-1 text in "ASCII" wire fields reaches `to_string_8'
- LOCATION: chat_json.e lines 198-199, 235-236, 256, 354, 369, 432-438; chat_client.e lines 398-402
- VERDICT: FIXED (for every path the client executes)
- EVIDENCE: `ascii_item' (chat_json.e 432-438): `if attached a_object.string_item (a_key) as s and then across s as c all c.natural_32_code < 128 end then Result := s.to_string_8 end' - the only `to_string_8' on wire text, guarded. Used for kind and created_at (198-199), mime and sha256 (235-236), username (256), token (354), code (369). `salvaged_code' guards its own `c.to_string_8' with `33..126' (chat_client.e 400-402). Every other client-side `to_string_8' is on a READABLE_STRING_8 (chat_endpoint.e 28, http_reply.e 27, http_request_record.e 16-21, chat_url_rules.e 103/105), where `is_valid_as_string_8' is trivially true. Tests: non-Latin-1 token (client_assault.e 121), non-Latin-1 kind (233).
- REMAINING/SUGGESTION: none in this cluster (`login_user_key' on the server belongs to another reviewer).

### [ISSUE 30]: `created_at' is parsed without validation
- LOCATION: chat_json.e lines 199, 204, 404-428; client_codec.e lines 50-61
- VERDICT: PARTIAL
- EVIDENCE: `is_iso8601' (404-428) checks the 19/20-character shape (digits, `-', `T', `:', optional `Z') before `create l_at.make_from_iso8601 (t)' (204). It does not check ranges. `SIMPLE_DATE_TIME.make_from_iso8601' -> `make_from_string' -> `SIMPLE_DATE.make_from_string' -> `create internal_date.make (l_year, l_month, l_day)', and EiffelBase `DATE.make' requires `correct_date: is_correct_date (y, m, d)'. So `"2026-13-01T00:00:00"' and `"2026-02-30T00:00:00"' pass `is_iso8601' and raise inside the codec. Two further shape-valid inputs produce made-up times silently: year `0000' (SIMPLE_DATE's "default to epoch" branch turns it into 1970-01-01) and out-of-range time fields (SIMPLE_TIME clamps `25:99:99' to `23:59:59') - exactly what the test comment at client_assault.e 235 says must never happen. On the client the raise is caught: CLIENT_CODEC.page/event wrap the call in `rescue l_failed := True; retry' (client_codec.e 58-61, 70-73), so the GUI and the poller see a 502, never an exception. I verified the mechanism: the exception is signalled in `event_from_json''s frame, propagates through `page_from_bytes' (no rescue) and is rescued in `CLIENT_CODEC.page'; `l_failed' is a local and locals keep their value across `retry', so the second pass skips the body and the routine ends with Result = Void - no loop, and the postcondition holds on Void. CHAT_JSON's own note (lines 9-15: a timestamp that is not ISO 8601 -> Void) is false for these inputs, and any consumer calling CHAT_JSON directly (server, replica, bots) is unprotected.
- REMAINING/SUGGESTION: make `is_iso8601' a validity check and say so in its postcondition:
  ```
  is_iso8601 (a_text: READABLE_STRING_8): BOOLEAN
          -- yyyy-mm-ddThh:mm:ss[Z] with a year > 0, a calendar-valid date and a time in range -
          -- what SIMPLE_DATE_TIME can build without inventing anything.
      do
          Result := has_iso8601_shape (a_text)
              and then a_text.substring (1, 4).to_integer > 0
              and then (create {DATE_VALIDITY_CHECKER}).is_correct_date (a_text.substring (1, 4).to_integer, a_text.substring (6, 7).to_integer, a_text.substring (9, 10).to_integer)
              and then a_text.substring (12, 13).to_integer <= 23
              and then a_text.substring (15, 16).to_integer <= 59
              and then a_text.substring (18, 19).to_integer <= 59
      ensure
          buildable: Result implies (create {DATE_VALIDITY_CHECKER}).is_correct_date (a_text.substring (1, 4).to_integer, a_text.substring (6, 7).to_integer, a_text.substring (9, 10).to_integer)
      end
  ```
  (`is_correct_date' is the predicate DATE.make itself requires.) Add to `event_from_json': `ensure time_kept: attached Result as e implies e.created_at.to_iso8601.starts_with (a_object.string_item (Key_created_at).substring (1, 19))' - the round trip is exact once the input is valid. Assault: `"2026-02-30T00:00:00"', `"0000-01-01T00:00:00"', `"2026-01-01T25:00:00"' each -> 502 through CHAT_CLIENT and Void through CHAT_JSON directly.

### [ISSUE 36]: The loopback test is a prefix match - `http://localhost@evil.example' gets the token in clear; no contract forbids a Bearer header on an insecure endpoint
- LOCATION: chat_url_rules.e lines 20-113; chat_endpoint.e lines 22-33, 56-69; chat_client.e lines 29-40, 324-335, 420-423; service_locator.e line 87
- VERDICT: FIXED
- EVIDENCE: `is_acceptable_url' (20-30) = `is_clean_url' (printable ASCII 33..126, no `@', `?', `#' anywhere - line 86) and no trailing slash and (https with a non-empty `authority_of', or `is_loopback_url'). `is_loopback_url' (32-64) parses the authority: a bracketed host or the host up to the first `:', then `is_loopback_host' (exactly `127.0.0.1', `[::1]', `localhost' any case, 69) and an optional `:' + `is_valid_port' (1-5 digits, 1..65535, 72-80). Forms tried against it: `http://localhost@evil.example', `http://127.0.0.1@evil', `http://localhost:8080@evil' (fail `is_clean_url'); `http://127.0.0.1.evil.example', `http://localhost.evil.example', `http://localhost.' (host mismatch); `http://[::1]x', `http://[::1]]', `http://[::1' (rest not `:port' / unclosed bracket); `http://localhost:', `:0', `:65536', `:80a', `:8080:1', `:+80', `:00000' (port rule); `http://localhost%40evil', `http://%6Cocalhost' (host mismatch); `HTTP://localhost' (case-sensitive scheme - refused, conservative); whitespace, tab, CR/LF, DEL, non-ASCII (clean rule); `http://127.0.0.1\@evil' (`@'); a backslash elsewhere keeps the authority intact (`http://127.0.0.1\evil' has host `127.0.0.1\evil' - refused); a path containing `..' is accepted (`http://127.0.0.1/..') and harmless, the authority is still loopback. `CHAT_ENDPOINT.is_secure' is derived from the URL (`base_url.starts_with (Https_scheme) or is_local', 59) and `is_local' from `is_loopback_url' (29), never from a caller's flag; invariants `acceptable', `local_is_loopback', `secure_by_construction' (65-69). The Bearer chain: `CHAT_CLIENT.make require secure: a_endpoint.is_secure' (31), invariant `never_plaintext: endpoint.is_secure' (423), `exchange require token_over_tls: a_headers.has (Header_authorization) implies endpoint.is_secure' (329), `authorized_headers' in `feature {NONE}' (302-313), `SERVICE_LOCATOR.locate ensure secure: Result.is_secure' (87). CLIENT_CONFIG inherits the same rules (`servers_acceptable', client_config.e 222). Test `test_hostile_urls_refused_loopbacks_accepted' (client_assault.e 273) fires twenty forms including the four from the finding.
- REMAINING/SUGGESTION: none for the token. Two cosmetic gaps: NEW-5 (https authority shape) and, in the LOW bundle, `base_url' is an exported mutable STRING_8 - a mutation from outside is caught only by invariant monitoring at the endpoint's next `url_for' (and not at all with assertions off).

### [ISSUE 25]: PASSWORD_HASHER.hash's `never_plaintext' is false for legal short passwords
- LOCATION: src/service/password_hasher.e lines 31, 38, 83 - NOT in this cluster (listed by the orchestrator as "notably"; reported as a courtesy, not counted in the cluster verdict)
- VERDICT: FIXED (out of cluster)
- EVIDENCE: `require long_enough: a_password.count >= Minimum_characters' (31), `Minimum_characters: INTEGER = 8' (83), `never_plaintext: not Result.has_substring (utf8 (a_password))' kept with the probabilistic note (38-39); SERVER_CONFIG invariant `password_minimum_sane: password_minimum >= {PASSWORD_HASHER}.Minimum_characters' (server_config.e 286). The name collision with CHAT_CLIENT's `never_plaintext' invariant (chat_client.e 423) is coincidental.
- REMAINING/SUGGESTION: none from here.

---

## B. Phase-2 MEDIUM findings located in this cluster (phase2-part-client.md order)

### [M1]: `CHAT_PRESENTER.pump' postconditions read poller state without the lock (`old pending_count', `drained')
- LOCATION: chat_presenter.e lines 208-261, 310-348
- VERDICT: DISSOLVED (the suggested replacement clauses are present)
- EVIDENCE: `pump''s postconditions (252-260) reference only root-processor objects: `shown_some: view.shown_count >= old view.shown_count', `in_order: (old view.shown_model) <= view.shown_model', `foreground_clears', `badge_matches: notifier.unread = unread', `last_seen_monotonic', `pumped_monotonic', `still_open', `room_kept'. The exact law lives where it is provable: `check shown_all: view.shown_count = l_shown_before + l_applied end' and `check unread_exact' inside `apply' (335-336). `shown_model' was lifted into deferred CHAT_VIEW (chat_view.e 18-24) with `show_event ensure appended: shown_model |=| ((old shown_model) & a_event.id)' (50). The inbox is touched only through `take_from'/`outage_from' (352-366), each a separate call of its own.
- REMAINING/SUGGESTION: none.

### [M2]: `page_result' enforces only half of the server's since-contract - foreign-room events and statuses are accepted
- LOCATION: chat_client.e lines 337-363, 153, 176
- VERDICT: FIXED
- EVIDENCE: `page_result' takes `a_room_id' and demands `all_in_room (p, a_room_id)' (344; 358-363: every event and every status has `room_id = a_room_id'), plus `p.events.count <= a_limit' and `p.events.first.id > a_since_id' (343; ascending is CHAT_PAGE's invariant, chat_page.e 101). Postconditions `same_room' on `page_result' (353), `events_since' (153) and `wait_for_events' (176). Test at client_assault.e 212 covers a foreign event, a foreign status, non-ascending, not-after-since, over-limit. The presenter re-filters by room in `apply' (321, 338) as defence in depth, tested at 617.
- REMAINING/SUGGESTION: none.

### [M3]: 401 mid-session has no contract; the token is kept and the poller has no backoff - a hot loop against the server
- LOCATION: event_poller.e lines 73-96, 100-101, 111-148, 150-171; event_inbox.e lines 127-141; chat_presenter.e lines 234-243
- VERDICT: PARTIAL
- EVIDENCE: Backoff: `backoff_seconds' (73-96) is 0 when healthy, 1 after one failure, doubling, `capped: Result <= Backoff_maximum_seconds' (30 s); `run' sleeps it between polls (163-165); invariant `quiet_when_healthy' (216); tested `<<1, 2, 4, 8, 16, 30, 30, 30>>' (client_assault.e 520). A refused page (foreign room, stale, non-ascending) is a failure like any other (page_result -> 502 -> `consecutive_failures + 1'), so the spin on a misbehaving server is gone. 401: `session_lost := err.http_status = 401' (135), `poll_once require session_alive: not session_lost' (115), `lost_on_401' (146), `run' ends (`ended: session_lost or else should_stop (inbox)', 168); tested at 490 including `run' on a lost session. What is still open is the finding's last clause - "decide by contract whether the client drops the token on 401" - and then what: after `session_lost' the poller reports the server's message once as an `outage' (136 -> event_inbox.e 127-141) and stops; nothing tells the presenter that the SESSION is dead as opposed to the server being down. `CHAT_PRESENTER.pump' shows the outage text once (237-239) and leaves the room open with `reported_outage' latched; `close_room' is never called; the GUI's CHAT_CLIENT keeps a token the server rejects (every `send' then fails with a fresh 401 shown as an error); no re-login is possible without `log_out' by hand. The host's client keeps its copy of the dead token in memory (harmless).
- REMAINING/SUGGESTION: give the inbox a session-lost signal distinct from an outage and make the presenter act on it:
  ```
  -- EVENT_INBOX
  is_session_lost: BOOLEAN
          -- Did the poller's server answer 401? Sticky, like `is_stopped'.

  report_session_lost (a_message: separate READABLE_STRING_32)
      do
          is_session_lost := True
          report_outage (a_message)
      ensure
          lost: is_session_lost
          reported: has_outage
          pages_kept: pages_model |=| old pages_model
      end

  -- EVENT_POLLER.poll_once, failure branch
  if session_lost then report_lost (inbox, err.message) else report (inbox, err.message) end

  -- CHAT_PRESENTER
  session_lost: BOOLEAN
          -- Did the last pump learn the session is dead? The room is closed; the window must ask for a login.

  pump ... ensure
      lost_closes: session_lost implies (not is_room_open and not client.is_logged_in)
      still_open: not session_lost implies is_room_open
  ```
  where `pump' calls `close_room' and `client.logout' when the inbox says the session is lost. Assault: a 401 through the poller, one pump -> room closed, GUI client logged out, error shown once.

### [M4]: "Show the connection error once" is wrong in both directions
- LOCATION: chat_presenter.e lines 101-102, 167, 234-243; event_inbox.e lines 68-71, 127-150
- VERDICT: FIXED
- EVIDENCE: presenter-owned latch `reported_outage' (101), reset on `open_room' (167) and whenever the inbox reports no outage (242); the poller reports every failed poll (`report', event_poller.e 136) and recovery (`recover', 123 -> `report_recovery', event_inbox.e 143-150). `pump': `if attached l_outage as o then if not reported_outage then view.show_error (o); reported_outage := True end else reported_outage := False end' (236-243). Neither "never" (a single fast failure stays latched in the inbox until recovery) nor "every tick" (the latch). Test `test_presenter_outage_reported_once' (client_assault.e 701): two pumps -> one error; recovery -> latch released; new outage -> shown again. A failure that begins and ends between two ticks is never shown - consistent with "healthy is quiet".
- REMAINING/SUGGESTION: none. (`show_connection' is never updated - NEW-7.)

### [M5]: "`pending' is always ascending" is a stated law with no contract; `drain.ascending' asserts something else
- LOCATION: event_poller.e (no `pending'); chat_page.e lines 87-102; chat_json.e line 291
- VERDICT: DISSOLVED
- EVIDENCE: no pending list exists. What replaces the law: CHAT_PAGE's invariant `ascending: is_ascending (events)' (chat_page.e 101, strictly increasing, 87-99), enforced by the decoder (`e.id > l_events.last.id', chat_json.e 291) and by `page_result''s `first.id > a_since_id' (chat_client.e 343). Across pages the order follows from the cursor's monotonicity plus the inbox's FIFO (`oldest', event_inbox.e 122).
- REMAINING/SUGGESTION: the composed law ("every event once, ascending, across pages") is not stated at the presenter - NEW-8.

### [M6]: Token shape is "64 characters", not "64 hex" - CRLF header injection from a hostile server
- LOCATION: chat_json.e lines 354, 360, 386-402; chat_client.e lines 73, 248-256, 417-421
- VERDICT: FIXED
- EVIDENCE: `login_from_bytes' accepts the token only through `ascii_item' and `is_hex_64 (t)' (354; `token_shape' postcondition 360; `is_hex_64': 64 characters each in 0-9a-f, 386-402). `CHAT_CLIENT.login' re-checks `is_hex_64 (l_login.token)' (73) before `token := l_login.token'; invariant `token_shape: token.is_empty or is_hex_64 (token)' (421). Nothing outside 0-9a-f can enter `"Bearer " + token' (310). Tests: uppercase hex, CR LF inside 64 characters, non-Latin-1 (client_assault.e 112-123).
- REMAINING/SUGGESTION: `is_hex_64' exists twice (CHAT_CLIENT 248, CHAT_JSON 386) - Single Choice: keep CHAT_JSON's (READABLE_STRING_GENERAL) and have CHAT_CLIENT delegate (`Result := codec.json.is_hex_64 (a_text)'). LOW.

### [M7]: The decode path can raise on hostile fields despite "Decoding never raises on bad input"
- LOCATION: chat_json.e lines 164-178, 180-262, 404-438; client_codec.e whole class
- VERDICT: PARTIAL
- EVIDENCE: `ascii_item' guards every `to_string_8' (Issue 29: fixed); `is_iso8601' guards the shape but not the validity of `created_at' (Issue 30: partial). Every `CHAT_EVENT.make', `CHAT_ATTACHMENT.make', `CHAT_MEMBER.make', `CHAT_STATUS.make' and `CHAT_ERROR.make' precondition reached from a `*_from_json' is re-checked in the decoder first - traced each: chat_json.e 215-219 against chat_event.e 28-36; 243 against chat_attachment.e 173-178 (including `uploader_stored' for a system sender with an attachment); 256-258 against chat_member.e 215-218; 266-269 against chat_status.e 153-158; 368-377 against chat_error.e 20-23. Two raises remain inside CHAT_JSON: the date (Issue 30) and an EMPTY body - `object_from_bytes' (164-170) hands `""' to `SIMPLE_JSON.parse_message', whose precondition `not_empty' (simple_json.e 33-34) is violated; every empty-bodied reply that is decoded (a proxy's bare 502, a `200' with no body on `members') takes the exception path. On the client both are absorbed by CLIENT_CODEC (rescue/retry, terminating - see Issue 30), so the client never sees an exception: tests at client_assault.e 98-141 and 212-247 drive hostile bodies through CHAT_CLIENT. CHAT_JSON's class note still promises what CHAT_JSON alone does not deliver.
- REMAINING/SUGGESTION: in CHAT_JSON: `object_from_bytes ... do if not a_bytes.is_empty and then attached parser.parse_message (...) as v and then v.is_object then ...' (same for `array_from_bytes'); plus the date fix of Issue 30. Then the note is true and the CLIENT_CODEC rescue is what it claims to be - defence in depth rather than the primary guard.

### [M8]: `logout' forgets the token only after the exchange returns
- LOCATION: chat_client.e lines 86-101
- VERDICT: FIXED
- EVIDENCE: `l_headers := authorized_headers; create token.make_empty; me := Void; l_reply := exchange ("POST", Path_logout, l_headers, Void, Default_timeout_seconds)' (94-97); `ensure logged_out: not is_logged_in; forgotten: me = Void' (99-100). No qualified call on Current sits between the two assignments, so the invariant `me_iff_logged_in' (422) is never observed half-way. A failed exchange leaves the client logged out (`test_logout_on_transport_failure_logs_out', client_assault.e 198). The server-side session survives an unheard logout until it expires; `logout' returns nothing, so the caller cannot know - acceptable, noted in the LOW bundle.
- REMAINING/SUGGESTION: none required.

### [M9]: No `close_room'; `open_room' twice orphans a poller; `send'/`pump' after `logout' violate preconditions one level down
- LOCATION: chat_presenter.e lines 156-206, 211-213, 265-267, 388-389; event_inbox.e lines 152-159
- VERDICT: FIXED
- EVIDENCE: `open_room require closed: not is_room_open' (160); `close_room' stops the poller through the inbox (`stop_inbox (b)' 184 -> `EVENT_INBOX.stop', sticky, 152-159) and forgets the room (186-187); `log_out' closes then logs out (194-206); `pump'/`send' require `open' and `logged_in' (211-213, 265-267); invariants `open_implies_session: is_room_open implies client.is_logged_in' and `room_iff_open' (388-389). The poller sees the stop at its next `should_stop (inbox)' (event_poller.e 160); pages arriving after the stop are dropped and counted (event_inbox.e 98-99). Tested at client_assault.e 549-591 (`close_room' -> `b.is_stopped', reopen from `last_seen_id', `log_out' -> `b2.is_stopped').
- REMAINING/SUGGESTION: `client' is exported (VAPE, 57-58): `client.logout' called directly while a room is open breaks `open_implies_session' at the presenter's next call. Document that the window goes through `presenter.log_out' only, or export `CHAT_CLIENT.logout' to `{CHAT_PRESENTER, CLIENT_APP}'. LOW.

### [M10]: `SERVICE_LOCATOR.is_alive' is a side-effecting query filed under "contract support"; `last_probe_status' comment is wrong
- LOCATION: service_locator.e lines 40-52, 98-113
- VERDICT: FIXED
- EVIDENCE: `probe (a_endpoint: CHAT_ENDPOINT)' is a command (98-113) with `ensure probed: probe_count = old probe_count + 1; alive_definition: last_probe_alive = (last_probe_status >= 200 and last_probe_status <= 299)'; queries `last_probe_alive', `last_probe_status' (comment now true: "0 before any probe, or when it failed at the transport" - `last_probe_status := l_reply.status' and HTTP_REPLY has status 0 exactly when not exchanged), `found_alive'. The health URL comes from `a_endpoint.url_for (Health_path)' (106), no concatenation outside CHAT_ENDPOINT. Invariant `alive_is_2xx' (125).
- REMAINING/SUGGESTION: none. (A 2xx of any body counts as alive - NEW-11.)

### [M11]: `authorized_headers' is exported - the token leaves the class through a public query
- LOCATION: chat_client.e lines 302-322, 103-133, 412-418
- VERDICT: FIXED
- EVIDENCE: `feature {NONE} -- Requests' holds `authorized_headers', `plain_headers', `exchange', `page_result', `all_in_room', `error_of', `unexpected_answer', `salvaged_code'. `token' is `feature {NONE}' (412-418). The only exported route for the token is `hand_session_to (a_other: separate CHAT_CLIENT)' (103-114) -> `adopt_session', exported to `{CHAT_CLIENT}' (116), which copies (`create l_token.make_from_separate (a_token)', 124) - the receiving client never retains a reference into the giver. The token crosses as a `separate READABLE_STRING_8' reference read under lock passing (the caller's own string is the actual argument, which makes the call synchronous) and lands as a fresh STRING_8 on the host's processor; the postcondition `handed: a_other.is_logged_in' is evaluated while `a_other' is still locked.
- REMAINING/SUGGESTION: `adopt_session' has no `require logged_out: not is_logged_in' - a second hand-over silently replaces a live session. Add it (a condition on Current, not a wait condition). LOW.

### [M12]: The assault proves "token never in a URL" for one GET only; `requests_model' and `mentions' unused; ten missing tests
- LOCATION: testing/client_assault.e; testing/test_app.e lines 52-77
- VERDICT: FIXED
- EVIDENCE: `test_token_never_in_url_or_body_across_all_requests' (52-79): six requests, `across t.requests as q all (not q.url.has_substring (hex64) and not q.body.has_substring (hex64)) end', login without a bearer, every other request with exactly `Bearer <hex64>'. The ten asked-for tests all exist: token across all requests (52), wait 0 -> timeout 5 (81), locator with no server (366), non-ascending page (212), foreground toggled mid-pump (623, via `set_flips_on_show'), foreground pump receiving another's message (652), `load_roster' (729), login on a non-JSON 200 (98), post echo for room 2 (144), logout on a transport failure (198). Also the session hand-over (171) and the SCOOP-shaped trio driven on one processor. All 26 tests are registered in TEST_APP (52-77).
- REMAINING/SUGGESTION: `requests_model' and `mentions' remain unused by any test (INFO); `poll_is_refused' relies on precondition monitoring - fine under the tests target.

### [M13]: One CHAT_CLIENT/transport shared by worker and GUI
- LOCATION: apps/client/poller_host.e lines 22-36, 63-80; apps/client/client_app.e lines 57-99; chat_client.e lines 13-17, 103-133
- VERDICT: FIXED
- EVIDENCE: POLLER_HOST creates `transport', `endpoint' and `client' on its own processor (`create transport.make; create endpoint.make (l_url); create client.make (transport, endpoint)', 31-33), receives the session by copy (`hand_session_to', client_app.e 86) and the inbox by reference (`set_inbox', 55-61). `poll' creates the EVENT_POLLER with the host's client and runs the loop on the host (`l_poller.run', 76) while holding no separate lock (the inbox is locked only inside `make'). `launch' passes only INTEGER_64s so `a_host.poll' is asynchronous (client_app.e 95-99); its preconditions `logged_in'/`has_inbox' are wait conditions already satisfied because `hand_session' and `attach_inbox' were queued ahead of it on the same processor. `last_status' is gone; `exchange_count' is per transport. No deadlock: the poller locks the inbox for short calls only, the root locks the inbox for short calls only, the root locks the host only during `start_polling', and neither the host nor the inbox ever locks the root except by lock passing inside a call the root itself made.
- REMAINING/SUGGESTION: none.

### [LOW bundle from phase2-part-client.md]
- LOCATION: various
- VERDICT: PARTIAL (most items closed; the remainder listed)
- EVIDENCE: closed - CHAT_ENDPOINT `no_trailing_slash' invariant (chat_endpoint.e 67); system events no longer count as unread nor ring (chat_presenter.e 323, 328); statuses ride in pages and `show_status' replaces the previous line; badge touched only when it would change (249-251); `members' has `distinct_ids' and every reader has `session_kept'; `page_result', `error_of', `room_path' contracted; `set_window', `last_id', `open_room', `send', `remember', `load_roster' contracted; `set_only_server_url' + `set_primary_url' replace the standby-discarding setter; `has_url' case-insensitive on scheme and host (`same_url'); 1xx refused as final (`final_status: 200..599', http_reply.e 23); `Body_maximum' 16 MiB (http_transport.e 50); display-name collisions disambiguated (`name_of', chat_presenter.e 71-92). Still open - exported mutable structures: `CHAT_ENDPOINT.base_url' (STRING_8, 37), `CLIENT_CONFIG.server_urls' (ARRAYED_LIST, 57), `CHAT_PAGE.events'/`statuses' kept by reference (chat_page.e 26-27, 40-41); test doubles' lists (fine); the status line is never cleared once shown (a "thinking..." stays after the answer arrives); `load'/`save' are Phase 4 stubs; `logout' cannot report whether the server heard; the runner's treatment of skeletal tests is outside this cluster.
- REMAINING/SUGGESTION: `base_url: IMMUTABLE_STRING_8' (or `{NONE}' storage plus a query returning `.twin'); `server_urls' to `{NONE}' with `server_url_at (i)'/`server_count' (tests can use `servers_model'); clear the status line in `apply' when an event of the open room arrives (add `CHAT_VIEW.clear_status ensure events_unchanged').

---

## C. New findings

### [NEW-1]: `salvaged_code' hands CHAT_ERROR.make a code it never checked against `is_known_code' - an unknown code plus an unusable message is a PRECONDITION_VIOLATION on the poller's processor
- LOCATION: CHAT_CLIENT.salvaged_code (chat_client.e 394-408) and CHAT_CLIENT.error_of line 377; CHAT_ERROR.make `known' (chat_error.e 21), `is_known_code' (49-56: eleven codes)
- VERDICT: NEW-HIGH
- EVIDENCE: `error_of', exchanged status >= 400, `codec.error' Void (message empty, missing, or not a string - `error_from_bytes' 369-370), then `create Result.make (salvaged_code (a_reply.body), "HTTP " + a_reply.status.out, a_reply.status)'. `salvaged_code' returns `c.to_string_8' when the body's `code' is 1..32 printable ASCII characters (398-402) - no `is_known_code'. `CHAT_ERROR.make require known: is_known_code (a_code)'. Triggers: `429 {"code":"throttled"}', `503 {"code":"maintenance","message":""}', `401 {"code":"expired","message":42}' - a future server version, a reverse proxy, a load balancer. Reachable from every call (`login', `events_since', `wait_for_events', `members', `post_message' all end in `error_of'). The violation is signalled in `error_of''s own frame; `error_of' has no rescue, nor do `page_result', `wait_for_events', `EVENT_POLLER.poll_once', `run', `POLLER_HOST.poll'. On the poller processor the chain was started by the asynchronous `a_host.poll' (client_app.e 98): the exception ends the loop with no `report' to the inbox, and SCOOP forwards it to the root only at the root's next call on that processor - which never comes. The poller dies silently; the GUI shows nothing and never recovers. On the root (a `send' or `login') it is an unhandled exception on the GUI thread. The test at client_assault.e 130-133 covers an EMPTY code and a KNOWN code with an empty message, not an unknown non-empty code - exactly the gap.
- REMAINING/SUGGESTION:
  ```
  salvaged_code (a_body: READABLE_STRING_8): STRING_8
          -- The "code" of an error reply whose message was unusable, when it is one CHAT_ERROR knows;
          -- else "unavailable". Never anything CHAT_ERROR.make would refuse.
      do
          if attached codec.object (a_body) as o and then attached o.string_item ({CHAT_JSON}.Key_code) as c
              and then not c.is_empty and then c.count <= Code_maximum
              and then across c as ch all (ch.natural_32_code >= 33 and ch.natural_32_code <= 126) end
              and then error_probe.is_known_code (c.to_string_8)
          then
              Result := c.to_string_8
          else
              Result := {CHAT_ERROR}.Code_unavailable
          end
      ensure
          given: not Result.is_empty
          known: error_probe.is_known_code (Result)
      end

  error_probe: CHAT_ERROR
          -- An instance to ask `is_known_code' of (it is not a class feature).
      once
          create Result.make ({CHAT_ERROR}.Code_unavailable, "probe", 503)
      end
  ```
  Better still: move `is_known_code' and the `Code_*' constants into a CHAT_ERROR_CODES class so neither CHAT_JSON line 372 nor this needs a throw-away instance. Assault: `t.script (429, "{%"code%":%"throttled%"}")' and `t.script (503, "{%"code%":%"maintenance%",%"message%":%"%"}")' through `events_since' and through `EVENT_POLLER.poll_once' -> a result carrying `Code_unavailable' and the status, `consecutive_failures = 1', no exception.

### [NEW-2]: A full inbox drops a page the poller has already moved its cursor past - the events are lost for the session, nothing observes `dropped', and the GUI is never told
- LOCATION: EVENT_INBOX.put (event_inbox.e 93-110), `dropped' (68-69), `Capacity' (163); EVENT_POLLER.poll_once lines 127-130 and `deliver' (183-192); CHAT_PRESENTER.pump (208-261) reads only `take' and `outage'
- VERDICT: NEW-HIGH
- EVIDENCE: `put': `if is_full or is_stopped then dropped := dropped + 1 else ... pages.extend (l_copy) end' (98-102) - honest and contracted (`refused', 107). But `poll_once' does `deliver (inbox, p.bytes); cursor := cursor.max (p.last_id)' unconditionally (128-129), and `deliver' counts `delivered := delivered + 1' whether or not the inbox took the page (189-191: `counted: delivered = old delivered + 1' is true even for a drop). The next poll asks `since = cursor', so the server never re-sends those events; the presenter's `last_seen_id' stays behind; the only recovery is a later `open_room' from `last_seen_id' (a restart). `dropped' is exported but no presenter feature reads it: no error, no notice, no badge. The class note's "far more than a GUI pumping every tick ever sees" is an assumption, not a contract: the root blocks for up to 15 s in `send'/`load_roster' (`Default_timeout_seconds') and for as long as any modal dialog holds the window, while a bot answering produces status-only pages ("thinking", "queued behind 1") that each count as news and return the long-poll at once. 64 pages then arrive in well under a minute, after which real messages are dropped and gone. This contradicts the addendum's law "every drained event was shown exactly once" - in the direction of never.
- REMAINING/SUGGESTION: make the refusal impossible on the live path with a SCOOP wait condition, and make the cursor depend on acceptance:
  ```
  -- EVENT_POLLER, feature {NONE} -- The inbox
  wait_for_room (a_inbox: separate EVENT_INBOX)
          -- Block this processor until the inbox can take a page, or it has been stopped
          -- (the precondition is a wait condition: the lock is released while it is false).
      require
          room_or_stopped: not a_inbox.is_full or a_inbox.is_stopped
      do
      end

  deliver (a_inbox: separate EVENT_INBOX; a_bytes: STRING_8): BOOLEAN
          -- Hand `a_bytes' to the inbox; True when it was queued, False when the inbox is stopped.
      require
          given: not a_bytes.is_empty
      do
          if not a_inbox.is_stopped then
              a_inbox.put (a_bytes)
              Result := True
              delivered := delivered + 1
          end
      ensure
          counted: Result implies delivered = old delivered + 1
          kept_when_not: not Result implies delivered = old delivered
          not_dropped: a_inbox.dropped = old a_inbox.dropped
      end

  -- poll_once, success branch
  if not p.is_empty then
      wait_for_room (inbox)
      if deliver (inbox, p.bytes) then
          cursor := cursor.max (p.last_id)
      end
  end
  ```
  `not_dropped' is provable because only this processor calls `put' and `wait_for_room' has just returned; `EVENT_INBOX.dropped' then counts post-stop pages only. If the drop-on-full policy is kept instead, the drop must at least reach the member: `CHAT_PRESENTER.pump' reads `a_inbox.dropped' into `pages_dropped' and shows "n pages of messages were skipped; reopen the room to catch up" once (a second latch), and `deliver' must not advance the cursor when `a_inbox.dropped' grew. Assault (single processor, as the existing tests do): fill the inbox with 64 pages, poll a 65th page of two events, check `cursor' did not move (or, with the wait-condition version, that `deliver' answers False only after `stop').

### [NEW-3]: `run' has no floor between successful polls - a server (or proxy) that answers an empty page at once, or a status flood, is polled in a tight loop
- LOCATION: EVENT_POLLER.run (event_poller.e 150-171), `backoff_seconds' (73-96)
- VERDICT: NEW-MEDIUM
- EVIDENCE: `backoff_seconds' is 0 whenever `consecutive_failures = 0' (`quiet_when_healthy', 92), and `run' sleeps only when it is > 0 (163). A 200 with an empty page is a success, so if the server returns it immediately - a server whose `seconds' parsing regressed, a replica that does not implement the wait, a reverse proxy answering 200 from a cache - the loop issues a full HTTP round trip continuously with no delay, from every member at once. The same loop runs, and additionally fills the inbox (NEW-2), when the server keeps returning a status-only page ("statuses alone are news", client_assault.e 458-459). The Phase-2 MEDIUM covered failures only; success is the open direction. Time cannot be contracted, but the pause can.
- REMAINING/SUGGESTION:
  ```
  quiet_polls: INTEGER
          -- Successive successful polls that brought nothing (no events, no statuses).

  pause_seconds: INTEGER
          -- What `run' waits before the next poll: the failure backoff, else one second after
          -- every quiet poll beyond the first (a server that honours `seconds' never answers
          -- quiet in under a second, so a healthy server never pays it).
      do
          if consecutive_failures > 0 then
              Result := backoff_seconds
          elseif quiet_polls > 1 then
              Result := Quiet_floor_seconds
          end
      ensure
          failure_backoff: consecutive_failures > 0 implies Result = backoff_seconds
          quiet_floor: (consecutive_failures = 0 and quiet_polls > 1) implies Result = Quiet_floor_seconds
          eager_when_busy: (consecutive_failures = 0 and quiet_polls <= 1) implies Result = 0
      end

  Quiet_floor_seconds: INTEGER = 1
  ```
  `poll_once' maintains `quiet_polls' (`ensure quiet_counted: (success and page empty) implies quiet_polls = old quiet_polls + 1; busy_resets: (success and page not empty) implies quiet_polls = 0'); `run' sleeps `pause_seconds'. Measuring the round trip would let the floor apply only to fast quiet answers; the counter form is contractible without a clock. Assault: three quiet successes -> `pause_seconds = 1'; a page -> 0; a failure -> `backoff_seconds'.

### [NEW-4]: JSON nesting depth is unbounded - a deeply nested body overflows the stack, which no `rescue' catches
- LOCATION: CHAT_JSON.object_from_bytes (chat_json.e 164-170) -> SIMPLE_JSON.parse_message -> ISE JSON_PARSER (recursive descent, `next_json_object'/`parse_array' recurse per level, no depth bound); CLIENT_CODEC (rescue-based guard)
- VERDICT: NEW-LOW
- EVIDENCE: `Body_maximum' is 16 MiB (http_transport.e 50); a body of a few hundred thousand `[' characters is far below it and recurses once per level. A stack overflow on Windows is a process crash, not an Eiffel exception, so CLIENT_CODEC's "every decoder answers Void on any exception" does not hold for it. Only a hostile or compromised server can send it, so the payoff is crashing the client, not the token - LOW.
- REMAINING/SUGGESTION: a byte pre-scan before parsing, in CLIENT_CODEC (the client's guard, not the codec's): `nesting_depth (a_bytes: READABLE_STRING_8): INTEGER' (deepest `['/`{' nesting, strings skipped), `Nesting_maximum: INTEGER = 16' (a page is four levels deep: page > events > event > attachment/payload), each decoder guarded by `nesting_depth (a_bytes) <= Nesting_maximum' with `ensure shallow: attached Result implies nesting_depth (a_bytes) <= Nesting_maximum'.

### [NEW-5]: The https branch of `is_acceptable_url' validates nothing about the authority but non-emptiness
- LOCATION: CHAT_URL_RULES.is_acceptable_url (chat_url_rules.e 20-30), `authority_of' (94-113), `scheme_of' (115-127)
- VERDICT: NEW-LOW
- EVIDENCE: `https://:443', `https://.', `https://host:0', `https://host:65536', `https://host:abc', `https://host:' all satisfy `has_authority: not authority_of (a_url).is_empty' and are accepted into CLIENT_CONFIG and CHAT_ENDPOINT. None leaks anything (the scheme is https; WinHTTP refuses them), so the token rule stands; the config merely accepts URLs that can never work. `HTTPS://host' is refused (scheme compared case-sensitively, 91 and 118-121) while `same_url' lowers the scheme for comparison - inconsistent but safe.
- REMAINING/SUGGESTION: `is_https_url (a_url) = a_url.starts_with (Https_scheme) and then is_valid_authority (authority_of (a_url))', with `is_valid_authority' = a non-empty host of `[A-Za-z0-9.-]' or a bracketed IPv6 literal, optionally `:' + `is_valid_port'; use it in `is_acceptable_url' and its postcondition `https_or_loopback'. Decide the scheme case once (accept `HTTPS://' by lowering it in CHAT_ENDPOINT.make, or refuse it in `same_url' too).

### [NEW-6]: A member whose display name is "system" is shown exactly like a system notice
- LOCATION: CHAT_PRESENTER.name_of (chat_presenter.e 71-92), `has_name_twin' (110-116), `System_name' (304)
- VERDICT: NEW-LOW
- EVIDENCE: `name_of (0)' is `"system"'; `name_of (9)' for a member with `display_name = "system"' is also `"system"' - `has_name_twin' looks for other MEMBERS with the same name, never at the reserved name. The view receives the CHAT_EVENT and can style by `is_system', which limits the spoof to the sender line and the tray notice (`notifier.notify (l_name, ...)' would read "system: ..."). Case-only twins ("Nick"/"nick") are not twins either.
- REMAINING/SUGGESTION: `has_name_twin' -> `is_ambiguous_name (a_member_id)' = another member with the same name (compared `as_lower') OR the name equal to `System_name' `as_lower'; postcondition `system_reserved: (a_sender_id /= 0 and knows (a_sender_id) and then members [a_sender_id].display_name.as_lower.same_string (System_name)) implies Result.ends_with ({STRING_32} ")")'.

### [NEW-7]: `show_connection (endpoint, True)' is asserted at `open_room' and never revised
- LOCATION: CHAT_PRESENTER.open_room line 168; pump 234-243; CHAT_VIEW.show_connection (chat_view.e 68-73)
- VERDICT: NEW-LOW
- EVIDENCE: the only call passes `True' before any poll has succeeded; an outage goes to `show_error' only, so a window that shows "connected to https://..." keeps saying so through a 30 s backoff and after a lost session. The locator knows `found_alive' but the presenter is never told.
- REMAINING/SUGGESTION: `open_room' takes `a_connected: BOOLEAN' (the locator's `found_alive'); `pump' calls `view.show_connection (client.endpoint, l_outage = Void)' exactly when the outage state changes (the same latch); add `connected: BOOLEAN' to CHAT_VIEW and `ensure connection_shown: view.connected = not reported_outage'.

### [NEW-8]: "Every event once, ascending, across pages" is not a presenter contract
- LOCATION: CHAT_PRESENTER.apply (chat_presenter.e 310-348), pump ensure (252-260); spec addendum line 78
- VERDICT: NEW-LOW
- EVIDENCE: `in_order: (old view.shown_model) <= view.shown_model' proves the view only appends; nothing states that the appended ids exceed `last_seen_id' or are strictly increasing. On the live path it follows from `page_result' (`first.id > since'), CHAT_PAGE `ascending', the monotone cursor and the inbox's FIFO - a composition across four classes that no single clause checks, and a duplicate page (any future re-delivery) would be shown twice without violating anything.
- REMAINING/SUGGESTION: in `apply', skip `e.id <= last_seen_id' (idempotent replay); add `ensure shown_ascending: is_strictly_increasing (view.shown_model)' to `pump' with a helper over MML_SEQUENCE [INTEGER_64]; invariant `seen_is_last_shown: view.shown_count > 0 implies last_seen_id >= view.shown_model.last'. Assault: put the same page twice -> shown once.

### [NEW-9]: CLIENT_CONFIG promises to persist the token under DPAPI; CHAT_CLIENT makes that impossible - the two notes contradict each other
- LOCATION: client_config.e lines 2-13 ("the session token only under DPAPI (intent-v3 Q17), never in clear"); chat_client.e lines 2-11 ("lives in memory only ... never through a public query"); `load'/`save' stubs (208-217)
- VERDICT: NEW-LOW
- EVIDENCE: no field, no query and no exported route exist for a token to reach `save' - correctly, given CHAT_CLIENT's rule. Left as written, the Phase 4 implementer of `save' will add the exported query the security argument depends on not having. Today the answer to "is the token ever written anywhere but memory" is no: CHAT_CLIENT, POLLER_HOST's client (its copy) and the test double's `HTTP_REQUEST_RECORD.headers' (memory) are the only holders; the client has no logger.
- REMAINING/SUGGESTION: strike the DPAPI sentence from CLIENT_CONFIG (re-login each launch), or record the decision explicitly with a `{CLIENT_CONFIG}'-exported `protected_token: STRING_8' on CHAT_CLIENT that yields DPAPI ciphertext and never the token. The former is consistent with the client as it stands.

### [NEW-10]: CLIENT_CODEC's rescue swallows every exception alike, and the empty-body path is exception-driven control flow
- LOCATION: client_codec.e 35-115; chat_json.e 164-178
- VERDICT: NEW-LOW
- EVIDENCE: correct as far as it goes (termination argued under Issue 30; the rescue sits in a caller frame of every precondition it must catch). But a codec BUG (a postcondition or invariant violation inside CHAT_JSON, a Void target) becomes an indistinguishable 502, and every empty body - the commonest error reply from proxies - is answered by raising and catching `SIMPLE_JSON.parse_message''s `not_empty' precondition (simple_json.e 34), twice per reply (`codec.error', then `salvaged_code' -> `codec.object').
- REMAINING/SUGGESTION: guard emptiness in CHAT_JSON (M7) so the rescue is the exception; keep a diagnostic `last_failure: detachable STRING_32' set in each rescue from `{EXCEPTION_MANAGER}.last_exception' (`description') so the assault can assert `last_failure' names the codec after a hostile body.

### [NEW-11]: The locator accepts any 2xx as "alive" - a foreign local service on the port receives the login (password) in plaintext http
- LOCATION: SERVICE_LOCATOR.probe line 109 (`last_probe_alive := l_reply.is_success'); CHAT_HEALTH (chat_health.e) defines the reply
- VERDICT: NEW-LOW
- EVIDENCE: `test_locator_prefers_live_local_then_standby' scripts `200 {"store":true}' but `200 ok' also passes (362-364). With `prefers_local' (the default, client_config.e 31) and something else listening on 127.0.0.1:8080 (a dev server, a printer daemon), the GUI chooses it and `login' POSTs the username and password to it. It is loopback, so only a local process sees them; the token is never involved (the answer is not a login reply -> 502). Still, a health probe that checks nothing is a weak discriminator.
- REMAINING/SUGGESTION: `probe' requires the body to decode to an object carrying the health flags CHAT_API.health emits: `last_probe_alive := l_reply.is_success and then is_health_reply (l_reply.body)'; `alive_definition' becomes `last_probe_alive implies (last_probe_status >= 200 and last_probe_status <= 299)' plus `shape_checked: last_probe_alive implies is_health_reply (last_probe_body)'.

### [NEW-12]: Small contract gaps (bundle)
- LOCATION: client_config.e 148-173; chat_client.e 116-133, 248-256; chat_url_rules.e 129-135; event_poller.e 194-198
- VERDICT: NEW-LOW
- EVIDENCE: (a) `set_primary_url' frames `preference_kept' and `port_kept' but not `window_kept', unlike `add_server_url' (131) and `set_only_server_url' (145). (b) `adopt_session' lacks `require logged_out' (M11). (c) `is_hex_64' duplicated (M6). (d) `same_url ensure reflexive_on_case: Result implies a_first.count = a_second.count' - the clause says "same length", not reflexivity; rename `same_length'. (e) `EVENT_INBOX.report_outage' substitutes a stock message for an empty one (134-138) - fine, but `EVENT_POLLER.report' could require `not a_message.is_empty' (CHAT_ERROR guarantees it, chat_error.e 75) and the fallback is then provably dead.
- REMAINING/SUGGESTION: add `window_kept' to `set_primary_url'; `adopt_session require logged_out: not is_logged_in'; delegate `is_hex_64'; rename the clause.

### [NEW-13]: Phase-4 notes to carry forward (INFO, no verdict weight)
- (a) HTTP_TRANSPORT must not follow redirects: `error_of' already treats a 3xx as a final 502 (`unusable_is_502'), so state it in the deferred contract note ("a 3xx is the reply; the transport never follows it") and set `WINHTTP_OPTION_REDIRECT_POLICY_NEVER' in WINHTTP_TRANSPORT - WinHTTP's default resends the Authorization header to an https redirect target. The exposure is only to a host the legitimate server names, hence INFO.
- (b) `send' and `load_roster' block the root processor for up to `Default_timeout_seconds' = 15 s (chat_client.e 291) - a 15 s stall is not a "short call" on a GUI thread; a 5 s post timeout or a poster processor is a Phase 4 choice.
- (c) The poller sleeps a backoff of up to 30 s and blocks inside WinHTTP for up to 30 s; `stop' is noticed only between the two, and SCOOP's runtime waits for processors at exit - closing the window may take up to a minute unless the transport can be cancelled (`WinHttpCloseHandle' from the root).
- (d) `requests_model' and `HTTP_REQUEST_RECORD.mentions' are still unused by any test.
- (e) The presenter decodes every page a second time on the root (the poller's client already decoded it to validate) - by design ("only bytes cross"); the cost is one 200-event decode per page per tick.

---

## D. Answers to the orchestrator's targeted questions (condensed)

- (a) URL rules: no defeat of the token rule found; forms tried are listed under Issue 36. The https authority shape is loose (NEW-5) but never plaintext.
- (b) CHAT_CLIENT: the token is written nowhere but memory (`token' is `{NONE}'; the host's copy; the test double's record). `hand_session_to' passes the root's own STRING_8 as a `separate READABLE_STRING_8' - lock passing makes the call synchronous and `adopt_session' copies with `make_from_separate' (124); the host retains no reference into the root. `adopt_session' is exported to `{CHAT_CLIENT}' and called only by `hand_session_to'. "Bearer only over TLS or loopback" is proved by CHAT_ENDPOINT's invariants `acceptable' + `secure_by_construction' (derived from the URL), CHAT_CLIENT's `make.secure', invariant `never_plaintext', `exchange.token_over_tls', and the `{NONE}' export of `authorized_headers'; the soft spot is the exported mutable `base_url'. `logout' clears before the exchange; a failed exchange still ends `logged_out', and the server-side session lives on until expiry (the caller is not told).
- (c) CLIENT_CODEC: the retry cannot loop (`l_failed' persists across `retry'; the second pass skips the body; Result stays Void; the postcondition then holds). A precondition violation of `CHAT_ERROR.make' inside CHAT_JSON is signalled in CHAT_JSON's frame and rescued one frame up in CLIENT_CODEC - the right frame. A precondition violation of `CLIENT_CODEC.error' itself would be signalled in `CHAT_CLIENT.error_of' and NOT rescued; it is unreachable (branch order + HTTP_REPLY invariant). The one that IS reachable and unrescued is `CHAT_ERROR.make' called directly from `error_of' (NEW-1).
- (d) EVENT_INBOX: `put' copies bytes (`make_from_separate', 101) and retains no separate reference; `take' returns `detachable STRING_8' (a reference on the inbox's processor) and the presenter copies it with `make_from_separate' (chat_presenter.e 356). Bounded at 64 with `dropped' counted - and `dropped' is observed by nobody (NEW-2).
- (e) EVENT_POLLER.run: `is_stopped' is read before every poll (`should_stop (inbox)' in the loop guard) and before every sleep; not during a sleep or a blocking poll. It spins when the server answers empty successes instantly (NEW-3). Cursor monotonicity is proved (`cursor.max', `cursor_monotonic'). 401 -> `session_lost' -> loop ends -> the GUI hears an outage text and nothing else (M3 PARTIAL).
- (f) CHAT_PRESENTER.pump: the foreground/unread/badge laws hold and are tested including a mid-pump flip; `pages_pumped' counts every page taken (unreadable ones included); a foreign-room page changes nothing but `pages_pumped' (tested); `name_of' disambiguates twins with ` (@username)' (tested) but not the reserved "system" (NEW-6).
- (g) SERVICE_LOCATOR: never remote unasked (`never_remote_unasked'), probes bounded (`bounded_probes'), health via `url_for'; a 2xx of garbage counts as alive (NEW-11).
- (h) CLIENT_CONFIG: `servers_distinct' and `has_url' both go through `same_url' (case-insensitive scheme and host), so the invariant and the query agree; `set_primary_url' moves a known entry to the front without duplicating it (tested with `https://SUE-CHAT...'); `window_kept' is the one missing frame (NEW-12a).

---

## Summary

| Verdict | Count | Items |
|---|---|---|
| FIXED | 13 | 22, 29, 36, M2, M4, M6, M8, M9, M10, M11, M12, M13 (+ Issue 25, out of cluster, not counted) |
| DISSOLVED | 4 | 4, 5, M1, M5 |
| PARTIAL | 5 | 28 (residual = NEW-1), 30, M3, M7, LOW bundle |
| OPEN | 0 | - |
| NEW-HIGH | 2 | NEW-1 (`salvaged_code' -> CHAT_ERROR.make `known' violation; the poller dies silently), NEW-2 (inbox drop after the cursor moved = events lost for the session; `dropped' unobserved) |
| NEW-MEDIUM | 1 | NEW-3 (no floor between successful polls - tight loop on an instant empty answer or a status flood) |
| NEW-LOW | 9 | NEW-4 .. NEW-12 |
| INFO | 1 | NEW-13 (a-e) |

Overall assessment: PASS WITH CONDITIONS.

The repair pass did what was asked, and the SCOOP restructuring genuinely dissolves the lock-related findings: the poller, the inbox and the presenter each own their state; every exact postcondition now names state that a single processor writes; only bytes cross processors (copied with `make_from_separate' in all four places); the token cannot be sent in clear by any path the contracts allow; the echo and since-contracts are enforced in the bodies; and the assault now proves the token law across every request and contains all ten tests the review asked for. Two conditions before this cluster is closed: (1) NEW-1 - `salvaged_code' must return only codes `CHAT_ERROR.is_known_code' accepts, otherwise a plausible error reply (`{"code":"throttled"}') is an uncaught precondition violation that kills the poller processor silently or the GUI loudly; (2) NEW-2 - the poller must not move its cursor past a page the inbox refused (the SCOOP wait-condition form makes the refusal impossible on the live path), or the drop must be surfaced to the member. Both are small, local changes. The four substantive PARTIALs are worth closing in the same pass: `is_iso8601' as a validity check plus an empty-body guard in CHAT_JSON (so the codec's own promise is true, not merely the client's rescue), and a session-lost signal from the inbox so a 401 closes the room and prompts a login instead of leaving a dead poller behind a latched error. The quiet-poll floor (NEW-3) is recommended before Phase 4 puts every member's client on the same server.
