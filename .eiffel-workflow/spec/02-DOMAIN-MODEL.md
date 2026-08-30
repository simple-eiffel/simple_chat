# DOMAIN MODEL: simple_chat

Date: 2026-08-29

## Domain Concepts

### Concept: User
**Definition:** A participant — a person or a bot — known to the server by a unique username.
**Attributes:** id, username (lowercase `[a-z0-9_]{1,32}`), display_name (1–40), password_hash (`salt$iterations$hash`, iterations ≥ 600,000; bots have none), is_admin, is_bot, is_active, created_at.
**Behaviors:** authenticates (people), owns sessions or bot tokens, authors events.
**Related to:** Membership, Session, BotToken, Event.
**Will become:** `CHAT_USER`

### Concept: Room
**Definition:** A named conversation with members and an ordered event log. v1 has one; the model has many.
**Attributes:** id, name, created_at.
**Behaviors:** admits members; accepts events.
**Related to:** Membership, Event.
**Will become:** `CHAT_ROOM`

### Concept: Membership
**Definition:** A user's standing in a room (member or admin of that room).
**Attributes:** room_id, user_id, role, joined_at.
**Will become:** `CHAT_MEMBERSHIP`

### Concept: Event
**Definition:** One entry in a room's log — the unit of history and of live delivery (the Matrix model). Messages and image posts are events; so are system notices. Kinds are extensible for edits, reactions, replies later.
**Attributes:** id (global, strictly increasing), room_id, kind (`message` | `image` | `system`), sender_id, created_at, body, attachment (for `image`), payload (JSON, kind-specific, forward-compatible).
**Behaviors:** immutable once appended (v1); serializes to JSON and to HTML.
**Related to:** Room, User, Attachment.
**Will become:** `CHAT_EVENT`

### Concept: Ephemeral status
**Definition:** A transient notice on the live stream that is never stored — "🤖 thinking…", typing later.
**Will become:** `CHAT_STATUS` (published on the bus, not appended to the store)

### Concept: Attachment
**Definition:** An uploaded file (PNG/JPEG in v1) kept on disk under the data folder, referenced by an image event.
**Attributes:** id, uploader_id, original_name, mime, size, sha256, stored_relpath, created_at.
**Will become:** `CHAT_ATTACHMENT`

### Concept: Session
**Definition:** A logged-in browser/client instance. The client holds the token; the server stores its hash.
**Attributes:** id, user_id, token_hash, created_at, last_seen_at, expires_at, user_agent.
**Behaviors:** authenticates requests; expires; is revoked on logout.
**Will become:** `CHAT_SESSION`

### Concept: Bot token
**Definition:** A long-lived credential for a bot user, presented as `Authorization: Bearer`. Same shape as a session, different lifetime and issuer.
**Will become:** `CHAT_SESSION` with `is_bot_token`

### Concept: Rate limit
**Definition:** A sliding-window count per key (`ai:<user>`, `post:<user>`, `login:<user>`, `login:<ip>`) with a limit per window.
**Will become:** `RATE_LIMITER`

### Concept: AI participant
**Definition:** Something that answers an addressed request with text and optionally an image path. Claude via `claude -p` in v1; Ollama or others later; a friend's relay is the same thing on another machine.
**Will become:** `AI_PARTICIPANT` (deferred) → `CLAUDE_CODE_PARTICIPANT`, `NULL_PARTICIPANT`

### Concept: Dispatcher
**Definition:** The room member that watches events for triggers, applies the rate limit, asks the participant, and posts the reply as the bot user with the marker.
**Will become:** `AI_DISPATCHER`

### Concept: Event bus
**Definition:** In-process fan-out of new events and statuses to live subscribers (SSE streams), thread-safe.
**Will become:** `EVENT_BUS`, `EVENT_SUBSCRIBER` (deferred), `SSE_STREAM`

### Concept: Store
**Definition:** Persistence for users, rooms, memberships, events, attachments, sessions, with schema versioning. SQLite in production, memory in tests.
**Will become:** `CHAT_STORE` (deferred) → `SQLITE_CHAT_STORE`, `MEMORY_CHAT_STORE`; `CHAT_SCHEMA`

### Concept: Front door
**Definition:** Whatever terminates TLS on the public port and forwards to the server on localhost. Caddy as a supervised child process now; an in-process Eiffel implementation later; none when a tunnel or reverse proxy elsewhere does the job.
**Will become:** `FRONT_DOOR` (deferred) → `CADDY_FRONT_DOOR`, `NO_FRONT_DOOR`, `EIFFEL_FRONT_DOOR` (Tier 1)

### Concept: Public name
**Definition:** The DNS name members use, kept pointed at the host's current IP.
**Will become:** `DDNS_UPDATER` (Duck DNS now; deferred `DYNAMIC_DNS` for other providers)

### Concept: Server configuration
**Definition:** The one TOML file: port, data dir, public name, front door choice, DDNS token, limits, AI settings.
**Will become:** `SERVER_CONFIG`

### Concept: Client shell
**Definition:** The member's window: a native frame hosting the server-rendered UI, plus tray, badge, notifications, remembered server URL.
**Will become:** `CHAT_CLIENT_APP`, `CLIENT_CONFIG`, `CLIENT_HOST` (deferred: `SHELL_WEBVIEW_HOST`, `VISION2_WEBVIEW_HOST`), `NOTIFICATION_BRIDGE`, `SHELL_TRAY` (in simple_shell)

## Concept Relationships
```
CHAT_ROOM ──── has-many ────> CHAT_EVENT ──── may-have ────> CHAT_ATTACHMENT
CHAT_ROOM ──── has-many ────> CHAT_MEMBERSHIP ────> CHAT_USER
CHAT_USER ──── has-many ────> CHAT_SESSION (sessions and bot tokens)
CHAT_EVENT ──── authored-by ────> CHAT_USER
AI_DISPATCHER ──── is-a ────> EVENT_SUBSCRIBER;  ──── uses ────> AI_PARTICIPANT, RATE_LIMITER, CHAT_SERVICE
SSE_STREAM ──── is-a ────> EVENT_SUBSCRIBER
CHAT_SERVICE ──── uses ────> CHAT_STORE, EVENT_BUS, RATE_LIMITER, SIMPLE_ENCRYPTION
SIMPLE_CHAT_SERVER ──── owns ────> CHAT_SERVICE, CHAT_WEB_APP, FRONT_DOOR, DDNS_UPDATER, AI_DISPATCHER
CADDY_FRONT_DOOR / NO_FRONT_DOOR / EIFFEL_FRONT_DOOR ──── is-a ────> FRONT_DOOR
SQLITE_CHAT_STORE / MEMORY_CHAT_STORE ──── is-a ────> CHAT_STORE
CLAUDE_CODE_PARTICIPANT / NULL_PARTICIPANT ──── is-a ────> AI_PARTICIPANT
```

## Domain Rules
| Rule | Description | Enforcement |
|------|-------------|-------------|
| DR-001 | Event ids are strictly increasing across the whole store | `CHAT_STORE.append_event` postcondition: `Result.id > old last_event_id` |
| DR-002 | A bot-authored message body begins with the 🤖 marker | `CHAT_SERVICE.post_message` postcondition when `sender.is_bot`; `CHAT_EVENT` invariant `is_bot_authored implies body.starts_with (Bot_marker)` |
| DR-003 | Only members post to a room | `CHAT_SERVICE.post_*` precondition `is_member (user, room)` |
| DR-004 | An AI request is served only within the asker's rate window | `AI_DISPATCHER.handle` guard on `RATE_LIMITER.is_allowed`; refusal posted instead |
| DR-005 | Password hashes are PBKDF2 at ≥ 600,000 iterations | `CHAT_USER` invariant on the stored format; `PASSWORD_HASHER` postcondition |
| DR-006 | Session tokens are 32 CSPRNG bytes; only their hash is stored | `SESSION_ISSUER` postcondition; `CHAT_SESSION` invariant `token_hash.count = 64` |
| DR-007 | Message length ≤ configured limit; upload ≤ configured limit | preconditions in `CHAT_SERVICE` (checked earlier by the API layer, reported as 4xx) |
| DR-008 | Events are immutable in v1 | no update feature on `CHAT_STORE` for events |
| DR-009 | Ephemeral statuses are never persisted | `EVENT_BUS.publish_status` has no store interaction; `CHAT_STORE` has no status table |
| DR-010 | The server trusts `X-Forwarded-*` only from localhost (the front door) | `CHAT_WEB_APP` reads them only when the peer is 127.0.0.1 |
| DR-011 | The server never handles a certificate | no TLS code in the library; `FRONT_DOOR` owns it |
| DR-012 | A logged line never contains a password, token or hash | `CHAT_LOG` redaction; NFR-007 test greps the log |
| DR-013 | Login backoff after 10 failures in 10 minutes per user and per IP | `RATE_LIMITER` keys `login:user:*`, `login:ip:*` |

## Glossary
| Term | Definition |
|------|------------|
| Event | One entry in a room's ordered log; messages, image posts and system notices are events |
| Since token | The last event id a client has; `events?since=N` and the stream replay from it |
| Front door | The TLS terminator and proxy on the public port; Caddy, the Eiffel one, or none |
| Marker | The 🤖 prefix every AI-authored message carries |
| Participant | An `AI_PARTICIPANT`: anything that answers an addressed request |
| Dispatcher | The room member that turns `Claude:` into a participant call and a reply |
| Status | An ephemeral stream-only notice ("🤖 thinking…") |
| Runnable folder | Larry's distribution unit: an exe, its DLLs, config, `start.bat`; no installer |
