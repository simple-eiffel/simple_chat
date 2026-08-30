# SPECIFICATION: simple_chat

Date: 2026-08-29

## Overview
A standalone group-chat system in Eiffel: a server on Larry's Windows PC (simple_web/EWF on localhost, SQLite, SSE) behind a swappable front door (Caddy now, an Eiffel door later), an Eiffel desktop client hosting the server-rendered UI in WebView2 (a swappable host; native rendering later via `simple_shaping`), Claude as a rate-limited, marked participant, and a bot API so any member's PC can run its own AI. Rules are contracts.

## Class Specifications

### SIMPLE_CHAT_SERVER (Facade)
```eiffel
note
	description: "One simple_chat server: assembles store, service, web app, front door, dynamic DNS and the AI dispatcher from a SERVER_CONFIG; starts and stops them in order. Holds no domain rule."
	author: "Larry Rix"

class
	SIMPLE_CHAT_SERVER

create
	make

feature {NONE} -- Initialization

	make
			-- Unconfigured server.
		do
			create bus.make
			create limits.make
		ensure
			not_configured: not is_configured
			not_running: not is_running
		end

feature -- Configuration

	set_config (a_config: SERVER_CONFIG): like Current
		require
			not_running: not is_running
		do
			config := a_config
			Result := Current
		ensure
			set: config = a_config
			result_current: Result = Current
		end

	set_store (a_store: CHAT_STORE): like Current
		require not_running: not is_running
		do store := a_store; Result := Current
		ensure set: store = a_store; result_current: Result = Current end

	set_front_door (a_door: FRONT_DOOR): like Current
		require not_running: not is_running
		do front_door := a_door; Result := Current
		ensure set: front_door = a_door; result_current: Result = Current end

	set_participant (a_participant: AI_PARTICIPANT): like Current
		require not_running: not is_running
		do participant := a_participant; Result := Current
		ensure set: participant = a_participant; result_current: Result = Current end

	set_dynamic_dns (a_dns: DYNAMIC_DNS): like Current
		require not_running: not is_running
		do dynamic_dns := a_dns; Result := Current
		ensure set: dynamic_dns = a_dns; result_current: Result = Current end

feature -- Core Operations

	start
			-- Open and migrate the store, start the web app on localhost, start the
			-- front door and dynamic DNS, subscribe the dispatcher.
		require
			configured: is_configured
			not_running: not is_running
		do
			-- build defaults for anything not overridden, in this order:
			-- store -> service -> web_app -> front_door -> dynamic_dns -> dispatcher
		ensure
			running_or_reported: is_running xor (last_error /= Void)
			store_open: is_running implies attached store as s and then s.is_open
			door_started: is_running implies attached front_door as d and then (d.is_serving or d.last_error /= Void)
			dispatcher_subscribed: is_running and config_ai_enabled implies bus.subscribers_model.has (dispatcher)
		end

	stop
			-- Reverse order. Never leaves a child process behind.
		ensure
			stopped: not is_running
			door_stopped: attached front_door as d implies not d.is_serving and not d.has_child_process
			store_closed: attached store as s implies not s.is_open
		end

feature -- Status

	is_configured: BOOLEAN
		do Result := attached config as c and then c.is_valid end

	is_running: BOOLEAN

	last_error: detachable CHAT_ERROR

	health: CHAT_HEALTH
		require running: is_running
		ensure attached_result: Result /= Void end

feature {NONE} -- Implementation

	config: detachable SERVER_CONFIG
	store: detachable CHAT_STORE
	service: detachable CHAT_SERVICE
	web_app: detachable CHAT_WEB_APP
	front_door: detachable FRONT_DOOR
	dynamic_dns: detachable DYNAMIC_DNS
	participant: detachable AI_PARTICIPANT
	dispatcher: detachable AI_DISPATCHER
	bus: EVENT_BUS
	limits: RATE_LIMITER

invariant
	running_implies_configured: is_running implies is_configured
	running_implies_parts: is_running implies (store /= Void and service /= Void and web_app /= Void and front_door /= Void)

end
```

### CHAT_EVENT (Data, immutable)
```eiffel
class CHAT_EVENT
create make
feature {NONE} -- Initialization
	make (a_id, a_room_id, a_sender_id: INTEGER_64; a_kind: STRING_8; a_created_at: SIMPLE_DATE_TIME;
			a_body: STRING_32; a_attachment: detachable CHAT_ATTACHMENT; a_payload: SIMPLE_JSON_OBJECT; a_bot: BOOLEAN)
		require
			positive: a_id > 0 and a_room_id > 0
			known_kind: is_known_kind (a_kind)
			message_has_body: a_kind ~ Kind_message implies not a_body.is_empty
			image_has_attachment: a_kind ~ Kind_image implies a_attachment /= Void
			bot_marked: a_bot and a_kind ~ Kind_message implies a_body.starts_with (Bot_marker)
		ensure
			set: id = a_id and room_id = a_room_id and kind ~ a_kind and body ~ a_body and is_bot_authored = a_bot
		end
feature -- Access
	id, room_id, sender_id: INTEGER_64
	kind: STRING_8
	created_at: SIMPLE_DATE_TIME
	body: STRING_32
	attachment: detachable CHAT_ATTACHMENT
	payload: SIMPLE_JSON_OBJECT
	is_bot_authored: BOOLEAN
feature -- Conversion
	to_json: SIMPLE_JSON_OBJECT
		ensure has_id: Result.integer_item ("id") = id end
feature -- Constants
	Kind_message: STRING_8 = "message"
	Kind_image: STRING_8 = "image"
	Kind_system: STRING_8 = "system"
	Bot_marker: STRING_32 = "🤖"
invariant
	positive_id: id > 0
	positive_room: room_id > 0
	known_kind: is_known_kind (kind)
	message_has_body: kind ~ Kind_message implies not body.is_empty
	image_has_attachment: kind ~ Kind_image implies attachment /= Void
	marked_when_bot: is_bot_authored and kind ~ Kind_message implies body.starts_with (Bot_marker)
end
```

### CHAT_USER, CHAT_SESSION, CHAT_ATTACHMENT, CHAT_ROOM, CHAT_MEMBERSHIP (Data)
As in 05-CONTRACT-DESIGN: `CHAT_USER` (username shape, display shape, people-have-hashes / bots-have-none), `CHAT_SESSION` (`token_hash.count = 64`, `expires_at > created_at`, `is_bot_token`), `CHAT_ATTACHMENT` (`size > 0`, `mime` in {image/png, image/jpeg}, `sha256.count = 64`, `stored_relpath` under `uploads/`), `CHAT_ROOM` (`name` 1–64), `CHAT_MEMBERSHIP` (`role` in {member, admin}).

### CHAT_RESULT [G] and CHAT_ERROR
```eiffel
class CHAT_RESULT [G]
create make_success, make_error
feature -- Access
	is_success: BOOLEAN
	value: detachable G
	error: detachable CHAT_ERROR
invariant
	success_xor_error: is_success xor (error /= Void)
	success_has_value: is_success implies value /= Void
end

class CHAT_ERROR
create make
feature -- Access
	code: STRING_8          -- "not_member", "too_long", "rate_limited", "bad_credentials", "locked_out", "exists", "too_large", "bad_type", "unavailable"
	message: STRING_32      -- safe to show a user
	http_status: INTEGER
invariant
	status_is_error: http_status >= 400 and http_status <= 599
	code_given: not code.is_empty
end
```

### CHAT_STORE (deferred) — contract in 05; descendants
`SQLITE_CHAT_STORE.make (a_path)` opens with `make_wal`, applies `CHAT_SCHEMA.migrate`, and wraps every feature in one `MUTEX` (`{NONE} -- Serialization: lock; unlock`), so correctness never depends on the SQLite build's threading mode. `MEMORY_CHAT_STORE.make` keeps `ARRAYED_LIST`s and exposes the MML model queries; it is the oracle the assault suite compares the SQLite store against.

`CHAT_SCHEMA`: table `schema_version (version)`; migrations `v1`: `user`, `room`, `membership`, `event` (id INTEGER PRIMARY KEY AUTOINCREMENT, room_id, kind, sender_id, created_at, body, attachment_id, payload_json, is_bot), `attachment`, `session` (token_hash UNIQUE, is_bot_token), indexes on `event(room_id, id)` and `session(token_hash)`.

### CHAT_SERVICE (Engine) — contract in 05
```eiffel
class CHAT_SERVICE
create make
feature {NONE} -- Initialization
	make (a_store: CHAT_STORE; a_bus: EVENT_BUS; a_limits: RATE_LIMITER; a_config: SERVER_CONFIG)
		require open: a_store.is_open
		ensure set: store = a_store and bus = a_bus and limits = a_limits and config = a_config
feature -- Authentication
	authenticate (a_username, a_password: READABLE_STRING_GENERAL; a_client_ip: READABLE_STRING_8): CHAT_RESULT [CHAT_SESSION]
	session_for_token (a_token: READABLE_STRING_8): detachable CHAT_SESSION
		ensure valid_if_attached: attached Result as s implies s.expires_at > now
	revoke (a_session: CHAT_SESSION)
		ensure gone: session_for_token_hash (a_session.token_hash) = Void
feature -- Posting
	post_message (a_sender: CHAT_USER; a_room: CHAT_ROOM; a_body: READABLE_STRING_32): CHAT_RESULT [CHAT_EVENT]
	post_image (a_sender: CHAT_USER; a_room: CHAT_ROOM; a_attachment: CHAT_ATTACHMENT; a_caption: READABLE_STRING_32): CHAT_RESULT [CHAT_EVENT]
	post_system (a_room: CHAT_ROOM; a_text: READABLE_STRING_32): CHAT_EVENT
	publish_status (a_room: CHAT_ROOM; a_from: CHAT_USER; a_text: READABLE_STRING_32)
		ensure not_stored: store.last_event_id = old store.last_event_id
feature -- Reading
	events_since (a_room: CHAT_ROOM; a_since_id: INTEGER_64; a_limit: INTEGER): ARRAYED_LIST [CHAT_EVENT]
	events_before (a_room: CHAT_ROOM; a_before_id: INTEGER_64; a_limit: INTEGER): ARRAYED_LIST [CHAT_EVENT]
	rooms_of (a_user: CHAT_USER): ARRAYED_LIST [CHAT_ROOM]
	is_member (a_user: CHAT_USER; a_room: CHAT_ROOM): BOOLEAN
feature -- Uploads
	store_upload (a_uploader: CHAT_USER; a_original_name, a_mime: READABLE_STRING_8; a_bytes: SPECIAL [NATURAL_8]): CHAT_RESULT [CHAT_ATTACHMENT]
		require has_bytes: a_bytes.count > 0
		ensure
			limited: a_bytes.count > config.upload_limit_bytes implies not Result.is_success
			typed: not is_allowed_mime (a_mime) implies not Result.is_success
			hashed: Result.is_success implies (attached Result.value as a and then a.sha256 ~ crypto.sha256 (bytes_as_string (a_bytes)))
feature -- Administration
	create_user (a_username, a_display_name, a_password: READABLE_STRING_GENERAL; a_is_admin: BOOLEAN): CHAT_RESULT [CHAT_USER]
	create_bot (a_username, a_display_name: READABLE_STRING_GENERAL): CHAT_RESULT [TUPLE [bot: CHAT_USER; token: STRING_8]]
	reset_password (a_user: CHAT_USER; a_password: READABLE_STRING_GENERAL): CHAT_RESULT [CHAT_USER]
	change_password (a_user: CHAT_USER; a_old, a_new: READABLE_STRING_GENERAL): CHAT_RESULT [CHAT_USER]
	revoke_bot_token (a_bot: CHAT_USER)
	backup: CHAT_RESULT [STRING_32]
		ensure consistent_copy: Result.is_success implies attached Result.value as p and then file_exists (p)
feature {NONE} -- Implementation
	store: CHAT_STORE;  bus: EVENT_BUS;  limits: RATE_LIMITER;  config: SERVER_CONFIG
	hasher: PASSWORD_HASHER;  issuer: SESSION_ISSUER;  crypto: SIMPLE_ENCRYPTION
invariant
	store_open: store.is_open
end
```

### RATE_LIMITER, EVENT_BUS, SSE_STREAM, LONG_POLL_SOURCE, AI_DISPATCHER, AI_PARTICIPANT, TRIGGER_PARSER
Contracts in 05. Notes:
- `RATE_LIMITER.make` takes the limits from `SERVER_CONFIG`; keys are `ai:<user id>`, `post:<user id>`, `login:user:<name>`, `login:ip:<ip>`; a `MUTEX` guards the table; `prune` drops expired timestamps.
- `EVENT_BUS.publish` delivers under its lock to a snapshot of subscribers; a subscriber that raises is unsubscribed and logged, never retried (a dead stream must not stall the room).
- `SSE_STREAM.make (a_response: WSF_RESPONSE; a_room_id, a_since_id: INTEGER_64; a_service: CHAT_SERVICE)` writes `Content-Type: text/event-stream`, `Cache-Control: no-cache`, `X-Accel-Buffering: no`, replays `events_since` in pages, then subscribes; each event as `id: <id>\nevent: message\ndata: <json>\n\n`; heartbeat `: hb\n\n` every 20 s; `close` on write failure.
- `TRIGGER_PARSER.parse (a_body): detachable TRIGGERED_REQUEST` — matches `^\s*(claude|robot)\s*[:：]\s*(.+)` case-insensitively; the question is the remainder trimmed.
- `AI_DISPATCHER.make (a_service, a_participant, a_limits, a_bot_user, a_config)`; `receive` runs the participant on a worker thread (one at a time), so the bus thread never blocks; before asking it publishes a status "🤖 thinking…"; after, posts the answer (prefixed with the marker if the participant omitted it), or a refusal ("🤖 I answered you N times this hour — try again at HH:MM") or an apology on error/timeout.
- `AI_REQUEST` (asker display name, question, room name, `max_characters`), `AI_ANSWER` (text, optional `image_path`, error).
- `CLAUDE_CODE_PARTICIPANT.answer` builds the persona system prompt (chat register, ≤ `max_characters`, emoji allowed, never fabricate specifics about people, cite when researching), sets the vault working directory, uses `CLAUDE_CODE_CLIENT` with `--json-schema {text, image_path}` (addition to simple_ai_client), and enforces the timeout.

### FRONT_DOOR (deferred) and CADDY_FRONT_DOOR
```eiffel
deferred class FRONT_DOOR
feature -- Access
	public_name: STRING_8;  upstream_port: INTEGER;  last_error: detachable CHAT_ERROR
feature -- Status
	is_serving: BOOLEAN deferred end
	is_public: BOOLEAN deferred end             -- False for NO_FRONT_DOOR behind a tunnel
	has_child_process: BOOLEAN deferred end
	sets_forwarded_headers: BOOLEAN deferred end
feature -- Basic operations
	start deferred ... end                       -- contract in 05
	stop  deferred ... end
	check_health                                 -- supervisor tick: restart a dead child, refresh last_error
		ensure reported: is_serving or last_error /= Void
invariant
	serving_has_name: is_serving and is_public implies not public_name.is_empty
	forwarded_headers: is_serving implies sets_forwarded_headers
end
```
`CADDY_FRONT_DOOR.make (a_config)`: `start` writes `Caddyfile` — `<public_name> { reverse_proxy 127.0.0.1:<upstream_port> { flush_interval -1 } }` — into the server folder, launches `caddy.exe run --config Caddyfile` through `simple_process` with a hidden window, waits for `is_serving` by probing `https://<public_name>/health` (or, before DNS resolves, the local port 443), and records `last_error` with Caddy's stderr tail on failure. `check_health` restarts an exited child with backoff. `stop` terminates the child and waits. `EIFFEL_FRONT_DOOR`: in v1 `start` sets `last_error := "the Eiffel front door is not in this build (Tier 1)"` — the contract holds, the swap is honest.

### DYNAMIC_DNS (deferred) and DUCKDNS_UPDATER
`update` ensures `last_result` in {ok, ko, unreachable} and `last_update_at` set; `DUCKDNS_UPDATER` issues `GET https://www.duckdns.org/update?domains=<d>&token=<t>` through WinHTTP (`SIMPLE_WINHTTP` — promoted from `OCR_HTTP`) every `interval_seconds` on a timer thread; the token never appears in `CHAT_LOG`.

### SERVER_CONFIG
`make_from_file (a_path)`: parses TOML via `simple_toml`, then `is_valid` with `validation_errors: LIST [STRING_32]`; invariant in 05.

### CHAT_WEB_APP, CHAT_API, CHAT_UI
`CHAT_WEB_APP.make (a_service, a_bus, a_config)` registers the routes of 06 on a `SIMPLE_WEB_SERVER` bound to `127.0.0.1:<port>`; `authenticate_request (req): detachable CHAT_USER` reads the cookie or Bearer; `client_ip (req)` honours `X-Forwarded-For` only when the peer is 127.0.0.1 (DR-010); `require_htmx (req)` enforces FR-NEW-005 on cookie-authenticated state changes. `CHAT_API` handlers produce JSON through `simple_json`; `CHAT_UI` produces pages and fragments through `simple_htmx` + `simple_alpine`, every message element `dir="auto"`, bot messages with `class="bot"`.

### CHAT_LOG
Wraps `SIMPLE_LOGGER`; `redact (a_text): STRING_32` masks anything matching a token/hash/password field name or a 64-hex run before writing; NFR-007's test greps the log after a full scenario.

### Client: CLIENT_APP, CLIENT_CONFIG, CLIENT_HOST, SHELL_WEBVIEW_HOST, NOTIFICATION_BRIDGE, SHELL_TRAY
```eiffel
deferred class CLIENT_HOST
feature
	show (a_url: READABLE_STRING_8) require valid: a_url.starts_with ("http") ensure shown: is_shown end
	bind (a_name: READABLE_STRING_8; a_handler: PROCEDURE [TUPLE [STRING_8, STRING_8]]) -- JS → Eiffel
	focus;  is_foreground: BOOLEAN;  run   -- message pump
end
```
`SHELL_WEBVIEW_HOST`: `SHELL_WINDOW` + `WEBVIEW_ENGINE.make_with_window (hwnd)` (Spike B). `VISION2_WEBVIEW_HOST`: `SB_WIDGET`. `NOTIFICATION_BRIDGE.make (a_host, a_tray)` binds `notify (sender, snippet)` → `tray.balloon (title ≤ 48, body ≤ 200)` unless `host.is_foreground`, and `badge (n)` → `tray.set_tooltip ("(" + n + ") simple_chat")` + window title. `SHELL_TRAY` (new in simple_shell): `add (icon, tooltip)`, `set_tooltip`, `balloon (title, text)`, `remove`; contracts `added implies visible`, title/body length limits from the notification-area guidelines; identified by GUID (`NOTIFYICON_VERSION_4`).

## Dependencies

| Library | Purpose | Version |
|---------|---------|---------|
| simple_web (EWF wsf, standalone httpd, thread handler) | server, routing, uploads, chunked responses | ≥ current |
| simple_htmx, simple_alpine | UI rendering | current (+ SSE attributes) |
| simple_sql (eiffel_sqlite_2025) | store, WAL | current |
| simple_encryption | PBKDF2, CSPRNG, SHA-256 | **2.0.0** |
| simple_json, simple_toml, simple_uuid, simple_datetime, simple_logger, simple_process, simple_base64 | plumbing | current |
| simple_ai_client | `CLAUDE_CODE_CLIENT` (+ `--json-schema`) | current + this project's addition |
| simple_shell | `SHELL_WINDOW`, `SHELL_TRAY` (new), clipboard | ≥ 1.8.0 + this project's addition |
| simple_browser (webview.dll, WebView2Loader.dll) | WebView2 host | current (Spike B) |
| simple_winhttp (promoted from OCR_HTTP) | DDNS and health probes without libcurl | new, small |
| simple_mml | model queries in the memory store and bus | current |
| simple_testing | assault suite | current |
| Caddy (caddy.exe, in the server folder) | `CADDY_FRONT_DOOR` | latest static Windows build |
| WebView2 Evergreen Runtime | client rendering | present or bootstrapped |

## File Structure

```
D:\prod\simple_chat\
├── simple_chat.ecf                 (targets: simple_chat, simple_chat_server, simple_chat_client, simple_chat_tests)
├── src\
│   ├── domain\      chat_user.e chat_room.e chat_membership.e chat_event.e chat_status.e chat_attachment.e chat_session.e chat_result.e chat_error.e
│   ├── store\       chat_store.e sqlite_chat_store.e memory_chat_store.e chat_schema.e
│   ├── service\     chat_service.e password_hasher.e session_issuer.e rate_limiter.e trigger_parser.e chat_log.e
│   ├── bus\         event_bus.e event_subscriber.e event_source.e sse_stream.e long_poll_source.e
│   ├── ai\          ai_participant.e ai_request.e ai_answer.e claude_code_participant.e null_participant.e ai_dispatcher.e
│   ├── door\        front_door.e caddy_front_door.e no_front_door.e eiffel_front_door.e dynamic_dns.e duckdns_updater.e
│   ├── web\         chat_web_app.e chat_api.e chat_ui.e
│   ├── config\      server_config.e chat_health.e
│   └── facade\      simple_chat_server.e
├── apps\
│   ├── server\      server_app.e
│   └── client\      client_app.e client_config.e client_host.e shell_webview_host.e vision2_webview_host.e notification_bridge.e
├── testing\
│   ├── test_app.e   (runner)
│   ├── chat_assault.e             (domain + service against MEMORY_CHAT_STORE, then SQLITE_CHAT_STORE)
│   ├── mock_participant.e         (scripted AI_PARTICIPANT)
│   └── vectors\                   (independent vectors for JSON, base64, token shapes)
├── dist\
│   ├── server\      simple_chat_server.toml.example  Caddyfile.example  start.bat  (caddy.exe dropped here)
│   └── client\      start.bat (WebView2 runtime check)  webview.dll  WebView2Loader.dll
└── .eiffel-workflow\  research\  spec\  evidence\
```
