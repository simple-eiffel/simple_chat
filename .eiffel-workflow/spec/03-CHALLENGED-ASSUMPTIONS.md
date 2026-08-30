# CHALLENGED ASSUMPTIONS: simple_chat

Date: 2026-08-29

## Assumptions Challenged

### A-1: Larry's ISP gives a public IPv4 (no CGNAT)
**Challenge:** Many residential ISPs now use CGNAT; if so, port-forwarding never works.
**Evidence for:** Larry has run home services before (unverified in this project).
**Evidence against:** none gathered — it has not been checked.
**Verdict:** NEEDS_VALIDATION
**Action:** Phase 0 check. Design consequence: the front door is a config choice (D-013), so the fallback (a tunnel process as `NO_FRONT_DOOR` + external proxy) changes one line, not the code.

### A-2: Members' PCs have the WebView2 runtime
**Challenge:** Some Windows 10 machines lack it.
**Verdict:** VALID with mitigation — `start.bat` checks the `pv` registry value and runs the bootstrapper (RISK-005).

### A-3: EWF's standalone server can hold 20 idle SSE streams
**Challenge:** A thread-per-connection server may cap or time out idle connections; keep-alive/socket timeouts could cut streams.
**Evidence for:** `WSF_RESPONSE.put_chunk` exists; knobs exist.
**Evidence against:** nothing measured.
**Verdict:** NEEDS_VALIDATION
**Action:** Spike A before Phase 1. Design consequence: `EVENT_SOURCE` is deferred with `SSE_STREAM` and `LONG_POLL_SOURCE` implementations behind the same `since` contract, so the fallback is a class swap.

### A-4: simple_browser can host WebView2 on a simple_shell HWND
**Challenge:** Its only demonstrated host is a Vision2 `EV_DRAWING_AREA`.
**Evidence for:** `WEBVIEW_ENGINE.make_with_window (hwnd)` takes any HWND.
**Verdict:** NEEDS_VALIDATION
**Action:** Spike B. Design consequence: `CLIENT_HOST` deferred; `SHELL_WEBVIEW_HOST` first, `VISION2_WEBVIEW_HOST` fallback.

### A-5: One SQLite connection under EWF threads suffices
**Challenge:** simple_sql's thread-safety is undocumented; SQLite serialized mode is a compile-time property of the bundled sqlite3.
**Verdict:** NEEDS_VALIDATION (cheap: `sqlite3_threadsafe()` probe)
**Action:** `CHAT_STORE` serializes every call through its own MUTEX regardless, so correctness never depends on the SQLite build; the probe only decides whether that mutex is redundant.

### A-6: `claude -p` latency of 2–30 s is acceptable
**Challenge:** In a chat, 30 s of silence reads as "broken."
**Verdict:** VALID with mitigation — ephemeral "🤖 thinking…" status on the stream (RISK-015); timeout posts an apology.

### A-7: Members will install a folder and log in once
**Challenge:** The adoption risk is the real one.
**Verdict:** NEEDS_VALIDATION (only use will tell)
**Action:** NFR-010 is a hard design target; the browser-tab path (FR-020) costs nothing and lowers the bar for a first look.

### A-8 (new): The AI dispatcher belongs in the server process
**Challenge:** Should Claude be a separate relay process like a friend's bot, for symmetry?
**Evidence for in-process:** `claude -p` runs on Larry's PC anyway; one process to supervise; no token round trip.
**Evidence for separate:** symmetry with I-002; a crash in dispatch cannot take the server down.
**Verdict:** VALID (in-process) — but through the same `AI_PARTICIPANT` abstraction and the same `CHAT_SERVICE` calls a relay would use, so moving it out is a deployment choice later.

### A-9 (new): Global event ids, not per-room
**Challenge:** Matrix uses per-room streams; per-room ids keep rooms independent.
**Verdict:** VALID (global) — one `since` number per client is simpler for catch-up across rooms and for the bot API; ordering within a room is preserved because ids are globally monotonic.

### A-10 (new): Config in TOML
**Challenge:** JSON is already everywhere in the ecosystem.
**Verdict:** VALID (TOML) — human-edited by the host; `simple_toml` exists; comments allowed.

## Requirements Questioned

### FR-010: Display names
**Challenge:** Is a second name worth a field? **Verdict:** KEEP — bots need a display identity ("🤖 Claude") distinct from a login name, and members will want it.

### FR-016: Unread badge
**Challenge:** Nice-to-have. **Verdict:** KEEP as SHOULD — it is the difference between a chat people return to and one they forget.

### FR-020: Browser tab
**Challenge:** Larry chose a desktop client. **Verdict:** KEEP as COULD — it is free once the server renders HTML, and it is the fallback if Spike B fails on someone's machine.

### FR-011/FR-013: Marker enforcement
**Challenge:** Should the marker be a rendering concern rather than a body prefix? **Verdict:** MODIFY — enforce both: the body carries 🤖 (so exports, bots reading the API, and search all see it) **and** bot-authored events render with a distinct style. The invariant stays on the body.

### FR-007: SSE
**Challenge:** Is WebSocket needed for bidirectional? **Verdict:** KEEP — posts are POSTs; nothing needs a socket back.

## Missing Requirements Identified
| ID | Missing Requirement | How Discovered |
|----|---------------------|----------------|
| FR-NEW-001 | Ephemeral status events on the stream (never stored) | A-6: "thinking…" must not clutter history |
| FR-NEW-002 | Schema versioning and forward migration | any store that lives more than one release |
| FR-NEW-003 | `GET /health` for the host and the front door supervisor | UC-009 needs a probe |
| FR-NEW-004 | Trust `X-Forwarded-For/Proto` only from localhost | DR-010; RISK-008 |
| FR-NEW-005 | CSRF defence for browser-originated state changes (`SameSite=Lax` cookie + required `HX-Request`/custom header; bots use Bearer, not cookies) | UI review |
| FR-NEW-006 | Redacting logger: no secrets ever logged | NFR-007 needs a mechanism, not a policy |
| FR-NEW-007 | Consistent backup (`VACUUM INTO` or SQLite backup API) from the admin page | WAL makes a naive copy unsafe mid-write |
| FR-NEW-008 | Client single-instance (mutex) and window-position memory | desktop hygiene |
| FR-NEW-009 | Members change their own password | obvious once admin-only creation was chosen |
| FR-NEW-010 | Event `kind` + `payload` JSON for forward compatibility (edits, reactions, replies) | D-011 said rooms from day one; events deserve the same |
| FR-NEW-011 | Startup warning if `ANTHROPIC_API_KEY` is set in the server's environment | RISK-016 |
| FR-NEW-012 | Front door supervision: restart `caddy.exe` if it exits; surface `last_error` | UC-009 |

## Design Constraints Validated
| Constraint | Valid? | Notes |
|------------|--------|-------|
| simple_* first | YES | simple_web, simple_htmx, simple_alpine, simple_sql, simple_encryption 2.0.0, simple_json, simple_uuid, simple_datetime, simple_logger, simple_toml, simple_shell (+SHELL_TRAY), simple_browser, simple_ai_client, simple_process, simple_base64; ISE: EWF (via simple_web), eel (via simple_encryption fallback) |
| SCOOP-compatible | YES | domain classes are plain; the server runs on EWF's thread handler, and shared state (`EVENT_BUS`, `RATE_LIMITER`, `CHAT_STORE`) is MUTEX-guarded; no `separate` in v1 |
| Void-safe | YES | `detachable` only on optional data (attachment, error, last_error) |
| Non-Eiffel components behind contracts | YES | `FRONT_DOOR` (Caddy), `CLIENT_HOST` (WebView2), `AI_PARTICIPANT` (claude CLI), `DYNAMIC_DNS` (Duck DNS) |
