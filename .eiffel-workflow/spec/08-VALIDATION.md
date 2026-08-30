# DESIGN VALIDATION: simple_chat

Date: 2026-08-29

## OOSC2 Compliance

| Principle | Status | Evidence |
|-----------|--------|----------|
| Single Responsibility | ✓ | facade assembles; `CHAT_SERVICE` holds every rule (Single Choice); stores persist; bus fans out; dispatcher reacts; doors terminate TLS |
| Open/Closed | ✓ | new front doors, stores, participants, hosts and DNS providers are new descendants of deferred classes; event kinds extend via `kind` + `payload` without schema change |
| Liskov Substitution | ✓ | every descendant keeps the parent's pre/postconditions (04 table); failure is reported through `last_error`/`CHAT_RESULT`, never by strengthening a precondition |
| Interface Segregation | ✓ | `EVENT_SUBSCRIBER` (receive) and `EVENT_SOURCE` (deliver since N) are separate; `SSE_STREAM` takes both, `AI_DISPATCHER` only the first |
| Dependency Inversion | ✓ | `CHAT_SERVICE` depends on `CHAT_STORE`, not SQLite; the facade on `FRONT_DOOR`, not Caddy; the client on `CLIENT_HOST`, not WebView2 (C-012) |

## Eiffel Excellence

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Command-Query Separation | ✓ | queries pure; `set_*` return `like Current` for chaining; service commands return `CHAT_RESULT` (documented outcome exception) |
| Uniform Access | ✓ | `is_serving`, `health`, `last_event_id` are queries whether attribute or function |
| Design by Contract | ✓ | 05: ordering, marker, rate limits, token entropy, hash floor, forwarded-header trust, no-orphan stop — as invariants/postconditions |
| Genericity | ✓ | `CHAT_RESULT [G]` |
| Inheritance | ✓ | IS-A only; multiple inheritance for `SSE_STREAM` (source + subscriber) is genuine |
| Information Hiding | ✓ | EWF, SQLite, Caddy, WebView2, `claude -p` are all `{NONE}`-side details of one class each |

## Practical Quality

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Void-safe | ✓ | `detachable` only for optional data; `attached … as` everywhere it is read |
| SCOOP-compatible | ✓ | domain classes plain; shared state behind MUTEX; no `separate` needed in v1; nothing forbids SCOOP later |
| simple_* first | ✓ | 03 table; ISE only through simple_web (EWF) and simple_encryption's fallback (eel) |
| MML postconditions | ✓ | memory store, bus and limiter carry model queries; frame conditions with `|=|` |
| Testable | ✓ | `MEMORY_CHAT_STORE` + `NULL_PARTICIPANT`/mock make the whole service testable without sockets; the SQLite store is checked against the memory oracle |
| Independent vectors | ✓ | testing/vectors for JSON and base64; simple_encryption 2.0.0 already verified |

## Requirements Traceability

| Requirement | Addressed By | Status |
|-------------|--------------|--------|
| FR-001 accounts | `CHAT_SERVICE.create_user`, `authenticate`, `PASSWORD_HASHER` | ✓ |
| FR-002 sessions persist | `CHAT_SESSION` in store; `session_for_token`; cookie 90 days | ✓ |
| FR-003 rooms | `CHAT_ROOM`, `CHAT_MEMBERSHIP`, `CHAT_SCHEMA` v1 | ✓ |
| FR-004 Unicode text | `STRING_32` bodies; UTF-8 JSON; `dir="auto"`; WebView2 | ✓ |
| FR-005 images | `store_upload`, `post_image`, `/attachments/{id}`, limits | ✓ |
| FR-006 paging | `events_before` | ✓ |
| FR-007 live | `SSE_STREAM`, `EVENT_BUS` | ✓ (Spike A) |
| FR-008 catch-up | `since` on the stream and `/events`; `last_delivered_id` | ✓ |
| FR-009 balloons | `NOTIFICATION_BRIDGE`, `SHELL_TRAY` | ✓ |
| FR-010 display names | `CHAT_USER.display_name` | ✓ |
| FR-011 Claude answers | `AI_DISPATCHER`, `TRIGGER_PARSER`, `CLAUDE_CODE_PARTICIPANT` | ✓ |
| FR-012 rate limit | `RATE_LIMITER` key `ai:` + dispatcher guard | ✓ |
| FR-013 marker | `CHAT_EVENT` invariant + `post_message` postcondition | ✓ |
| FR-014 bot API | Bearer auth in `CHAT_WEB_APP`; same JSON routes; `create_bot` | ✓ |
| FR-015 admin page | `CHAT_UI` `/admin`, `CHAT_API` admin routes | ✓ |
| FR-016 badge | `badge (n)` bridge → tray tooltip + title | ✓ |
| FR-017 limits | `SERVER_CONFIG` limits; service preconditions → 4xx | ✓ |
| FR-018 config file | `SERVER_CONFIG.make_from_file` | ✓ |
| FR-019 client URL | `CLIENT_CONFIG` | ✓ |
| FR-020 browser tab | server-rendered UI; bridge is a no-op without the shell | ✓ |
| FR-NEW-001..012 | `CHAT_STATUS`/`publish_status`; `CHAT_SCHEMA`; `/health`; DR-010 in `client_ip`; `require_htmx`; `CHAT_LOG.redact`; `backup`; single-instance mutex + window memory; `change_password`; `payload`; startup key warning; `FRONT_DOOR.check_health` | ✓ |
| NFR-001/002 | one thread per stream (EWF), heartbeat, tuned knobs | ✓ (Spike A) |
| NFR-003 | `FRONT_DOOR`; no TLS in the library (DR-011) | ✓ |
| NFR-004/005/006/007 | `PASSWORD_HASHER` floor; `SESSION_ISSUER`; `login:` limiter keys; `CHAT_LOG` | ✓ |
| NFR-008/009 | WAL; `backup`; clients resume from `since` | ✓ |
| NFR-010/011 | runnable folders; `start.bat`; scheduled task; supervised Caddy | ✓ |
| NFR-012 | only DNS and the CA outside | ✓ |
| NFR-013 | WebView2 + `dir="auto"` | ✓ |
| NFR-014/015 | contracts in 05; memory oracle; vectors | ✓ |
| C-012 swappable non-Eiffel parts | `FRONT_DOOR`, `CLIENT_HOST`, `AI_PARTICIPANT`, `DYNAMIC_DNS` | ✓ |

## Risk Mitigations Implemented

| Risk | Mitigation in Design |
|------|---------------------|
| RISK-001 CGNAT | `front_door = "none"` + external tunnel is a config change |
| RISK-002 EOL OpenSSL | no TLS code in the library; Caddy or the Eiffel door |
| RISK-003 SSE on EWF | `EVENT_SOURCE` with `LONG_POLL_SOURCE` fallback; heartbeat; Spike A first |
| RISK-004 simple_browser | `CLIENT_HOST` with Vision2 fallback; Spike B first |
| RISK-005 WebView2 runtime | client `start.bat` registry check + bootstrapper |
| RISK-007 host PC | scheduled task at logon; `check_health` supervision; clients catch up |
| RISK-008 exposure | localhost bind; DR-010; backoff; limits; `HX-Request` |
| RISK-009 quota | `ai:` limiter; `max_concurrent = 1`; usage on `/admin` |
| RISK-010 SQLite threads | store-level MUTEX regardless of build |
| RISK-015 latency | ephemeral status; timeout apology |
| RISK-016 API key in env | startup warning; `CLAUDE_CODE_CLIENT` clears it per child |

## Open Issues
0. **Addendum 09 (addressable participants — `@tools-larry`, `@shape-larry`, local Ollama phrasing)** generalizes `AI_PARTICIPANT`/`TRIGGER_PARSER`/`AI_DISPATCHER` to `PARTICIPANT`/`ADDRESS_PARSER`/`PARTICIPANT_DISPATCHER` with a registry and per-tool argument allowlists; Phase 1 contracts are written against the addendum's names.
1. **Spike A** (SSE on EWF, 20 idle streams) and **Spike B** (WebView2 on a `simple_shell` HWND) precede Phase 1 implementation; the design already contains their fallbacks.
2. **CGNAT check** is Larry's; the design does not depend on the answer, the deployment does.
3. `--json-schema` in `CLAUDE_CODE_CLIENT`, `SHELL_TRAY` in simple_shell, SSE attributes in simple_htmx, and `simple_winhttp` are small additions to other libraries; each is a one-session task and is listed in 07's dependencies.
4. Caddy's `flush_interval -1` for SSE passthrough is to be confirmed in Spike A.
5. Whether `AI_DISPATCHER` runs the participant on a worker thread or through `simple_process` asynchronously is an implementation choice; the contract (`asked_once`, `always_answers`, `one_at_a_time`) is fixed either way.

## Ready for Implementation
- [x] All requirements traced
- [x] All risks mitigated in design (two gated on spikes)
- [x] All principles satisfied
- [x] Design is complete for Phase 1; Tier 1 (`EIFFEL_FRONT_DOOR`) and Tier 2 (`simple_shaping`) have their contracts reserved

**VERDICT:** READY — proceed to `/eiffel.intent`, then Phase 0 spikes, then Phase 1 contracts.
