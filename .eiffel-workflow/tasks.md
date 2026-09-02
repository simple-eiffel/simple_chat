# Implementation Tasks: simple_chat (Phase 4)

**Status 2026-09-02:** Tasks 1–10 DONE, plus Task 9b. The server is complete (live; `@claude`
answers in the room — smoke-proven over HTTP; SSE streams and the per-IP lockout proven live; three
SCOOP concurrency defects and the re-entrant-wake phantom raise found live and fixed). The client
stack ran a live WinHTTP round trip, and **Task 10 landed the window**: `SW_CHAT_VIEW` over
simple_widgets with shaped text on, `LOGIN_WINDOW`, and a `CLIENT_APP` that locates, resumes or asks,
opens the room and pumps the presenter from the window's own heartbeat. What remains is not code:
Larry's console smoke at the keyboard (`RUNBOOK.md`), because no headless assault can look at pixels.

Ordered by dependency (approach.md section 4; stub inventory of 2026-08-31: 80 `Phase 4` markers).
Standing rules for every task: the contracts are the specification — bodies satisfy them; a
contract change is reported, never slipped in. Clean compile (`rm -rf EIFGENs`), zero warnings,
whole assault green, tests added per task, CRLF preserved, README/docs updated when behavior lands.

## Task 1: CHAT_SERVICE bodies over the memory store  ✔ DONE
**Files:** src/service/chat_service.e (15 stubs)
**Features:** authenticate, session_for_token, revoke, revoke_bot_token, post_message, post_image,
post_system, publish_status, store_upload, events_since, events_before, create_user,
create_first_admin, create_bot, reset_password, change_password
### Acceptance
- [ ] Every postcondition already written holds at runtime (lockout via limits, marker rule,
      duplicate refusals, sha256/path pinning, sessions revoked on reset)
- [ ] Behavioral assault: login lockout after config.login_failures_per_10_minutes (limits.advance
      to expire), bot marker prefixed exactly once, upload by signature stored as <sha256>.<ext>,
      paging gapless, token round trip (create_bot → session_for_token → revoke)
- [ ] No store schema change; MEMORY_CHAT_STORE contracts already carry the needed operations
### Dependencies: none — pure memory + PASSWORD_HASHER/SESSION_ISSUER/SIMPLE_ENCRYPTION.

## Task 2: CHAT_API + CHAT_REQUEST_HANDLER completion  ✔ DONE
**Files:** src/web/chat_api.e (login token path `not_yet`, attachment serving, admin answers),
src/web/chat_request_handler.e (wall-clock `needs_session` clauses — re-review NEW-LOW)
### Acceptance: token travels once in the login reply and nowhere else; every route answers per
its contract against the in-memory service; handler tests through TEST_SCOOP_CONSUMER patterns.
### Dependencies: Task 1.

## Task 3: Cross-processor doorbell assault (Phase 5 item pulled early — MANDATORY)  ✔ DONE
**Files:** new testing target (pattern: simple_web_scoop_tests)
### Acceptance: subscribe → post → wake → wait_for across real processors; an empty wait times out
at ~seconds; a post during the wait returns early with the page; no wake is lost; dispatcher
wake→dispatch_pending→dispatcher_post round trip over the separate API.
### Dependencies: Tasks 1-2 (a service that actually posts).

## Task 4: SQLITE_CHAT_STORE + CHAT_SCHEMA.migrate + equivalence assault  ✔ DONE
**Files:** src/store/sqlite_chat_store.e (40 stubs), src/store/chat_schema.e
### Acceptance: the SAME store assault runs against both stores with identical outcomes (ordering,
errors, ids); migrations back up first; open refuses an ahead schema via last_open_error.
### Dependencies: Task 1; simple_sql (present).

## Task 5: Configuration + server app  ✔ DONE
**Files:** src/config/server_config.e (make_from_file), apps/server/server_app.e (serve,
create_admin with double password prompt), facade door_matches_config (re-review M-G)
### Acceptance: an invalid file refuses to serve and names each field (D6: config problems are
validation outcomes, not crashes); --create-admin refused once an admin exists.
### Dependencies: TOML parsing — verify whether a simple_toml library exists; if not, research
before building (never riff).

## Task 6: Ops — the door and DNS actually run  ✔ DONE
**Files:** apps/server/ops/caddy_front_door.e (start/stop/check_health child management, absolute
caddy.exe discovery — M-J), apps/server/ops/duckdns_updater.e (the HTTP update)
### Acceptance: stop proves the child is gone (Issue 27); update never logs or urls the token.
### Dependencies: simple_process wait_for_exit/kill (dependency task — not landed).

## Task 7: Participant engines  ✔ DONE
**Files:** claude_code_participant.e (answer: claude -p, sessions, --json-schema, image_path
fence), ollama_participant.e / ollama_shaper.e / claude_shaper.e, bible/shape run_arguments
(SIMPLE_ASYNC_PROCESS wait_seconds/kill)
### Acceptance: a hung engine is killed at timeout_seconds and counted one failure; the sandbox
and tools-off invariants hold on the real child; the marker and via disclosure laws hold end to end.
### Dependencies: Task 1; Larry merges simple_ai_client feature/claude-code-sandbox-flags;
CLAUDE_CODE_CLIENT --json-schema (dependency task); simple_process kill.

## Task 8: Web streaming + peer address  ✔ DONE
**Files:** src/web/web_stream_sink.e, handle_stream (SSE), per-IP lockout wiring (M-F),
STREAM_SINK byte-count wording under real sockets (M-A), CHAT_WEB_APP pre-bind claim
### Dependencies: simple_web streaming response + peer address + multipart (dependency tasks).

## Task 9: Client transport and shell  ✔ DONE
**Files:** apps/client/winhttp_transport.e (REDIRECT_POLICY_NEVER), client_config.e load/save
(%APPDATA%, token only as DPAPI ciphertext), tray_notifier.e, client_app.e + POLLER_HOST wiring
### Dependencies: simple_winhttp (promote OCR_HTTP), SHELL_TRAY (simple_shell), DPAPI
(simple_encryption) — all dependency tasks.

## Task 9b (2026-09-02): client post_image + service backup  ✔ DONE
**Files:** src/client/chat_client.e (post_image), src/domain/chat_header_text.e (NEW),
src/web/chat_request_handler.e (header_32 now decodes what the client writes),
src/service/chat_service.e (backup, fresh_backup_path), src/store/chat_store.e
(ADDITIVE `backup_to`), sqlite_chat_store.e, memory_chat_store.e
### What landed
- `CHAT_CLIENT.post_image` sends the bytes as the body, the name and caption on
  `X-File-Name` / `X-Caption` as percent-encoded UTF-8 (CHAT_HEADER_TEXT: a header
  line carries printable ASCII and nothing else - SIMPLE_WINHTTP refuses the rest
  before a byte leaves the machine), `Content-Type: application/octet-stream`, the
  bearer where it always is, and decodes the 201 through CLIENT_CODEC.
- **ADDITIVE store feature** (reported, not slipped in): `CHAT_STORE.backup_to
  (a_path: READABLE_STRING_32): BOOLEAN` - SQLite effects it with `VACUUM INTO`,
  the memory oracle answers False and writes nothing. No existing require, ensure,
  invariant or signature was touched.
- `CHAT_SERVICE.backup` writes to `<data_dir>/backups/simple_chat-<stamp>[-N].db`
  and answers the path; a failure is a 503 result, never an exception. POST
  /admin/backup has worked all along and now answers 200 with the path.
### Acceptance
- [x] Scripted post_image round trip: method, path, both headers, byte count,
      bearer, decoded event (is_image, room id); Hebrew + U+1F916 survive to the
      request and back through the server's own decoder; the header table passes
      SIMPLE_WINHTTP.is_header_table_clean
- [x] backup over a REAL SQLite store in a scratch data_dir: the path is under
      data/backups/, the copy re-opens as a database and reads the posted event
      back, two backups in one second are two files; the memory store answers an
      error and never raises
- [x] Live: the finalized server booted, the client posted a PNG whose Hebrew file
      name and emoji caption came back byte for byte over real HTTP

## Task 10: The visible client  ✔ DONE (console smoke pending)
**Files:** `apps/client/sw_chat_view.e` (CHAT_VIEW effected over simple_widgets: SW_CHAT_THREAD with
`enable_shaped_text`, composer, send, header strip with the room name / unread badge / connection
line, status and error lines), `apps/client/login_window.e` (server, name, masked password,
remember-me, refusal line; `attempt` is the host's agent, so the door is assaultable with no server),
`apps/client/chat_input_box.e` (SW_TEXT_BOX with Enter-to-send, the hook the toolkit does not offer),
`apps/client/client_app.e` (locate → remembered session or the door → first room → poller → the
window whose 250 ms tick is one `pump`), `apps/client/stage_client.sh`, `testing/window_assault.e`,
the live pane round trip in `testing/wiring_assault.e`, and `RUNBOOK.md`.

Additive, contract-carrying features in `src/` (no existing clause touched): `CHAT_CLIENT.resume`
(take up a remembered token, proved at `GET /me`), `CHAT_CLIENT.rooms`, `CHAT_CLIENT.remember_session_in`
(seals the session without ever exposing the token), `CLIENT_CODEC.member` / `.array`.

### Acceptance
- [x] Every CHAT_VIEW contract discharged by SW_CHAT_VIEW; the pane assaulted OFFSCREEN
      (SW_WINDOW allocates a cairo image surface in `make` and creates nothing native
      until `run`), including under a real CHAT_PRESENTER with a real EVENT_INBOX
- [x] The window carries an SW_SHAPING kit and lays the D-015 acceptance line out RTL,
      Greek run leftmost and Hebrew run rightmost, every character covered
- [x] Enter submits; an empty line is never handed on; an ordinary character types
- [x] LOGIN_WINDOW refuses a non-https stranger, an empty or spaced name and an empty
      password before a byte leaves the PC, and shows the server's own message otherwise
- [x] CLIENT_APP's decision tree over a scripted transport: a sealed blob that `GET /me`
      honours means no password; no blob (or a refused one) means the door
- [x] LIVE: the booted server exe, `attempt_login` (the door's own agent), `open_room`,
      `send_text`, and `tick` until the posted line comes back through the REAL poller
      into the REAL pane; then a second CLIENT_APP over the same client.toml logs in
      with no password at all
- [ ] **Console smoke (Larry, at the keyboard):** `שלום 🤖 Χριστός` renders with the
      Hebrew rightmost, the robot as the Noto picture and the Greek intact; `@claude`
      answers; resize re-wraps at the drag's end; close and reopen skips the login.
      `RUNBOOK.md` is the script.

### Stated limits (deliberate, not omissions)
- An IMAGE event is shown as a named, sized attachment line carrying its caption, NOT as
  a picture: no WIC decoder is linked into this client (D-020's deferred half). The bytes
  and the name are already on the wire; only the decode is missing.
- The unread badge lives in the pane's header strip and the tray tooltip, never in the
  native title bar: simple_shell publishes no `SetWindowText` and is not this project's
  to change.
- `is_foreground` is answered by `GetForegroundWindow` against the window's own handle
  (simple_shell raises no activation event), and is False whenever there is no native
  window — which is the honest answer and the branch the headless assault drives.

### Dependencies: simple_shaping (LANDED, reached through simple_widgets' SW_SHAPING);
WIC image decoder (still deferred — see the stated limits).

## External dependency tasks (tracked, not simple_chat code)
simple_toml (existence check first) · simple_process wait_for_exit/kill · simple_winhttp ·
SHELL_TRAY · DPAPI in simple_encryption · simple_web streaming/peer/multipart/127.0.0.1 bind ·
CLAUDE_CODE_CLIENT --json-schema · merge feature/claude-code-sandbox-flags · simple_shaping · WIC
