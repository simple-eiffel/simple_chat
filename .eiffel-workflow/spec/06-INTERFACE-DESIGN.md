# INTERFACE DESIGN: simple_chat

Date: 2026-08-29

## Public API Summary — library (Eiffel)

### Creation
| Feature | Purpose | Typical Use |
|---------|---------|-------------|
| `SIMPLE_CHAT_SERVER.make` | unconfigured server | `create server.make` |
| `SERVER_CONFIG.make_from_file (path)` | parse + validate TOML | `create cfg.make_from_file ("simple_chat_server.toml")` |
| `CHAT_SERVICE.make (store, bus, limits, config)` | the engine | built by the facade |
| `CADDY_FRONT_DOOR.make (config)` / `NO_FRONT_DOOR.make (config)` | a door | built by the facade from `config.front_door_kind` |
| `CLAUDE_CODE_PARTICIPANT.make (config)` / `NULL_PARTICIPANT.make` | a participant | built by the facade |

### Configuration (Builder Pattern)
| Feature | Returns | Purpose |
|---------|---------|---------|
| `set_config (cfg)` | `like Current` | the TOML |
| `set_store (store)` | `like Current` | override (tests: `MEMORY_CHAT_STORE`) |
| `set_front_door (door)` | `like Current` | override the config's door |
| `set_participant (p)` | `like Current` | override (tests: mock) |
| `set_dynamic_dns (d)` | `like Current` | override |

### Core Operations
| Feature | Returns | Purpose |
|---------|---------|---------|
| `start` | — | run everything (blocking EWF launch happens in `SERVER_APP`, not the facade) |
| `stop` | — | orderly shutdown, no orphaned `caddy.exe` |

### Status Queries
| Feature | Returns | Purpose |
|---------|---------|---------|
| `is_configured` | BOOLEAN | config attached and valid |
| `is_running` | BOOLEAN | web app up |
| `health` | `CHAT_HEALTH` | store / web / door / dns / dispatcher |

## Fluent API Example
```eiffel
create server.make
server
    .set_config (create {SERVER_CONFIG}.make_from_file ("simple_chat_server.toml"))
    .set_participant (create {CLAUDE_CODE_PARTICIPANT}.make (cfg))
    .start
```

## Error Handling Pattern
```eiffel
r := service.post_message (user, room, body)
if r.is_success and then attached r.value as e then
    respond_json (e)
elseif attached r.error as err then
    respond_error (err.http_status, err.message)     -- 400 too long, 403 not a member, 429 rate limited
end
```

## Command-Query Separation
| Feature | Type | Modifies State? | Returns Value? |
|---------|------|-----------------|----------------|
| `set_*` | Command | YES | `like Current` (chaining) |
| `start` / `stop` | Command | YES | no |
| `is_*`, `health`, `events_since` | Query | NO | YES |
| `authenticate`, `post_message`, `create_user` | Command | YES | `CHAT_RESULT` (the documented exception: an outcome, not a computed value) |
| `RATE_LIMITER.is_allowed` / `record` | Query / Command | NO / YES | YES / no |

## HTTP API — the bot API and the UI's data calls (same routes)

Authentication: browser sessions by cookie `sc_session` (`Secure; HttpOnly; SameSite=Lax`); bots by `Authorization: Bearer <token>`. State-changing browser calls must carry `HX-Request: true` (FR-NEW-005). All JSON is UTF-8.

| Method | Path | Auth | Purpose | Success | Errors |
|---|---|---|---|---|---|
| POST | `/login` | none | username+password → session cookie | 303 → `/` | 401; 429 backoff |
| POST | `/logout` | session | revoke | 303 → `/login` | |
| GET | `/health` | none | liveness for host/supervisor | 200 `{store, web, door, dns, dispatcher}` | 503 |
| GET | `/rooms` | any | rooms the caller belongs to | 200 `[{id,name}]` | |
| GET | `/rooms/{id}/events?since=N&limit=M` | any | events after N, ascending, ≤ M (default 100, max 500) | 200 `[event]` | 403 |
| GET | `/rooms/{id}/events?before=N&limit=M` | any | history paging, descending window | 200 `[event]` | 403 |
| GET | `/rooms/{id}/stream?since=N` | any | SSE: replay > N, then live; `event: message` / `event: status` / `: heartbeat` | 200 text/event-stream | 403 |
| POST | `/rooms/{id}/messages` | any | `{ "body": "…" }` | 201 `event` | 400 length; 403; 429 |
| POST | `/rooms/{id}/images` | any | multipart `file` (+ `caption`) | 201 `event` | 413 too large; 415 type; 403 |
| GET | `/attachments/{id}` | any | the file (immutable, cacheable) | 200 | 404 |
| GET | `/me` | any | caller's user | 200 | |
| POST | `/me/password` | session | `{old, new}` | 204 | 401 |
| GET | `/admin/users` | admin | list | 200 | 403 |
| POST | `/admin/users` | admin | `{username, display_name, password, is_admin}` | 201 | 409 exists |
| POST | `/admin/users/{id}/password` | admin | reset | 204 | |
| POST | `/admin/bots` | admin | `{username, display_name}` → token shown **once** | 201 `{bot, token}` | 409 |
| DELETE | `/admin/bots/{id}/token` | admin | revoke | 204 | |
| POST | `/admin/backup` | admin | consistent backup into `data/backups/` | 201 `{path}` | |

Event JSON: `{ "id", "room_id", "kind", "sender": {"id","display_name","is_bot"}, "created_at", "body", "attachment": {"id","mime","size"}|null, "payload": {} }`. Status JSON (stream only): `{ "kind": "status", "room_id", "text", "from": {"display_name"} }`.

## HTML UI — pages and fragments (`CHAT_UI`)
| Route | Renders |
|---|---|
| `GET /` | the room page: message list (loaded from `/rooms/{id}/events?before=`), composer, SSE subscription (`hx-ext="sse" sse-connect="/rooms/{id}/stream?since=N"`, `sse-swap="message"` appends a fragment, `sse-swap="status"` updates the status line) |
| `GET /login` | login form |
| `GET /admin` | users, bots, backup |
| fragments | `message` (one event as HTML with `dir="auto"`, bot style when `is_bot`), `status`, `image` |

The page calls the shell bridge, when present, on each new event: `window.simple_chat?.notify(sender, snippet)` and `window.simple_chat?.badge(count)`; in a plain browser these are no-ops.

## Client shell (`CLIENT_APP`) — behaviours, not an API
| Behaviour | Mechanism |
|---|---|
| First run asks for the server URL; remembered | `CLIENT_CONFIG` in `%APPDATA%\simple_chat\client.toml` |
| Shows the UI | `CLIENT_HOST.show (url)` |
| Tray icon, tooltip "(3) simple_chat", balloon on notify | `SHELL_TRAY` + `NOTIFICATION_BRIDGE` (`on_call ("notify")`, `on_call ("badge")`) |
| Foreground clears the badge | host focus event → `badge (0)` |
| Single instance | named mutex; second launch focuses the first |
| Window position/size remembered | `CLIENT_CONFIG` |

## Configuration file — `simple_chat_server.toml`
```toml
[server]
port = 8080                 # localhost only; the front door owns the public port
data_dir = "data"
public_name = "rixchat.duckdns.org"
front_door = "caddy"        # caddy | eiffel | none

[limits]
message_characters = 4000
upload_bytes = 8388608
ai_requests_per_hour = 5
posts_per_minute = 30
login_failures_per_10_minutes = 10
session_days = 90

[ddns]
provider = "duckdns"
domains = "rixchat"
token = "..."               # never logged
interval_seconds = 300

[ai]
participant = "claude_code" # claude_code | none
bot_username = "claude"
bot_display_name = "🤖 Claude"
working_directory = "C:/Users/LJR19/OneDrive/Documents/Obsidian Vault/Scholars"
model = "claude-opus-5"
max_characters = 1200
timeout_seconds = 120
```
