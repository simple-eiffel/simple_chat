# Intent: simple_chat

Date: 2026-08-29 · Phase 0 · Pre-populated from `.eiffel-workflow/spec/` (01, 03, 07, 09) — nothing here re-asks what the spec already settled.

## What
A standalone group-chat system in Eiffel for a private friend group on Windows PCs:

- a **server** on Larry's PC — `simple_web` (EWF standalone) on localhost, SQLite, Server-Sent Events, rooms and an ordered event log, password accounts, image posts — behind a **swappable front door** (Caddy now, an Eiffel door later, none when a tunnel is used);
- an **Eiffel desktop client** hosting the server-rendered HTMX/Alpine UI in WebView2 (a swappable host), with tray icon, unread badge and balloon notifications;
- **addressable participants** in the room: `@claude` (Larry's subscription, via `claude -p`), `@tools-larry` (the Eiffel Bible tools — `bible.exe` one-shot, no AI), `@shape-larry` (read-only `shape.db`), `@qwen` (local Ollama), with optional **query shaping** (free-form question → the tool's strict form) and **response shaping** (mechanical result → readable prose), cheapest engine by default and `via claude` on request;
- a **bot API** so any member's PC can run its own participant.

## Why
The group lives in Facebook Messenger, which has no API for personal group chats, so nothing can put an AI — or Larry's instruments — in the room. A screen-reading robot (the `chat_robot_spike`) proved fragile and one-machine. The group is PC-only, and Larry wants the system to stand alone: his PC, a DNS name, a certificate authority, and nothing else outside; distributed as runnable folders; everything non-Eiffel (Caddy, WebView2, `claude`, Ollama) held behind contracts so it can be replaced piece by piece — the same philosophy as CNG for crypto.

## Users
| Who | How |
|---|---|
| Larry (host, admin) | runs the server folder at logon; creates accounts; owns the participants and their limits; addresses Claude and his tools in the room |
| Nick, Mike, others (members) | copy the client folder, run it, enter the server URL and their password once; chat with text and pictures; get balloons; address `@tools-larry Gen 1:1` or `Claude: …` |
| A member's own AI (bot) | a relay on that member's PC posting through the bot API with a token, as its own 🤖 identity |
| Larry's tools (participants) | `bible.exe`, `shape.db`, Ollama — invoked by the server, answering as 🤖 members |

## Acceptance Criteria
- [ ] Larry creates an account from the admin page; that member logs in from another PC over the internet and stays logged in across client restarts
- [ ] `שלום 🤖 Χριστός` posted by one member renders correctly for every other within 2 s (WAN), RTL intact
- [ ] A 2 MB PNG posts and renders inline for every member within 2 s; a 9 MB file is refused with a message
- [ ] A member's client, asleep for 10 minutes, shows every message posted meanwhile exactly once on wake
- [ ] Scrolling up loads earlier pages with no gaps or duplicates
- [ ] A message starting `Claude:` gets a reply from `🤖 Claude` in the room; a 6th request from the same member within an hour gets a polite refusal and no Claude call
- [ ] Every AI- or tool-authored message begins with 🤖 (an invariant, not a convention)
- [ ] `@tools-larry Gen 1:1` returns the verse (WLC + KJV) from `bible.exe`; `@tools-larry Gen 1:1 | dir` is refused with a help line (argv allowlist)
- [ ] `@shape-larry en_christo` returns the FITS/PARTIAL/FAILS counts; `via claude` phrases it through Claude; `via plain` returns the raw result; the reply echoes what was actually run
- [ ] A curl script with a bot token reads events since N and posts as `🤖 MikeBot`
- [ ] A balloon appears on a new message while the client is not foreground; the tray tooltip shows the unread count; focus clears it
- [ ] Changing `front_door = "caddy"` to `"none"` and restarting changes nothing else; `EIFFEL_FRONT_DOOR` reports "not in this build" honestly
- [ ] `simple_chat_server.exe` refuses to start with an invalid TOML and names the field; warns if `ANTHROPIC_API_KEY` is set in its environment
- [ ] The server log after a full scenario contains no password, token or hash (grep test)
- [ ] The assault suite runs the whole service against `MEMORY_CHAT_STORE` and again against `SQLITE_CHAT_STORE` with identical results; contracts live in the shipped build's tests
- [ ] JSON and base64 dependencies pass independent vectors before the first release

## Out of Scope
- End-to-end encryption; voice/video; federation; phones
- A Messenger bridge (the spike stays a separate experiment)
- Native (non-WebView2) rendering — `simple_shaping` is its own Tier 2 project with swappable backends
- The Eiffel front door itself (`simple_tls`, `simple_acme`) — Tier 1, behind the contract this project declares
- Replies, reactions, @mentions of people, search, link previews, typing indicators, read markers, editing, pins — Phase 2
- A Windows service wrapper — a scheduled task at logon suffices for v1

## Dependencies (REQUIRED - simple_* First Policy)

| Need | Library | Justification |
|------|---------|---------------|
| HTTP server, routing, uploads, chunked responses | simple_web (over ISE EWF) | production wrapper; raw `wsf_request`/`wsf_response` reachable for multipart and SSE |
| UI rendering | simple_htmx, simple_alpine | `bible_htmx` precedent; needs SSE attributes added |
| Storage | simple_sql (eiffel_sqlite_2025) | WAL presets; the ecosystem's database |
| Password hashing, CSPRNG, SHA-256 | simple_encryption 2.0.0 | fixed and independently verified this project |
| JSON | simple_json | events, API, payloads (to be vector-checked) |
| Config | simple_toml | human-edited server config |
| IDs, time, logging, processes | simple_uuid, simple_datetime, simple_logger, simple_process | plumbing |
| Base64 | simple_base64 | tokens; (to be vector-checked) |
| UTF-8 conversions | simple_encoding | STRING_32 ↔ bytes at the HTTP edge |
| Claude / Ollama engines | simple_ai_client (`CLAUDE_CODE_CLIENT`, `OLLAMA_CLIENT`) | participants and shapers |
| Client window, clipboard, tray | simple_shell (≥ 1.8.0; `SHELL_TRAY` to add) | native shell |
| WebView2 host | simple_browser | `SHELL_WEBVIEW_HOST` (Spike B) |
| Periodic ticks (DDNS, supervision) | simple_scheduler | present in the ecosystem |
| Model queries | simple_mml | frame conditions in memory store, bus, limiter |
| Tests | simple_testing | assault suite |
| Regex for the address parser and allowlists | simple_regex | `@handle … via …`, verse-reference shapes |

**ISE only (no simple_* equivalent):** `base`; `thread` (MUTEX for the store, bus and limiter — no simple_thread exists); EWF through simple_web.

## MML Decision (REQUIRED)

**Decision:** YES-Optional
**Rationale:** Model queries (`MML_SEQUENCE`, `MML_MAP`, `MML_SET`) give the memory store, the event bus and the rate limiter provable frame conditions (`|=|`), and the memory store is the oracle the SQLite store is tested against. The SQLite store satisfies the same postconditions by construction and does not carry model queries in the production build.
