# ADDENDUM 11: Phase 1b - SCOOP restructuring and the repair of the Phase 2 findings

Date: 2026-08-29 · Supersedes every thread/MUTEX/CONDITION_VARIABLE mention in 07-SPECIFICATION.md, 09-ADDENDUM-PARTICIPANTS.md and 10-ADDENDUM-THICK-CLIENT.md · Decisions: D1 SCOOP (Larry: "SCOOP is your threading solution. Use it."), D3 sandboxed `@claude`, D4 the marker authenticates, D5 the oracle stores twins (approved "continue on")

## 1. What changed and why

Phase 2 found 38 HIGH findings. Findings 1-10 were one defect seen ten times: the contracts were written for a single thread of control while the web layer served a thread per connection, so every exact clause (`count = old count + 1`) and every "unchanged" frame was wrong for correct code. Larry's answer was SCOOP, and simple_web 0.2.0 was fixed to run in SCOOP mode (dependency task 0). With one processor owning each piece of shared state, the exact forms are right again; no MUTEX, CONDITION_VARIABLE or lock order exists anywhere in simple_chat.

Findings 11-38 (wrong by construction, never-raises broken, security claims unwritten) were repaired cluster by cluster in five passes, each ending in a clean compile with zero warnings and a green assault. Main after the passes: 85/85.

## 2. The processors (as built)

Server
- Root: `SERVER_APP`, `SERVER_CONFIG`, `SIMPLE_CHAT_SERVER` (lifecycle only). `SIMPLE_CHAT_SERVER.start` shares the configuration path through `SIMPLE_WEB_SHARED` and forces `CHAT_SHARED.shared_api`, so the API processor exists before the first request.
- The API processor: `CHAT_SHARED.shared_api: separate CHAT_API` is a `once ("PROCESS")` of separate type; `CHAT_API` owns `CHAT_SERVICE`, which owns the store, the `EVENT_BUS`, the `RATE_LIMITER` and the `CHAT_LOG` as ordinary attributes. Every request reaches it through a formal argument (`api_* (a_api: separate CHAT_API; ...)`), and only bytes come back: `CHAT_REPLY` (status, content type, body, item count) copied with `make_from_separate`.
- Request processors: simple_web's `SIMPLE_WEB_HANDLER_SERVER [CHAT_REQUEST_HANDLER]` creates one `CHAT_REQUEST_HANDLER` per request on the request's processor; it declares the 20 routes, extracts the Bearer token (64 hex characters or nothing), decides the client address (forwarded headers trusted only from the loopback door), bounds every query integer and body, and sets `nosniff` on every reply.
- Long-poll (`GET /rooms/{id}/wait`): the handler creates `separate POLL_WAITER` (room-scoped news counter) and `separate POLL_ALARM` (sleeps `seconds`, then `expire (waiter)`), subscribes the waiter with the bus (a ticket), reads `events`; if the page is empty and `seconds > 0` it calls `POLL_WAIT.wait_for (a_waiter)` whose precondition `ready: a_waiter.is_ready` (news or timed out) is a SCOOP wait condition, then reads again with the statuses and unsubscribes. The API is never held during the wait.
- `EVENT_BUS.ring (room)` issues `wake_one` to each `separate EVENT_SUBSCRIBER` as an asynchronous command: posters never stall, subscribers run their wakes one at a time on their own processors, and the dispatcher cannot re-enter itself (D2). Subscriptions are integer tickets; `unsubscribe` is idempotent.
- The dispatcher processor: `separate PARTICIPANT_DISPATCHER` with per-room cursors (`start_after` from the store on restart, never 0), a bounded queue per room (`Max_queue_depth = 8`), `answered` ids (never twice), never answering bots, membership checked before an engine is spent, rate limit per asker through `CHAT_API.dispatcher_try_ask`. It reads pages and posts answers through the `feature {PARTICIPANT_DISPATCHER}` section of `CHAT_API`.
- Ops: `CADDY_FRONT_DOOR` and `DUCKDNS_UPDATER` as before (they may become separate objects in Phase 4; nothing in their contracts depends on it).

Client
- Root: the simple_widgets pump, `CHAT_PRESENTER`, `CHAT_VIEW`, `NOTIFIER`, and the GUI's own `CHAT_CLIENT` for posting.
- Poller: `separate EVENT_POLLER` with its own `CHAT_CLIENT` (the session is handed over once, `CHAT_CLIENT.hand_session_to (separate CHAT_CLIENT)`, memory to memory), `poll_once` per loop, backoff 1..30 s on failure, `lost` on 401.
- Inbox: `separate EVENT_INBOX`, `put (separate READABLE_STRING_8)` copies the page bytes onto its processor, bounded at 64 pages with drops counted and outages explained; the presenter's `pump` takes pages, decodes them on the root with `CLIENT_CODEC` (every decoder answers Void on any exception, which the client reports as 502), and applies the unread/badge/foreground laws.

## 3. Repairs by theme (where the clause lives now)

- Lockout and limiter: `CHAT_SERVICE.login` counts failures per IP and per user with exact clauses, refuses inactive users and bots, never creates a session on failure; `RATE_LIMITER` windows are per key; `is_allowed` then `record` is atomic on the API processor.
- Not gap-free / oldest-N: `CHAT_STORE.events_since` and `events_before` are contracted `gapless`/`newest`/`adjacent` against the model; `EVENT_SOURCE` delivers `each_once_in_order`, `all_after_since`.
- Oracle reference semantics (D5): `MEMORY_CHAT_STORE` stores and returns twins; integrity invariants (`count_within_ids`, memberships as a relation, one session per token hash).
- Image with an unstored attachment: `append_event` requires `attachment_stored` and `bot_flag_truthful` (D4: a human's message may not begin with the marker; a bot's must).
- Never raises: `CHAT_JSON` decoders are guarded (`ascii_item`, `is_iso8601`, `is_hex_64`, `error_from_bytes` maps unknown codes); one malformed event refuses the whole page; every `to_string_8` is preceded by `is_valid_as_string_8`.
- Security: argv only (`TOOL_PARTICIPANT.is_safe_argument`, `arguments_of` bounded, no option prefixes; the shaped output is gated exactly like raw text); `via` must be a configured choice; `CLAUDE_CODE_PARTICIPANT` requires `sandboxed` (a dedicated directory under the server's participants folder, never the vault, tools off, sessions mapped) and fences `image_path` (relative, no parent segment, an image extension, bounded); uploads stored as `<sha256>.<ext>` under the uploads folder by `CHAT_ATTACHMENT_RULES.stored_path_for`, magic bytes checked; `CHAT_URL_RULES.is_loopback_url` parses the authority (userinfo defeats it); Bearer only over TLS or loopback (`CHAT_CLIENT.make require secure`); revocation contracted (`revoke_bot_token`, `reset_password ensure sessions_revoked`); the Caddyfile is `admin off` + one site + loopback upstream and `public_name` must be a hostname; the DuckDNS token never appears in `update_url` (invariant).

## 4. Consequences for Phase 3/4

- Every blocking operation lives on its own processor and never holds the API: engines on the dispatcher, sleeps on alarms, WinHTTP on the poller.
- Contract forms: exact where one processor owns the state; a routine's separate formals are reserved for its duration, so a routine must not keep one across anything that can block.
- Pool sizing (spike S3): each open long-poll pins one request processor for up to 25 s; `CHAT_WEB_APP.Max_connections = 64` must stay above members + 4.
- Still-stubbed bodies whose postconditions will fail when first reached (Phase 4 work, not defects): `CHAT_LOG.*` counters, `RATE_LIMITER.record`, `SQLITE_CHAT_STORE`, `SERVER_CONFIG.make_from_file` (simple_toml), `SERVER_APP.serve/create_admin`, `BIBLE/SHAPE_TOOL_PARTICIPANT.run_arguments`.
- Dependency tasks unchanged: simple_shaping, WIC decoder, simple_winhttp, SHELL_TRAY, DPAPI, simple_process wait/kill, simple_web peer address + streaming + multipart.
