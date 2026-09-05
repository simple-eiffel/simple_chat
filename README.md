# simple_chat

A standalone group chat for a private circle of friends on Windows PCs: an Eiffel server you host yourself, an Eiffel thick client, and addressable AI and tool participants in the room. Part of the [Simple Eiffel](https://github.com/simple-eiffel) ecosystem.

## Status

**Phase 4 — the window exists; Larry's console smoke is what remains.** The full class
design with its contracts (preconditions, postconditions, invariants, MML model queries and frame
conditions) is implemented and exercised by an assault suite, and Phase 4 implementation Tasks 1–10
are complete. The server runs — accounts, rooms, messages, images, history, SQLite persistence, SSE
streams for bots and curl, a per-IP lockout keyed by the real peer, the Caddy front door and DuckDNS
updater, and a live `@claude` participant that answers in the room through a sandboxed `claude -p` -
addressed by its handle **anywhere in a message** (`hello @Claude what is 2+2`), carrying the room's
last `context_messages` messages into every turn
(proven end to end over HTTP). The client stack has run a live round trip over WinHTTP (login, post,
**images**, events, logout) with the session remembered as a DPAPI blob and a tray notifier.

**Task 10 landed the visible client.** `SW_CHAT_VIEW` is the room pane over simple_widgets with
**shaped text on** — one `SW_SHAPING` kit per window, so Hebrew reads right-to-left inside a
left-to-right pane, Greek keeps its accents and an emoji is the same Noto picture on every member's
screen; bubble height is the layout's own `total_height`, never a line count times a constant.
`LOGIN_WINDOW` is the door (server, name, masked password, remember-me, and one line that says why
the last attempt was refused). `CLIENT_APP` assembles it: locate the server, try the session this PC
remembers (`GET /me` proves it), else the door; open the first room; run the pane whose 250 ms
heartbeat is one `CHAT_PRESENTER.pump` on the GUI processor while the poller holds the server's
doorbell open on its own. A live test drives that whole path — the real poller, the real pane —
against the booted server exe, and times every frame *and every allocation*: a 25-second poll costs
the GUI **1 ms**. It is safe to hold that exchange only because the transport says so —
`SIMPLE_WINHTTP.c_send` is marked `external "C blocking inline"` (simple_winhttp 0.1.1), which tells
the runtime the thread has left Eiffel, so ISE's collector (it stops *every* thread before it
collects) never waits on the poll. Unmarked, the same poll froze the window for 21 seconds at a time;
see `CHANGELOG.md` and `.eiffel-workflow/evidence/phase4-freeze.txt`.

**The composer wraps.** `CHAT_INPUT_BOX` was the room's one-line field; it is now multi-line and
measured-word-wrapping, growing with what is typed up to five lines and then scrolling instead of
growing the window further. Plain Enter still sends and never leaves a trailing newline; Shift+Enter
inserts one. And since Larry could type but not discover the `@claude` convention, the pane now
opens with a system bubble naming any bot in the roster by its real `@username` — never a literal
typed into this codebase — the moment the room's membership says one is there.

And it grows *when* it wraps. A row measures a wrapping child at the whole row's width while
arranging it at its share of that width, so the composer was measured 120 px wider than it was
drawn — the Send button plus one theme gap — and the second line painted below the box until
the text was long enough to wrap at the wider width too; `COMPOSER_ROW` measures the way the row
allocates. The band under the thread went the same way: an empty `SW_LABEL` still reserves a
font-derived row (47 px at 2x) and a column still charges a gap for it, which was 142 px of nothing
between the last bubble and the box. `STATUS_LINE` makes silence free and `COLLAPSING_COLUMN` stops
buying a gap for a flat child, so the thread sits one 16 px theme gap above the composer and the
line comes back the instant there is something to say. Offscreen at 2x, before and after:
`.eiffel-workflow/evidence/gap-before.png`, `gap-after.png`.

**The bubbles are lines now, and they are text.** simple_widgets 0.6.0 cuts a message into
paragraphs before either text path lays anything out, so an assistant's numbered list arrives as a
numbered list — `BUBBLE_TEXT`, the workaround that flattened every reply into one paragraph so the
newlines would not be shaped into empty boxes, named this release as its retirement condition and is
gone. The same release brings the keyboard: the menu bar owns the Alt key and draws its mnemonics
underlined, and `Ctrl+X` / `C` / `V` / `A` plus the room's own `Ctrl+M` (summarize) and `Ctrl+U`
(catch up) are window-wide accelerators. A claimed accelerator *takes* the key from the focused
widget, so every editing key ROUTES: Copy takes the composer's selection when the composer has the
caret and the bubble's when a bubble does, and the Edit menu calls the very same agents, so there is
one meaning of Copy and two ways to reach it. Offscreen at 2x:
`.eiffel-workflow/evidence/thread-lines-client-2x.png`. **And `Alt+F` opens File.** simple_shell 1.9.3
delivers Alt+letter as the ordinary key-down event and swallows the `WM_SYSCHAR` behind it, which is
the door `SW_WINDOW.activate_mnemonic` was listening at — so the pane registers four Alt accelerators
of its own, one per pad, exactly as the library's README invites a host to. If simple_widgets later
routes an unclaimed Alt+letter to `activate_mnemonic` itself, those four come back out.

**Right-click a bubble and the menu is about THAT message.** Reply, one of eight emoji,
Edit, Delete — added to the library's own Copy items rather than replacing them. The pane
draws the result of all four: an edited bubble reads the new words and says `edited` under
them, a deleted one becomes a `message deleted` tombstone **that keeps its place in the**
**order**, a reply carries a one-line quote of what it answers, and reactions sit under the
bubble as chips you can click to toggle. Nothing is ever rewritten and nothing is ever
removed: an edit, a delete and a reaction are new EVENTS naming the message they act on,
and one pass (`MESSAGE_FOLD`) folds them into what a reader should see.

The rule the menu greys by is the server's own — **the author may edit their own; the**
**author or an administrator may delete; nobody may edit anyone else's words**, an
administrator included. Removing someone's words is moderation; rewriting them under their
own name is putting words in their mouth. A greyed item is still SHOWN, because a menu that
hides what you may not do teaches nothing. Reply, Edit and Delete all aim the one composer
at one message and a strip above it says which; Escape backs out. The delete confirm is in
that strip and **not a modal** — a dialog that steals the keyboard is how a window stops
pumping, and Windows discards the keystrokes of a window that stopped pumping. Offscreen:
`.eiffel-workflow/evidence/message-fold-pane.png`.

What no headless assault can prove is that the **pixels** are right; that is `RUNBOOK.md`, and it is
the one thing still owed. Two limits are stated rather than hidden: an image event is shown as a
named, sized attachment line and not as a picture (no WIC decoder is linked into this client), and
the unread count lives in the pane's header strip and the tray tooltip rather than the native title
bar (simple_shell publishes no `SetWindowText`).

## What it will be

- **Server** (`simple_chat_server.exe`): runs as a background service on the host's PC, bound to `127.0.0.1`, reached from the internet through a swappable *front door* (Caddy today, an Eiffel TLS door later) and a dynamic-DNS name. SQLite store, append-only event log with global monotonic ids, sessions as hashed random tokens, PBKDF2 passwords (600,000 iterations, `simple_encryption` 2.0.0).
- **Client** (`simple_chat.exe`): a thick `simple_widgets` application — no browser, no WebView, no HTML anywhere. It *finds* its server: the local service first, then the configured primary, then any standby host. Live updates arrive on the server's doorbell, held open for up to 25 s so a line typed elsewhere lands on the round trip that carries it; Hebrew, Greek and emoji render natively once `simple_shaping` lands.
- **Participants**: `Claude:` / `ROBOT:` (Claude Code on the host's subscription), `@tools-larry` (Bible tools, no AI, argv-allowlisted), `@shape-larry`, `@qwen` (Ollama). Every one is an ordinary member with a 🤖 identity marker enforced as a class invariant, its own rate limit, and its own engine. Chat text never reaches a shell string.
- **Bot API**: JSON over HTTP with Bearer tokens, so a friend's PC can run its own participant.

## Design

| Piece | Where | Notes |
|---|---|---|
| Domain | `src/domain/` | `CHAT_EVENT` (marker invariant), `CHAT_USER`, `CHAT_MEMBER` (public view — never a hash), `CHAT_JSON` (one wire codec, both directions), `CHAT_RESULT [G]` |
| Store | `src/store/` | `CHAT_STORE` deferred; `MEMORY_CHAT_STORE` is the model-checked oracle; `SQLITE_CHAT_STORE` with a MUTEX |
| Service | `src/service/` | `CHAT_SERVICE` holds every rule; `RATE_LIMITER`; `PASSWORD_HASHER`; `SESSION_ISSUER`; `ADDRESS_PARSER` |
| Bus | `src/bus/` | The **doorbell**: `EVENT_BUS.ring (room)`; readers pull `events_since` from the store. `POLL_WAITER` (long-poll), `SSE_STREAM` (bots, curl) |
| Participants | `src/participants/` | `PARTICIPANT` and `SHAPER` hierarchies, `PARTICIPANT_REGISTRY`, `PARTICIPANT_DISPATCHER`, `TOOL_PARTICIPANT` |
| Web | `src/web/` | `CHAT_WEB_APP`, `CHAT_API` over `simple_web` — no EWF type appears in this project |
| Client stack | `src/client/` | UI-free and assaulted headless: `CHAT_CLIENT`, `EVENT_POLLER`, `CHAT_PRESENTER`, `SERVICE_LOCATOR`, `HTTP_TRANSPORT` (deferred; `MEMORY_HTTP_TRANSPORT` is scripted), `CHAT_VIEW` / `NOTIFIER` (deferred) |
| Front door, DNS | `src/door/`, `apps/server/ops/` | `FRONT_DOOR` deferred → `CADDY_FRONT_DOOR`, `NO_FRONT_DOOR`, `EIFFEL_FRONT_DOOR`; `DUCKDNS_UPDATER` |
| Window | `apps/client/` | `SW_CHAT_VIEW` (CHAT_VIEW over simple_widgets, shaped text), `LOGIN_WINDOW`, `CHAT_INPUT_BOX` (Enter submits), `SHELL_CLIPBOARD_IMAGE` (Ctrl+V with a picture alone on the clipboard holds it for Return; `CLIPBOARD_IMAGE_SOURCE` is the seam the assault scripts) |
| Apps | `apps/server/`, `apps/client/` | `SERVER_APP` (`--create-admin`, `--create-user`, `--reset-password`), `CLIENT_APP`, `TRAY_NOTIFIER`, `WINHTTP_TRANSPORT`, `POLLER_HOST` |

Lock order, never inverted: store < limiter < bus, and no lock is held while calling out to a subscriber.

## Install

`installer/SimpleChat-Setup.exe` (~36 MB) installs both halves. One installer, two
components:

- **The chat window** — installed always. This is the same executable for the host and
  for every friend; the only difference between them is which address it talks to.
- **The server** — a single plain-language checkbox, **unticked by default**: *"This PC
  will host the chat room (installs the server, Caddy and the hosting tools)."* Most
  installs are a friend who only wants to use the chat. Re-running the installer later
  with the box ticked adds the server to an existing install, which is how a friend is
  promoted to a standby host.

**Hosting requires an administrator install**, by design: the server writes to
`{commonappdata}`, registers a machine-wide logon task, and places `caddy.exe` where an
elevated install makes it unwritable by a standard user - which is what stops that user
tampering with the executable the elevated task launches. In a per-user install the server
component does not exist and `/COMPONENTS=client,server` yields the client alone. The
client is per-user-installable precisely because it needs none of that.

A host gets a `SimpleChat Server` Start Menu folder — start, stop, create the first
admin, create a user, reset a password, the log, the config, back up the room, restore a
backup — and a
**hosting guide** written for a non-programmer: the two lines in `server.toml` that turn
hosting on, a free DuckDNS name, router port forwarding, how to tell whether your
provider's CGNAT makes that impossible, backups, and the cold-standby procedure.

Accounts are minted by the host (`--create-admin` once, then `--create-user` per person);
there is no self-registration. Both prompt for a display name and read the console as
UTF-8, so a Hebrew or Greek name survives. **Passwords show one dot per key and never the characters** — all three account
flags read them with `SIMPLE_CONSOLE.read_masked_line_default`, which masks every key on a real
console and reads the ordinary way when standard input is redirected from a file or a
pipe, so the shipped scripts keep working; end of input before a password changes
nothing and leaves with exit status 1. A forgotten password is not the end of the
room: `--reset-password <username>` gives an existing member a new one and signs out
every session they hold.

**Signing in when nothing answers.** A sign-in that never reaches a server does not show
you the transport's complaint; it shows you what to do. If the address is this PC's own
loopback, the window says no chat server is running here and names the Start Menu entry
that starts one — *SimpleChat Server > Start server*. If it is a friend's address, it names
the address it could not reach and points at `%APPDATA%\simple_chat\client.toml`, where
that address is kept. A wrong password is a different thing entirely and still comes back
in the server's own words.

**Uninstalling never deletes the room.** The data folder, `server.toml`, the backups and
each member's `client.toml` all survive, so reinstalling picks up where it left off.

To rebuild the installer, see `installer/README.md`. Two rules that bite: drive Inno
Setup from **PowerShell, never Git Bash** (MSYS silently rewrites `/VERYSILENT` into a
path), and compile test installs with `ISCC /DVERIFY=1` so they share no AppId, install
directory or scheduled-task name with the real product.

## Build and test

```bash
cd /d/prod/simple_chat
/d/prod/ec.sh test -config simple_chat.ecf -target simple_chat_tests
cp $SIMPLE_EIFFEL/simple_cairo/cairo.dll EIFGENs/simple_chat_tests/F_code/
./EIFGENs/simple_chat_tests/F_code/simple_chat.exe
```

`cairo.dll` has to be beside the test runner since Task 10: the suite builds real
`SW_CHAT_VIEW` and `LOGIN_WINDOW` objects offscreen, and simple_cairo links an **import**
library — a missing DLL is a launch failure, not a degraded run. Every finalize wipes
`F_code`, so copy it back after each build.

The client's own runnable folder is built by `apps/client/stage_client.sh`, which stages
`SimpleChat.exe` (the client target renamed, because every target here finalizes to
`simple_chat.exe`), `cairo.dll`, `LICENSE-ASSETS.md`, `assets/noto-emoji/png/128/` and a
`client.toml` template into `dist/simple_chat_client/`. It is a folder you `cd` into and run,
never a zip.

Targets: `simple_chat` (library), `simple_chat_server`, `simple_chat_client`, `simple_chat_tests`,
`simple_chat_doorbell_tests`.

`RUNBOOK.md` is the console smoke: start the server, start the client, log in, post, make
`@claude` answer, post `שלום 🤖 Χριστός` and check the Hebrew is rightmost, resize, close and
reopen on the remembered session.

## Dependencies

`base` (the only ISE library — `MUTEX` and `CONDITION_VARIABLE` live in EiffelBase) plus simple_mml, simple_json (≥ 0.2.0 — earlier versions lose emoji), simple_datetime, simple_logger, simple_encryption (≥ 2.0.0), simple_uuid, simple_sql, simple_process, simple_base64, simple_encoding, simple_web, simple_ai_client; the client adds simple_shell and simple_widgets.

Landed, and all of them on the critical path: `simple_shaping` (Hebrew/RTL/emoji, reached through
simple_widgets' `SW_SHAPING`), `simple_winhttp`, `SHELL_TRAY`, DPAPI token storage in
simple_encryption. Still deferred by choice: a **WIC image decoder** — until one exists an image
event is a named, sized attachment line rather than a picture.

## Design record

`.eiffel-workflow/research/` (scope, landscape, requirements, decisions D-001–D-020, innovations, risks, recommendation), `.eiffel-workflow/spec/` (01–08 plus addenda 09 *participants* and 10 *thick client*), `intent.md` → `intent-v3.md`, and `evidence/` for every phase gate.

## Never

End-to-end encryption, voice or video, federation, phones, a Messenger bridge.

## License

MIT
