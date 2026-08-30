# PARSED REQUIREMENTS: simple_chat

Date: 2026-08-29 · Source: `.eiffel-workflow/research/01..07` (read in full; authored 2026-08-28/29)

## Problem Summary
A private friend group on Windows PCs wants a chat of its own in which AI participants — Larry's Claude on his subscription, and later each member's own AI — can be addressed by name mid-conversation. Their current chat (Facebook Messenger) has no API for personal group chats. The system must stand alone on Larry's PC, reach members over the internet with nothing but a DNS name and a certificate authority outside it, install as a runnable folder, and put nothing non-Eiffel on the critical path that cannot later be swapped out.

## Scope
### In Scope
- Server on Larry's Windows PC over `simple_web` (EWF standalone httpd), plain HTTP on localhost behind a **swappable front door** (D-013)
- Username + password accounts, admin-created; sessions that survive client restarts
- Rooms modeled from day one; v1 UI shows one group room
- Text (emoji, Hebrew, Greek) and image posts; full history with paging; live updates (SSE) with catch-up
- Eiffel desktop client from day one: WebView2 shell, tray icon, balloon notifications, unread badge
- Claude as a server-side participant (`Claude:` / `ROBOT:`), per-user rate limit, 🤖 marker
- Bot API with per-bot tokens so any member's PC can run its own participant
- Runnable-folder distribution for server and client; one config file; dynamic-DNS updater

### Out of Scope
- End-to-end encryption; voice/video; federation; phones; a Messenger bridge (the screen-robot spike stays separate)
- Native (non-WebView2) rendering: `simple_shaping` is its own Tier 2 project (D-014)
- The Eiffel front door itself (`simple_tls` + `simple_acme`): Tier 1, ships behind the D-013 contract later

## Functional Requirements
| ID | Requirement | Priority | Source | Acceptance |
|----|-------------|----------|--------|------------|
| FR-001 | Admin-created accounts, username + password | MUST | research/03 | Admin creates `nick`; Nick logs in; wrong password refused |
| FR-002 | Session persists across client restarts until logout | MUST | research/03 | Reopen client → still in; logout → login screen |
| FR-003 | Rooms modeled; v1 shows the default room | MUST | research/03 | `room`/`membership` tables; UI opens default room |
| FR-004 | Text messages with full Unicode | MUST | research/03 | `שלום 🤖 Χριστός` renders for every member, RTL intact |
| FR-005 | Image posts (PNG/JPEG) inline, size-limited | MUST | research/03 | 2 MB PNG inline ≤ 2 s; oversize refused with message |
| FR-006 | History with scroll-back paging | MUST | research/03 | Pages load without gaps or duplicates |
| FR-007 | Live updates without refresh | MUST | research/03 | ≤ 1 s LAN, ≤ 2 s WAN |
| FR-008 | Catch-up after disconnect, no loss | MUST | research/03 | Sleep 10 min; every message appears once on wake |
| FR-009 | Tray balloon on new message when not foreground | MUST | research/03 | Balloon shows sender + first 100 chars |
| FR-010 | Display names distinct from usernames | SHOULD | research/03 | "Nick 🎸" on messages |
| FR-011 | Claude participant answers `Claude:` / `ROBOT:` in-room | MUST | research/03 | Reply posts as 🤖 Claude within the rate limit |
| FR-012 | Per-user AI rate limit | MUST | research/03 | 6th request in an hour refused politely, no Claude call |
| FR-013 | Every AI post carries 🤖 and the bot identity | MUST | research/03 | No bot message renders without it |
| FR-014 | Bot API: token auth; read events since N; post text/image | MUST | research/03 | curl on Mike's PC posts as 🤖 MikeBot |
| FR-015 | Admin page: users, create, reset password, revoke bot token | SHOULD | research/03 | Larry does all four from the UI |
| FR-016 | Unread count on tray tooltip / title | SHOULD | research/03 | "(3) simple_chat" |
| FR-017 | Message length and upload size limits, configurable | SHOULD | research/03 | Defaults 4,000 chars / 8 MB |
| FR-018 | Server config file | MUST | research/03 | Edit TOML, restart, applied |
| FR-019 | Client remembers server URL | MUST | research/03 | Asked once |
| FR-020 | Browser-tab access to the same UI | COULD | research/03 | Edge opens the URL and chats |

## Non-Functional Requirements
| ID | Requirement | Category | Measure | Target |
|----|-------------|----------|---------|--------|
| NFR-001 | Concurrent clients, each holding an SSE stream | PERFORMANCE | connections | 20 without degradation |
| NFR-002 | Delivery latency | PERFORMANCE | post → visible elsewhere | ≤ 2 s WAN |
| NFR-003 | Transport security | SECURITY | TLS on the public port | TLS 1.2+ on a maintained stack (front door) |
| NFR-004 | Password storage | SECURITY | KDF | PBKDF2-HMAC-SHA256 ≥ 600,000 (simple_encryption 2.0.0, verified) |
| NFR-005 | Session tokens | SECURITY | entropy / transport | 256-bit CSPRNG; `Secure; HttpOnly; SameSite=Lax` |
| NFR-006 | Login abuse | SECURITY | attempts | backoff after 10 failures / 10 min per user and per IP |
| NFR-007 | No secrets in logs | SECURITY | review | never a password, token, or hash in a log line |
| NFR-008 | Durability | RELIABILITY | crash mid-write | SQLite WAL; backup = data folder copy |
| NFR-009 | Recovery | RELIABILITY | server restart | clients reconnect and catch up ≤ 30 s |
| NFR-010 | Member install | OPERABILITY | steps | copy folder, run exe, enter URL + password |
| NFR-011 | Host burden | OPERABILITY | | starts at logon; survives sleep; one config; one data folder |
| NFR-012 | Privacy | PRIVACY | third parties in the data path | none but DNS and the CA |
| NFR-013 | Rendering | UX | scripts | Emoji, Hebrew (RTL), Greek, Syriac via WebView2; `dir="auto"` |
| NFR-014 | Contracts | QUALITY | DbC | every public feature; invariants on domain objects |
| NFR-015 | Tests | QUALITY | automated | domain + API without a browser; assault style; independent vectors for any format/crypto dependency |

## Constraints (simple_* First)
| ID | Constraint | Type |
|----|------------|------|
| C-001 | simple_* over ISE; ISE (EWF, eel) only where simple_* lacks it | ECOSYSTEM |
| C-002 | SCOOP-capable library code; EWF thread handler in the server | TECHNICAL |
| C-003 | Void-safe | TECHNICAL |
| C-004 | Windows 10/11 only (v1) | PLATFORM |
| C-005 | Port-forward reach; no third-party tunnel | OPERATIONS |
| C-006 | Username + password | PRODUCT |
| C-007 | Eiffel desktop client from day one | PRODUCT |
| C-008 | Runnable folders, no installer | DISTRIBUTION |
| C-009 | Message pane renders Hebrew → WebView2 until `simple_shaping` | TECHNICAL |
| C-010 | Claude via `claude -p`; child must not see `ANTHROPIC_API_KEY` | TECHNICAL |
| C-011 | Everything on Larry's PC | DATA |
| C-012 | Non-Eiffel components (Caddy, WebView2) only behind swappable contracts | ARCHITECTURE (D-013, D-014) |

## Decisions Already Made
| ID | Decision | Rationale | From |
|----|----------|-----------|------|
| D-001 | BUILD in Eiffel, reuse bible_htmx / simple_shell / simple_sql / CLAUDE_CODE_CLIENT | nothing adoptable meets the constraints | research/04 |
| D-002 | simple_web over EWF standalone, thread handler | production wrapper; raw WSF escape hatches | research/04 |
| D-003 | SSE via `WSF_RESPONSE.put_chunk`; long-poll fallback behind the same `since` API | one-directional push suffices | research/04 |
| D-004 | Caddy terminates TLS on the same PC; EWF on localhost | EWF ssl ships EOL OpenSSL 1.1.1 | research/04 |
| D-005 | Duck DNS + 5-minute updater | name must follow the IP | research/04 |
| D-006 | simple_encryption 2.0.0 (CNG PBKDF2, CSPRNG) | independently verified | research/04 |
| D-007 | SQLite (simple_sql), WAL, serialized, one guarded connection; images as files | ten users; one file to back up | research/04 |
| D-008 | Eiffel shell hosting WebView2; server-rendered HTMX/Alpine UI; tray via new SHELL_TRAY | one UI codebase; Hebrew renders | research/04 |
| D-009 | Server-side AI dispatcher with triggers, rate limit, 🤖 marker; bot API tokens | the product's point | research/04 |
| D-010 | Runnable folders for server and client | Larry's standing rule | research/04 |
| D-011 | Rooms from day one | schema is not reversible | research/04 |
| D-013 | Front door behind one contract: `CADDY_FRONT_DOOR` now, `EIFFEL_FRONT_DOOR` later, chosen by config | swappable by design | research/04 |
| D-014 | Text shaping as `simple_shaping` with independently swappable backends (DirectWrite → Eiffel) | pure Eiffel is the destination | research/04 |

## Innovations to Implement
| ID | Innovation | Design Impact |
|----|------------|---------------|
| I-001 | AI as a participant, addressed by name | bots are users; dispatcher is a member with a token |
| I-002 | Bring-your-own-AI, symmetrically | bot API = the UI's API; relay program later |
| I-003 | Contracts as guardrails | invariants on EVENT ordering, bot marker, rate limits, session entropy |
| I-004 | One home PC, no third-party service | operability is first-class: start at logon, supervise Caddy, DDNS |
| I-005 | Server-rendered UI, native shell | HTML once; shell adds tray/badge/autostart |
| I-006 | Claude session continuity per room (later) | dispatcher keeps `last_session_id` per room |

## Risks to Address in Design
| ID | Risk | Mitigation Strategy |
|----|------|---------------------|
| RISK-001 | CGNAT | Phase 0 check; `NO_FRONT_DOOR` + tunnel is a config change, not a code change |
| RISK-002 | EOL OpenSSL in EWF ssl | never used: front door terminates TLS |
| RISK-003 | SSE starves EWF | heartbeat; tuned knobs; `EVENT_SOURCE` contract has a long-poll implementation |
| RISK-004 | simple_browser maturity | `CLIENT_HOST` deferred: `SHELL_WEBVIEW_HOST` first, `VISION2_WEBVIEW_HOST` fallback |
| RISK-005 | WebView2 runtime missing | `start.bat` registry check + bootstrapper |
| RISK-006 | Adoption | NFR-010; notifications; seed content |
| RISK-007 | Host PC sleeps/reboots | scheduled task at logon; clients catch up (FR-008) |
| RISK-008 | Home network exposure | localhost binding; backoff; limits; forwarded-header trust only from the front door |
| RISK-009 | Claude quota | RATE_LIMITER; concurrency 1; usage on admin page |
| RISK-010 | SQLite across threads | `CHAT_STORE` serializes through one MUTEX |
| RISK-015 | Claude latency | ephemeral "thinking" status event on the stream |
| RISK-016 | `ANTHROPIC_API_KEY` in server env | `CLAUDE_CODE_CLIENT` clears it; startup warning |

## Use Cases
### UC-001: Log in
**Actor:** Member · **Precondition:** account exists · **Main flow:** 1. client posts username/password; 2. server verifies (PBKDF2), checks backoff; 3. creates session (256-bit token, cookie); 4. redirects to the default room · **Postcondition:** session row exists; cookie set; failed attempts counter reset.

### UC-002: Post a text message
**Actor:** Member · **Precondition:** valid session; member of room · **Main flow:** 1. POST body; 2. service validates length, rate; 3. store appends event (monotonic id); 4. bus publishes; 5. every stream writes the event · **Postcondition:** event persisted; all connected clients show it.

### UC-003: Post an image
**Actor:** Member · **Precondition:** as UC-002 · **Main flow:** 1. multipart upload; 2. size/type check; 3. file stored, SHA-256 recorded; 4. image event appended and published · **Postcondition:** attachment row + file; event visible inline.

### UC-004: Live stream and catch-up
**Actor:** Client · **Precondition:** session · **Main flow:** 1. GET `/rooms/{id}/stream?since=N`; 2. server replays events > N; 3. holds the response, heartbeats every 20 s; 4. writes each published event · **Postcondition:** client has every event exactly once; reconnect resumes from its last id.

### UC-005: Address Claude
**Actor:** Member · **Precondition:** dispatcher enabled · **Main flow:** 1. message starts `Claude:`; 2. dispatcher sees the event, checks the asker's rate limit; 3. publishes ephemeral "🤖 thinking…"; 4. runs `claude -p` with persona, sender name, question; 5. posts reply as the bot user (🤖 marker enforced) · **Postcondition:** reply event persisted; rate-limit window recorded; on failure an apologetic reply is posted.

### UC-006: A member's own bot posts
**Actor:** Bot (token) · **Precondition:** bot user + token issued by admin · **Main flow:** 1. GET events since N with `Authorization: Bearer`; 2. POST message as the bot · **Postcondition:** event authored by the bot user, marker enforced.

### UC-007: Admin creates a user
**Actor:** Admin · **Main flow:** 1. admin page form; 2. service creates user with hashed password; 3. adds to default room · **Postcondition:** user can log in.

### UC-008: Notification
**Actor:** Client shell · **Precondition:** window not foreground · **Main flow:** 1. page receives event via SSE; 2. JS calls the shell bridge; 3. `SHELL_TRAY` shows a balloon and updates the badge · **Postcondition:** balloon shown; unread count incremented; cleared on focus.

### UC-009: Server start with the Caddy front door
**Actor:** Host · **Main flow:** 1. load TOML; 2. open store, migrate schema; 3. start EWF on localhost; 4. `CADDY_FRONT_DOOR.start` writes the Caddyfile and spawns `caddy.exe`; 5. DDNS updater ticks · **Postcondition:** `is_serving` on both; public name resolves; HTTPS answers.

### UC-010: Swap the front door
**Actor:** Host · **Main flow:** 1. change `front_door = "eiffel"` in TOML; 2. restart · **Postcondition:** identical behaviour through `EIFFEL_FRONT_DOOR`; no code change in the chat.
