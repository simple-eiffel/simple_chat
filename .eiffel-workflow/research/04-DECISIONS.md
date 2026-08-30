# DECISIONS: simple_chat

Date: 2026-08-28. Decisions marked **(Larry)** were made by Larry before research; the rest are research recommendations for /eiffel.spec and /eiffel.intent to confirm.

## Decision Log

### D-001: Build, adopt, or adapt
**Question:** Build in Eiffel, or adopt an existing self-hosted chat?
**Options:**
1. Adopt Matrix (Conduit + Element): fast, mature clients; members install Element and make accounts; client-side encryption fights a server-side AI; Windows binary unverified; nothing Eiffel.
2. Build over simple_web/EWF: meets every stated decision; more work; the ecosystem already has server, HTMX, WebView2, SQLite, Claude pieces.
3. Adapt simple_scholar's bible_htmx: right server pattern, wrong domain.

**Decision:** BUILD, reusing the bible_htmx server pattern, simple_shell, simple_sql, CLAUDE_CODE_CLIENT.
**Rationale:** Larry's constraints (Eiffel, standalone, runnable folder, AI-in-room on his subscription) fit no adoptable product.
**Implications:** simple_chat is an application (server + client) with a library core; spec kit applies.
**Reversible:** YES (the Matrix event model is copied, so a bridge is conceivable later).

### D-002: Server framework
**Question:** simple_web (EWF standalone) vs raw EWF vs a new socket server?
**Decision:** simple_web over EWF's standalone httpd with the **thread** connection handler.
**Rationale:** Production status, routing, request/response wrappers, raw `wsf_request`/`wsf_response` escape hatches; `bible_htmx` proves the shape. EWF knobs (`max_concurrent_connections`, `keep_alive_timeout_ns`, `socket_timeout_ns`) are available for the SSE load.
**Implications:** Handlers run on EWF threads → domain state needs a mutex; SQLite must be used in serialized mode.
**Reversible:** YES.

### D-003: Live updates
**Question:** SSE, WebSocket, or long-polling?
**Options:**
1. SSE via `WSF_RESPONSE.put_chunk` with `Transfer-Encoding: chunked`; HTMX SSE extension (`hx-ext="sse" sse-connect`, `sse-swap`, `hx-trigger="sse:name"`; "an exponential-backoff algorithm" reconnect) — https://htmx.org/extensions/sse/
2. WebSocket: simple_websocket has frames only, no server loop; EWF standalone has no WS upgrade path in what was inspected.
3. Long-polling `GET /events?since=N` blocking ≤ 25 s: works with any request/response server.

**Decision:** SSE, with long-polling as the guaranteed fallback behind the same `since` semantics.
**Rationale:** One-directional push is all chat needs; posts are plain POSTs; SSE is HTTP, so it passes any proxy or TLS terminator.
**Implications:** Spike early (A-3): one handler holding a response open per client; verify EWF keep-alive/socket timeouts don't cut idle streams (send a heartbeat comment every 20 s).
**Reversible:** YES.

### D-004: TLS termination — **needs Larry's confirmation**
**Question:** Larry chose "EWF's own SSL." Research: EWF's ssl connector links the OpenSSL DLLs EiffelStudio 25.02 ships — `libssl-1_1-x64.dll` / `libcrypto-1_1-x64.dll`, i.e. OpenSSL 1.1.1, which "has reached its EOL as of … 11th September 2023" and "will no longer receive publicly available security fixes" (https://openssl-library.org/post/2023-09-11-eol-111/). Putting that on an internet-facing port is the largest security risk in the design.
**Options:**
1. EWF ssl as shipped: zero extra components; EOL crypto on the public port.
2. Rebuild EWF's ssl glue against OpenSSL 3.x DLLs: keeps "own SSL"; unknown effort; certificate issuance still needs win-acme ("Automatically creates a scheduled task to renew certificates" — https://www.win-acme.com/).
3. **Caddy** on the same PC as the TLS terminator and reverse proxy: "Certificates are obtained and renewed for all qualifying domain names," redirects HTTP→HTTPS, needs "your domain's A/AAAA records point to your server" and "ports 80 and 443 are open externally" (https://caddyserver.com/docs/automatic-https); Windows static binaries, `choco install caddy`, `scoop install caddy` (https://caddyserver.com/docs/install). EWF then serves plain HTTP on `127.0.0.1` only.

**Decision (recommended):** Option 3. It is software on Larry's PC, not a third-party *service*, so the "no tunnel" decision holds; it removes EOL crypto, certificate scripting, and renewal from the Eiffel code entirely.
**Rationale:** Modern TLS and automatic Let's Encrypt for one extra executable in the server folder.
**Implications:** Server folder ships `caddy.exe` + a 5-line Caddyfile; simple_chat itself never touches certificates. If Larry insists on option 1/2, D-005 uses win-acme and the EWF ssl configuration.
**Reversible:** YES.

**Addendum 2026-08-29 — "why not an Eiffel simple_caddy?"** Feasible, and partly already begun: `simple_email`'s `SE_TLS_SOCKET` (531 lines) is an SChannel **client** TLS socket (`AcquireCredentialsHandle`, `InitializeSecurityContext`, `EncryptMessage`/`DecryptMessage`); the server side is its mirror (`AcceptSecurityContext` with a certificate credential). The missing pieces are an ACME client (`simple_acme`: JWS over CNG `BCryptSignHash`, CSR via CryptoAPI, HTTP-01 challenge, renewal) and a small TLS-terminating reverse proxy with SSE passthrough. The crypto stays Microsoft's (SChannel/CNG/CryptoAPI); Eiffel owns protocol logic and plumbing. Sequenced **after** simple_chat v1: Caddy now, swap later — this decision is reversible by design.

### D-005: Public name and dynamic IP
**Question:** How do members find the server when the home IP changes?
**Options:**
1. Own domain + DNS provider API updater.
2. Duck DNS (free): update by `https://www.duckdns.org/update?domains=…&token=…`; "If you do not specify the IP address, then it will be detected" (https://www.duckdns.org/spec.jsp).

**Decision:** A domain Larry owns if he has one; otherwise Duck DNS. Either way an updater runs as a scheduled task every 5 minutes (a curl one-liner, or a feature of the server).
**Rationale:** Let's Encrypt (via Caddy or win-acme) needs a name; the name must follow the IP.
**Implications:** Prerequisite check for A-1 (no CGNAT) before anything is built.
**Reversible:** YES.

### D-006: Password storage
**Question:** What KDF, with what implementation?
**Options:**
1. Argon2id (OWASP first choice: "19 MiB of memory, an iteration count of 2, and 1 degree of parallelism") — no Eiffel or shipped C implementation.
2. PBKDF2-HMAC-SHA256, "600,000 iterations (recommended)" (https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html) via **Windows CNG** `BCryptDeriveKeyPBKDF2` — `Bcrypt.dll`, Windows 7+, "derives a key … using the PBKDF2 key derivation algorithm as defined by RFC 2898" (https://learn.microsoft.com/en-us/windows/win32/api/bcrypt/nf-bcrypt-bcryptderivekeypbkdf2). No redistributable.
3. PBKDF2 in pure Eiffel over simple_hash's HMAC-SHA256: no C, but 600,000 HMAC rounds in Eiffel may take seconds per login — measure.

**Decision (revised 2026-08-29, evening):** `simple_encryption` **2.0.0**. Verification of the 1.x library against Python `hashlib` found its PBKDF2 diverged from RFC 8018 from iteration 119 (EEL's `INTEGER_X.as_bytes` drops leading zero bytes), took 69 s per hash at 600k, and drew salts/tokens from a clock-seeded LCG. 2.0.0 fixes all three: option 2 (CNG `BCryptDeriveKeyPBKDF2`, `BCryptHash`, `BCryptGenRandom`) behind the same `hash_password` / `verify_password` interface, portable path corrected as the non-Windows fallback, RFC vectors and the iteration-119 regression in the suite (18/18). Hash + verify + reject at 600,000 iterations: 0.29 s. Disclosed in the library's CHANGELOG and README.
**Rationale:** OWASP-compliant, maintained by Microsoft, zero shipping burden — and now independently verified.
**Implications:** Store `pbkdf2$600000$salt$hash`; re-hash on parameter upgrade at login.
**Reversible:** YES.

### D-007: Storage
**Decision:** SQLite via simple_sql; WAL ("readers do not block writers and a writer does not block readers" … "there can only be one writer at a time" — https://www.sqlite.org/wal.html); default **serialized** threading ("The default mode is serialized" — https://www.sqlite.org/threadsafe.html), one connection guarded by an application mutex for writes; images as files under `data/uploads/` with rows in `attachment`.
**Rationale:** Ten users; one file to back up; the ecosystem's database.
**Reversible:** YES.

### D-008: Client architecture **(Larry: Eiffel shell from day one)**
**Decision:** An Eiffel executable that opens a `simple_shell` window, hosts WebView2 through `simple_browser`'s engine on that HWND (A-4 spike; fallback `SB_WIDGET` on Vision2 as `bible_htmx` does), and loads the server's HTMX/Alpine UI. Native pieces: tray icon and balloon (new `SHELL_TRAY` over `Shell_NotifyIcon`, `NOTIFYICON_VERSION_4`, `NIF_INFO` — https://learn.microsoft.com/en-us/windows/win32/shell/notification-area), window title badge, remembered server URL, auto-start option.
**Rationale:** One UI codebase; Hebrew/Greek render; the shell adds what a browser tab cannot (tray, toasts, autostart).
**Implications:** WebView2 Runtime must be present: check the `pv` value under `HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}` (or HKCU) and, if absent, run `MicrosoftEdgeWebview2Setup.exe /silent /install`; ship `WebView2Loader.dll` (https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution). "Developers and end-users must have the WebView2 runtime installed on their system for any version of Windows before Windows 11" (https://github.com/webview/webview).
**Reversible:** YES.

### D-009: AI participant
**Decision:** A server-side dispatcher: trigger `^(Claude|ROBOT)[:：]\s*(.+)` at message start → `CLAUDE_CODE_CLIENT` with the vault working directory (skills, memory), a persona system prompt (chat register, ≤ 1,200 chars unless asked, emoji allowed, never fabricate specifics in Larry's voice), the sender's display name, and web search allowed; reply posted as user `🤖 Claude`. Per-user rate limit (default 5/hour), a global concurrency of 1, and a "🤖 thinking…" placeholder message edited into the reply. Bot API tokens let other machines run participants the same way.
**Rationale:** The whole point of the product; the guardrails Larry said yes to.
**Implications:** `CLAUDE_CODE_CLIENT` gains `--json-schema` for `{text, image_path}` so Claude can return a generated PNG path to post.
**Reversible:** YES.

### D-010: Distribution — runnable folders
**Decision:** `simple_chat_server\` (server exe, `simple_chat_server.toml`, `data\`, `caddy.exe` + `Caddyfile`, `start.bat`) and `simple_chat\` (client exe, `webview.dll`, `WebView2Loader.dll`, `start.bat` that checks the runtime key and offers the bootstrapper). No zip installer.
**Reversible:** YES.

### D-011: Rooms from day one
**Decision:** `room`, `membership`, `event` tables; v1 UI shows one room; the API is room-scoped.
**Reversible:** NO (schema).

### D-012: Explicitly not doing
End-to-end encryption; voice/video; federation; mobile clients; a Messenger bridge (the spike stays separate).

### D-013: The front door is a swappable component (Larry, 2026-08-29)
**Question:** Caddy now; an Eiffel front door later — how do they swap without touching the chat?
**Decision:** simple_chat's server always speaks plain HTTP on `127.0.0.1:<port>` and never knows what terminates TLS. The *front door* is a component behind one contract - deferred class `FRONT_DOOR` (`start`, `stop`, `is_serving`, `public_name`, `certificate_expiry`, `last_error`; invariants: serving implies a valid certificate; forwarded headers `X-Forwarded-Proto/For` always set) - with two effective descendants: `CADDY_FRONT_DOOR` (generates the Caddyfile, spawns and supervises `caddy.exe` as a child process) and `EIFFEL_FRONT_DOOR` (in-process: `simple_tls` server side + `simple_acme` + the streaming proxy). Selected by one line in `simple_chat_server.toml`: `front_door = "caddy" | "eiffel" | "none"`. Caddy therefore becomes a managed child of the server, not something Larry runs by hand, and swapping is a creation-time choice with identical contracts.
**Implications:** The server's own request handling must not assume TLS (it reads the forwarded headers); the SSE stream must survive either proxy (heartbeats); `EIFFEL_FRONT_DOOR` is Tier 1 work and ships behind the same contract.
**Reversible:** YES by design.

### D-014: Text shaping is a simple_* library with swappable backends (Larry, 2026-08-29)
**Question:** WebView2 renders Hebrew today; `simple_widgets` cannot. DirectWrite is acceptable now, but a pure-Eiffel solution is the destination.
**Decision:** A new library, `simple_shaping` (the name `simple_widgets`' own verdict file already uses), whose pipeline is four contracts that swap **independently**: `BIDI_RESOLVER` (UAX #9: paragraph direction, embedding levels, run reordering), `SCRIPT_ITEMIZER` (runs by script/UAX #24), `GLYPH_SHAPER` (characters → positioned glyphs with cluster map; OpenType GSUB/GPOS is the hard part - Hebrew vowel and cantillation positioning), `FONT_FALLBACK` (a face per run). Backends: `DIRECTWRITE_*` first (IDWriteTextAnalyzer does all four; Windows-maintained, like CNG for crypto), `EIFFEL_*` stage by stage - bidi and itemization are tractable pure Eiffel and verifiable against Unicode's own `BidiTest.txt` / `BidiCharacterTest.txt`; OpenType shaping is the long pole. Output is a `GLYPH_RUN` sequence that `simple_cairo` draws with `cairo_show_glyphs` through the matching font face, so `simple_widgets` gains correct Hebrew/Greek without knowing which backend produced the glyphs.
**Implications:** simple_chat v1 still uses WebView2 (D-008); `simple_shaping` is Tier 2 and gets its own /eiffel.research; the pure-Eiffel path is a sequence of backend swaps, not a rewrite.
**Reversible:** YES by design.

### D-015: Thick client on simple_widgets; no browser anywhere (Larry, 2026-08-29)
**Question:** WebView2 renders Hebrew today; simple_widgets does not — yet. Browser first, or thick first?
**Decision:** Thick first. Supersedes the client half of D-008 (WebView2 host, HTMX/Alpine UI, cookies, CSP). The server-rendered HTML tier is removed, not deferred; the JSON API is the only client surface. Rationale in Larry's words: control ("building it means I control it"), no Chromium runtime, no script engine to inject into, one toolkit for chat and the scholar GUI, contracts reaching the UI.
**Implications:** `simple_shaping` (D-014) moves to the front of the queue; an image decoder (WIC) and `simple_winhttp` follow; `simple_browser` and `simple_htmx` are dropped from the ECF. See spec/10-ADDENDUM-THICK-CLIENT.md.
**Reversible:** the JSON API is UI-agnostic, so a browser UI could be added later without touching the server — but it is not planned.

### D-016: The GUI finds the server; the server is a service, not a window (Larry, 2026-08-29)
**Decision:** The host runs `simple_chat_server` as a background service on his PC; the thick GUI locates it (`SERVICE_LOCATOR`: local `/health` first when `prefers_local`, else the configured URL) and talks to it over HTTP/JSON exactly as a remote member's GUI does. Same runnable folder, one launcher, two processes; never an in-process shortcut.
**Rationale:** one code path for every client; the server's lifetime (logon-to-logoff, restart-safe) is independent of any window; a rendering crash cannot take the room down.

### D-017: Replica mode and manual promotion are designed for, not built (2026-08-29)
**Decision:** A member may later run `simple_chat_server --replica <primary> <token>`: it pulls the append-only log by id (`events_since`) and the sha256-addressed attachments, serves them locally, forwards posts. One writer at a time; promotion ("Sue is host now") is manual; schema v2 reserves an `epoch` column. Hosting still requires a forwarded port and a public name — the roster will record which members are host-capable.
**Reversible:** yes; nothing in v1 depends on it.

### D-018: Long-poll is the thick client's live path; SSE stays for bots (2026-08-29)
**Decision:** `GET /rooms/{id}/wait?since=N&limit=M&seconds=S` (S ≤ 25) waits on the doorbell (`POLL_WAITER`, MUTEX + `CONDITION_VARIABLE.wait_with_timeout` from EiffelBase) and returns events after N plus any ephemeral statuses seen during the wait. The client needs no streaming reader; `SSE_STREAM` remains for `curl` and bots.
**Rationale:** one ordinary request per wait; WinHTTP synchronous on a worker thread; the doorbell already guarantees no loss.

### D-019: Emoji as inline pictures (proposed; decided at the simple_shaping research)
**Proposal:** Render emoji sequences as PNGs from one open set shipped with the client (Noto Emoji, Apache 2.0; or Twemoji, CC-BY 4.0), keyed by code-point sequence. The 🤖 marker is the same picture on every screen; cairo 1.17.2 needs no COLR/CBDT support.

### D-020: Image decoding through WIC (2026-08-29)
**Decision:** `IWICImagingFactory` → 32bpp BGRA → `CAIRO_SURFACE`, for PNG/JPEG/GIF/BMP/WebP, as S05 §7 of simple_widgets planned (a codec in simple_shell, or `simple_wic` if it grows). The same code lets the server re-encode uploads to PNG (intent-v2 Q5(c)).
