# Approach: simple_chat implementation sketch

Date: 2026-08-29 · Phase 2 input · Source of truth for the design: `spec/07-SPECIFICATION.md` + addenda `09` (participants) and `10` (thick client); decisions D-001–D-020 in `research/04-DECISIONS.md`; intent v3.

## 1. Architecture

```
                         ┌────────────────────────── server process (simple_chat_server.exe, a service) ──────────────────────────┐
  internet ──► FRONT_DOOR (Caddy | Eiffel | none) ──► CHAT_WEB_APP (simple_web, 127.0.0.1:port) ──► CHAT_API (JSON handlers)      │
                 apps/server/ops                          │ bearer_token / client_ip                     │                          │
                                                          ▼                                              ▼                          │
                                                   CHAT_SERVICE (every rule) ──── RATE_LIMITER ──── PASSWORD_HASHER / SESSION_ISSUER│
                                                          │                                                                        │
                                          ┌───────────────┼──────────────────┐                                                     │
                                          ▼               ▼                  ▼                                                     │
                                     CHAT_STORE      EVENT_BUS (doorbell)   CHAT_LOG (redacting)                                   │
                                  (SQLITE | MEMORY)      │ ring(room) / ring_status                                                │
                                          ▲       ┌──────┼────────────────┐                                                        │
                                          │       ▼      ▼                ▼                                                        │
                                          └── POLL_WAITER  SSE_STREAM   PARTICIPANT_DISPATCHER ──► PARTICIPANT_REGISTRY ──► PARTICIPANT
                                            (long-poll)   (bots, curl)   (pulls events_since its cursor)      (from TOML)      │  claude_code | ollama | bible_tool | shape_tool
                                                                                                                             SHAPER (null | ollama | claude)
  DYNAMIC_DNS (DuckDNS) ticks on its own timer                                                                                       │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  client process (simple_chat.exe, simple_widgets — no browser)
  CLIENT_CONFIG ──► SERVICE_LOCATOR ──► CHAT_ENDPOINT ──► CHAT_CLIENT ──► HTTP_TRANSPORT (WINHTTP | MEMORY)
                                                            │  login / events / wait / post / members
                                     EVENT_POLLER (worker) ─┘ poll_once → pending ──drain──► CHAT_PRESENTER (GUI thread) ──► CHAT_VIEW (SW_CHAT_VIEW | MEMORY)
                                                                                                         └──► NOTIFIER (TRAY | MEMORY)
```

Every seam that touches something non-Eiffel or non-simple_* sits behind a deferred class with a memory/null double: `CHAT_STORE`, `STREAM_SINK`, `FRONT_DOOR`, `DYNAMIC_DNS`, `PARTICIPANT`, `SHAPER`, `HTTP_TRANSPORT`, `CHAT_VIEW`, `NOTIFIER`. That is what lets the assault suite run headless and what lets Caddy, WinHTTP, Ollama and the tray be swapped.

## 2. Data flow

**Post (person).** `CHAT_API.handle_post_message` → `bearer_token` → `CHAT_SERVICE.session_for_token` → `post_message (sender, room, body)`:
1. rate limit: `limits.is_allowed ("post:<id>")` then `record` — under the limiter's lock as one step (see review);
2. `store.append_event (draft)` under the store lock → global id `last_event_id + 1`;
3. release the store lock; `bus.ring (room)` — the bus snapshots subscribers under its lock, releases, wakes each.

**Deliver (long-poll).** `handle_wait` → `wait_for_events (room, since, limit, seconds)`: `waiter.arm (room)`; `bus.subscribe (waiter)`; `store.events_since`; if empty and seconds > 0: `waiter.wait (seconds·1000)`; re-read; `bus.unsubscribe`; answer `CHAT_JSON.page_to_json (events, waiter.statuses)`. One `POLL_WAITER` per request; nothing stored.

**Deliver (SSE).** `handle_stream` → `SSE_STREAM.open (room, since)` over a `WEB_STREAM_SINK`; replay by pages; on `wake` pull and write; heartbeat every 20 s; write deadline 5 s → close + unsubscribe.

**Participants.** `PARTICIPANT_DISPATCHER.wake (room)` → `events_since (cursor)` → skip bot-authored → `ADDRESS_PARSER.parse (body)` → `registry.find (handle)` → per-participant bounded FIFO → `participant.answer (request)` (query shaping → engine → response shaping) → `service.post_message (bot_user, room, marker + text)` → ring (the dispatcher ignores its own bot post on the next wake). Tools receive **argv** only, every element allowlisted; the reply echoes what ran and discloses phrasing.

**Client.** `SERVICE_LOCATOR.locate` (local `/health`, then `server_urls` in order) → `CHAT_CLIENT.login` (token in memory only) → `CHAT_PRESENTER.open_room` → worker: `EVENT_POLLER.poll_once (25)` in a loop → GUI timer: `presenter.pump` (drain → view.show_event, unread law, notifier) → `presenter.send` → `client.post_message`; the echo arrives through the poller.

## 3. Database schema (v1, `CHAT_SCHEMA.migrate`)

```sql
CREATE TABLE schema_version (version INTEGER NOT NULL);
CREATE TABLE user (
  id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT NOT NULL UNIQUE,        -- lowercase [a-z0-9_]{1,32}
  display_name TEXT NOT NULL, password_hash TEXT NOT NULL,                     -- '' for bots
  is_admin INTEGER NOT NULL DEFAULT 0, is_bot INTEGER NOT NULL DEFAULT 0, is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL);
CREATE TABLE room (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, created_at TEXT NOT NULL);
CREATE TABLE membership (user_id INTEGER NOT NULL REFERENCES user(id), room_id INTEGER NOT NULL REFERENCES room(id),
  joined_at TEXT NOT NULL, PRIMARY KEY (user_id, room_id));
CREATE TABLE attachment (id INTEGER PRIMARY KEY AUTOINCREMENT, uploader_id INTEGER NOT NULL REFERENCES user(id),
  original_name TEXT NOT NULL, mime TEXT NOT NULL, size INTEGER NOT NULL, sha256 TEXT NOT NULL,
  stored_relpath TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL);
CREATE TABLE event (
  id INTEGER PRIMARY KEY AUTOINCREMENT,                                        -- the global monotonic id
  room_id INTEGER NOT NULL REFERENCES room(id), kind TEXT NOT NULL CHECK (kind IN ('message','image','system')),
  sender_id INTEGER NOT NULL,                                                  -- 0 for system
  created_at TEXT NOT NULL, body TEXT NOT NULL, attachment_id INTEGER REFERENCES attachment(id),
  payload_json TEXT NOT NULL DEFAULT '{}', is_bot INTEGER NOT NULL DEFAULT 0);
CREATE INDEX event_room_id ON event (room_id, id);
CREATE TABLE session (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER NOT NULL REFERENCES user(id),
  token_hash TEXT NOT NULL UNIQUE, is_bot_token INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, expires_at TEXT NOT NULL);
CREATE INDEX session_user ON session (user_id);
```
WAL mode; `PRAGMA foreign_keys = ON`; every command in a transaction; `backup` = `VACUUM INTO 'data/backups/<stamp>.db'`. Text columns are UTF-8; `created_at` ISO 8601 (server clock is the only clock). Schema v2 reserves `epoch` on `event` for replica promotion (D-017).

## 4. Implementation order (Phase 4)

Each step is compiled and assaulted before the next; the memory store is the oracle for the SQLite store at step 3.

1. **Domain + codec** — already implemented where pure: `CHAT_JSON`, rules, `CHAT_EVENT.to_json`. Add: `SERVER_CONFIG.make_from_file` (simple_toml) and its validation messages.
2. **`MEMORY_CHAT_STORE`** bodies (all commands and queries; they are the specification of the SQLite behaviour).
3. **`CHAT_SCHEMA.migrate` + `SQLITE_CHAT_STORE`** under its MUTEX; the assault runs the same scenario against both stores and compares (`store_equivalence` test).
4. **`RATE_LIMITER`** with timestamps per key (sliding window) and an atomic `try_record`.
5. **`CHAT_SERVICE`** — authenticate / sessions / post / uploads / admin / `wait_for_events`, with `POLL_WAITER` and `EVENT_BUS` bodies (already partly real).
6. **`CHAT_WEB_APP` + `CHAT_API`** over simple_web: routing, bearer auth, JSON bodies, uploads (simple_web multipart — dependency task), `/wait`, `/stream` (needs simple_web streaming response — Spike A), `/health`.
7. **`SERVER_APP`**: `--create-admin`, config load, `SIMPLE_CHAT_SERVER.start/run/stop`, `NO_FRONT_DOOR` first; then `CADDY_FRONT_DOOR` (child supervision needs simple_process wait/kill — dependency task) and `DUCKDNS_UPDATER` (needs simple_winhttp).
8. **Participants**: `NULL_PARTICIPANT` end-to-end through the dispatcher first (proves the loop and the marker), then `CLAUDE_CODE_PARTICIPANT` (needs the simple_process timeout to be real), `BIBLE_TOOL_PARTICIPANT`, `OLLAMA_PARTICIPANT`, shapers.
9. **Client**: `WINHTTP_TRANSPORT` (simple_winhttp), then the worker thread for `EVENT_POLLER`, then `SW_CHAT_VIEW` + `TRAY_NOTIFIER` once `simple_shaping` renders Hebrew and `SHELL_TRAY` exists. Until then a console client over the same stack is the interim harness.

## 5. Key design decisions (carried into implementation)

- **Doorbell, not push** (D-011/intent Q3): the bus carries room ids, readers pull — no lost-message race between concurrent posts, and reconnect and live delivery are one code path.
- **Lock order store < limiter < bus**, and no lock held across a call-out (intent Q2). `EVENT_BUS.ring` snapshots then releases.
- **Long-poll for the thick client** (D-018), SSE kept for bots; `POLL_WAITER` closes the check-then-wait race by retaining wakes since `arm`.
- **Bearer tokens only**; the store keeps sha256 of the token; sessions revocable; no cookies anywhere (intent v3).
- **Bot marker as an invariant** of `CHAT_EVENT`; the dispatcher ignores bot-authored events (no loops).
- **Tools get argv, allowlisted** — the security control of the participant design; the echo line is the transparency control.
- **Swappable seams** behind deferred classes (front door, DNS, transport, view, notifier, store, sink, participant, shaper).
- **The client finds the server** (D-016) — local service first, then primary, then standbys (D-017); one HTTP code path for host and friends.

## 6. Dependencies

Present: base, simple_mml, simple_json ≥ 0.2.0 (astral fix), simple_datetime, simple_logger, simple_encryption ≥ 2.0.0, simple_uuid, simple_sql, simple_process, simple_base64, simple_encoding, simple_web, simple_ai_client (`CLAUDE_CODE_CLIENT`, `OLLAMA_CLIENT`), simple_shell 1.8.0, simple_widgets, simple_testing.

Missing (dependency tasks, in the order Phase 4 needs them): simple_web streaming response + multipart upload + `SIMPLE_WEB_SERVER_REQUEST.header` availability (Spike A); `simple_process.wait_for_exit (ms)` / `kill` (Caddy supervision, `claude -p` timeout); `simple_winhttp` (promote `OCR_HTTP`: HTTPS, headers, receive timeout ≥ 30 s, bytes POST); `SHELL_TRAY`; `simple_shaping` (Hebrew/RTL/emoji in simple_widgets); a WIC decoder; DPAPI protect/unprotect in simple_encryption; simple_toml for `make_from_file`.

## 7. Risk areas

1. **Concurrency contracts** — RESOLVED by decision D1 (SCOOP, §8): the exact forms stand because one processor owns the service and everything it guards; what remains is the restructuring in §8 and dependency task 0.
2. **`EVENT_POLLER` shared state** — RESOLVED by §8: the poller and an inbox are separate objects; nothing is shared unguarded.
3. **`RATE_LIMITER.record` requires `is_allowed`** — RESOLVED by §8: `is_allowed` then `record` inside one service routine is atomic on the service's processor.
4. **Store equivalence** — the SQLite store must match the memory oracle exactly, including ordering and error cases; a dedicated equivalence assault is mandatory.
5. **Uploads and the front door** are where untrusted bytes and the public internet meet: magic-byte validation, size cap, `nosniff`, X-Forwarded-For trusted only from localhost, Caddyfile pinned to a loopback upstream.
6. **`claude -p` timeouts are advisory** until simple_process can kill — a hung participant pins its worker.
7. **simple_shaping** is the long pole for the visible client; everything else can be assaulted headless.
8. **simple_web in SCOOP mode** — DONE 2026-08-29 (simple_web 0.2.0): `SIMPLE_WEB_HANDLER_SERVER [H]` creates one `SIMPLE_WEB_REQUEST_HANDLER` per request on the request's processor (routes are per-request `SIMPLE_WEB_ROUTES`; process-wide strings through `SIMPLE_WEB_SHARED`); the agent-based `SIMPLE_WEB_SERVER` moved to a thread-only cluster. Proof target `simple_web_scoop_tests`: real socket, shared value reaching a handler, 404, two 2-second requests served in 2 s. simple_chat compiles with `use="scoop"`: zero warnings, 30/30.

## 8. Concurrency: SCOOP (decided by Larry, 2026-08-29)

No MUTEX, no CONDITION_VARIABLE, no lock order anywhere in simple_chat. Processors:

**Server**
- *Root processor*: `SERVER_APP`, `SERVER_CONFIG`, the `SIMPLE_CHAT_SERVER` facade; starts everything else and runs the web server's accept loop.
- *EWF handler processors* (the httpd SCOOP pool, one per concurrent connection): each request runs `SIMPLE_WEB_SERVER_EXECUTION` → a `CHAT_API` **created per execution on that processor**, holding a `separate CHAT_SERVICE` reference. This is the simple_web change: routes become data and handlers are created per execution (a factory), never process-wide agents.
- *The service processor*: `separate CHAT_SERVICE` — **one** processor owning `CHAT_STORE` (the single SQLite connection), `EVENT_BUS`, `RATE_LIMITER`, `CHAT_LOG` as ordinary non-separate attributes. Every service call from any handler is serialized here, so `store.last_event_id = old store.last_event_id + 1`, `count = old count + 1` and `is_allowed`-then-`record` are exact and atomic. The service **never blocks**: no waiting, no child processes, no network — only SQLite and memory.
- *Per long-poll request*: the handler creates `separate POLL_WAITER` and `separate ALARM` (the alarm sleeps `seconds` then calls `waiter.time_out`), subscribes the waiter (`service.subscribe (waiter)` — the bus holds `separate EVENT_SUBSCRIBER`s), reads `events_since` through the service, and if empty calls `wait_for_news (waiter)` whose precondition `ready: waiter.has_news or waiter.is_timed_out` is a SCOOP **wait condition** — the handler blocks until a wake or the alarm; then re-reads, unsubscribes, answers. SSE is the same loop repeated with heartbeats. `EVENT_BUS.ring` issues `s.wake (room)` to each separate subscriber — **asynchronous commands**: posters never stall, and each subscriber runs its wakes one at a time on its own processor, so the dispatcher cannot re-enter itself.
- *The dispatcher processor*: `separate PARTICIPANT_DISPATCHER` with per-room cursors; participant engines (child processes) run here one answer at a time — `max_concurrent = 1` for free; a processor per participant later if parallel answers are wanted. Posts go back through `service.post_message`.
- *Ops processors*: `separate CADDY_FRONT_DOOR` (supervising its child), `separate DUCKDNS_UPDATER` (sleep-tick loop).

**Client**
- *Root processor*: the simple_widgets pump, `CHAT_PRESENTER`, `CHAT_VIEW`, `NOTIFIER`, and the GUI's own `CHAT_CLIENT` for posting.
- *Poller processor*: `separate EVENT_POLLER` with **its own** `CHAT_CLIENT` and transport (the token string is copied to it at `open_room`; still memory-only), looping `poll_once` — blocking inside WinHTTP for up to 30 s never touches the GUI.
- *Inbox processor*: `separate EVENT_INBOX` — the poller does `inbox.put (page_bytes)` (async); the GUI timer does `inbox.drain` (a quick query on a processor that never blocks), copies the bytes with `make_from_separate` and decodes with `CHAT_JSON` on the root. `EVENT_POLLER.pending`, `drain` and the MUTEX disappear; the drain laws move to the inbox with exact contracts.

**Contract consequences**: exact forms are correct wherever one processor owns the state; a routine with a `separate` argument holds that processor for its duration (SCOOP locks separate arguments), and its preconditions on that argument are wait conditions. The Phase 2 findings 1–10 are absorbed by this restructuring; findings 11–38 remain as written.

**Spikes before Phase 3**: (S1) simple_web SCOOP mode — DONE (`simple_web_scoop_tests`, two concurrent 2 s requests served in 2 s); (S2) the simple_widgets pump on the root processor with a `separate` poller + inbox delivering into the window; (S3) EWF's `max_concurrent_connections` versus the number of members holding a long-poll at once (each open poll pins a pool processor for ≤ 25 s — size the pool ≥ members + 4).
