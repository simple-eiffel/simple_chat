# RISKS: simple_chat

Date: 2026-08-28

## Risk Register

| ID | Risk | Likelihood | Impact | Mitigation |
|----|------|------------|--------|------------|
| RISK-001 | Larry's ISP uses CGNAT → port-forwarding cannot work | MED | HIGH | Check before building: router WAN address vs. a public "what is my IP" result; if they differ, D-005 reach must change (IPv6 or a tunnel) |
| RISK-002 | EWF's ssl connector ships OpenSSL 1.1.1 (EOL 2023-09-11) on a public port | HIGH if used | HIGH | D-004: Caddy terminates TLS; EWF listens on 127.0.0.1 only |
| RISK-003 | EWF standalone starves under long-lived SSE streams (thread pool, keep-alive/socket timeouts cut idle streams) | MED | MED | Spike first; heartbeat comment every 20 s; tune `max_concurrent_connections`, `keep_alive_timeout_ns`, `socket_timeout_ns`; long-poll fallback behind the same `since` API |
| RISK-004 | simple_browser is "Development" status, last commit 2026-02-06, and embeds via Vision2 (`SB_WIDGET`) | MED | MED | Spike hosting on a `simple_shell` HWND (`WEBVIEW_ENGINE.make_with_window`); fallback to `SB_WIDGET` + Vision2 as `bible_htmx` already does |
| RISK-005 | WebView2 Runtime absent on a member's Windows 10 PC | LOW | MED | `start.bat` checks the `pv` registry value and runs `MicrosoftEdgeWebview2Setup.exe /silent /install` |
| RISK-006 | Members don't install / don't return (adoption) | MED | HIGH | One folder, one exe, one URL, one password; Larry seeds the room; notifications make it sticky; keep the Messenger robot spike as the bridge while the group migrates |
| RISK-007 | Home PC sleeps, reboots for Windows Update, or the app crashes | HIGH | MED | Server runs as a scheduled task at logon with restart-on-failure; power plan never sleeps; clients reconnect and catch up (FR-008) |
| RISK-008 | Exposing a home network port | MED | HIGH | Only 80/443 forwarded to Caddy; EWF bound to localhost; login backoff (NFR-006); PBKDF2 600k; sessions `Secure; HttpOnly`; upload limits; admin actions require the admin session |
| RISK-009 | Claude subscription quota consumed by friends' requests | MED | MED | Per-user rate limit (FR-012), global concurrency 1, usage visible on the admin page; API-key path exists if it ever becomes a product for others |
| RISK-010 | SQLite misuse across EWF threads (one connection, concurrent handlers) | MED | HIGH | Serialized mode (default) + one application mutex around writes; assault tests hammer concurrent posts |
| RISK-011 | RTL/Hebrew rendering glitches in mixed lines | LOW | MED | `dir="auto"` per message element; a Hebrew/Greek fixture in the UI tests |
| RISK-012 | Scope creep ("as many features as possible") | HIGH | MED | Phase gates in 07; nothing from Phase 2 before the group uses Phase 1 daily |
| RISK-013 | Dynamic IP change breaks the name | MED | LOW | Duck DNS (or domain API) updater every 5 min; low DNS TTL |
| RISK-014 | Large uploads / message floods | LOW | LOW | FR-017 limits; per-user post rate limit |
| RISK-015 | `claude -p` latency (2–30 s) reads as "broken" | MED | LOW | Immediate "🤖 thinking…" placeholder edited into the reply; timeout with an apology message |
| RISK-016 | `ANTHROPIC_API_KEY` present in the server's environment (no credit; shadows the login) | HIGH | HIGH | `CLAUDE_CODE_CLIENT` already clears it per child; a startup check warns if it is set |
| RISK-017 | `--bare` becoming the `-p` default in Claude Code would force API-key auth | LOW/UNKNOWN | HIGH | Pin non-bare explicitly; watch release notes; API path is the fallback |

## Technical Risks

### RISK-001: CGNAT
**Description:** If the router's WAN address is a private/shared address (100.64.0.0/10 or RFC 1918), inbound port-forwarding never reaches the PC.
**Indicators:** Router status page WAN IP ≠ public IP seen from outside.
**Mitigation:** Verify first. This is the go/no-go for the "port-forward" decision.
**Contingency:** IPv6 with a AAAA record, or a tunnel (contradicts C-004 — Larry's call).

### RISK-002: EOL OpenSSL in EWF ssl
**Description:** Public HTTPS on a library that no longer receives security fixes.
**Indicators:** `libssl-1_1-x64.dll` beside the server exe.
**Mitigation:** Caddy in front (D-004).
**Contingency:** Rebuild EWF's ssl glue against OpenSSL 3.x — effort unknown.

### RISK-003: SSE on EWF standalone
**Description:** Each SSE client holds a connection; EWF's thread handler may cap concurrent connections or time out idle sockets.
**Indicators:** Streams drop after N seconds; new requests queue while streams are open.
**Mitigation:** Spike with 20 idle streams + posts; heartbeats; tune knobs.
**Contingency:** Long-polling with 25 s waits behind the identical `since` contract.

### RISK-004: WebView2 host without Vision2
**Description:** `simple_browser` only demonstrates embedding through `EV_DRAWING_AREA`.
**Indicators:** `make_with_window (hwnd)` on a `SHELL_WINDOW` HWND fails to paint or size.
**Mitigation:** Spike in the first week.
**Contingency:** Vision2 host (`SB_WIDGET`), accepting the heavier runtime.

### RISK-010: Thread + SQLite
**Description:** Handlers on EWF threads sharing one connection.
**Mitigation:** Serialized mode + mutex; or a connection per thread if contention shows.

## Ecosystem Risks
- `simple_web`, `simple_browser`, `simple_websocket`, `simple_clipboard` last committed 2026-02-06; `simple_shell` and `simple_widgets` moved far since — expect small API mismatches when they meet.
- `simple_htmx` has no SSE helper yet; a few lines of attribute generation.
- EWF is ISE-maintained; its standalone server is the least-changed part of the stack.

## Resource Risks
- One developer (Larry) plus Claude sessions; the spec kit's phases are the schedule.
- Members' patience: the first install must work first time (NFR-010) or adoption fails (RISK-006).
