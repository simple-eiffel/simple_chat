# INNOVATIONS: simple_chat

Date: 2026-08-28

## What Makes This Different

### I-001: The AI is a participant, not a feature
**Problem Solved:** Existing chats bolt AI on as a sidebar or a command; nobody in the room can *address* it the way they address a person.
**Approach:** `Claude:` / `ROBOT:` at the start of a message is the whole interface. The reply is an ordinary message from an ordinary user with a 🤖 name, subject to the same history, search, and notifications.
**Novelty:** Addressability plus disclosure: every AI post is marked, rate-limited per asker, and attributed ("Nick asked…").
**Design Impact:** Bots are users (Matrix's model); the dispatcher is a room member with a token, not a special path through the server.

### I-002: Bring-your-own-AI, symmetrically
**Problem Solved:** Larry's subscription answers for the room today; friends may want their own model, their own persona, their own machine.
**Approach:** The bot API is the same HTTP API the UI uses (`/events?since=N`, `POST /rooms/{id}/messages`, uploads) with a token per bot user. A friend runs the same relay program on their PC pointed at Ollama or `claude -p`; it appears as `🤖 MikeBot`.
**Novelty:** Several AIs in one room as distinct, visible participants — no relay chain through the host.
**Design Impact:** The relay is a separate small program (or a mode of the client); the server never knows which model is behind a bot.

### I-003: Design by Contract on a chat server
**Problem Solved:** Chat servers accumulate silent rule drift (rate limits bypassed, markers dropped, ordering broken).
**Approach:** Invariants on `EVENT` (monotonic ids per room), `MESSAGE` (bot posts carry the marker), `RATE_LIMITER` (never more than N per window), `SESSION` (token entropy) — enforced at runtime in the assault build.
**Novelty:** The guardrails Larry insisted on are contracts, not conventions.
**Design Impact:** Domain classes are pure Eiffel with no EWF dependency, testable without a socket.

### I-004: One home PC, no third-party service
**Problem Solved:** Every hosted chat routes the group's words through someone else's servers.
**Approach:** Server, database, image store, TLS terminator, DNS updater — all in one folder on Larry's PC; only DNS and a certificate authority are external.
**Novelty:** Not new in principle; unusual to make it a one-folder Windows deliverable.
**Design Impact:** Operability requirements (start at logon, survive sleep, one config) are first-class, not afterthoughts.

### I-005: Server-rendered UI, native shell
**Problem Solved:** Two UIs (web and desktop) double the work; a pure native UI cannot render Hebrew today.
**Approach:** The server renders HTMX/Alpine HTML once; the Eiffel shell hosts it in WebView2 and adds the native parts (tray, balloons, badge, autostart). A browser tab gets the same UI for free.
**Novelty:** The desktop client is ~1,000 lines of Eiffel because the UI lives on the server.
**Design Impact:** UI changes ship by restarting the server; clients rarely need updates.

### I-006: Claude session continuity per room (later)
**Problem Solved:** Each `claude -p` call starts cold.
**Approach:** `CLAUDE_CODE_CLIENT.last_session_id` per room; `--resume` for follow-ups within a window.
**Novelty:** The robot remembers the thread it was asked about.
**Design Impact:** The dispatcher keeps a small session table; a `/forget` command clears it.

## Differentiation from Existing Solutions
| Aspect | Existing | Our Approach | Benefit |
|--------|----------|--------------|---------|
| AI in the room | Plugins, slash commands, sidebars | Addressed by name; answers as a marked member | Natural for non-technical friends |
| Whose model | The vendor's | Any member's, on their own PC | Symmetry, privacy, no per-seat fees |
| Hosting | Cloud or containers | One folder on a Windows PC | Nothing to rent, nothing to learn |
| Rules | Conventions in code | Contracts in the assault build | Rules cannot silently rot |
| Clients | Native app per platform | Server-rendered UI + thin Eiffel shell | One UI, Hebrew renders, tray works |
