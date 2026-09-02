# simple_chat

A standalone group chat for a private circle of friends on Windows PCs: an Eiffel server you host yourself, an Eiffel thick client, and addressable AI and tool participants in the room. Part of the [Simple Eiffel](https://github.com/simple-eiffel) ecosystem.

## Status

**Phase 4 — the window exists; Larry's console smoke is what remains.** The full class
design with its contracts (preconditions, postconditions, invariants, MML model queries and frame
conditions) is implemented and exercised by an assault suite, and Phase 4 implementation Tasks 1–10
are complete. The server runs — accounts, rooms, messages, images, history, SQLite persistence, SSE
streams for bots and curl, a per-IP lockout keyed by the real peer, the Caddy front door and DuckDNS
updater, and a live `@claude` participant that answers in the room through a sandboxed `claude -p`
(proven end to end over HTTP). The client stack has run a live round trip over WinHTTP (login, post,
**images**, events, logout) with the session remembered as a DPAPI blob and a tray notifier.

**Task 10 landed the visible client.** `SW_CHAT_VIEW` is the room pane over simple_widgets with
**shaped text on** — one `SW_SHAPING` kit per window, so Hebrew reads right-to-left inside a
left-to-right pane, Greek keeps its accents and an emoji is the same Noto picture on every member's
screen; bubble height is the layout's own `total_height`, never a line count times a constant.
`LOGIN_WINDOW` is the door (server, name, masked password, remember-me, and one line that says why
the last attempt was refused). `CLIENT_APP` assembles it: locate the server, try the session this PC
remembers (`GET /me` proves it), else the door; open the first room; run the pane whose 250 ms
heartbeat is one `CHAT_PRESENTER.pump` on the GUI processor while the poller blocks on its own.
A live test drives that whole path — the real poller, the real pane — against the booted server exe.

What no headless assault can prove is that the **pixels** are right; that is `RUNBOOK.md`, and it is
the one thing still owed. Two limits are stated rather than hidden: an image event is shown as a
named, sized attachment line and not as a picture (no WIC decoder is linked into this client), and
the unread count lives in the pane's header strip and the tray tooltip rather than the native title
bar (simple_shell publishes no `SetWindowText`).

## What it will be

- **Server** (`simple_chat_server.exe`): runs as a background service on the host's PC, bound to `127.0.0.1`, reached from the internet through a swappable *front door* (Caddy today, an Eiffel TLS door later) and a dynamic-DNS name. SQLite store, append-only event log with global monotonic ids, sessions as hashed random tokens, PBKDF2 passwords (600,000 iterations, `simple_encryption` 2.0.0).
- **Client** (`simple_chat.exe`): a thick `simple_widgets` application — no browser, no WebView, no HTML anywhere. It *finds* its server: the local service first, then the configured primary, then any standby host. Live updates arrive by long-poll on the server's doorbell; Hebrew, Greek and emoji render natively once `simple_shaping` lands.
- **Participants**: `Claude:` / `ROBOT:` (Claude Code on the host's subscription), `@tools-larry` (Bible tools, no AI, argv-allowlisted), `@shape-larry`, `@qwen` (Ollama). Every one is an ordinary member with a 🤖 identity marker enforced as a class invariant, its own rate limit, and its own engine. Chat text never reaches a shell string.
- **Bot API**: JSON over HTTP with Bearer tokens, so a friend's PC can run its own participant.

## Design

| Piece | Where | Notes |
|---|---|---|
| Domain | `src/domain/` | `CHAT_EVENT` (marker invariant), `CHAT_USER`, `CHAT_MEMBER` (public view — never a hash), `CHAT_JSON` (one wire codec, both directions), `CHAT_RESULT [G]` |
| Store | `src/store/` | `CHAT_STORE` deferred; `MEMORY_CHAT_STORE` is the model-checked oracle; `SQLITE_CHAT_STORE` with a MUTEX |
| Service | `src/service/` | `CHAT_SERVICE` holds every rule; `RATE_LIMITER`; `PASSWORD_HASHER`; `SESSION_ISSUER`; `ADDRESS_PARSER` |
| Bus | `src/bus/` | The **doorbell**: `EVENT_BUS.ring (room)`; readers pull `events_since` from the store. `POLL_WAITER` (long-poll), `SSE_STREAM` (bots, curl) |
| Participants | `src/participants/` | `PARTICIPANT` and `SHAPER` hierarchies, `PARTICIPANT_REGISTRY`, `PARTICIPANT_DISPATCHER`, `TOOL_PARTICIPANT` |
| Web | `src/web/` | `CHAT_WEB_APP`, `CHAT_API` over `simple_web` — no EWF type appears in this project |
| Client stack | `src/client/` | UI-free and assaulted headless: `CHAT_CLIENT`, `EVENT_POLLER`, `CHAT_PRESENTER`, `SERVICE_LOCATOR`, `HTTP_TRANSPORT` (deferred; `MEMORY_HTTP_TRANSPORT` is scripted), `CHAT_VIEW` / `NOTIFIER` (deferred) |
| Front door, DNS | `src/door/`, `apps/server/ops/` | `FRONT_DOOR` deferred → `CADDY_FRONT_DOOR`, `NO_FRONT_DOOR`, `EIFFEL_FRONT_DOOR`; `DUCKDNS_UPDATER` |
| Window | `apps/client/` | `SW_CHAT_VIEW` (CHAT_VIEW over simple_widgets, shaped text), `LOGIN_WINDOW`, `CHAT_INPUT_BOX` (Enter submits) |
| Apps | `apps/server/`, `apps/client/` | `SERVER_APP` (`--create-admin`), `CLIENT_APP`, `TRAY_NOTIFIER`, `WINHTTP_TRANSPORT`, `POLLER_HOST` |

Lock order, never inverted: store < limiter < bus, and no lock is held while calling out to a subscriber.

## Build and test

```bash
cd /d/prod/simple_chat
/d/prod/ec.sh test -config simple_chat.ecf -target simple_chat_tests
cp $SIMPLE_EIFFEL/simple_cairo/cairo.dll EIFGENs/simple_chat_tests/F_code/
./EIFGENs/simple_chat_tests/F_code/simple_chat.exe
```

`cairo.dll` has to be beside the test runner since Task 10: the suite builds real
`SW_CHAT_VIEW` and `LOGIN_WINDOW` objects offscreen, and simple_cairo links an **import**
library — a missing DLL is a launch failure, not a degraded run. Every finalize wipes
`F_code`, so copy it back after each build.

The client's own runnable folder is built by `apps/client/stage_client.sh`, which stages
`SimpleChat.exe` (the client target renamed, because every target here finalizes to
`simple_chat.exe`), `cairo.dll`, `LICENSE-ASSETS.md`, `assets/noto-emoji/png/128/` and a
`client.toml` template into `dist/simple_chat_client/`. It is a folder you `cd` into and run,
never a zip.

Targets: `simple_chat` (library), `simple_chat_server`, `simple_chat_client`, `simple_chat_tests`,
`simple_chat_doorbell_tests`.

`RUNBOOK.md` is the console smoke: start the server, start the client, log in, post, make
`@claude` answer, post `שלום 🤖 Χριστός` and check the Hebrew is rightmost, resize, close and
reopen on the remembered session.

## Dependencies

`base` (the only ISE library — `MUTEX` and `CONDITION_VARIABLE` live in EiffelBase) plus simple_mml, simple_json (≥ 0.2.0 — earlier versions lose emoji), simple_datetime, simple_logger, simple_encryption (≥ 2.0.0), simple_uuid, simple_sql, simple_process, simple_base64, simple_encoding, simple_web, simple_ai_client; the client adds simple_shell and simple_widgets.

Landed, and all of them on the critical path: `simple_shaping` (Hebrew/RTL/emoji, reached through
simple_widgets' `SW_SHAPING`), `simple_winhttp`, `SHELL_TRAY`, DPAPI token storage in
simple_encryption. Still deferred by choice: a **WIC image decoder** — until one exists an image
event is a named, sized attachment line rather than a picture.

## Design record

`.eiffel-workflow/research/` (scope, landscape, requirements, decisions D-001–D-020, innovations, risks, recommendation), `.eiffel-workflow/spec/` (01–08 plus addenda 09 *participants* and 10 *thick client*), `intent.md` → `intent-v3.md`, and `evidence/` for every phase gate.

## Never

End-to-end encryption, voice or video, federation, phones, a Messenger bridge.

## License

MIT
