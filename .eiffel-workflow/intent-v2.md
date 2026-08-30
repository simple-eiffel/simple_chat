# Intent v2: simple_chat

Date: 2026-08-29 · Phase 0, after deep review · Base intent: `intent.md` (carried forward in full; this file adds the review, the dependency audit, and the refinements they forced).

## What / Why / Users / Out of Scope
As in `intent.md`. Refinements from the review are marked **[R]** in the criteria below.

## Acceptance Criteria (refined)
- [ ] Admin creates an account; the member logs in over the internet and stays logged in across restarts
- [ ] **[R]** The very first admin is created by `simple_chat_server.exe --create-admin <name>` prompting for a password; the command refuses if an admin already exists; there is no default password anywhere
- [ ] `שלום 🤖 Χριστός` renders for every member within 2 s WAN, RTL intact; **[R]** bidi control characters (U+202A–U+202E, U+2066–U+2069) are stripped from display names so no one can spoof a name's reading order
- [ ] A 2 MB PNG posts inline within 2 s; a 9 MB file is refused; **[R]** a file whose bytes are not a PNG/JPEG signature is refused regardless of its name; uploads are stored as `data/uploads/<sha256>.<ext>` and served with `X-Content-Type-Options: nosniff`
- [ ] A client asleep 10 minutes shows every message posted meanwhile exactly once on wake; **[R]** two members posting in the same instant never cause a third client to miss either message (the doorbell test, Q3)
- [ ] Scroll-back pages with no gaps or duplicates
- [ ] `Claude:` gets a `🤖 Claude` reply; the 6th request in an hour gets a refusal and no call; **[R]** a hung `claude -p` is killed at the timeout and an apology is posted
- [ ] Every AI/tool message begins with 🤖 (invariant)
- [ ] `@tools-larry Gen 1:1` returns the verse; `@tools-larry Gen 1:1 | dir` is refused; **[R]** a shaped query that the allowlist rejects is refused with the help line and the shaped text shown
- [ ] `@shape-larry en_christo` returns counts; `via claude` / `via plain` select the phrasing; the reply echoes what ran
- [ ] A bot token reads since N and posts as `🤖 MikeBot`
- [ ] Balloon + badge on new messages; focus clears
- [ ] `front_door` swap changes nothing else; the Eiffel door reports honestly
- [ ] Invalid TOML is refused with the field named; `ANTHROPIC_API_KEY` in the environment is warned about
- [ ] Log contains no password, token or hash
- [ ] Assault suite: memory store and SQLite store give identical results; **[R]** a concurrent test posts from 8 threads while 4 streams read and proves no loss, no duplicate, no deadlock
- [ ] JSON and base64 pass independent vectors; **[R]** a `<script>` body renders as text in the UI (XSS vector) and the page carries a CSP

## Deep Intent Review — questions, alternatives, recommended answers

Adversarial pass over the spec. Each answer below is the recommendation; Larry can override any at approval.

### Q1. Where is the library/application line? (scope-creep trap)
**Risk:** Process supervision (Caddy), DDNS ticks, scheduled-task installation and `--create-admin` are operations concerns; if they land in the library, every consumer inherits Caddy.
**Alternatives:** (a) everything in one library; (b) library = domain + store + service + bus + participants + web app; server *application* = front doors, DDNS, supervision, CLI commands; (c) three libraries.
**Recommended:** (b). The library declares the deferred `FRONT_DOOR` and `DYNAMIC_DNS` contracts; `CADDY_FRONT_DOOR`, `DUCKDNS_UPDATER` and supervision live in `apps/server/ops/`. Same ECF, separate clusters; the library target has no Caddy in it.

### Q2. Threads and locks — what is the lock order, and where can it deadlock?
**Risk:** EWF runs handlers on threads. `post_message` takes the store lock, appends, then publishes; if `publish` holds the bus lock while writing to a subscriber's socket, and that write blocks on a slow client, every poster waits on a slow reader. Two locks taken in different orders somewhere = deadlock.
**Alternatives:** (a) SCOOP processors per stream (EWF has a SCOOP handler, but simple_web uses the thread handler); (b) threads with a documented lock hierarchy and never calling out under a lock; (c) a single global lock.
**Recommended:** (b). Hierarchy: `store` < `limiter` < `bus`, never nested outward; `EVENT_BUS.publish` snapshots the subscriber set under its lock, releases, then delivers; each `SSE_STREAM` has its own write lock and a write deadline; a subscriber that blocks past the deadline is closed and unsubscribed, never retried. Enforced by a concurrent assault test, not by hope.

### Q3. Out-of-order publication loses messages — the sharpest edge in the design
**Risk:** Two concurrent posts commit ids 5 and 6; thread B publishes 6 before thread A publishes 5. A stream with `last_delivered_id = 4` receives 6 (now 6), then 5 — dropped as a "duplicate" by the monotonic rule. **A message is lost on a live client.**
**Alternatives:** (a) hold the store lock through publish (serializes posting; simple, slower); (b) **doorbell pattern**: the bus carries only "room R has news," and each stream pulls `events_since (last_delivered_id)` from the store — the store is the truth, the bus is a wake-up; (c) streams buffer and reorder with a gap timeout.
**Recommended:** (b). It makes the stream's `last_delivered_id` contract exact, makes reconnect and live delivery the same code path, and costs one indexed query per wake-up. The 05 contract `monotonic duplicates dropped` stays; `receive` becomes `wake (a_room_id)`.

### Q4. Sessions: hashed DB tokens vs stateless JWT
**Risk:** simple_jwt exists and is tempting; stateless tokens cannot be revoked on logout or by the admin.
**Alternatives:** (a) JWT; (b) DB-backed random token, hash stored; (c) both.
**Recommended:** (b), as specified. One consequence found: the `Secure` cookie flag must follow the actual scheme — behind Caddy it is `https`; with `front_door = "none"` on a LAN test it may be `http`, and a `Secure` cookie would silently never return. `SERVER_CONFIG.cookie_secure` derives from the door's `is_public`, overridable for testing.

### Q5. Uploads: what stops a "PNG" that is HTML from becoming XSS?
**Risk:** A browser served an HTML file as `image/png` may sniff and execute it; user-supplied filenames on disk invite path traversal.
**Alternatives:** (a) trust the declared MIME; (b) validate magic bytes, store by hash, serve the validated type with `nosniff`; (c) re-encode every image through cairo.
**Recommended:** (b) for v1 (`(c)` when `simple_wic` exists). Names on disk are `<sha256>.<png|jpg>`; the original name is only metadata; `Content-Disposition: inline; filename="…"` sanitized to ASCII.

### Q6. Rendering user text: escaping and CSP vs Alpine
**Risk:** Server-rendered fragments with user text are XSS unless every insertion is escaped; Alpine.js evaluates expressions with `new Function`, which a strict CSP forbids.
**Alternatives:** (a) no CSP; (b) CSP `default-src 'self'` with Alpine's CSP build and HTMX-only interactions where possible; (c) drop Alpine.
**Recommended:** (b). `CHAT_UI` has exactly one text-insertion function and it escapes; the assault suite posts `<script>alert(1)</script>` and asserts it renders as text. Alpine is kept for small client state (composer, badge) via its CSP-compatible build; if that proves awkward, (c).

### Q7. A hung participant: who kills `claude -p`?
**Risk:** `CLAUDE_CODE_CLIENT.timeout_seconds` is advisory — "the CLI is not killed." `simple_process` exposes `launch` but no visible kill/wait-with-timeout. A hung child pins the participant's single worker forever and the room's Claude goes silent.
**Alternatives:** (a) accept; (b) add wait-with-timeout + kill to `simple_process` and honour `timeout_seconds` in `CLAUDE_CODE_CLIENT` (also needed for `bible.exe` and Ollama); (c) a watchdog thread per participant that kills by PID.
**Recommended:** (b), as a dependency task before Phase 1 implementation. Contract: `bounded_runtime` becomes real.

### Q8. Participant queues: fairness and attribution
**Risk:** Two members address `@tools-larry` at once; with `max_concurrent = 1` the second waits with no feedback; statuses could attribute wrongly.
**Alternatives:** (a) reject when busy; (b) FIFO queue per participant with a queued status ("🤖 Tools: queued behind 1"); (c) unbounded parallelism.
**Recommended:** (b), bounded queue (e.g. 8) with a polite refusal beyond it; every status carries the asker's name.

### Q9. Where do rate limits live across restarts?
**Risk:** An in-memory limiter forgets on restart; Larry restarting the server resets everyone's hour — harmless; but login backoff resetting on restart could be probed by making the host restart (it can't be, remotely).
**Alternatives:** (a) memory; (b) persisted counters; (c) memory for posts/AI, persisted for login failures.
**Recommended:** (a) for v1 — only the host can restart the server. Revisit if the server ever runs where others can bounce it.

### Q10. Schema evolution
**Risk:** v1's tables will change in Phase 2 (reactions, edits); a store with no migration discipline becomes a rewrite.
**Alternatives:** (a) hand-edited SQL; (b) numbered forward-only migrations in `CHAT_SCHEMA`, each in a transaction, with a backup before migrating and a `schema_version` row; (c) an ORM.
**Recommended:** (b). The assault suite migrates a v0 (empty) and a v1 database and asserts the resulting schema; a migration that fails leaves the previous version intact.

### Q11. How are SSE and the front door tested deterministically?
**Risk:** Sockets, timing and real certificates are not unit-testable; if the only tests are domain tests, the riskiest parts are untested.
**Alternatives:** (a) domain tests only; (b) domain tests + an integration target that starts the real server on a random localhost port and drives it (WinHTTP client), with the front door tested as a state machine against a fake child; (c) end-to-end with Caddy and Let's Encrypt staging.
**Recommended:** (b). `CADDY_FRONT_DOOR` is tested for Caddyfile generation, child spawn, exit detection and restart backoff using `cmd /c` stand-ins; real Caddy runs only in Spike A and in Larry's hands.

### Q12. Naming
**Risk:** The ecosystem uses short prefixes (`SW_`, `SE_`, `SB_`, `OCR_`); long prefixes read as noise.
**Alternatives:** (a) `CHAT_*`; (b) `SC_*`; (c) unprefixed domain names (`USER`, `ROOM`) — collide with ISE and other libraries.
**Recommended:** (a). `CHAT_` reads as the domain; the facade stays `SIMPLE_CHAT_SERVER` per ecosystem convention; app roots `SERVER_APP` / `CLIENT_APP`; participants `*_PARTICIPANT`; shapers `*_SHAPER`.

### Q13. What is premature?
**Recommended deferrals:** `LONG_POLL_SOURCE` — specify, implement only if Spike A fails; `VISION2_WEBVIEW_HOST` — only if Spike B fails; `/participants` completion UI — Phase 2; `PHRASED_PARTICIPANT` as a separate class — fold into `TOOL_PARTICIPANT.response_shaper` (one concept fewer); a Windows service — never for v1. **Kept on purpose:** `EIFFEL_FRONT_DOOR` stub (it *is* the swap point), `backup` (data safety is not a feature), the echo line on tool replies (transparency is the security control).

### Q14. Edge cases the spec did not name (now named)
| Case | Behaviour |
|---|---|
| Disk full on upload | refuse with 507, log, no partial file (write to temp, rename on success) |
| SSE client stops reading | write deadline (5 s) → close + unsubscribe; client reconnects with `since` |
| Duplicate username differing only in case | usernames are lowercase ASCII; `Nick` and `nick` are the same account |
| Display name with bidi controls or only whitespace | stripped / refused |
| Message of 4,000 characters of emoji | `STRING_32.count` is characters; the DB stores UTF-8; the limit is characters |
| Participant answers with an image path outside the data folder | refused: `image_path` must resolve under the participant's allowed output folder |
| Clock skew between server and client | expiry is judged on the server clock only |
| Server restarted mid-request | clients retry POSTs? — no: a lost POST is shown as failed in the composer; the member re-sends |
| Two admins edit the same user | last write wins; no locking needed at this scale |

## Dependency Audit (simple_* First) — 2026-08-29, `D:\prod`

| Need | Result |
|---|---|
| toml, mml, regex, http, web, htmx, alpine, sql, encryption (2.0.0), json, uuid, datetime, logger, process, base64, file, encoding, config, ai_client, shell (1.8.0), browser, testing, scheduler | **present** |
| thread / mutex | no simple_* library — but `MUTEX` lives in **EiffelBase** itself (`base/ise/synchronization`), so no ISE `thread` library is needed; Phase 1 confirmed: the ECF depends on `base` only. Not a gap. |
| winhttp | **MISSING** — `OCR_HTTP` in simple_ocr_capture has the WinHTTP code; simple_http resolves libcurl.dll from EiffelStudio's bin and cannot ship |
| timer | MISSING — simple_scheduler covers the need |
| service, tray, image/wic, zip | MISSING — tray goes into simple_shell (`SHELL_TRAY`); service not needed; image processing is Phase 2 |
| process kill / wait-with-timeout | **MISSING in simple_process** — required by Q7 |

### Gaps Identified (Potential simple_* Libraries)

| Gap | Current Workaround | Proposed simple_* |
|-----|-------------------|-------------------|
| Mutex / thread primitives | ISE `thread` library (`MUTEX`, `THREAD`) | `simple_thread` (thin, contracted MUTEX/THREAD wrappers; SCOOP-aware) |
| WinHTTP client without libcurl | `OCR_HTTP` copied into the app | `simple_winhttp` (promote `OCR_HTTP`; GET/POST/JSON; used by DDNS, health probes, the relay) |
| Process wait-with-timeout and kill | none | addition to `simple_process` (`wait_for_exit (ms)`, `kill`), then honoured by `CLAUDE_CODE_CLIENT` and `OLLAMA_CLIENT` |
| Tray icon and balloon | none | `SHELL_TRAY` in simple_shell (planned) |
| SSE attributes in HTMX rendering | hand-written attributes | small addition to `simple_htmx` (already on its roadmap) |
| Image decode / thumbnails | serve originals only | `simple_wic` (Phase 2; also named in simple_widgets' verdicts) |

## Corrections and refinements to the spec (to carry into Phase 1)
1. **Doorbell pattern** replaces push-through-bus (Q3): `EVENT_BUS.publish` → `EVENT_BUS.ring (a_room_id)`; `SSE_STREAM.wake` pulls from the store. `EVENT_SUBSCRIBER.receive (event)` becomes `wake (room_id)`; `AI_DISPATCHER`/`PARTICIPANT_DISPATCHER` pulls events since its own cursor.
2. **Lock hierarchy** documented in `CHAT_SERVICE` and enforced by test (Q2).
3. **Library/app split** (Q1): front doors, DDNS, supervision and CLI commands in `apps/server/ops/`.
4. `SERVER_CONFIG.cookie_secure` (Q4); `--create-admin` (Q1/Acceptance); upload hardening (Q5); CSP + single escaping point (Q6); process timeout/kill dependency (Q7); per-participant bounded FIFO with queued statuses (Q8); `CHAT_SCHEMA` migrations with backup (Q10); integration test target (Q11).
5. `PHRASED_PARTICIPANT` folded into `TOOL_PARTICIPANT.response_shaper` (Q13).
6. Edge-case table (Q14) becomes preconditions/postconditions in Phase 1.

## MML Decision (REQUIRED)
**Decision:** YES-Optional — as in `intent.md`; model queries on `MEMORY_CHAT_STORE`, `EVENT_BUS`, `RATE_LIMITER`.

## Approval
Pending Larry's approval to proceed to Phase 1 (`/eiffel.contracts`).
