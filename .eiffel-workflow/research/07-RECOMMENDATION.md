# RECOMMENDATION: simple_chat

Date: 2026-08-28

## Executive Summary
Build simple_chat in Eiffel as a server + desktop-client pair on Larry's Windows PC, reusing the ecosystem's server (simple_web/EWF), UI (HTMX/Alpine, the bible_htmx pattern), WebView2 host (simple_browser), platform shell (simple_shell), database (simple_sql) and Claude dispatch (CLAUDE_CODE_CLIENT). Nothing adoptable meets the stated constraints. Two of Larry's decisions need a second look before design: TLS should terminate in Caddy rather than EWF's EOL OpenSSL, and port-forwarding must be verified against CGNAT before anything else.

## Recommendation
**Action:** BUILD
**Confidence:** HIGH for the MVP; MEDIUM for the SSE-on-EWF and WebView2-on-simple_shell paths until their spikes pass.

## Rationale
- Every existing self-hosted chat either has no Windows server (Zulip, Prosody), needs containers (Rocket.Chat), or needs members to adopt a foreign client and account (Matrix/Element) — and none puts an AI in the room on the host's subscription.
- The ecosystem already contains a working Eiffel HTTP server app (`bible_htmx`, 22 routes), a WebView2 host, a Unicode-safe platform shell, SQLite, and the Claude dispatcher built this week. The new code is the chat domain, the SSE stream, the dispatcher's rules, the tray, and the shell.
- Design by Contract turns the guardrails Larry insisted on (rate limit, 🤖 marker, ordering) into enforced invariants.

## Proposed Approach

### Phase 0 — Go/no-go checks (before /eiffel.spec is acted on)
- CGNAT check (RISK-001).
- Spike A: SSE through `WSF_RESPONSE.put_chunk` with 20 idle clients (RISK-003).
- Spike B: WebView2 on a `simple_shell` HWND (RISK-004).
- Larry confirms D-004 (Caddy) and D-005 (domain vs Duck DNS).

### Phase 1 (MVP) — "the basics"
- Accounts (admin-created), login, sessions
- One room (rooms modeled), text + image posts, history paging
- SSE live updates with catch-up
- Eiffel client shell: WebView2 UI, tray icon, balloon notifications, unread badge, remembered server URL
- Claude participant with triggers, rate limit, 🤖 marker, "thinking…" placeholder
- Bot API with per-bot tokens
- Server config file; runnable folders for server and client; `start.bat` runtime check
- Assault tests for the domain and API

### Phase 2 (Full)
- Replies, reactions, @mentions, FTS5 search, link previews, typing indicators, read markers, editing/deletion, pins
- Admin page polish; per-user AI relays as a shipped program; Claude session continuity per room
- Autostart, single-instance, window position memory in the shell

## Key Features
1. **Addressable AI participant** — `Claude: …` answered in-room as a marked member, rate-limited.
2. **Bring-your-own-AI bot API** — any member's PC runs its own participant.
3. **One-folder server on a home PC** — SQLite, uploads, Caddy TLS, DNS updater.
4. **Server-rendered UI in a native shell** — Hebrew/Greek/emoji render; tray and balloons native.
5. **Contracts as guardrails** — the rules are invariants in the assault build.

## Success Criteria
- Three members posting in week one; Claude answering addressed requests unattended.
- Image posts inline within 2 s; live updates ≤ 2 s WAN; catch-up after sleep with no loss.
- No third-party service in the data path; TLS on a maintained stack.
- Assault suite green; contracts live in the shipped build's tests.

## Dependencies
| Library | Purpose | simple_* Preferred |
|---------|---------|-------------------|
| simple_web (EWF wsf, standalone httpd, thread handler) | HTTP server, routing, uploads, chunked responses | YES (wraps ISE) |
| simple_htmx, simple_alpine | Server-rendered UI | YES |
| simple_browser (webview.dll, WebView2Loader.dll) | WebView2 host in the client | YES |
| simple_shell (+ new SHELL_TRAY) | Client window, tray, balloons, clipboard | YES |
| simple_sql | SQLite storage, WAL | YES |
| simple_hash (+ new pbkdf2_sha256 over CNG) | Password storage | YES |
| simple_json, simple_uuid, simple_datetime, simple_logger, simple_config | Plumbing | YES |
| simple_ai_client (CLAUDE_CODE_CLIENT, + `--json-schema`) | Claude participant | YES |
| ISE eel | HMAC/SHA fallback | NO (only if simple_hash lacks something) |
| Caddy (external exe, in the server folder) | TLS termination, certificates | n/a |
| WebView2 Evergreen Runtime (Microsoft) | Client rendering | n/a |

## Next Steps
1. Run the Phase 0 checks (CGNAT; Spike A; Spike B) and confirm D-004/D-005 with Larry.
2. Run `/eiffel.spec D:\prod\simple_chat` to transform this research into the specification.
3. Then `/eiffel.intent`, and continue the Eiffel Spec Kit workflow.

## Open Questions
- D-004: Caddy as TLS terminator (recommended) vs EWF's ssl with EOL OpenSSL vs rebuilding against OpenSSL 3 — Larry's call.
- D-005: Does Larry own a domain, or Duck DNS?
- Accounts: admin-created only, or invite codes that let a member self-register?
- Rate-limit numbers (default 5 AI requests/user/hour; 1 concurrent).
- Upload limit (default 8 MB) and message limit (4,000 chars).
- Should the client also be usable as the per-member AI relay (a "my AI" setting), or is the relay a separate program?
- Library/application split: `simple_chat` (domain + API + server) and `simple_chat_client` as two ECF targets in one project, or two projects?
