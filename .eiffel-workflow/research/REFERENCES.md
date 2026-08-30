# REFERENCES: simple_chat

All fetched 2026-08-28 unless noted. Failed fetches are listed so no claim rests on them.

## Documentation Consulted
- https://conduit.rs/ — Conduit is "a lightweight open-source server implementation of the Matrix Specification with a focus on easy setup and low system requirements"; "a single binary with an embedded database"; beta.
- https://gitlab.com/famedly/conduit — Apache License 2.0; deployment details not on the project page.
- https://zulip.readthedocs.io/en/stable/production/requirements.html — Linux only ("Ubuntu 22.04, Ubuntu 24.04, Ubuntu 26.04, Debian 12, and Debian 13"); "At least 2 GB RAM".
- https://prosody.im/download/ — "Windows support has been deprecated. Downloads are no longer available"; "The last version before support was dropped has unresolved security issues."
- https://github.com/RocketChat/Rocket.Chat — "Docker, Podman, or Kubernetes"; MIT.
- https://thelounge.chat/ — "a modern IRC client with push notifications, link previews, file uploads, and IRCv3 support"; Node.js; MIT.
- https://developers.facebook.com/docs/messenger-platform/overview — business Pages only; "A person must initiate the conversation"; no group chats.
- https://github.com/EiffelWebFramework/EWF — EWSGI + WSF layers; "a standalone httpd web server component, written in Eiffel"; multi-platform.
- https://github.com/webview/webview — "Uses WebKit (GTK/Cocoa) and Edge WebView2 (Windows)"; "Developers and end-users must have the WebView2 runtime installed on their system for any version of Windows before Windows 11"; MIT.
- https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution — Evergreen runtime detection via the `pv` registry value under `EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}`; bootstrapper `MicrosoftEdgeWebview2Setup.exe /silent /install`; ship `WebView2Loader.dll`.
- https://htmx.org/extensions/sse/ — `hx-ext="sse" sse-connect="<url>"`, `sse-swap="<name>"`, `hx-trigger="sse:<name>"`; reconnect with "an exponential-backoff algorithm".
- https://openssl-library.org/post/2023-09-11-eol-111/ — "OpenSSL 1.1.1 has reached its EOL as of today, 11th September 2023"; "it will no longer receive publicly available security fixes".
- https://www.win-acme.com/ — "Automatically creates a scheduled task to renew certificates when needed"; HTTP and DNS validation.
- https://caddyserver.com/docs/automatic-https — "Certificates are obtained and renewed for all qualifying domain names"; HTTP→HTTPS redirects; needs A/AAAA records and open ports 80/443.
- https://caddyserver.com/docs/install — Windows: static binaries, `choco install caddy`, `scoop install caddy`, webi.
- https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html — Argon2id "19 MiB of memory, an iteration count of 2, and 1 degree of parallelism"; "PBKDF2-HMAC-SHA256: 600,000 iterations (recommended)".
- https://learn.microsoft.com/en-us/windows/win32/api/bcrypt/nf-bcrypt-bcryptderivekeypbkdf2 — `BCryptDeriveKeyPBKDF2`, `Bcrypt.dll`, Windows 7+, RFC 2898.
- https://www.sqlite.org/threadsafe.html — "The default mode is serialized"; one connection may be shared across threads in serialized mode.
- https://www.sqlite.org/wal.html — "readers do not block writers and a writer does not block readers"; "there can only be one writer at a time"; WAL must be on the same host.
- https://learn.microsoft.com/en-us/windows/win32/shell/notification-area — `Shell_NotifyIcon`, `NOTIFYICONDATA`, `NOTIFYICON_VERSION_4`, GUID identification, balloon title ≤ 48 / body ≤ 200 chars, quiet time.
- https://www.duckdns.org/ and https://www.duckdns.org/spec.jsp — free dynamic DNS; `https://www.duckdns.org/update?domains=…&token=…[&ip=…]`; IPv4 auto-detected when omitted.

## Repositories / Local Sources Examined (D:\prod and EiffelStudio 25.02)
- `simple_web/src/server/*` — `SIMPLE_WEB_SERVER` (inherits `WSF_DEFAULT_SERVICE`), request/response wrappers exposing `wsf_request` / `wsf_response`.
- `simple_scholar/htmx/bible_htmx_app.e` — 554-line HTMX app on simple_web, 22 routes on port 5500.
- `simple_browser/src/{core,widget}` — `SIMPLE_BROWSER` API; `SB_WIDGET` via `EV_DRAWING_AREA` HWND → `WEBVIEW_ENGINE.make_with_window`.
- `simple_shell` 1.8.0 — `SHELL_WINDOW`, `SHELL_CLIPBOARD` (+ bitmap), `SHELL_INPUT`; no tray yet.
- `simple_sql/README.md` — WAL presets, busy timeout.
- `simple_hash/README.md` — SHA-256, HMAC-SHA256, MD5.
- `simple_ai_client/src/providers/claude_code/claude_code_client.e` — subscription dispatch; clears `ANTHROPIC_API_KEY` per child.
- EiffelStudio `contrib/library/web/framework/ewf/wsf/src/wsf_response.e` — `put_string`, `put_chunk`, `put_header`.
- EiffelStudio `contrib/library/web/framework/ewf/httpd/{concurrency/thread,concurrency/scoop,ssl,no_ssl}` — handlers and configurations; `max_concurrent_connections`, `max_tcp_clients`, `socket_timeout_ns`, `keep_alive_timeout_ns` in the standalone connector.
- EiffelStudio `studio/spec/win64/bin/libssl-1_1-x64.dll`, `libcrypto-1_1-x64.dll` — the OpenSSL EWF links.
- EiffelStudio `contrib/library/text/encryption/eel` — SHA256, HMAC-SHA256.

## Failed Fetches (no claims made)
- https://docs.mattermost.com/install/software-hardware-requirements.html — redirect, no content.
- https://docs.mattermost.com/deploy/server/software-hardware-requirements.html — HTTP 404.
- https://prosody.im/doc/installing — HTTP 404 (superseded by /download/).
- https://www.eiffel.org/doc/solutions/EiffelWeb — page describes the obsolete CGI EiffelWeb, not EWF.
