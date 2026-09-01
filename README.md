# simple_chat

A standalone group chat for a private circle of friends on Windows PCs: an Eiffel server you host yourself, an Eiffel thick client, and addressable AI and tool participants in the room. Part of the [Simple Eiffel](https://github.com/simple-eiffel) ecosystem.

## Status

**Phase 1 — contracts and skeletons.** Nothing here chats yet. What exists is the full class design with its contracts (preconditions, postconditions, invariants, MML model queries and frame conditions), the parts small enough to implement outright, and an assault suite that exercises them: **148 unit tests plus a 6-scenario cross-processor SCOOP proof, zero compiler warnings.** Two adversarial review rounds and their repairs are done, and Phase 4 implementation Tasks 1–7 are complete: the server runs — accounts, rooms, messages, images, history, SQLite persistence, and a live `@claude` participant that answers in the room through a sandboxed `claude -p` (proven end to end over HTTP). The design record lives in `.eiffel-workflow/`; remaining work is SSE streaming, the public door, and the thick client.

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
| Apps | `apps/server/`, `apps/client/` | `SERVER_APP` (`--create-admin`), `CLIENT_APP`, `TRAY_NOTIFIER`, `WINHTTP_TRANSPORT` |

Lock order, never inverted: store < limiter < bus, and no lock is held while calling out to a subscriber.

## Build and test

```bash
cd /d/prod/simple_chat
/d/prod/ec.sh test -config simple_chat.ecf -target simple_chat_tests
./EIFGENs/simple_chat_tests/F_code/simple_chat.exe
```

Targets: `simple_chat` (library), `simple_chat_server`, `simple_chat_client` (compiles once `SHELL_TRAY` in simple_shell and `simple_winhttp` exist), `simple_chat_tests`.

## Dependencies

`base` (the only ISE library — `MUTEX` and `CONDITION_VARIABLE` live in EiffelBase) plus simple_mml, simple_json (≥ 0.2.0 — earlier versions lose emoji), simple_datetime, simple_logger, simple_encryption (≥ 2.0.0), simple_uuid, simple_sql, simple_process, simple_base64, simple_encoding, simple_web, simple_ai_client; the client adds simple_shell and simple_widgets.

On the critical path before the first conversation: `simple_shaping` (Hebrew/RTL/emoji in simple_widgets), a WIC image decoder, `simple_winhttp`, `SHELL_TRAY`, DPAPI token storage in simple_encryption.

## Design record

`.eiffel-workflow/research/` (scope, landscape, requirements, decisions D-001–D-020, innovations, risks, recommendation), `.eiffel-workflow/spec/` (01–08 plus addenda 09 *participants* and 10 *thick client*), `intent.md` → `intent-v3.md`, and `evidence/` for every phase gate.

## Never

End-to-end encryption, voice or video, federation, phones, a Messenger bridge.

## License

MIT
