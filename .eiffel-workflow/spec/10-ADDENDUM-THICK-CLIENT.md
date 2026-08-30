# ADDENDUM: The thick client — simple_widgets, no browser

Date: 2026-08-29 (Larry's decision after Phase 1m). Supersedes the client half of D-008 and every browser-dependent item in 04–07 and intent-v2 (Q4 cookies, Q6 CSP/escaping, Q13's `VISION2_WEBVIEW_HOST`). The server, the store, the bus, the participants and the JSON API carry over unchanged; what changes is *who renders* and *how live updates reach a client*.

## The decision, in Larry's words
"Thick first and no browser. I don't want a browser." Hebrew, Greek and emoji "don't render in simple_widgets **yet**" — the operative word is *yet*: `simple_shaping` moves to the front of the queue. Images need a decoder — "if it's another library, then it's another library." The host runs the server as a service on his PC and the GUI *goes looking for it*; on other members' machines the GUI either connects straight to the host or to a local service of its own, which opens the door to someone else hosting if the primary fails.

## What is removed
| Gone | Why |
|---|---|
| `CHAT_UI` (server-rendered HTML, HTMX fragments, the single escaping point) | no browser renders anything |
| `CLIENT_HOST`, `SHELL_WEBVIEW_HOST`, `VISION2_WEBVIEW_HOST`, `NOTIFICATION_BRIDGE` (JS→Eiffel) | no WebView2 |
| `simple_browser`, `simple_htmx`, Alpine, the WebView2 Runtime check in `start.bat` | not linked, not shipped |
| Session cookies, `HX-Request` CSRF guard, `SERVER_CONFIG.cookie_secure`, CSP header, `<script>` XSS acceptance test | every session is a Bearer token; there is no script engine anywhere to inject into |
| Spike B (WebView2 on a simple_shell HWND) | replaced by the simple_shaping work |

Two acceptance criteria are struck (CSP/XSS; browser-tab rendering) and two are added (below).

## What is added

### Client architecture (library cluster `src/client/`, UI-free, assaulted headless)
```
CLIENT_CONFIG        what the client remembers: server URL, local port, prefers_local, window placement
CHAT_ENDPOINT        a base URL + is_local; url_for (path)
SERVICE_LOCATOR      locate (config, transport): the live local service if preferred and answering /health, else the configured URL
HTTP_TRANSPORT       deferred: send (method, url, headers, body, timeout) : HTTP_REPLY   — the only place bytes leave the client
  MEMORY_HTTP_TRANSPORT   scripted replies + recorded requests (the test double; requests_model)
  WINHTTP_TRANSPORT       apps/client, over simple_winhttp (promoted from OCR_HTTP) — Phase 4
HTTP_REPLY           status, body, transport error
CHAT_MEMBER          the public view of a user (id, username, display name, flags) — the client never holds a password hash
CHAT_JSON            the wire codec, both directions: events, members, login reply, error reply
CHAT_CLIENT          login / logout / events_since / wait_for_events / post_message / post_image / rooms / members;
                     the token lives in memory only and travels only as `Authorization: Bearer`
EVENT_POLLER         the long-poll machine: poll_once advances `cursor`, queues into `pending`; drain hands them over
CHAT_VIEW            deferred: show_event / show_status / show_error / show_connection / is_foreground
  MEMORY_CHAT_VIEW        records what it was told (tests)
  SW_CHAT_VIEW            apps/client, simple_widgets — Phase 4, after simple_shaping
NOTIFIER             deferred: notify / badge / clear / unread
  MEMORY_NOTIFIER         tests
  TRAY_NOTIFIER           apps/client, over SHELL_TRAY — Phase 4
CHAT_PRESENTER       the logic between client, poller, view and notifier: pump, send, unread law
```
`CLIENT_APP` (apps/client) assembles them: locate → login → open room → run the simple_widgets window whose timer calls `presenter.pump`.

**Threading.** The long-poll blocks up to `seconds`; it must not run on the GUI thread. `EVENT_POLLER.poll_once` is the unit of work; Phase 4 drives it from a worker (EiffelBase `THREAD` or a SCOOP processor — decided in Phase 4 by whichever coexists cleanly with the simple_widgets pump) and the GUI thread only ever calls `drain` under the poller's MUTEX.

### Server additions
- `GET /rooms/{id}/wait?since=N&limit=M&seconds=S` — **long-poll**: returns immediately with events after N if any; otherwise waits on the doorbell up to S seconds (≤ 25) and returns what arrived, or an empty list. Ephemeral statuses that arrived during the wait ride along in `statuses`.
- `POLL_WAITER` (bus subscriber): `arm (room)` → caller checks the store → `wait (ms)`; a wake that lands between the check and the wait is retained, so the check-then-wait race is closed. Implemented in full now (MUTEX + `CONDITION_VARIABLE.wait_with_timeout`, both in EiffelBase).
- `CHAT_SERVICE.wait_for_events (room, since, limit, seconds)`.
- `SSE_STREAM` stays for bots and `curl`; it is no longer the client's path.
- `SERVER_CONFIG.is_public` replaces `cookie_secure`.

### Discovery and topology
```
Larry's PC   simple_chat_server (PRIMARY: owns the log, public via Caddy + DuckDNS)   <-- GUI on 127.0.0.1
Nick's PC    GUI --> https://rixchat.duckdns.org                                     (direct; day one)
Sue's PC     simple_chat_server --replica (outbound-only; local SQLite copy)          <-- GUI on 127.0.0.1
```
- **Direct** and **via local service** are the same client code: `SERVICE_LOCATOR` prefers `http://127.0.0.1:<local_port>` when `prefers_local` and `/health` answers, else the configured URL.
- **Replica mode (deferred, designed for):** a server started with `--replica <primary-url> <bot-token>` pulls `events_since` and the attachments it references (content-addressed by sha256) and serves them read-through locally; posts are forwarded to the primary. One writer at a time; ids continue from the replica's last id on promotion.
- **Promotion is manual in v1.x** ("Sue is host now"); automatic election is where split-brain lives. Schema v2 reserves an `epoch` column so a promoted host's ids are distinguishable.
- **Reachability is the hard bound:** a member can host only with a forwarded port and a public name. The roster (`/members`) will carry `host_endpoint` for host-capable members; the software cannot conjure inbound reachability.

## Dependencies now on the critical path (in order)
1. **`simple_shaping`** — D-014; own /eiffel.research. Backends: DirectWrite first (`IDWriteTextAnalyzer` bidi + script + glyphs, `IDWriteFontFallback::MapCharacters`), glyph bridge into cairo via `cairo_win32_font_face_create_for_logfontw` + `cairo_show_glyphs` (glyph ids are font-intrinsic, so DirectWrite's indices draw correctly through GDI faces). Pure-Eiffel bidi (UAX #9, verifiable against `BidiTest.txt`) is the first swap.
2. **Emoji** — proposal D-019: render emoji as inline images from an open set (Noto Emoji PNG, Apache 2.0 / Twemoji, CC-BY 4.0) keyed by code-point sequence, not as color-font glyphs. Deterministic, identical for every member, no COLR support needed from cairo 1.17.2. Decided at the shaping research.
3. **Image decode** — WIC (`IWICImagingFactory`) → ARGB32 → `CAIRO_SURFACE`; PNG, JPEG, GIF, BMP, WebP. Lives where S05 §7 planned it: a codec in simple_shell, or `simple_wic` if it grows. Re-encoding uploads to PNG on the server (intent-v2 Q5(c)) becomes possible with the same code.
4. **`simple_winhttp`** — promote `OCR_HTTP`: add HTTPS (`WINHTTP_FLAG_SECURE`), request headers, receive timeout ≥ long-poll seconds, raw-bytes POST for uploads.
5. **`SHELL_TRAY`** — as before.
6. simple_widgets: `SW_CHAT_THREAD` already exists (bubbles by role, sticky bottom, `append_to_last` for streaming); needs rich runs (sender line, images inline, the 🤖 badge), `SW_TEXT_BOX` needs bidi caret/hit-testing from simple_shaping, and an emoji picker over the image set.

## Contracts added in this amendment (Phase 1 style; the small ones implemented)
- `POLL_WAITER`: `wait` returns True ⇒ a wake for the armed room arrived since `arm`; other rooms never wake it.
- `CHAT_JSON`: `event_from_json (event_to_json (e))` preserves id, room, sender, kind, body, bot flag, attachment id.
- `CHAT_CLIENT`: `token_never_in_url`; `bearer_when_logged_in`; `logged_in = (token.count = 64)`.
- `EVENT_POLLER`: `cursor` never decreases; `drain` empties `pending`; pending ids strictly increasing and all > old cursor.
- `CHAT_PRESENTER`: after `pump`, `unread = 0` when the view is foreground; `last_seen_id` never decreases; every drained event was shown exactly once.
- `SERVICE_LOCATOR`: result is local ⇒ health answered; not local ⇒ result is the configured URL.

## Acceptance criteria (replacing the two struck)
- The simple_widgets client shows `שלום 🤖 Χριστός` with Hebrew right-to-left, the marker as the same picture on every member's screen, and Greek intact — natively, no browser process anywhere on the machine.
- A message posted by another member appears in the client within 2 s over the WAN through long-poll alone, with SSE disabled.
