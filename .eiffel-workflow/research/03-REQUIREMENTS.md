# REQUIREMENTS: simple_chat

Date: 2026-08-28

## Functional Requirements

| ID | Requirement | Priority | Acceptance Criteria |
|----|-------------|----------|---------------------|
| FR-001 | Accounts with username + password; created by the admin (or by invite code) | MUST | Admin creates user `nick`; Nick logs in from his PC; a wrong password is refused |
| FR-002 | Session persists across client restarts until logout | MUST | Close and reopen the client → still logged in; logout → login screen |
| FR-003 | Rooms modeled (id, name, members); v1 UI shows the one group room | MUST | Schema has `room`; UI opens the default room on login |
| FR-004 | Post a text message (Unicode: emoji, Hebrew, Greek) | MUST | `שלום 🤖 Χριστός` posts and renders correctly for every member, RTL run intact |
| FR-005 | Post an image (PNG/JPEG) from disk; inline render | MUST | A 2 MB PNG appears inline for all members within 2 s; oversize is refused with a message |
| FR-006 | Full history with scroll-back paging | MUST | Scrolling up loads earlier messages in pages; no duplicates, no gaps |
| FR-007 | Live updates: a new message appears for connected clients without refresh | MUST | Latency ≤ 1 s on LAN, ≤ 2 s over WAN (measured) |
| FR-008 | Catch-up after disconnect (sleep, network drop) with no lost messages | MUST | Sleep laptop 10 min; on wake, every message posted meanwhile appears once |
| FR-009 | Desktop notification (tray balloon) on a new message while the client is not foreground | MUST | Balloon shows sender + first 100 chars; none while the room is foreground |
| FR-010 | Display names distinct from usernames | SHOULD | Nick sets "Nick 🎸"; shows on messages |
| FR-011 | Claude participant: a message starting `Claude:` or `ROBOT:` (case-insensitive) is answered in-room by user 🤖 Claude | MUST | Within the rate limit, a reply posts; the trigger text is passed to `claude -p` with sender name |
| FR-012 | Per-user rate limit on AI requests | MUST | 6th request in an hour by one user gets a polite refusal message, not a Claude call |
| FR-013 | Every AI-authored post carries the 🤖 marker and the bot identity | MUST | No bot message renders without it |
| FR-014 | Bot API: token-authenticated HTTP to read events since N and post text/image as a bot user | MUST | A curl script on Mike's PC reads new events and posts a reply as "🤖 MikeBot" |
| FR-015 | Admin page: list users, create user, reset password, revoke bot token | SHOULD | Larry does all four from the UI |
| FR-016 | Unread count on tray icon tooltip / window title | SHOULD | Title shows "(3) simple_chat" |
| FR-017 | Message length limit and upload size limit, configurable | SHOULD | Defaults 4,000 chars / 8 MB |
| FR-018 | Server config file (port, data dir, limits, Claude settings) | MUST | Edit `simple_chat_server.toml` (or json), restart, settings apply |
| FR-019 | Client config: server URL, remembered on first run | MUST | First run asks for `https://…`; remembered |
| FR-020 | Browser-tab access to the same UI (no client) | COULD | A member opens the URL in Edge and chats |

## Non-Functional Requirements

| ID | Requirement | Category | Measure | Target |
|----|-------------|----------|---------|--------|
| NFR-001 | Concurrency for the group | PERFORMANCE | Simultaneous connected clients (each holding one SSE stream) | 20 without degradation |
| NFR-002 | Message delivery latency | PERFORMANCE | Post → visible on another client | ≤ 2 s WAN |
| NFR-003 | Transport security | SECURITY | TLS version on the public port | TLS 1.2+ with a maintained stack (see D-004) |
| NFR-004 | Password storage | SECURITY | KDF and parameters | PBKDF2-HMAC-SHA256, ≥ 600,000 iterations (OWASP), 16-byte salt, or stronger |
| NFR-005 | Session tokens | SECURITY | Entropy; transport | ≥ 128 bits random; cookie `Secure; HttpOnly; SameSite=Lax` |
| NFR-006 | Login abuse | SECURITY | Failed attempts per user/IP | Lockout/backoff after 10 in 10 min |
| NFR-007 | Secrets never in logs | SECURITY | Log review | No password or token strings in any log line |
| NFR-008 | Data durability | RELIABILITY | Crash mid-write | SQLite WAL; no corruption; backup = copy of data folder |
| NFR-009 | Recovery | RELIABILITY | Server restart | Clients reconnect and catch up automatically within 30 s |
| NFR-010 | Distribution | OPERABILITY | What a member does | Copy one folder, run one exe, enter server URL and password |
| NFR-011 | Server operability | OPERABILITY | Host burden | Starts at logon; survives sleep/wake; one config file; one data folder |
| NFR-012 | Privacy | PRIVACY | Third parties in the data path | None except DNS and the certificate authority |
| NFR-013 | Rendering | UX | Scripts | Emoji, Hebrew (RTL), Greek, Syriac render via WebView2; `dir="auto"` per message |
| NFR-014 | Contracts | QUALITY | DbC coverage | Every public feature has pre/postconditions; class invariants on domain objects |
| NFR-015 | Tests | QUALITY | Automated | Server domain + API tests run without a browser; contract-assault style |

## Constraints

| ID | Constraint | Type | Immutable? |
|----|------------|------|------------|
| C-001 | SCOOP-capable library code (EWF standalone uses its thread handler; domain code must not assume single-threading) | TECHNICAL | YES |
| C-002 | Prefer simple_* over ISE; ISE (EWF, eel) only where simple_* lacks it | ECOSYSTEM | YES |
| C-003 | Windows 10/11 only | PLATFORM | YES (for v1) |
| C-004 | No third-party tunnel; reach by port-forward (Larry) | OPERATIONS | YES |
| C-005 | Username + password identity (Larry) | PRODUCT | YES |
| C-006 | Eiffel desktop client from day one (Larry) | PRODUCT | YES |
| C-007 | Runnable-folder distribution, no installer | DISTRIBUTION | YES |
| C-008 | Message pane must render Hebrew → WebView2, not simple_widgets | TECHNICAL | YES until simple_shaping exists |
| C-009 | Claude via `claude -p` on Larry's subscription; `ANTHROPIC_API_KEY` must be cleared in the child (it has no credit and shadows the login) | TECHNICAL | YES |
| C-010 | Everything on Larry's PC: SQLite file + image folder | DATA | YES |
