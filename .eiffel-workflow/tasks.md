# Implementation Tasks: simple_chat (Phase 4)

**Status 2026-09-02:** Tasks 1–9 DONE. The server is complete (live; `@claude` answers in
the room — smoke-proven over HTTP; SSE streams and the per-IP lockout proven live; three SCOOP
concurrency defects and the re-entrant-wake phantom raise found live and fixed). The client
stack compiles and ran a live WinHTTP round trip. Task 10 (the visible client) is gated on
simple_shaping, which is at its Phase 2 repair pass.

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

## Task 10: The visible client
**Files:** SW_CHAT_VIEW over simple_widgets (SW_CHAT_THREAD exists)
### Dependencies: /eiffel.research D:\prod\simple_shaping (the long pole), WIC image decoder.

## External dependency tasks (tracked, not simple_chat code)
simple_toml (existence check first) · simple_process wait_for_exit/kill · simple_winhttp ·
SHELL_TRAY · DPAPI in simple_encryption · simple_web streaming/peer/multipart/127.0.0.1 bind ·
CLAUDE_CODE_CLIENT --json-schema · merge feature/claude-code-sandbox-flags · simple_shaping · WIC
