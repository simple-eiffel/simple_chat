# LANDSCAPE: simple_chat

Date: 2026-08-28. Every URL below was fetched during this research; where a fetch failed, it says so rather than guessing.

## Existing Solutions

### Matrix protocol + Conduit homeserver (+ Element Desktop client)
| Aspect | Assessment |
|--------|------------|
| Type | PROTOCOL + SERVER (Conduit) + CLIENT (Element) |
| Platform | Rust single binary with embedded RocksDB; Windows support not stated on the site |
| URL | https://conduit.rs/ · https://gitlab.com/famedly/conduit |
| Maturity | GROWING — "This project is beta. It can be used already, but is missing some smaller features." |
| License | Apache License 2.0 |

**Strengths:** "a single binary with an embedded database"; "focus on easy setup and low system requirements"; bots are ordinary users in the Matrix model; mature desktop clients exist.
**Weaknesses:** Adoption means every member installs Element and creates a Matrix account; encryption is on by default in clients, which fights a server-side AI participant; nothing of it is Eiffel; Windows binaries unverified from the sources fetched.
**Relevance:** 60% — the closest existing answer to "private chat with AI users," and the model to copy for rooms, events, and the since-token sync.

### Zulip
| Aspect | Assessment |
|--------|------------|
| Type | SERVER + CLIENTS |
| Platform | Linux only — "Ubuntu 22.04, Ubuntu 24.04, Ubuntu 26.04, Debian 12, and Debian 13 are supported for running Zulip in production." |
| URL | https://zulip.readthedocs.io/en/stable/production/requirements.html |
| Maturity | MATURE |
| License | Apache 2.0 (project's stated license; not on the fetched page) |

**Strengths:** Topic-threaded conversations; "At least 2 GB RAM" — light.
**Weaknesses:** No Windows server. Would need WSL or a second machine on Larry's side.
**Relevance:** 20% — a design reference for topics/threads only.

### Rocket.Chat
| Aspect | Assessment |
|--------|------------|
| Type | SERVER + CLIENTS |
| Platform | "You can deploy using one of the recommended methods: Docker, Podman, or Kubernetes." |
| URL | https://github.com/RocketChat/Rocket.Chat |
| Maturity | MATURE |
| License | MIT |

**Strengths:** Full feature set; Windows Store desktop client.
**Weaknesses:** Container deployment on a home Windows PC; heavyweight for ten people.
**Relevance:** 20%.

### XMPP — Prosody server
| Aspect | Assessment |
|--------|------------|
| Type | PROTOCOL + SERVER |
| Platform | Linux/BSD; "⚠️ Windows support has been deprecated. Downloads are no longer available." — "The last version before support was dropped has unresolved security issues." |
| URL | https://prosody.im/download/ |
| Maturity | MATURE (not on Windows) |
| License | MIT |

**Relevance:** 10% — rules out the XMPP route on a Windows host.

### The Lounge (self-hosted web IRC client)
| Aspect | Assessment |
|--------|------------|
| Type | WEB CLIENT (needs an IRC server) |
| Platform | "just works wherever Node.js runs" |
| URL | https://thelounge.chat/ |
| Maturity | MATURE |
| License | MIT |

**Strengths:** "a modern IRC client with push notifications, link previews, file uploads, and IRCv3 support"; persistent server-side connection so users "resume where you left off on any device."
**Weaknesses:** Client only; still needs an IRC daemon; Node.js runtime.
**Relevance:** 25% — the pattern of a server that stays connected on the user's behalf and pushes to a thin UI is exactly the SSE design.

### Mattermost
Not assessed: the requirements page returned a redirect and then HTTP 404 for both URLs tried (`docs.mattermost.com/install/…` and `docs.mattermost.com/deploy/server/…`). No claims made.

### Facebook Messenger Platform (the door that is closed)
"Messenger from Meta lets a business' Facebook Page or Instagram Professional account respond to people who message them" and "A person must initiate the conversation." No group chats. — https://developers.facebook.com/docs/messenger-platform/overview

## Eiffel Ecosystem Check

### ISE Libraries
- **EWF** (`contrib/library/web/framework/ewf`): "a standalone httpd web server component, written in Eiffel"; WSF routing; "multi-platform: it can be set on Windows, Linux" — https://github.com/EiffelWebFramework/EWF. Verified locally in EiffelStudio 25.02: standalone connection handlers for **thread** and **scoop** (`httpd/concurrency/{thread,scoop}/httpd_connection_handler.e`); knobs `max_concurrent_connections`, `max_tcp_clients`, `socket_timeout_ns`, `keep_alive_timeout_ns`; an **ssl** variant (`httpd/ssl/httpd_configuration.e`, TLS 1.2) linked against the OpenSSL DLLs EiffelStudio ships: `libssl-1_1-x64.dll`, `libcrypto-1_1-x64.dll` — OpenSSL **1.1.1**, end-of-life (see 06-RISKS).
- **WSF_RESPONSE** (`wsf/src/wsf_response.e`): `put_string`, `put_chunk` ("you should have header Transfer-Encoding: chunked"), `put_header` — the primitives Server-Sent Events need.
- **eel** (`contrib/library/text/encryption/eel`): SHA-256, HMAC-SHA256 in Eiffel.
- **Vision2**: only if `SB_WIDGET` must host WebView2 (see below).

### simple_* Libraries (all at `D:\prod`)
- **simple_web** — wrapper over EWF; `SIMPLE_WEB_SERVER` inherits `WSF_DEFAULT_SERVICE`; exposes the raw `wsf_request` / `wsf_response`, so uploads (`WSF_REQUEST.uploaded_files`) and chunked output are reachable even where the wrapper has no helper. Last commit 2026-02-06. `simple_scholar`'s `bible_htmx` face (554 lines, 22 routes) is a working precedent.
- **simple_htmx**, **simple_alpine** — HTML generation; SSE helpers are on simple_htmx's roadmap, not shipped.
- **simple_browser** — WebView2 via the webview/webview library (`lib/webview.dll`, `lib/WebView2Loader.dll`); `SIMPLE_BROWSER` API: `navigate_to`, `set_html_content`, `load_htmx_page`, `eval`, `inject`, `on_call` (JS→Eiffel binding), `respond`; `SB_WIDGET` embeds via a Vision2 `EV_DRAWING_AREA` HWND and `WEBVIEW_ENGINE.make_with_window (hwnd)` — an HWND is the contract, so a `simple_shell` window may host it (A-4). Status "Development", last commit 2026-02-06.
- **simple_shell** 1.8.0 — native window, message pump, Unicode clipboard + bitmap, `SHELL_INPUT`; **no tray icon / balloon yet** (new `SHELL_TRAY` needed).
- **simple_sql** — SQLite; presets `make_wal`, `make_performance`, `make_safe`; busy timeout.
- **simple_hash** — SHA-256, HMAC-SHA256 (pure Eiffel). **simple_jwt** — HS256.
- **simple_json**, **simple_uuid**, **simple_datetime**, **simple_logger**, **simple_config**, **simple_process**.
- **simple_ai_client** — `CLAUDE_CODE_CLIENT` (subscription via `claude -p`), `CLAUDE_CLIENT` (API), `OLLAMA_CLIENT`.
- **simple_websocket** — RFC 6455 frames and handshake only; no server loop. Not needed if SSE + POST suffices.

### Gobo Libraries
- Not required.

### Gap Analysis
Not available in Eiffel today: SSE helper on the server and in `simple_htmx`; tray icon / balloon; PBKDF2 or Argon2; a chat domain model; a maintained TLS stack in EWF (OpenSSL 1.1.1 is EOL); a non-Vision2 WebView2 host in `simple_browser`.

## Comparison Matrix
| Feature | Matrix/Conduit | Zulip | Rocket.Chat | The Lounge | Our Need |
|---------|----------------|-------|-------------|------------|----------|
| Windows server | unverified | ✗ | ✗ (containers) | ✓ (Node) | MUST |
| Bots as users | ✓ | ✓ | ✓ | n/a | MUST |
| Live sync w/o refresh | ✓ | ✓ | ✓ | ✓ | MUST |
| Desktop notifications | ✓ (Element) | ✓ | ✓ | ✓ (push) | MUST |
| Images inline | ✓ | ✓ | ✓ | ✓ | MUST |
| No third-party service | ✓ | ✓ | ✓ | ✓ | MUST |
| Eiffel, runnable folder | ✗ | ✗ | ✗ | ✗ | MUST |
| AI participant on host's subscription | ✗ (bot work) | ✗ | ✗ | ✗ | MUST |

## Patterns Identified
| Pattern | Seen In | Adopt? |
|---------|---------|--------|
| Room → ordered event log; clients sync with a `since` token | Matrix | YES — `/events?since=N` is both the SSE catch-up and the bot API read |
| A bot is an ordinary user with a token | Matrix, Rocket.Chat | YES |
| Server stays connected and pushes to a thin UI | The Lounge | YES — SSE |
| Topic threading | Zulip | LATER (replies first) |
| E2E encryption by default | Matrix/Element | NO — incompatible with a server-side AI participant |
| Container-first deployment | Rocket.Chat, Zulip | NO — runnable folder |

## Build vs Buy vs Adapt
| Option | Effort | Risk | Fit |
|--------|--------|------|-----|
| Build (Eiffel over simple_web/EWF, reusing bible_htmx patterns) | HIGH | MED | 95% |
| Adopt (Conduit + Element Desktop) | LOW | MED | 55% — members install Element; Windows binary unverified; no Eiffel; encryption fights the AI participant |
| Adapt (extend simple_scholar's bible_htmx) | MED | MED | 70% — the server pattern is right, the domain is wrong; better to reuse than extend |

**Initial Recommendation:** BUILD — with `bible_htmx`, `simple_shell`, `simple_sql`, and `CLAUDE_CODE_CLIENT` as the reuse base, and the Matrix event/since model as the design reference.
