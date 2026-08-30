# CLASS DESIGN: simple_chat

Date: 2026-08-29. One project, one ECF, three application targets over one library core:

- **library `simple_chat`** — domain, store, service, bus, dispatcher, front door, config, HTTP app, UI rendering
- **target `simple_chat_server`** — root `SERVER_APP`
- **target `simple_chat_client`** — root `CLIENT_APP` (WebView2 shell)
- **target `simple_chat_tests`** — root `TEST_APP` (assault suite, memory store, mock participant)

## Class Inventory

| Class | Role | Single Responsibility |
|-------|------|----------------------|
| `SIMPLE_CHAT_SERVER` | Facade | Configure and run one server: store, service, web app, front door, DDNS, dispatcher |
| `SERVER_CONFIG` | Config | Parse and validate the TOML; nothing else reads the file |
| `CHAT_USER` | Data | A person or bot; invariants on names and hash format |
| `CHAT_ROOM` | Data | A room |
| `CHAT_MEMBERSHIP` | Data | A user's standing in a room |
| `CHAT_EVENT` | Data | One immutable log entry; kind + payload |
| `CHAT_STATUS` | Data | One ephemeral stream notice |
| `CHAT_ATTACHMENT` | Data | One stored upload |
| `CHAT_SESSION` | Data | A session or bot token (hash only) |
| `CHAT_RESULT [G]` | Data | Success-with-value xor error |
| `CHAT_ERROR` | Data | Code + message + HTTP status |
| `CHAT_STORE` | Deferred | Persistence contract for all aggregates; serializes access |
| `SQLITE_CHAT_STORE` | Engine | `CHAT_STORE` over simple_sql (WAL) |
| `MEMORY_CHAT_STORE` | Engine | `CHAT_STORE` in memory for tests |
| `CHAT_SCHEMA` | Engine | Versioned DDL and migrations |
| `CHAT_SERVICE` | Engine | Every domain operation with its rules: auth, sessions, posting, listing, admin |
| `PASSWORD_HASHER` | Engine | Hash/verify via simple_encryption; pins the iteration floor |
| `SESSION_ISSUER` | Engine | Mint tokens (CSPRNG), hash them, expire them |
| `RATE_LIMITER` | Engine | Sliding-window counts per key; MUTEX-guarded |
| `TRIGGER_PARSER` | Engine | `Claude:` / `ROBOT:` recognition |
| `EVENT_BUS` | Engine | Thread-safe fan-out of events and statuses to subscribers |
| `EVENT_SUBSCRIBER` | Deferred | Receives events/statuses |
| `EVENT_SOURCE` | Deferred | Delivers a room's events from a `since` id to one client |
| `SSE_STREAM` | Engine | `EVENT_SOURCE` + `EVENT_SUBSCRIBER` over a held `WSF_RESPONSE`; heartbeat |
| `LONG_POLL_SOURCE` | Engine | `EVENT_SOURCE` fallback: waits ≤ 25 s for new events |
| `AI_PARTICIPANT` | Deferred | Answers an addressed request |
| `CLAUDE_CODE_PARTICIPANT` | Engine | `AI_PARTICIPANT` over `CLAUDE_CODE_CLIENT` |
| `NULL_PARTICIPANT` | Engine | Never answers; for tests and "AI off" |
| `AI_DISPATCHER` | Engine | `EVENT_SUBSCRIBER`: triggers → rate limit → participant → reply |
| `FRONT_DOOR` | Deferred | TLS termination + proxy on the public port, as a contract |
| `CADDY_FRONT_DOOR` | Engine | Generates Caddyfile, spawns and supervises `caddy.exe` |
| `NO_FRONT_DOOR` | Engine | Nothing in front (tunnel or external proxy) |
| `EIFFEL_FRONT_DOOR` | Engine (Tier 1) | In-process `simple_tls` + `simple_acme` + proxy; stub in v1 |
| `DYNAMIC_DNS` | Deferred | Keep a public name pointed at this host |
| `DUCKDNS_UPDATER` | Engine | `DYNAMIC_DNS` over the Duck DNS update URL |
| `CHAT_WEB_APP` | Engine | Routes → handlers on `SIMPLE_WEB_SERVER`; auth middleware; forwarded-header trust |
| `CHAT_API` | Engine | JSON handlers (the bot API and the UI's data calls) |
| `CHAT_UI` | Engine | HTML pages and HTMX fragments via simple_htmx/alpine |
| `CHAT_LOG` | Engine | Redacting logger over simple_logger |
| `SERVER_APP` | Root | Console entry: load config, build facade, run |
| `CLIENT_APP` | Root | Desktop entry: config, host, tray, bridge |
| `CLIENT_CONFIG` | Config | Server URL, window state |
| `CLIENT_HOST` | Deferred | A window that shows a URL |
| `SHELL_WEBVIEW_HOST` | Engine | `CLIENT_HOST` on `SHELL_WINDOW` + `WEBVIEW_ENGINE` |
| `VISION2_WEBVIEW_HOST` | Engine | Fallback `CLIENT_HOST` on `SB_WIDGET` |
| `NOTIFICATION_BRIDGE` | Engine | JS → Eiffel calls: notify, badge, focus |
| `SHELL_TRAY` | Engine (simple_shell) | Tray icon, tooltip badge, balloon |

## Facade Design: SIMPLE_CHAT_SERVER

**Purpose:** The single entry point a host program uses.
**Responsibility:** Assemble the parts from a `SERVER_CONFIG`, start and stop them in order, report status. It contains no domain rule itself.

```eiffel
class SIMPLE_CHAT_SERVER

create
    make

feature -- Configuration (Builder Pattern)

    set_config (a_config: SERVER_CONFIG): like Current
    set_store (a_store: CHAT_STORE): like Current            -- default: SQLITE_CHAT_STORE from config
    set_front_door (a_door: FRONT_DOOR): like Current        -- default: from config.front_door_kind
    set_participant (a_participant: AI_PARTICIPANT): like Current  -- default: CLAUDE_CODE_PARTICIPANT or NULL
    set_dynamic_dns (a_dns: DYNAMIC_DNS): like Current       -- default: DUCKDNS_UPDATER when configured

feature -- Core Operations

    start
        -- Open store (migrate), start web app on localhost, start front door, start DDNS, subscribe dispatcher.
    stop
        -- Reverse order; never leaves caddy.exe orphaned.

feature -- Status

    is_configured: BOOLEAN
    is_running: BOOLEAN
    health: CHAT_HEALTH           -- store ok, web ok, door serving, dns fresh, dispatcher enabled
```

**Hides:** `CHAT_WEB_APP`, `EVENT_BUS`, `AI_DISPATCHER`, `CHAT_SCHEMA`, the EWF launch.

## Engine Design: CHAT_SERVICE

**Purpose:** Every domain operation, with every rule, in one place (Single Choice).
**Responsibility:** authenticate; issue/revoke sessions; create users and bots; post messages and images; list events since; membership; admin queries. Returns `CHAT_RESULT [G]`; never raises for a user error.

```eiffel
class CHAT_SERVICE

create
    make (a_store: CHAT_STORE; a_bus: EVENT_BUS; a_limits: RATE_LIMITER; a_config: SERVER_CONFIG)

feature -- Authentication
    authenticate (a_username, a_password: READABLE_STRING_GENERAL; a_client_ip: READABLE_STRING_8): CHAT_RESULT [CHAT_SESSION]
    session_for_token (a_token: READABLE_STRING_8): detachable CHAT_SESSION
    revoke (a_session: CHAT_SESSION)

feature -- Posting
    post_message (a_sender: CHAT_USER; a_room: CHAT_ROOM; a_body: READABLE_STRING_32): CHAT_RESULT [CHAT_EVENT]
    post_image (a_sender: CHAT_USER; a_room: CHAT_ROOM; a_attachment: CHAT_ATTACHMENT; a_caption: READABLE_STRING_32): CHAT_RESULT [CHAT_EVENT]

feature -- Reading
    events_since (a_room: CHAT_ROOM; a_since_id: INTEGER_64; a_limit: INTEGER): ARRAYED_LIST [CHAT_EVENT]
    events_before (a_room: CHAT_ROOM; a_before_id: INTEGER_64; a_limit: INTEGER): ARRAYED_LIST [CHAT_EVENT]

feature -- Administration
    create_user (a_username, a_display_name, a_password: READABLE_STRING_GENERAL; a_is_admin: BOOLEAN): CHAT_RESULT [CHAT_USER]
    create_bot (a_username, a_display_name: READABLE_STRING_GENERAL): CHAT_RESULT [TUPLE [bot: CHAT_USER; token: STRING_8]]
    reset_password (a_user: CHAT_USER; a_password: READABLE_STRING_GENERAL): CHAT_RESULT [CHAT_USER]
```

## Data Class Design: CHAT_RESULT [G]

**Purpose:** Hold an operation's outcome. **Immutable:** YES.

```eiffel
class CHAT_RESULT [G]

create
    make_success (a_value: G), make_error (a_error: CHAT_ERROR)

feature -- Access
    is_success: BOOLEAN
    value: detachable G
    error: detachable CHAT_ERROR

invariant
    success_xor_error: is_success xor (error /= Void)
    success_has_value: is_success implies value /= Void
```

## Data Class Design: CHAT_EVENT

**Immutable:** YES (v1). Kinds are string constants; `payload` is a JSON object for kind-specific data so new kinds (edit, reaction, reply) need no schema change.

```eiffel
class CHAT_EVENT
feature -- Access
    id: INTEGER_64;  room_id: INTEGER_64;  kind: STRING_8;  sender_id: INTEGER_64
    created_at: SIMPLE_DATE_TIME;  body: STRING_32;  attachment: detachable CHAT_ATTACHMENT
    payload: SIMPLE_JSON_OBJECT;  is_bot_authored: BOOLEAN
invariant
    positive_id: id > 0
    known_kind: kind ~ Kind_message or kind ~ Kind_image or kind ~ Kind_system
    message_has_body: kind ~ Kind_message implies not body.is_empty
    image_has_attachment: kind ~ Kind_image implies attachment /= Void
    marked_when_bot: is_bot_authored and kind ~ Kind_message implies body.starts_with (Bot_marker)
```

## Inheritance Hierarchy

```
FRONT_DOOR (deferred)             CHAT_STORE (deferred)         AI_PARTICIPANT (deferred)
   │                                 │                              │
   ├── CADDY_FRONT_DOOR              ├── SQLITE_CHAT_STORE          ├── CLAUDE_CODE_PARTICIPANT
   ├── NO_FRONT_DOOR                 └── MEMORY_CHAT_STORE          └── NULL_PARTICIPANT
   └── EIFFEL_FRONT_DOOR (Tier 1)

EVENT_SUBSCRIBER (deferred)       EVENT_SOURCE (deferred)       CLIENT_HOST (deferred)      DYNAMIC_DNS (deferred)
   │                                 │                              │                          │
   ├── SSE_STREAM ───────────────────┤                              ├── SHELL_WEBVIEW_HOST     └── DUCKDNS_UPDATER
   └── AI_DISPATCHER                 └── LONG_POLL_SOURCE           └── VISION2_WEBVIEW_HOST
```

**Inheritance Justification:**
| Child | Parent | IS-A Valid? | Liskov OK? |
|-------|--------|-------------|------------|
| `CADDY_FRONT_DOOR` | `FRONT_DOOR` | a front door that happens to be Caddy | YES — same pre/postconditions; `start` may fail, reported via `last_error`, never a stronger precondition |
| `NO_FRONT_DOOR` | `FRONT_DOOR` | the degenerate door: `is_serving` is True at once, `public_name` from config | YES |
| `EIFFEL_FRONT_DOOR` | `FRONT_DOOR` | in-process door | YES (v1: `start` sets `last_error` "not available in this build") |
| `SQLITE_CHAT_STORE` / `MEMORY_CHAT_STORE` | `CHAT_STORE` | persistence strategies | YES — identical contracts; memory store is the test oracle |
| `SSE_STREAM` | `EVENT_SOURCE` + `EVENT_SUBSCRIBER` | delivers since-N and receives live events | YES (multiple inheritance, both interfaces) |
| `AI_DISPATCHER` | `EVENT_SUBSCRIBER` | a subscriber that reacts | YES |
| `CLAUDE_CODE_PARTICIPANT` | `AI_PARTICIPANT` | one way to answer | YES |
| `SHELL_WEBVIEW_HOST` / `VISION2_WEBVIEW_HOST` | `CLIENT_HOST` | two hosts for one page | YES |

## Generic Classes

| Class | Type Parameter | Constraint | Purpose |
|-------|----------------|------------|---------|
| `CHAT_RESULT [G]` | G | none (detachable ANY) | one outcome type for every service call |

## Class Diagram

```
┌──────────────────────────────────────────────────────────┐
│                  SIMPLE_CHAT_SERVER (Facade)             │
│ + set_config / set_store / set_front_door / set_participant │
│ + start / stop / is_running / health                     │
└──┬───────────┬───────────────┬──────────────┬────────────┘
   │ owns      │ owns          │ owns         │ owns
   ▼           ▼               ▼              ▼
┌────────┐ ┌─────────────┐ ┌────────────┐ ┌──────────────┐
│CHAT_   │ │CHAT_WEB_APP │ │FRONT_DOOR  │ │AI_DISPATCHER │
│SERVICE │ │ (routes)    │ │ (deferred) │ │(subscriber)  │
└──┬─────┘ │ ├─ CHAT_API │ └─────┬──────┘ └──┬─────┬─────┘
   │       │ └─ CHAT_UI  │       │           │     │ uses
   │ uses  └──────┬──────┘  Caddy│None│Eiffel│     ▼
   ▼              │ creates                  │ ┌──────────────┐
┌──────────┐      ▼                          │ │AI_PARTICIPANT│
│CHAT_STORE│ ┌──────────┐  publish   ┌───────┴─┐ (deferred)   │
│(deferred)│ │SSE_STREAM│◄──────────│EVENT_BUS│ └─────┬────────┘
└──┬───────┘ └──────────┘           └─────────┘  Claude│Null
 SQLite│Memory
```
