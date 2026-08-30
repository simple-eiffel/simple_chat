# SCOPE: simple_chat

Date: 2026-08-28 · Researcher: Claude (with Larry Rix) · Status: DRAFT for /eiffel.spec

## Problem Statement

In one sentence: A private friend group wants a chat of its own in which AI participants — Larry's Claude and, later, each member's own AI — can be addressed mid-conversation, and no existing chat they use permits that.

**What's wrong today:** The group lives in Facebook Messenger. Messenger has no API for personal group chats (the Messenger Platform is business-Page only — see REFERENCES), so the only way to put an AI in the room is a screen-reading robot (`D:\prod\chat_robot_spike`, proven headless 2026-08-28), which is fragile, single-machine, and grey under Facebook's terms.

**Who experiences this:** Larry (host, Windows PC, Claude Max subscription, the vault and its databases), Nick, Mike, and a handful of others — all on Windows PCs, all currently Messenger-only, non-technical as users.

**Impact of not solving:** The AI-in-the-room idea stays a one-off robot; the research-chat pattern Larry wants ("ROBOT: look this up for us") never becomes a habit for the group.

## Target Users

| User Type | Needs | Pain Level |
|-----------|-------|------------|
| Host (Larry) | Runs the server on his PC; Claude answers in-room on his subscription; images (memes, infographics) post directly; nothing leaves his machine | HIGH |
| Member (Nick, Mike, …) | Install one folder, log in once, chat with text and pictures, get notified, address the robot by name | HIGH |
| Member with own AI (later) | Attach a local Ollama / `claude -p` as *their* participant without Larry's involvement | MED |
| Bot author (Larry, later) | A stable HTTP API to read the room and post as a bot | MED |

## Success Criteria

| Level | Criterion | Measure |
|-------|-----------|---------|
| MVP | The group uses simple_chat instead of Messenger for the "robot" conversations | ≥ 3 members logged in and posting in the first week |
| MVP | Claude answers an addressed request in-room | "Claude: …" → 🤖 reply in the room, rate-limited, no operator action |
| MVP | Images post and render | A PNG from disk appears inline for every member within 2 s |
| MVP | Members are notified | A tray balloon on a new message while the client is minimized |
| MVP | Zero third-party services | Only Larry's PC, a DNS name, and a certificate authority |
| Full | Members' own AIs participate | ≥ 1 non-Larry bot user posting via the bot API |
| Full | Conversation features | Replies, reactions, @mentions, search, link previews, read markers, editing, pins |

## Scope Boundaries

### In Scope (MUST)
- Server on Larry's Windows PC, reachable from the members' PCs over the internet
- Username + password accounts; admin creates them (or invite codes) — Larry's decision
- Rooms modeled from day one; v1 shows one group room
- Text messages with emoji, Hebrew, Greek rendered correctly
- Image posts (PNG/JPEG) inline
- Full history with scroll-back
- Live updates without refresh
- Eiffel desktop client from day one (Larry's decision): WebView2 shell showing the server-rendered UI, tray icon, balloon notifications
- Claude as a server-side participant, addressed by `Claude:` / `ROBOT:`, per-user rate limit, 🤖 identity marker on every bot post
- Bot API (token) so any member's PC can run its own AI participant
- Distribution as runnable folders (Larry's standing rule), server and client

### In Scope (SHOULD)
- Unread badge on the tray icon / title
- Admin page: users, reset password, invites
- Automatic reconnect after sleep / network drop
- Message length and upload size limits

### Out of Scope
- End-to-end encryption: the server is Larry's own PC and must read messages to dispatch Claude
- Voice / video: a different product
- Federation with other servers: single private server by design
- Phones: Larry's correction — PC only
- Facebook Messenger bridge: the screen-robot spike stays a separate experiment

### Deferred to Future
- Replies / threads, reactions, @mentions, FTS5 search, link previews, typing indicators, read markers, editing/deletion, pins: after the basics are in daily use
- Per-room Claude session continuity (`last_session_id` → `--resume`): once the dispatcher is stable
- Browser-tab client (same UI, no install): trivially available once the server renders HTML; not a v1 deliverable

## Constraints

| Type | Constraint |
|------|------------|
| Platform | Windows 10/11 only, server and clients |
| Language | Eiffel; simple_* libraries first, ISE second, no Gobo unless forced |
| Reach | Port-forward from Larry's router; **no third-party tunnel** (Larry's decision) |
| TLS | Larry chose "EWF's own SSL"; research finds EWF ships OpenSSL 1.1.1 (EOL 2023-09-11) — see 04-DECISIONS D-004 |
| Identity | Username + password (Larry's decision) |
| Client | Eiffel desktop shell from day one (Larry's decision); `simple_widgets` cannot render Hebrew (bidi BLOCKED pending `simple_shaping`), so the message surface is WebView2 |
| Distribution | Runnable folder, no installer/zip; must run from a DOS prompt |
| AI | Claude via `CLAUDE_CODE_CLIENT` (`claude -p`, subscription) — the key that ships with the API path has no credit |
| Data | All data stays on Larry's PC (SQLite + image files) |

## Assumptions to Validate

| ID | Assumption | Risk if False |
|----|------------|---------------|
| A-1 | Larry's ISP assigns a public IPv4 to his router (no CGNAT) | Port-forwarding is impossible; a tunnel or IPv6 becomes mandatory, contradicting the reach decision |
| A-2 | Members' PCs are Windows 10/11 with the WebView2 Evergreen runtime present | Client fails to start; needs the ~2 MB bootstrapper step in setup |
| A-3 | EWF's standalone server holds tens of long-lived SSE connections on its thread handler without starving request handling | Live updates degrade; fall back to long-polling |
| A-4 | `simple_browser` (status "Development", last commit 2026-02-06) can host WebView2 on a `simple_shell` window HWND, not only a Vision2 drawing area | Shell must use Vision2 (`SB_WIDGET`) as `bible_htmx` does — heavier but proven |
| A-5 | SQLite in serialized mode + WAL with one guarded connection is enough for ≤ 10 users | Contention → per-thread connections |
| A-6 | `claude -p` round trips of 2–30 s are acceptable for an addressed request | Members perceive the robot as slow; add "thinking…" indicator and streaming later |
| A-7 | Members will install a folder and log in once | The Messenger robot remains the only bridge |

## Research Questions
- What do existing self-hosted chats do that we should copy for rooms, events, bots, and live sync? (→ 02)
- Can the server terminate TLS safely with what EWF ships, or does a local terminator belong on the PC? (→ 04 D-004)
- What is the cheapest correct password storage on Windows without new C dependencies? (→ 04 D-006)
- Does SSE through EWF's `WSF_RESPONSE.put_chunk` work, and does HTMX's SSE extension consume it? (→ 04 D-003, spike)
- What must ship beside the client executable for WebView2? (→ 04 D-010)
- How does a home server stay reachable when the IP changes and the PC sleeps? (→ 04 D-005, 06)
