# Changelog

All notable changes to simple_chat are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] — 2026-09-05

The paste release: a picture on the clipboard goes into the room with Ctrl+V and Return.

### Added

- **Ctrl+V with a picture on the clipboard posts it.** The first half of FR-005
  that a member could actually use: the server has taken PNG/JPEG uploads by
  signature since Phase 4, `CHAT_CLIENT.post_image` has put them on the wire
  since Task 9b, and until today nothing in the window called it. Now a
  screenshot, a snip or a browser's "Copy image", pasted into the composer, is
  **held**: the line above the composer says *Pasted picture, 640 x 480
  (123 KB) - Return sends it, with whatever is typed as its caption; Escape
  discards it.* Return posts the PNG bytes as `pasted-YYYYMMDD-HHMMSS.png` with
  the composer's text - empty or not - as the caption; Escape throws it away. A
  held picture is a composer mode like a reply or an edit: taking one ends
  either of those, and beginning either ends it (`CLIENT_APP.take_pasted_image`,
  `cancel_compose`).

  **Text wins.** A word copied out of a document often travels with a rendering
  of itself, and a member who pastes a word means the word; a screenshot travels
  alone. So the picture is taken only when nothing else is on the clipboard, and
  Ctrl+V with text pastes text exactly as it always did
  (`SW_CHAT_VIEW.route_paste`; the reasoning is in `CLIPBOARD_IMAGE_SOURCE`'s
  class note).

  A refusal (413, say) puts the server's reason on the error line and gives the
  caption back to the composer; the picture is not kept - a paste is cheap to do
  again, a stale one is a surprise. A picture that cannot be read says so on the
  status line rather than silently pasting nothing.

- `CLIPBOARD_IMAGE_SOURCE` (deferred: `has_image`, `has_text`, `width`, `height`,
  `png_bytes`, never raises), `SHELL_CLIPBOARD_IMAGE` over simple_shell 1.10.0's
  new `SHELL_CLIPBOARD.image_into` and simple_cairo's PNG writer (a relative,
  ASCII scratch name in the working directory CLIENT_APP already moved to
  `%APPDATA%\simple_chat` - cairo's writer takes a one-byte-per-character path,
  and a member's profile folder need not be spellable that way), and
  `MEMORY_CLIPBOARD_IMAGE` for the assault, so no test writes to the clipboard
  Larry is using while the suite runs - except the one that proves the shipped
  path end to end, which puts back the text it found.

- simple_shell 1.10.0: `SHELL_CLIPBOARD.image_into` - the library could put a
  bitmap and read its size back, but no caller could get at the pixels. simple_cairo
  is now named explicitly on the client and tests targets.

### Added (tests)

- Six assaults in `WINDOW_ASSAULT`, driving `CLIENT_APP` over the REAL window
  offscreen: the held picture, the strip's wording, nothing on the wire until
  Return, then `POST /rooms/4/images` with the PNG bytes as the body first to last,
  a dated `pasted-*.png` name and the caption percent-encoded on `X-Caption`; text
  beside a picture pastes text and never even reads the picture; Escape discards
  and a bare Return then sends nothing; a 413 puts the reason on the error line
  and the caption back in the composer; an unreadable picture is said, not
  swallowed; and the REAL clipboard - a 4x3 bitmap put through simple_shell -
  comes back through `SHELL_CLIPBOARD_IMAGE` as PNG bytes whose IHDR says 4 x 3,
  scratch file gone. Suite: **272 passed, 0 failed, zero SKIP**.

### Changed

- `CLIENT_APP.cancel_compose` gains one postcondition, `no_picture` - the one
  existing clause strengthened on this branch; everything else is on new features.
- `CHAT_VERSION`: 0.3.0, against simple_shell 1.10.0 and simple_web 0.4.0.

### Known

- The receiving side still draws an image event as a `[image] name (size)` line:
  the inline decoder is the next item, not this one.

## [0.2.4] — 2026-09-05

The listener release: the server is bound to 127.0.0.1 at the socket, not merely in a configuration class.

### Fixed

- **The server listened on every interface. It had said 127.0.0.1 since the day
  it was written.** `SERVER_CONFIG` pins `bind_address` to `127.0.0.1`, refuses
  the key in `server.toml` (*"not configurable; the server always binds
  127.0.0.1"*) and asserts it in two invariants; the server's boot line prints
  `serving on http://127.0.0.1:<port>/`; the README, the hosting guide and the
  `server.toml` template all say the same. And on 2026-09-05 the live room was
  observed at `0.0.0.0:8090` — every interface on the host's PC, reachable by
  anything on the LAN that could type the address.

  The value never reached a socket. `CHAT_WEB_APP.start` built the simple_web
  server with `make (port)` and nothing else, because until simple_web 0.4.0
  there was nothing else to call: EWF's standalone launcher was handed no
  address, and `HTTPD_SERVER_I.new_listening_socket` took its
  `make_server_by_port` branch. A contract on a configuration value is not
  enforcement at the socket, and every one of those documents was describing an
  intent.

  `start` now calls `set_bind_address (config.bind_address)` on the server it
  builds (simple_web 0.4.0, which sets EWF's `server_name` so the connector
  takes `make_server_by_address_and_port`). The socket itself is bound to
  `127.0.0.1`; the front door (Caddy) remains the only way in from anywhere
  else, exactly as the hosting guide has always described it.

  **If anyone was reaching a room directly on its port from another machine,
  that stops working with this release.** It only ever worked by accident; a
  host who wants the room reachable from outside turns the front door on
  (`front_door = "caddy"`, hosting guide §3) — the design, now enforced.

### Added (tests)

- `BIND_ASSAULT.test_the_server_listens_on_loopback_and_not_on_every_interface`
  refuses to read a value. It boots the real finalized server executable on a
  scratch port (18214, as `sc_bind_server.exe`, stdout to a file) and asks
  **Windows** what the socket is bound to: `Get-NetTCPConnection -State Listen`
  must report `127.0.0.1` and must NOT report `0.0.0.0` — both asserted, since
  one is not the negation of the other — and a real HTTP request to this
  machine's own LAN address on that port must be refused. A machine with no
  non-loopback IPv4 address FAILS the assault rather than quietly proving half
  of it. Verified: `LocalAddress 127.0.0.1`; `GET http://192.168.1.145:18214/health`
  -> `cannot connect (Win32 12029)`. Suite: **266 passed, 0 failed, zero SKIP**.

### Changed

- `CHAT_VERSION`: 0.2.4, built 2026-09-05, against simple_web 0.4.0.

## [0.2.3] — 2026-09-04

The uninstaller release: every stop is scoped to its own install folder, a silent upgrade restarts the server it stopped, the Room menu answers to Alt+M, and a summary is a private ask that never touches the room's engine session.

### Fixed

- **Uninstalling ANY install of SimpleChat stopped EVERY SimpleChat server on
  the PC.** `[UninstallRun]` said
  `Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM SimpleChatServer.exe"`.
  It matched an image name and carried no component condition, so a client-only
  install's uninstall — which has no server of its own at all — and a
  verification build's uninstall both reached across every install on the
  machine. On 2026-09-04 that took Larry's live room down twice in one
  afternoon, with a conversation in it.

  **The verify identity could not have caught this.** The `/DVERIFY` block
  switches every symbol two installs can collide over — AppId, AppName,
  DirName, ServerRoot, TaskName, ClientCfgDir, OutBase — and `ServerExe` is not
  among them and cannot be: it is the same compiled binary in both builds, and
  that rename is what keeps the client, the server and the test runner (all
  three finalize to `simple_chat.exe`) from being three files with one name.
  The image name is the one property of this product that the verify identity
  must not switch, and it was the one property the uninstaller keyed on.

  The stop now matches the full executable path `{app}\SimpleChatServer.exe`,
  in PowerShell — `taskkill` filters on an image name and cannot filter on a
  path — and carries `Components: server` as a second lock. The component
  condition is **not** the fix: it would have skipped the client-only case by
  accident, and a verify build *with* the server component would still have
  killed the live room. `{app}` is per-install always.

  `templates/stop_server.cmd` gets the same scoping, for the server and for
  Caddy — its own comment had promised it since the day it was written
  (*"only the copy that lives in our own folder"*) while the code below said
  `/IM caddy.exe`. `templates/start_server.cmd`'s "is it already running?"
  test is scoped too: by image name it answered about *any* install's server,
  so a verification build could not be started at all while the real room was
  up.

- **A silent upgrade over a running server left the room dark.**
  `CloseApplications` was unset, so Restart Manager was free to close the
  running server to replace its file, and every `[Run]` entry carried
  `skipifsilent` — so nothing started it again and nothing said so. The host
  found out from his friends.

  `StopServerFromAppDir` now runs at `ssInstall`, before a file is copied: it
  finds a server running from this install's own folder by path, records
  `ServerWasRunning` **first** and stops it second, so an upgrade knows the
  room was up even when the stop fails and Restart Manager closes the process
  instead. A `[Run]` entry with `Check: ServerNeedsSilentRestart` then
  relaunches it through `start_server_hidden.vbs`, hidden, as the original
  user.

  It restarts **only** a server the installer itself stopped: a first install,
  or an upgrade over a room the host had deliberately stopped, starts nothing.
  It is `postinstall` because plain `[Run]` entries execute before
  `ssPostInstall`, which is where `server_root.cmd` is written — started any
  earlier, `run_server.cmd` falls back to `%ProgramData%\SimpleChat` and a
  verification build would restart a server against the real room. And it is
  silent-only, because on the interactive path the host has a visible, ticked
  "Start the server now" and two automatic starters would race: `wscript`
  returns the moment it has spawned `cmd`, long before `SimpleChatServer.exe`
  exists. The finish briefing now tells an interactive host that the installer
  stopped a running server, so he knows what unticking that step costs.

  `CloseApplications=yes` is now stated rather than defaulted, with the reason:
  it stays on for the chat *window*, and the server is deliberately not left to
  it.
- **`Alt+R` never opened the Room menu, and never could.** Larry, in the room
  itself: he found a HUD on his screen reading `FPS N/A | GPU 24% | CPU 2% |
  LAT N/A` and recognised it - the NVIDIA overlay registers `Alt+R` as a
  **global** hotkey, and a global hook is consulted before any window's own
  accelerator table. The keystroke never reached this application at all.

  **simple_widgets was measured and cleared before a line was changed here.**
  Headless, at 2x, with this client's exact four pads and its real Room menu:
  `menu_for_mnemonic('r')` finds pad 3, `activate_mnemonic` returns True, and
  the popup opens with both items - identical to `f`, `e` and `h`. There are
  also two independent paths into it (the accelerator, then
  `key_down_mnemonic_fired` as a fallback), and both work. Two working paths
  failing together is what says the key never arrived.

  The mnemonic moves to the **m**: `Text_menu_room` is `"Roo&m"`, and the Alt
  accelerator is registered on `Vk_m` instead of `Vk_r`. **The label is
  unchanged** - it still reads "Room" - because underlining a non-initial
  letter is ordinary Windows practice, the same shape as `E&xit`. Renaming the
  pad to "Options" to buy a free initial letter was the alternative and was
  declined: it would have cost the reader a word he already knows.

  `Ctrl+M` (Summarize) is untouched and does not collide - the accelerator
  table matches the modifier state exactly, so `Alt+M` and `Ctrl+M` are two
  different keys.

  The assault now asserts the negative as well as the positive: `Alt+M` opens
  Room, and **`Alt+R` is claimed by nothing**. A pad that answered to `Alt+R`
  would draw an underline promising a gesture the application can never
  receive, which is the defect this release exists for.

## [0.2.2] — 2026-09-04

The addressing release: the per-message menu acts on the message under the pointer in every room shape - a hint bubble had put every action one message out of step, so that an emoji on the newest message did nothing and a Delete could have tombstoned its neighbour - and every refusal from the menu now states its reason. Rebuilt against simple_widgets 0.7.2.

### Fixed

- **Choosing an emoji from a message's menu did nothing — no chip, no error.**
  Larry, on the installed 0.2.1. The cause was not the menu and not the widget:
  simple_widgets was cleared by measurement, every painted row being the row a
  click finds. It was this client's own bookkeeping.

  `SW_CHAT_VIEW` kept `shown_ids`, one entry per event it had drawn. But
  `show_hint` draws a bubble and — by its own comment — **never adds to
  `shown_ids`**. The per-message menu asks `message_at` for a **thread** index
  and hands it to `event_of_bubble`, which reads `shown_ids`. From the first
  hint onwards the two lists disagree by one.

  **A room with a bot in the roster gets a hint bubble at the top**, which is
  the room Larry has. So every menu action was off by one, and on the newest
  message the index ran past the end of `shown_ids`, which answered 0 — and
  every gate in `react_to` refused in silence. Worse than nothing happening:
  an action that *did* get through landed on the neighbouring message, so an
  administrator's Delete could tombstone the bubble **above** the one he
  right-clicked. The same mapping serves Reply, Edit, Delete, the chips, the
  tombstones and the greying, so all of them were misaddressed together.

  The fix is a `bubble_ids` list kept in step with the **thread** — one entry
  per bubble, 0 for a hint — and two invariants that forbid the drift ever
  returning: `one_entry_per_bubble` and `every_shown_id_has_a_bubble`.
  `shown_ids` and `shown_model` are untouched, so nothing that counts *events*
  changed meaning.

  Why the stage-3 assaults missed it: **they built a roster with no bot**,
  purely to keep the indices simple. That one convenience is what hid the
  defect. The four new assaults use the room Larry actually has.

- **No gate refuses in silence any more.** Larry's entire report was "nothing
  happens", which a member cannot tell from a dead menu item — and that
  ambiguity is what cost a release. Every gate in the per-message path now says
  its reason on the status line: that bubble is a notice and not a message,
  that message was withdrawn, only the author may edit, only the author or an
  administrator may delete, no emoji was chosen, not signed in to a room. None
  of them is an *error* — the member did nothing wrong — so none goes to
  `show_error`.

## [0.2.1] — 2026-09-04

The emoji release: the right-click menu's emoji are pictures, not boxes - rebuilt against simple_widgets 0.7.2; the greying rule is proven by a painted menu in the test suite.

### Changed

- **The per-message menu is now proven by a picture, not just an assertion.**
  0.2.0 shipped with a gap named in its own notes: `SW_WINDOW.show_popup` was
  private and only the window's own right-click dispatch called it, so the
  assault could build the menu and read every item off it but could never make
  the window PAINT one. The frame written at the time showed the pane with no
  menu on it, and was deleted rather than shipped under a name that claimed
  otherwise.

  simple_widgets 0.7.1 closes it with `simulate_context_click`, so `menu_on`
  now opens the menu **by a real right-click** — event 11 through the shipped
  dispatch — and reads it back off the window as `open_popup`. Everything
  between the click and the painted menu is under test rather than assumed:
  that `target_at` finds the widget, that `bubble_context` walks to the first
  ancestor offering a menu, that the thread takes the focus a right-click gives
  it, that the menu is placed. All four greying assaults — author, other
  member, plain member, tombstone — ride the new door, and Escape closes what
  the pointer opened.

  Evidence: `evidence/message-menu-greying-2x.png` — an open context menu,
  painted at the room's own 2x, with **Edit drawn dim** on somebody else's
  message and **Delete drawn live** because this reader is an administrator.
  `SW_MENU` renders a disabled item in `ink_muted` rather than `ink`, which is
  the greying rule made visible.

### Fixed

- **The eight emoji in the right-click menu draw as emoji, not boxes** -
  rebuilt against simple_widgets 0.7.2, in which a menu's labels take the
  shaping kit whenever the painter has one, so an emoji label is a picture
  and a Hebrew title keeps its mnemonic underline under the right glyph.
  0.2.0 shipped with the boxes; the painted-menu test caught it minutes
  after it existed.

### Known

- **The menu's eight emoji draw as empty boxes — found by looking at the frame,
  which is the entire reason for demanding one.** No assertion could see this:
  every one of the eight items is present, enabled, and carries the right
  emoji string, so the greying assaults pass exactly as they should. The
  picture shows eight identical squares labelled `react`.

  It is **not** the known "artwork lives beside the running binary" deployment
  fact. Staging `assets
oto-emoji` beside the test executable changed nothing,
  which is what ruled that out. The cause is one layer down: `SW_MENU.draw`
  paints its labels with the painter's plain `text`, while `SW_CHAT_THREAD`
  uses `draw_shaped_layout` whenever `SW_PAINTER.has_shaping` — and the
  shaping kit is what resolves colour-emoji artwork. **A menu never asks the
  shaping kit**, so it cannot draw an emoji, in this harness or in the shipped
  client.

  That makes the emoji picker in the per-message menu unusable as it stands,
  and it is a simple_widgets change to fix (a shaped path in `SW_MENU.draw`),
  so it is written down here rather than slipped into this branch. Everything
  else about the menu — the items, the greying, the actions, the chips already
  drawn under a bubble by the thread — is unaffected.

## [0.2.0] — 2026-09-04

The message release: right-click any message to reply, react with an emoji, edit your own, or delete your own - an admin may delete anyone's but never edit another's words. Edits show as edits, a deleted message becomes a visible 'message deleted' in its place, replies quote their parent, reactions are chips you can click. Underneath: three new event kinds folded over the room's append-only log, and a thread that can change a bubble it has drawn (simple_widgets 0.7.0).

### Added

- **Edit, delete, reply and react — the server half.** Four things you can do to a
  message that already exists, built the way everything else in this room is built:
  as EVENTS. Nothing is ever rewritten and nothing is ever removed. An edit, a
  delete and a reaction are new events that NAME the message they act on, and one
  pass folds them into what a reader should see.

  `MESSAGE_FOLD` is that pass, and it holds the rules that are easy to get subtly
  wrong, written down in one place:

  - **Order is the arbiter.** Events fold oldest first, so the last edit wins.
  - **A delete is final.** An edit arriving after a tombstone changes nothing a
    reader sees. An author who withdrew their words does not get them resurrected
    by a stray event.
  - **Reactions dedupe per person per emoji**, last word wins — so the same person
    clicking twice ends with it off, and two people are two.
  - **A fold event never draws.** `standalone` is what a client turns into bubbles.
  - **Anything malformed is dropped in silence** — a bad payload, a target outside
    the page. A room must render whatever the log holds, never raise on it.

  A **reply is not a kind of its own**: it is an ordinary message carrying a parent
  id, so every rule a message already obeys it obeys too, and nothing folds it away.

- **The permission rule, as Larry set it.** The author may edit their own; the
  author **or an administrator** may delete. **Nobody may edit anyone else's words,
  an administrator included** — removing someone's words is moderation, but
  rewriting them under their own name is putting words in their mouth, and no role
  here carries that.

- **Four endpoints** — `POST /rooms/{id}/messages/{eid}/edit`, `/delete`,
  `/reactions`, `/replies` — and **five assaults**, 239 → **244**, zero skips.

- **The per-message menu, and the room can see it — the client half.** Right-click a
  bubble and the menu names what you may do to *that* message: **Reply**, one of
  eight emoji, **Edit**, **Delete**. The pane draws the result of all four —
  an edited bubble reads the new words and says `edited` under them, a deleted one
  becomes a `message deleted` tombstone **that keeps its place in the order**, a
  reply carries a one-line quote of what it answers, and reactions sit under the
  bubble as chips carrying the tally.

  **A greyed item is still shown.** A menu that hides what you may not do teaches
  nothing; a member who wonders why Edit is grey on somebody else's message has
  just learned the rule. The rule is asked fresh every time the menu opens, so an
  item greys the instant state turns against it — and the rule asked is the
  server's own, never a second copy that could drift from it.

- **A click on a chip toggles that one emoji** — no menu, one click, and which way
  it goes is decided by the row that is **drawn**, so the pane and the wire cannot
  disagree about what the click meant.

- **The compose strip says what Return will do.** Reply, Edit and Delete all aim
  the one composer at one message, and the line above it says which: who is being
  answered, that an edit is in progress, or that a delete wants confirming.
  Escape backs out of any of them. Edit loads the words that are **on screen**, so
  they are changed rather than retyped, and after either an edit or a reply the
  composer goes back to meaning an ordinary message — a composer that stayed aimed
  would silently rewrite the next thing typed into it.

- **The delete confirm is in the pane, not a modal.** The first Delete says what
  will happen; the second does it. A dialog that steals the keyboard to ask "are
  you sure" is how a window stops pumping, and Windows discards the keystrokes of
  a window that stopped pumping. This room has been bitten by that before.

- **Fourteen assaults**, 244 → **258**, zero skips. Seven drive the fold through
  the presenter; seven drive the real pane through `CLIENT_APP` — signed in as an
  administrator and again as a plain member, the menu asked for at a point the
  pane's own hit-testing says is on the bubble, and every action reached **by
  invoking the menu item**, so none of them would still pass the day the menu
  stopped calling what it says it calls. Offscreen frame:
  `evidence/message-fold-pane.png`.

### Fixed

- **Taking back your only reaction left the chip on screen.** The client applied a
  reaction row only when it had something in it, so the one moment an empty row
  matters — the moment it *became* empty — was the one moment it was skipped, and
  the chip stayed until some unrelated event happened to redraw the bubble. A row
  is replaced wholesale, empty included.

- **`CHAT_EVENT` carried a second copy of the list of valid event kinds.** The
  moment three kinds were added to the shared `CHAT_EVENT_KINDS`, the two
  disagreed: the shared list accepted them, the private copy refused, and every
  event of a new kind died on `CHAT_EVENT`'s own precondition — three assaults red
  on exactly that. The duplicate is gone rather than extended: `is_known_kind` now
  delegates, so there is ONE definition. A list written twice is a list that will
  drift, and this one already had.

## [0.1.5] — 2026-09-04

The keyboard release: an open menu answers the arrow keys, Home, End, Enter and Escape, and Left and Right walk the menu bar. Rebuilt against simple_widgets 0.6.2; no chat source changed.

### Changed

- **An open menu answers the keyboard** - rebuilt against simple_widgets
  0.6.2. Down and Up walk the items and step over separators and greyed
  entries, Home and End jump, Enter runs the highlighted item, Escape closes,
  Left and Right move to the neighbouring menu and open it, wrapping at both
  ends - whether the menu was opened by Alt+letter or by the mouse. Larry, in
  the room on 2026-09-04: the menus opened and then ignored the arrow keys;
  the library's popup dispatch had no branch for virtual-key events at all.
  No chat source changed for this; the window's version text names the
  library.

## [0.1.4] — 2026-09-03

The window release: a menu bar with File, Edit, Room and Help - About names the version and the fleet it was built against; summary on demand and catch-up on return, each an answer to the person who asked and never a room event; real line breaks in the pane, a numbered list drawn as a list; selection and Copy from the thread; Ctrl and Alt keys that reach the menu; the assistant told it has no tools, and tool-call markup refused; the room's members addressed by handle. Built against simple_widgets 0.6.1, simple_shell 1.9.3, simple_console 1.2.0 and the UTF-8 simple_ai_client.

### Added

- **A menu bar** — File (Close), Edit (Cut/Copy/Paste/Select All, each greyed live),
  Room (Summarize the room now, Catch me up), Help (How to address the assistant,
  About). Asked for at the first smoke test and again in the room; never built until
  now.

- **Help > About**, Larry's exact ask: the version, the build date and the fleet it
  was built against. `CHAT_VERSION` is the single source of truth for all three;
  the installer declares the same number at `installer\SimpleChat.iss` line 48
  (`#define AppVersion`) and **the two are kept in step by hand** — there is no
  build step that derives one from the other, so a release touches both.

  The Edit combos (`Ctrl+A/C/X/V/Z/Y`) already worked in the composer, and
  right-clicking it already offered the same menu; the bar is where they become
  *visible*. Window-wide accelerators are **not** here: `SW_WINDOW` routes keys only
  to the focused widget and `handle_key` carries no Ctrl flag, so a global
  `Ctrl+M` needs a simple_widgets change on its own branch.

- **The empty boxes in the assistant's replies were the bubble WRAP, not emoji and
  not CRLF.** `SW_CHAT_THREAD` wraps by splitting on the space character alone, so a
  newline is never a break — it stays inside a "word" and is drawn as a glyph.
  Larry's own messages are single lines and looked right; the assistant's are not,
  and every line break in them became a box. The Noto artwork resolves correctly
  (`emoji_u1f916.png` is present) and the store holds exactly what was sent, so both
  of the theories on offer were wrong; his own instinct — the display's line
  handling — was right.

  `BUBBLE_TEXT.one_line` collapses breaks and blanks before drawing. **The structure
  is the cost**: a numbered list arrives as one flowing paragraph. It is a WORKAROUND
  and it names its own retirement condition — simple_widgets'
  `feature/thread-lines-keys-selection`, which makes the thread break on newlines and
  lay out the lines it is given. Once that lands this class is not merely
  unnecessary but harmful, and both call sites come out.

  **That condition is met and the class is gone** — see *simple_widgets 0.6.0 adopted*
  at the top of this section.

- **"Room > Summarize the room now" was a dead menu item.** The two lines wiring the
  menu to its actions were never in the file — an earlier patch reported success
  having applied only half of itself — so `on_summary` stayed Void, which builds the
  items DISABLED. Larry clicked a dead item while the typed `@claude sum` worked,
  because the typed path does not go through that wiring.

- **A summary on demand, and a catch-up when you come back.** Both were designed
  in Larry's own words after his second look at the branch client — *no rolling
  summary on an arbitrary timer; a summary on demand (`@claude sum last 10
  minutes`); and a catch-up when the window regains focus after an absence,
  summarising exactly the gap* — and both are built to the ruling that came with
  them: **a summary is an engine reply to the person who asked, shown in their own
  window, and never a room event.** Events are never per-person, so a summary must
  not be one.

  **On demand.** A composer line that mentions an assistant and *opens* with a
  summary verb — `sum`, `summary`, `summarise`, `summarize`, `recap`, `catch (me)
  up` — is never posted. `CLIENT_APP.send_text` sends it to `POST
  /rooms/{id}/summary` instead and draws what comes back with `show_hint`, which
  is a real bubble in the thread that deliberately never touches `shown_model`. So
  nothing downstream can mistake a summary for a room event. The rule lives in its
  own class, `SUMMARY_ASK`, and is deliberately conservative: it would rather miss
  than over-reach, because the cost of guessing wrong is a question the room never
  sees. `@claude can you write a summary of the roof job` is a question and is
  posted; `@claude summertime is here` is a message, not a verb.

  **On returning.** simple_shell raises no activation event and swallows minimise
  outright, so there is nothing to subscribe to: the window's return is found by
  edge-detecting `view.is_foreground` in the 250 ms tick — **before** the pump,
  because the pump is what clears the very unread count the decision reads. Two
  thresholds must both be passed, and they are in `client.toml`:
  `catch_up_away_seconds` (default 300) and `catch_up_minimum_messages` (default
  5). A long lunch in a silent room is not a gap, and three messages while the
  kettle boiled are not an absence. The catch-up summarises `since` the last event
  seen when the window went away — exactly the gap, not a line more.

- **A summary has its own engine budget.** `summaries_per_hour` (default 12) in
  `server.toml`, charged under an `s:` prefix, entirely separate from the
  participant's `p:` answer budget. Catching up on what you missed must never cost
  you the right to ask a question — which is the whole reason the budgets are two.

### Changed

- **The client's bot hint no longer teaches the superseded rule.** It said
  *"Address the room's assistant by starting a line with @claude"*; a mention
  anywhere has addressed the assistant since 0.1.3, and it now says **by
  mentioning**. A hint that teaches the old rule is worse than no hint, and this
  one was the discoverability gap Larry raised.

### Fixed

- **`@claude sum` was posted to the room instead of being intercepted.** The
  client's rule matched `"@" + username` from the roster — but the roster carries
  the bot USER (`claude_bot`), while the server's address parser matches the
  participant HANDLE (`@claude`). The two are not the same string, so the rule
  never fired and the line went through as an ordinary message. Larry hit it on
  the first try. The client now fetches the real handles from `GET /participants`.

- **That fetch was itself broken**, which is why the first fix changed nothing:
  `/participants` answers `{"participants": [...]}` — an object *wrapping* the
  array — and it was decoded as a bare array (the `/rooms` shape). The failure was
  silent, the handle list stayed empty, and an empty list makes the rule answer
  False. Both halves are needed; either alone still posts the line.

- **The sign-in hint was telling members to type an address that cannot work.** It
  was built from the roster too, so it read `@claude_bot`. It now names the
  handles, and falls back to the roster only when `/participants` has not answered.

- **The assistant answered a question about the local drive with a fabricated tool
  call.** Asked whether it could see a folder, it produced an `<invoke name="Bash">`
  block and a directory listing — of folders that **do not exist**. The sandbox and
  `--tools ""` held and nothing was read; what failed was honesty, and the room was
  shown a transcript of work that never happened. Two fixes: the persona now states
  it has no tools, no file access and no memory beyond the room's messages, and
  must say so when asked; and any reply carrying tool-call markup is replaced with
  one plain sentence before it can reach the room.

- **A summary would have frozen the window.** It was issued on the GUI processor,
  and a `claude -p` call takes seconds — Windows ghosts a window that stops pumping
  for about five of them and discards the keystrokes aimed at it (the standing bar
  from `phase4-freeze.txt`). The request now runs on `SUMMARY_HOST`'s own
  processor, the answer lands in a `SUMMARY_SLOT` that only ever assigns fields,
  and the 250 ms tick collects it — the poller's choreography exactly. The member
  sees `Summarizing…` at once and keeps a working composer.

### Added — simple_widgets 0.6.0 adopted: real lines, real keys, real copy

- **The newline workaround is RETIRED, and the structure it cost is back.**
  `BUBBLE_TEXT.one_line` turned every line break into a space so `SW_CHAT_THREAD` would
  not shape an LF into an empty box, and its own class note named simple_widgets'
  `feature/thread-lines-keys-selection` as its retirement condition. That branch merged
  as **0.6.0**: the thread now cuts a message into PARAGRAPHS before either text path
  lays anything out. Both call sites — `show_event` and `show_hint` — hand the thread
  the text exactly as it was sent, and `src/client/bubble_text.e` is DELETED; nothing
  else needed it. A three-line reply is three lines and a numbered list is a numbered
  list, proven not by eye but by `layout_spans`, which says how many `SHAPED_LAYOUT`s a
  message became — one per paragraph, so **3** for a three-line reply and **1** for a
  flat one. Offscreen at the room's real 2x:
  `.eiffel-workflow/evidence/thread-lines-client-2x.png`.

- **The menu bar owns the Alt key and draws its mnemonics.** `&File`, `&Edit`, `&Room`,
  `&Help`; `Cu&t`, `&Copy`, `&Paste`, `Select &All`, `&Summarize the room now`, `&Catch
  me up on what I missed`, `&How to address the assistant`, `&About simple_chat`. The
  library keeps the PLAIN reading in `labels` and `items.label`, so nothing that reads a
  label sees the marker, and `SW_WINDOW.set_menu_bar` is called with the bar — which bar
  owns Alt is TOLD, never discovered.

- **Alt+F opens File, and closing that last mile took a finding.** simple_shell **1.9.3**
  landed mid-branch and delivers Alt+letter at last — as the ORDINARY key-down event 4,
  with the virtual key, swallowing the `WM_SYSCHAR` behind it so `DefWindowProc` cannot
  open the system menu behind the application's back. But simple_widgets tries only its
  **accelerator table** on event 4; `SW_WINDOW.activate_mnemonic` — the feature that
  opens a pad — sits on the `WM_CHAR` door, which is precisely the message the shell now
  swallows. So the gesture reaches the table and dies there. The library's README names
  the way out ("a host can drive it from an accelerator or a click today") and that is
  what `open_menu_pad` is: four Alt accelerators, one per pad, each opening the menu that
  underlines its letter. `Alt+F` / `Alt+E` / `Alt+R` / `Alt+H` work end to end now, and
  the second half of the gesture — a bare letter picking the item while the menu is open —
  always did. **If simple_widgets later routes an unclaimed event-4 Alt+letter to
  `activate_mnemonic` itself, these four registrations become redundant and come out.**
  They take nothing from any widget: an Alt+letter reaching a text box does nothing.

- **Ten window-wide accelerators.** `Ctrl+X` / `Ctrl+C` / `Ctrl+V` / `Ctrl+A` for editing,
  and `Ctrl+M` (*Summarize the room now*), `Ctrl+U` (*Catch me up on what I missed*) and
  the four `Alt` pads above. Both room keys are stated in the menu itself, in the hint
  column that used to carry the typed form; the typed forms did not go away, they moved into
  **Help > How to address the assistant**, which is where a sentence belongs and a hint
  column is not.

- **THE RULE, and the routing it forces.** simple_widgets consults the window's
  accelerator table BEFORE the focused widget, so a claimed key is **taken** from that
  widget: claiming `Ctrl+C` removed it from `SW_TEXT_BOX`'s own control-code-3 handling
  *and* from `SW_CHAT_THREAD`'s. Every editing accelerator therefore ROUTES.
  `route_copy` copies the pane's selection when the pane has focus and the composer's
  when the composer has. `route_cut` and `route_paste` do nothing at all with a bubble in
  focus, because nothing removes text from a transcript or puts text into it.
  `route_select_all` takes the whole composer line, or the whole of **one** bubble —
  simple_widgets keeps a selection inside a single message deliberately, since a range
  spanning three speakers has no honest text to hand the clipboard. `Ctrl+Z` and `Ctrl+Y`
  are deliberately **not** registered, so undo and redo still reach the composer's own
  stack exactly as they always did.

- **The Edit menu can no longer offer what the key would refuse.** Every item calls the
  same agent its accelerator calls, and its greying reads the same `can_cut` / `can_copy`
  / `can_paste` / `can_select_all` query that agent guards itself with. One meaning of
  Copy in this window, two doors to it.

- **Copying from the thread needed nothing new in the pane.** A press lands on the thread
  (`SW_WINDOW.target_at`), the thread accepts focus, and the library's own dispatch gives
  it the keys — so press-drag, double-click, right-click *Copy* and `Ctrl+C` all work
  through simple_widgets. What this client owed was the routing above and the greying,
  and both focus cases are assaulted through the clipboard the feature really writes to
  (whatever was on it is put back at the end of the test).

- **Nine assaults, 230 → 239, zero skips**, and one retired: the old
  `a_bubble_never_carries_a_line_break` — which pinned the workaround — is replaced by
  `a_bubble_keeps_the_line_breaks_it_was_given`, which pins the law that made the
  workaround removable. The new eight cover the lines reaching the thread and the frame
  written from that state; the mnemonics and who owns Alt; the room menu stating its two
  keys; the accelerator table including the keys deliberately left unclaimed; Copy
  routing to whichever widget has focus; Cut/Paste/Select All routing the same way;
  the Edit menu greying for both focus cases; and a press on a bubble being what gives
  the pane the keys; and Alt+letter opening that pad end to end, driven through
  `fire_accelerator` the way the shell drives it — no keystroke, no window.

### Found while adopting — two simple_widgets 0.6.0 seams, NEITHER fixed here

- **`SW_WINDOW` never routes an event-4 Alt+letter to `activate_mnemonic`.** With
  simple_shell 1.9.3 an Alt+letter now arrives as event 4 by virtual key and its
  `WM_SYSCHAR` is swallowed, so the WM_CHAR door `char_accelerator_fired` reads — the
  only door that calls `activate_mnemonic` — is never knocked on for that gesture.
  `dispatch_plain`'s event-4 arm should, when the accelerator table declines a key and
  `alt_down` is true, try `activate_mnemonic` before handing the key to the focused
  widget. Until it does, every host must register its own Alt accelerators, as this one
  now does.

- **`SW_CHAT_THREAD` cannot be given a message after it has drawn a shaped frame.** Its
  invariant `spans_match_when_present` requires `layout_spans.count = messages.count`
  whenever `shaped_layouts` is non-empty, but `layout_spans` is rebuilt only by `draw`.
  So `add_message` after a first paint leaves the counts one apart and the invariant
  fails — which is *precisely* what this client does on every event after the first
  frame. It does not bite Larry, because the shipped client is finalized and finalized
  code checks no invariants; it bites any workbench build and it bit this branch's own
  assault, which now fills a pane and then paints it rather than painting and then
  filling. **The fix belongs in simple_widgets** (rebuild the spans in `add_message`, or
  weaken the invariant to `<=` and state the rebuild in `draw`), and this branch was
  scoped to `apps/client`, `src/client`, `testing` and the docs, so it is reported here
  rather than patched around.

### Known — CLOSED by simple_widgets 0.6.0, except one half that is simple_shell's

- ~~**No Alt/Alt+F, and no mnemonic underlines on the menu bar.**~~ ~~**The chat display
  cannot be selected or copied.**~~ Both were waiting on simple_widgets'
  `feature/thread-lines-keys-selection`. It merged as 0.6.0 and this branch adopts it —
  see *simple_widgets 0.6.0 adopted* at the top of Unreleased.
- ~~**Alt+letter delivery.**~~ **CLOSED during this branch.** simple_shell 1.9.3 shipped
  the Alt door on 2026-09-03 and this branch closed the remaining seam above it — see
  *Alt+F opens File* at the top of Unreleased. `Alt+F` / `Alt+E` / `Alt+R` / `Alt+H` open
  their pads; a bare letter then picks the item.

- **Eleven assaults**, 219 → **230**, zero skips. Among them:
  `the_window_keeps_its_heartbeat_while_a_summary_runs` times every collect while a
  **3-second** summary is in flight and fails if the worst exceeds one frame;
  `summary_is_never_a_room_event` pins the law the design hangs on;
  `a_reply_carrying_tool_markup_never_reaches_the_room` covers the fabricated tool
  call, including that `5 < 10` is arithmetic and not markup.

### Notes on the shape

- **The engine call never runs on the API's processor.** That processor serves
  every request in the process; an engine call takes seconds. So the request's own
  processor waits on the dispatcher instead — exactly as the long-poll already
  blocks, and for the same reason. `CHAT_API` holds the dispatcher only as a
  reference (`participant_dispatcher`, registered by `DISPATCHER_HOST`) and never
  calls it.
- **Only scalars cross into `summary_of`**, and it posts nothing, so none of the
  lock-passing hazards that produced the second-call freeze can recur on this
  path. Its postcondition says so out loud: nothing posted, nothing rung, no
  cursor moved, no id marked answered, no wake.
- The status and the text are read under **one** reservation of the dispatcher's
  processor (`summary_through`), so a second member's summary cannot land between
  a text and its status.
- With no gap named, the summary reads the room's **latest** page, pulling
  backwards from the end. Pulling forward from 0 would have summarised the oldest
  page in the room — wrong, and silently so.

## [0.1.3] — 2026-09-03

The conversation release: the assistant answers a mention anywhere in a message and carries the room's last twelve messages into every turn; the dispatcher no longer rings itself (one answer per process with contracts on, since the first day); the pane follows its tail and has a scrollbar; the composer wraps and grows; password prompts show dots; the assistant's text is decoded correctly. Built against simple_widgets 0.5.0, simple_console 1.2.0 and simple_ai_client with the UTF-8 fix, on top of 0.1.2's libraries.

### Added

- **A participant is addressed by its handle anywhere in a message**, not only at the
  start. The rule, stated once in `ADDRESS_PARSER`'s note and tested there: a message
  mentions a participant when, anywhere in its text, an `@` stands that is **not itself
  preceded by a handle character** (`a-z0-9_-`), the unbroken run of handle characters
  after it **equals** that participant's handle or one of its `@`-shaped aliases, and
  that run **ends the text or is followed by a character that is not a handle
  character**. Case is folded on both sides. So `hello @Claude what is 2+2`,
  `and times 3 @claude`, `@claude:`, `@Claude,`, `so what @claude?` and `(@CLAUDE)` all
  address `@claude`; `@claudette` and `@claude_bot` do not (their run is longer — `_` is
  a handle character); `bob@claude` does not (the `@` follows a handle character). A
  message that names **two** bots is answered by both, each exactly once, in the order
  it names them; the same message delivered twice still answers once per bot; a
  bot-authored message never addresses anybody, so nothing can loop. The handle is taken
  out of the question the engine sees. Colon aliases (`Claude:`) keep the older
  start-of-text rule — anywhere else they are ordinary words — and `address_of`,
  `is_addressed` and `parse` are untouched, so every message that was addressed before
  is addressed exactly as before: a middle mention is rewritten into the leading form
  (`ADDRESS_PARSER.addressed_body`) and travels the one addressed-request path that
  already existed.
- **Memory: a per-participant context window.** A new `[[participants]]` setting,
  `context_messages` (0..50, **12** when not given), says how many of the room's most
  recent messages come with every request. The dispatcher reads them from the room
  itself through the new `CHAT_API.dispatcher_context`, oldest first, each prefixed by
  its sender's display name and shortened to 400 characters, the bot's own replies among
  them, and every engine puts them in front of the question
  (`PARTICIPANT.context_block_of`, `CLAUDE_CODE_PARTICIPANT.contextual_prompt_of`). It
  is read from the store, never from anything the dispatcher remembers, so it survives a
  restart and holds the room's last N messages whether or not the bot was there when
  they were posted. `context_messages = 0` sends exactly the prompt that was sent
  before. Under it, `@claude` still resumes the room's CLI session, and now
  **forgets a session that answered nothing** (`forget_session`), so a session the CLI
  will not resume is never asked for twice.
- **Ten assaults**, 196 → **206** (`testing/participants_assault.e`): the boundary rule
  at the start, in the middle, at the end, against punctuation, case, a longer word, an
  `@` inside a word, an `@`-shaped alias and the same handle named twice; the rewrite
  into the leading address with the `via` surviving it; a middle mention answered once
  with the handle out of the question; a bot's own mention, a longer word and a system
  event addressing nobody; two bots in one message each replying once and the page
  delivered twice not doubling either; the rate limit still charged and obeyed on a
  middle mention; a three-turn exchange in a real room whose third request carries the
  first two turns and the bot's own reply, oldest first; the window capped at
  `context_messages` and taken away by zero; the session kept per room and dropped on
  failure; and the configuration setting with its default, its zero and its cap.

- **A wrapping, growing composer** (`apps/client/chat_input_box.e`, `CHAT_INPUT_BOX`). Larry's
  report from the live room: "The input textbox/field does not wrap within the textbox. That is
  a problem." The one-line `SW_TEXT_BOX` composer is now multi-line and measured-word-wrapping
  (`make_wrapping`, alongside the still-available `make_single_line`): text wraps at the box's
  width, the box grows with its content from one line up to a cap of five lines at the theme's
  own scaled line height, and past the cap it scrolls internally (`draw` clips to the held
  rectangle and shifts the parent's own painting up by the overflow) rather than growing the
  window further. Plain **Return sends** and never leaves a trailing newline in the sent text,
  even when the last thing typed was a Shift+Return with nothing after it; **Shift+Return**
  inserts a newline, exactly the way the parent's own multi-line Return always has. Detecting
  Shift on a Return that only ever arrives at `handle_char` as a bare character code required a
  small `handle_key` redefinition too: `SW_WINDOW` dispatches the paired `WM_KEYDOWN` — carrying
  the live Shift flag — immediately before the `WM_CHAR` that reaches `handle_char`, so
  `handle_key` remembers it a moment early. `SW_CHAT_VIEW` now creates the composer with
  `make_wrapping` in place of `make_single_line`.

- **`@claude` discoverability** (`CHAT_VIEW.show_hint`/`hint_count`, effected in `SW_CHAT_VIEW` and
  `MEMORY_CHAT_VIEW`; `CHAT_PRESENTER.bot_members`; `CLIENT_APP.open_room`). Larry's report: "I am
  unsure how to send questions to the embedded Claude instance." (He then typed "@Claude Who are
  you?" and it worked — the match was already case-insensitive; the problem was never knowing the
  convention existed.) `CLIENT_APP.open_room` now shows one system-role bubble the moment a room's
  roster (already fetched by the existing `load_roster`/`GET /rooms/{id}/members`) lists a bot,
  naming every bot member actually present by its real `@username` — never a literal `"@claude"`
  typed into this codebase, so the hint stays true the day a bot is renamed or a second one joins.
  No hint is shown when the roster carries no bot.

- **Five assaults, 214 → 219** (`testing/participants_assault.e`).

  `dispatcher_post_does_not_ring_the_dispatcher_back` is the regression test, at
  the seam where the defect was made: a member's post rings the room **and wakes
  the dispatcher**, which is the whole point of the doorbell; the dispatcher's own
  answer rings the room and **does not** wake it; and the next member's message
  wakes it again, so the doorbell is not left switched off. It is driven through
  `handle_event`, not through a drain, so the only ring on the stack is the
  answer's own — on **one** processor a bus wake is a plain call, so a drain
  *started by* a ring would post from inside that ring's own frame and break
  `EVENT_BUS.ring.counted`, which the server never does (there the wake is
  asynchronous and `ring` returns long before the dispatcher moves). That
  asymmetry is why the fixture subscribes deliberately rather than by default.

  Around it: `dispatcher_answers_the_second_and_third_request_of_a_run` (what the
  freeze actually cost), `dispatcher_answers_two_requests_that_arrive_together`
  (both sitting on one page before the drain begins — the shape Larry hit),
  `dispatcher_two_bots_answer_the_same_room` (the second bot's *first* call, which
  the freeze took just as surely, because it was never about the participant), and
  `bus_mutes_one_ticket_and_only_for_that_post`, which also pins
  `EVENT_BUS.Dispatcher_subscriber_name` to
  `PARTICIPANT_DISPATCHER.subscriber_name`, since the mute is keyed on it.

  Proven red before green: with the mute disabled the regression test dies on
  `handle_event`'s own `accounted` and `cursors_unchanged`, because the re-entrant
  wake nests a whole drain under the frame that is answering.

### Changed

- **Password prompts show one dot per keystroke** (`apps/server/server_app.e`,
  all three account commands). 0.1.2 read passwords with
  `SIMPLE_CONSOLE.read_hidden_line`, which shows nothing at all; Larry, at the
  installer's console: "I was surprised by not even have dots for pw chars.
  That meant that I didn't know whether my keystrokes were being registered."
  The prompts now use `read_masked_line_default` from simple_console 1.2.0 -
  a dot per accepted character, Backspace erases one, Enter ends, nothing of
  the password itself on screen. Redirected input (the verification scripts)
  reads a plain line exactly as before.

### Fixed

- `PARTICIPANT_DISPATCHER` no longer makes a **separate call from a postcondition**
  (`context_line_of` checked a display name by asking the API again). ISE SCOOP
  evaluates a lock-passed call's postcondition after the caller's locks are returned,
  and the late reach for a processor nobody is holding froze the dispatcher solid the
  first time a context window had a line in it. The name is checked against the local
  cache the body filled.

- **The composer grows on the frame the wrap happens** (`apps/client/composer_row.e`,
  `COMPOSER_ROW`; `SW_CHAT_VIEW`). Larry, typing into the live room at 2x: "The new wrap-of-text
  will start below the textbox area until I get to about 1/3-1/2 of the way left-to-right and only
  then does the text box grow in size." Nothing was stale and nothing was deferred: `SW_WINDOW`
  re-lays the whole tree out on every frame — `after_input` runs `render`, and `render` runs
  `arrange` then `draw` — so the box is measured and painted inside the same frame as the
  keystroke that changed it. The disagreement was a WIDTH. `SW_ROW.arrange_line` hands each child
  its share of the row (the non-growers keep their natural widths, the growers split what is left),
  but `SW_ROW.preferred_height` asks every child for its height at the WHOLE row width, as if the
  child were alone on it. For a label or a button that is harmless — their heights do not depend
  on width. For a wrapping `SW_TEXT_BOX` it meant the composer was measured **120 px wider than it
  was drawn** — the `Send` button's 104 px plus one 16 px theme gap — so the paint wrapped to
  a second line while the measurement still said one, the column gave the row a one-line height, and
  the second line landed BELOW the box until the text was long enough to wrap at the wider measuring
  width too. That surplus is exactly how far across the second line got before the box finally grew.
  Measured offscreen at 2x: the box is 732 px wide inside an 852 px row, and the first frame that
  painted outside the box came at character 48 of an 80-character sentence — seven such frames in
  all. `COMPOSER_ROW` measures the way `arrange_line` allocates, so the measured width and the
  painted width are the same number; the bad-frame count is now zero.

- **Empty status and error lines take no vertical space** (`apps/client/status_line.e`,
  `STATUS_LINE`; `apps/client/collapsing_column.e`, `COLLAPSING_COLUMN`; `SW_CHAT_VIEW`). Larry:
  "What remains is a rather large space between the bottom of the text area (above) and the top of
  this textbox/field below. The space isn't huge, but remains fixed-space between the two." Measured
  offscreen at 2x it was **142 px**, and every pixel of it is accounted for: since simple_widgets
  0.4.0 an `SW_LABEL` measures its height from the FONT whether or not it has any text, so the empty
  status line and the empty error line reserved **47 px each**, and `SW_COLUMN` charges a theme gap
  for every join whether or not the child has any height — **16 + 47 + 16 + 47 + 16 = 142**.
  `STATUS_LINE` asks for zero height (and paints nothing) while its text is empty;
  `COLLAPSING_COLUMN` treats a flat child as ABSENT, so it costs no row and no join. The thread now
  sits exactly **one theme gap — 16 px** above the composer (thread bottom 528, composer top
  544), and a line gets its row back on the very next frame the instant there is something to say:
  nothing is added to or removed from the tree and there is no flag to get out of step, because the
  column re-asks every frame. The gap stays 16 px as the composer grows, which is what Larry already
  observed of the old one. Both rules belong in simple_widgets — an empty label should be free,
  and a zero-height child should not buy a gap — and are written here only because simple_widgets
  is checked out on `fix/chat-thread-scrolling` this week. Evidence:
  `.eiffel-workflow/evidence/gap-before.png` and `gap-after.png`, rendered offscreen at the room's
  real 2x scale.

- **The dispatcher answers the second question of a server run, and the third.**
  It answered the first and then went deaf for the life of the process: no child
  started, nothing logged, the rest of the server serving normally. Reproduced
  here with a fake engine (a `bible_tool` entry whose engine is `PING.EXE` — a
  real child on the real dispatcher path, no subscription needed) in one run, and
  then with the three messages **four seconds apart**, which is what killed the
  timing story the first report carried: back-to-back was never the trigger.

  Answering **posts**, and the post rang the dispatcher back into itself.
  `PARTICIPANT_DISPATCHER.post_reply` hands `CHAT_API.dispatcher_post` the
  dispatcher's own string, which under ISE SCOOP passes the dispatcher's lock to
  the API for the length of the call; the post rings the bus, the bus wakes its
  subscribers, and because the API already held that lock the dispatcher's `wake`
  did not queue for its own turn — it ran there and then, on the API's thread, by
  impersonation, **inside `handle_page`, inside the drain**. It queued a room and
  counted a wake under a frame that promises neither
  (`handle_page.nothing_queued`, `dispatch_pending.wakes_untouched`). The
  postcondition raised, unwound `dispatch_pending` into an *asynchronous* `wake`
  whose caller was long gone — so the exception went nowhere and printed nothing —
  and left `is_dispatching` **True**. Every later wake queued its room and
  returned. Measured with timestamped traces and settled two ways: a rescue named
  the clause (`POSTCONDITION_VIOLATION: nothing_queued`, `handle_page @23`), and
  the same source finalized **without contracts** answered every turn and drained
  for ever. Full record in
  `.eiffel-workflow/evidence/phase4-second-call-freeze.txt`.

  The rule now is **nobody is rung for their own post**. `EVENT_BUS` notes the
  dispatcher's ticket when it subscribes — by the name the subscriber gives, since
  the bus never holds a subscriber's type and no contract there may touch another
  processor — and `mute_dispatcher` / `unmute` make `ring` pass that one
  subscription over. `CHAT_API.dispatcher_post` mutes for the length of its own
  post and unmutes in the body and in a rescue. Nothing is lost to the silence: a
  bot's own answer is an event the dispatcher ignores anyway, and news from
  anyone *else* rings on its own poster's turn, where no lock is passed, the wake
  is a plain asynchronous call, and it waits behind the drain instead of cutting
  into it.

  The two contracts were right and are untouched — the diff adds clauses and
  removes none. What was wrong was the wiring.

- **A raise inside the drain no longer latches the dispatcher off in silence.**
  `dispatch_pending` gains a rescue that puts `is_dispatching` down and **logs**
  the raise before it propagates. That is not the fix above; it is the reason the
  fix took three weeks to become visible — an exception in an asynchronous SCOOP
  call has no caller left to tell, so the dispatcher went quiet without a single
  line anywhere. Whatever the next such raise turns out to be, the next wake will
  drain again and the log will say what happened.

### Known

- The dispatcher answers the **first** `claude -p` of a server run and then freezes on
  the **second**: no child is started, nothing is logged, the rest of the server keeps
  serving. Reproduced on `main`'s own binary with two leading `@claude` turns, and with
  a *second participant's first* call, so it is neither `--resume` nor the context
  window nor the addressing rule. It sits below simple_chat, in the process/engine path.

- `CHAT_API.dispatcher_try_ask` is the other lock-passing call on the answering
  path, and its postcondition re-reads the caller's separate string at exit
  (`local_8 (a_key)`) — the same pattern `dispatcher_post` carries a comment about
  having fixed once, and which surfaces as a phantom raise at the caller's next
  synchronization point. It did not fire in any run on this branch. It is a frozen
  contract and was **not** touched; the next cycle should decide whether to
  re-state both clauses over a local copy as `dispatcher_post` did.

### Testing

- Three more assaults in `testing/window_assault.e`, **201 — 204**, all offscreen at the room's
  real 2x scale and driving whole frames through `SW_WINDOW.request_render` — the same `render`
  (arrange, then draw) a keystroke triggers.
  `test_composer_grows_on_the_frame_the_wrap_happens` types an 80-character sentence one
  `handle_char` at a time and, after EVERY frame, requires the height the box was given to equal the
  height its own wrapped text needs AT THE WIDTH IT WAS GIVEN — zero bad frames now, seven
  before, the first at character 48 — names the number the two halves have to agree on,
  requiring `COMPOSER_ROW.allotted_width` for the box to equal the box's own `width`, and requires
  the grown box to be a whole number of rows
  plus its own inset (132 px = 2 x 60 + 12; the EMPTY box is not one row but 80 px, floored at the
  painter's `min_control_height`, which is why the law is stated of the grown box).
  `test_empty_status_rows_cost_nothing_and_a_spoken_one_costs_its_row` requires both empty lines to
  ask for zero height and to be given none, the thread to sit one theme gap above the composer, and
  a line that speaks to get its natural `line_step` back with the pane giving up exactly that row
  plus its one new gap. `test_the_gap_holds_while_the_composer_grows` requires the gap to be one
  theme gap with an empty composer AND unchanged with a paragraph in it, prints the whole vertical
  accounting, and writes `.eiffel-workflow/evidence/gap-after.png` from that very state.

- Three new assaults in `testing/window_assault.e` prove the composer directly against the real
  `SW_CHAT_VIEW`/`CHAT_INPUT_BOX`, calling `preferred_height`/`draw`/`handle_key`/`handle_char` the
  way a real keypress pair would, entirely offscreen: growth is exactly one `row_height` per line
  from one line to the five-line cap and then holds flat past it
  (`test_composer_grows_with_content_then_caps_at_five_lines`); `draw`'s temporary scroll shift of
  its own `y` is fully restored after painting past the cap
  (`test_composer_draw_restores_its_own_geometry_after_scrolling`); and Shift+Return inserts a
  newline while a plain Return after it sends the whole line with none trailing
  (`test_composer_return_sends_but_shift_return_inserts_a_newline`). Two more prove the hint through
  the real `CLIENT_APP.open_room`, one roster with a bot and one without
  (`test_client_app_hints_the_room_when_a_bot_is_in_the_roster`,
  `test_client_app_shows_no_hint_when_the_roster_has_no_bot`). 196 → **201** assaults.

## [0.1.2] — 2026-09-03

The first-run release: a hosting install finishes by creating the first administrator, starting the server and opening the window, in that order; passwords never echo; the door says where the server is; the host can reset a password; every window inherits Vision2's spacing model from simple_widgets 0.4.0. Built against simple_winhttp 0.1.1, simple_process 1.0.1, simple_encryption 2.1.1, simple_shell 1.9.2, simple_widgets 0.4.0 and simple_console 1.1.0.

### Added

- **`server_app_prompts_over_redirected_stdin`**, 191 → **192** assaults
  (`testing/config_load_assault.e`). It runs the finalized executable as a real
  child with standard input redirected **from a file** — no console is opened and
  no keystroke is synthesised — in two halves. First an input file that runs out
  before the password: the prompts appear, the refusal names the missing password,
  `ERRORLEVEL` is 1 and there is not even a database file afterwards, because the
  store is never opened. Then the same file with all three lines: the admin is
  created under the display name that was *typed*, and `ERRORLEVEL` is 0 — which
  is what proves the redirected path is intact rather than merely refusing
  everything. The exit status is read out of `ERRORLEVEL` inside `cmd`, because
  that is what `create_admin.cmd` and `reset_password.cmd` actually branch on.

  The **real-console** path is not exercised here and is not claimed to be: it
  needs a real console, which a test runner's redirected standard input is not.
  It was proven in simple_console itself.

- **`--reset-password <username> [config.toml]`** on the server executable
  (`apps/server/server_app.e`). A host who forgot the password had exactly one
  remedy before this: delete `data/simple_chat.db*` and lose every message in
  the room with it. `CHAT_SERVICE.reset_password` had been implemented,
  contracted and assaulted since Phase 4 — it was reachable only over HTTP,
  from an admin session, which is precisely what a locked-out admin does not
  have.

  The console shape is `--create-admin`'s, minus the display-name prompt: the
  account already has a name and nothing here renames anybody. The new password
  is typed twice, under the same `password_minimum` rule. (It was landed behind
  the same “the password will echo” warning the other two printed; that warning
  and the echo it warned about are gone — see “Passwords no longer echo” above.)
  On success it says the password
  was reset **and that every live session that member held was signed out**,
  which is `reset_password`'s own `sessions_revoked` postcondition: a password
  somebody else has learned is taken away, not merely replaced.

  Refused, with a line saying which and **a non-zero exit status**, changing
  nothing: a configuration that will not load, a store that will not open, a
  username this room does not know, a username naming a **bot** (a bot holds a
  token and no password — `CHAT_USER`'s `bots_have_none`), two entries that
  differ, and an entry below the minimum. The exit status is what lets
  `reset_password.cmd` tell the host “nothing was changed” instead of assuming a
  reset it never saw.

  Two new pure queries carry it, both assaulted through `SERVER_APP.make_idle`:
  `is_resettable_member` (the gate that discharges `reset_password`'s `person`
  and `stored` preconditions before the call, so a host naming the room's bot
  gets a sentence rather than a contract violation) and `exit_with_failure`.
  No existing contract was touched.

- **Installer: “Reset a password”** in the `SimpleChat Server` Start Menu folder
  (`installer/templates/reset_password.cmd`, staged and registered like
  `create_user.cmd`). It sets code page 65001, lowercases the typed username in
  pure batch, refuses to run while `SimpleChatServer.exe` is up — all three
  store-direct commands do, and for a reset a lost `SQLITE_BUSY` race would
  leave the old password working and everyone still signed in — and reads the
  exit status to report what actually happened. The hosting guide gains a
  “When somebody forgets their password” section — including the case that
  motivated the whole command, the host who is the only administrator and is
  the one locked out — and its stop-the-server warning now names all three
  store-direct commands.

- Three assaults, 188 → **191**: `server_app_reset_password_gate` (the pure
  gates: a stored person, an unstored one, a bot, and the argv username rules),
  `password_reset_by_the_host` (the store-direct path — unknown username finds
  nobody, bot refused, live session revoked, old password dead, new one alive,
  nobody else touched) and `host_console_reset_kills_a_live_token` (the same
  reset seen from the HTTP surface: a token issued beforehand answers 401, the
  old password is refused at `/login`, the new one accepted — with no admin
  session anywhere in it, unlike the endpoint test beside it).

### Changed

- **The installer's finish sequence, for a hosting install, is now an order.**
  It was: open the chat window, and list three chores for the host to go and do.
  On 2026-09-02 Larry installed on a PC with no server running and no account,
  and was met by a sign-in that could not possibly work — nothing was listening,
  and there was no account to answer with. For a host the window is the **last**
  thing that should happen. Pressing Finish now runs, each step waiting for the
  one before it:

  1. **create the first administrator** in a console — skipped when
     `{commonappdata}\SimpleChat\data\simple_chat.db` already exists, so
     re-running the installer over an existing room never offers to mint a second
     first-admin (the server refuses one anyway, but only *after* asking for a
     display name and a password twice);
  2. **start the server**, and say whether it answered `/health`, or name the
     program holding the port;
  3. **open the chat window**, with something to sign in to.

  The hosting guide opens last, behind the window; it is reference material, not
  a step. A client-only install has no steps 1 or 2 and keeps “Open SimpleChat
  now” exactly as it was. All four entries carry `runasoriginaluser`: the install
  is elevated, the Start Menu entries that run the same scripts are not, and a
  server started elevated could not afterwards be stopped by “Stop server”,
  because a non-elevated `taskkill` cannot touch an elevated process.

- **The finish message** says what the wizard is about to do instead of listing
  three chores, and keeps only the guide — going public, and a standby host — as
  the manual part.

- **`start_server.cmd` takes `/nopause`.** It prints everything it always printed
  and holds the window open long enough to read, but does not wait for a
  keypress, which would stall the wizard behind a key nobody is present to press.
  Without the switch — which is how the Start Menu entry runs it — it pauses as
  it always has.

- **`create_admin.cmd` leaves quietly when the room already has an
  administrator**: it says so and exits 0 rather than walking the host through a
  display name and two passwords on the way to a refusal.

- **The sign-in door's refusal line is an ordinary UI label again**
  (`apps/client/login_window.e`). It carried a nominal size of 9.0 as a
  workaround for a simple_widgets defect - a wrapped `SW_LABEL` stepped its
  lines by `size + 9.0` while painting at `size * text_scale`. simple_widgets
  0.4.0 derives the step from the measured font metrics at the painted size,
  so the workaround and its constant are gone; the line is drawn at the form's
  size like every other label on it. The same release gives every window built
  on the library Vision2's spacing model - a border between the window edge and
  its content, padding between siblings, an inner inset in every control, and
  control minimum sizes that follow the font - which this client inherits
  without a change, because it never set spacing of its own.

- **Passwords no longer echo at the console.** `--create-admin`, `--create-user`
  and `--reset-password` (`apps/server/server_app.e`) read every password — and
  every “Again:” confirmation — through `SIMPLE_CONSOLE.read_hidden_line`
  (simple_console 1.1.0, added to the `simple_chat_server` and `simple_chat_tests`
  targets). It clears `ENABLE_ECHO_INPUT` for the read and restores the console
  mode on **every** exit path, keeping Backspace and Enter working. The line
  `WARNING: the password will echo on this console (no echo suppression in v1).`
  is gone from all three commands, because it is no longer true.

  The display name stays an ordinary echoing read: a person has to see the name
  they are giving themselves. The username still arrives from argv.

  **Redirected standard input is untouched.** When stdin is a file or a pipe —
  which is how the shipped `.cmd` wrappers and `installer/VERIFICATION-2026-09-02.md`
  feed a password in — the line is read the ordinary way and no console mode is
  touched. **End of input before a password** is refused, changing nothing, with
  **exit status 1**: `read_hidden_line` answers Void on end of input and never a
  partial line, and the exit is taken only *after* the store is closed, which is
  the discipline `--reset-password` already had. A line ended by pressing Enter
  alone is still the empty password, refused by `password_minimum` as before.

  Passwords are now decoded as UTF-8 on the way in rather than widened
  byte-for-byte. An ASCII password hashes to exactly what it hashed to before;
  a **non-ASCII** one now hashes the bytes that were actually typed instead of a
  double encoding of them, which is what the HTTP `/login` path always sent. A
  non-ASCII password created at the console *before* this change will not verify
  after it — reset it with `--reset-password`. The now-unused `line_read` is
  deleted; it carried no contract.

- **A missing server executable FAILS the live assaults instead of skipping**
  (`testing/wiring_assault.e`, new `testing/server_exe.e`, `testing/test_app.e`).
  This is the one sanctioned contract change of this branch and it is in the
  assault, not in `src/` or `apps/`.

  Three live rounds — `live_client_stack_round_trip`,
  `live_client_app_shows_an_event_in_the_real_pane` and
  `live_gui_latency_through_a_quiet_poll` — printed
  `SKIP: ... which is not built` and then asserted `True`, so a skip counted as a
  pass. That hid a real failure three times on 2026-09-02 and 2026-09-03.

  Removed from each of the three (verbatim):

  - `assert ("skipped cleanly without a server exe", True)`
  - the comment lines `-- Skips, and passes, when the exe is not built.` (and, on
    the round trip, `-- when the exe is not built - the SKIP line says so out loud.`)

  Added in their place:

  - `assert (a_what + " needs " + l_exe.Relative_path + ", which is not built", False)`
    in the new `report_unbuilt_server`, so `Results:` shows a failure
  - the comment lines `-- FAILS when the exe is not built (see `report_unbuilt_server').`

  New contracts (all additions): `SERVER_EXE.is_built`'s
  `definition: Result = (path /= Void)`, `SERVER_EXE.name`'s
  `empty_exactly_when_unbuilt: Result.is_empty = not is_built`,
  `SERVER_EXE.explain_missing`'s `not_built: not is_built`, and
  `CONFIG_LOAD_ASSAULT.create_admin_command`'s `named`, `redirected` and
  `status_reported`. `WIRING_ASSAULT.prepare_scratch` keeps its own
  `room_seeded` and `server_exe_copied` unchanged.

  **The path is no longer resolved against the working directory alone.**
  `SERVER_EXE` asks the file system twice: the working directory (where
  `RUNBOOK.md` says to run from — the old answer, kept), and then this running
  executable's own directory and each ancestor up to eight levels, so a runner
  started inside `EIFGENs\simple_chat_tests\F_code` walks the three levels to the
  project root and finds the same file. `{ARGUMENTS_32}.command_name` gives argv[0]
  and `PATH.absolute_path` resolves it, so a bare or relative argv[0] still lands
  somewhere real. Running from inside `F_code` no longer changes the answer.

  When it really is not built, each assault prints where the file belongs and
  `ec.sh test -config simple_chat.ecf -target simple_chat_server`, and `TEST_APP`
  repeats it once under `Results:` (`name_the_missing_build`). No escape hatch was
  invented: there was none to keep. Proven red — with the executable renamed the
  run reports **188 passed, 4 failed**.

  (`window_assault.e`'s `SKIP: no DPAPI on this platform` is left alone. It is not
  a missing build but a missing platform capability, and it never triggers on
  Windows.)

- **A sign-in that reaches nothing at all now says what to do about it, instead of
  quoting the transport.** Larry installed the client on a PC with no server
  running and no account yet; the finish page opened the window, he typed a name
  and a password, and it "didn't work". Everything the window could tell him was
  true and useless: a connection label reading *not answering*, and on the door's
  refusal line whatever WinHTTP called the failure — a mechanism, never an action.

  `HTTP_REPLY.status` is 0 **exactly** when the transport failed, so that is the
  fact the client now keeps (`CHAT_CLIENT.last_status`, added). `CHAT_ERROR`
  cannot carry it: `error_of` maps a transport failure onto 503, and a server
  answers 503 of its own accord as well (`CHAT_SERVICE.backup` does), so the two
  are indistinguishable by the time the door sees them.

  `CONNECTION_ADVICE` (new, `src/client/`) is the one place the words live, and
  the *address* is the whole distinction it draws. This PC's own loopback — the
  address `CLIENT_CONFIG.prefers_local` and `local_port` build — means the room is
  meant to be hosted here and no server is running, so the member is pointed at
  the Start Menu entry that starts one, word for word as `installer/SimpleChat.iss`
  writes it. Any other address is somebody else's server, so he is pointed at the
  host and at `%APPDATA%\simple_chat\client.toml`, and is never told to start a
  server of his own.

  **A refusal is not an outage.** A wrong password, an unknown name, a locked
  account: those carry a real HTTP status and the server's own wording, and
  nothing here touches them. `CLIENT_APP.attempt_login` asks for advice only when
  `last_status` is 0.

- **The door's refusal line wraps** (`apps/client/login_window.e`). An instruction
  a member cannot read whole is not an instruction: a single-line `SW_LABEL` ran
  the advice off the right edge and took the Start Menu entry with it. The window
  grew from 460 × 340 to 640 × 420 to hold three wrapped lines, and the refusal
  line carries its own nominal size (`Error_text_size`) because `SW_LABEL` steps a
  wrapped line by `size + 9.0` while `SW_PAINTER` paints it at
  `size * theme.text_scale` — at `Text_scale` 2.0 the two only agree while the
  nominal size stays small.

  Proven on the finalized client against a dead loopback port, not only in the
  assault: the door shows *"No chat server is running on this PC (nothing answers
  at http://127.0.0.1:45999). If this PC hosts the room: Start Menu > SimpleChat
  Server > Start server, then sign in again. If a friend hosts it: put their
  address in %APPDATA%\simple_chat\client.toml"* across three legible lines, with
  the buttons still on the form.

### Fixed

- **Pressing Enter at the username prompt produced gibberish.** `set /p` leaves
  the variable **undefined** on an empty line, and `!ADMIN:A=a!` on an undefined
  variable does not expand to nothing — it expands to the literal text `A=a`. The
  “No username given” guard sat *after* the lowercasing chain and so could never
  fire: the script printed `Using username: A=a` and then an error about `a-z`
  and underscores. The guard now runs before the chain, with the old one kept as
  a second net for an answer of nothing but spaces. This is the first prompt the
  new finish sequence puts in front of a host.

- **The port was never read out of `server.toml`.** `for /f (' … ')` runs its
  command through `cmd /c`, and cmd strips the first and last quote of any `/c`
  string that begins with a quote and holds more than two — so
  `'"%SYS%\findstr.exe" /r /c:"^ *port *=" "%ROOT%\server.toml"'` arrived as
  `C:\Windows\System32\findstr.exe" /r /c:" *port`, which is not a command at
  all. Measured against a config saying `port = 8097`: the shipped form yielded
  `8090`, the bare-path form `8097`. The same shape defeated the
  **port-collision** loop in both `start_server.cmd` and `run_server.cmd`, which
  is worse — quoted, it ran nothing, so a collision was never detected and the
  server was launched at a door already taken. Both files now leave the
  executable path bare (System32 has no space in it) and keep the quotes on every
  argument.

- **`timeout.exe` does not return when stdin is redirected or `NUL`**, which
  wedged two verification runs. The `/nopause` hold is `ping -n N 127.0.0.1`
  instead — the batch sleep that has no opinion about stdin.

## [0.1.1] — 2026-09-02

Libraries this release is built against, each fixed today for the same
defect class (a C external that waits without the `blocking` marker stalls
ISE's collector and every SCOOP processor with it): simple_winhttp 0.1.1
(the client's long poll), simple_process 1.0.1 (the server no longer freezes
the whole room while `claude -p` or a curl-driven engine thinks),
simple_encryption 2.1.1 (login hashing crosses on C memory), simple_shell
1.9.2 (the window's message pump and popup menu).

### Fixed

- **The window froze for up to twenty-five seconds at a time after a few posts**
  (`src/client/event_poller.e`). Thirteen stalls in one twenty-minute session,
  211.6 s frozen in all, every one of them just under `Max_wait_seconds` — and
  the stored messages showed the cost was not delay but *lost input*: lines cut
  off mid-sentence, lines missing their first characters, doubled letters and
  words. Windows ghosts a window that stops pumping for about five seconds and
  discards the keystrokes aimed at the ghost, so no amount of catching up
  afterwards can recover them.

  It was not this project's concurrency. Every separate call the GUI makes on
  the inbox came back inside 2 ms while it was happening. **ISE's garbage
  collector stops every thread in the system before it collects, and a thread
  inside a plain `external "C inline"` call is where the runtime cannot see it
  or stop it** — so a collection waits for that call to return, and the GUI
  freezes at its very next allocation. `SIMPLE_WINHTTP.c_send` carries no
  `blocking` marker, and one exchange was a whole 25-second long poll. Measured
  on the live stack: a pure allocation burst on the GUI's processor took
  **21,058 ms**, while the heartbeat itself took 3 ms. The same wait spent in
  `EXECUTION_ENVIRONMENT.sleep` instead costs the GUI **1 ms**.

  `EVENT_POLLER.run` now polls in slices of `Poll_slice_seconds` (added, 0)
  rather than `{CHAT_CLIENT}.Max_wait_seconds`. `CHAT_REQUEST_HANDLER.handle_wait`
  holds the doorbell only while `seconds` > 0, so an exchange is now one round
  trip and one round trip is the most the window can ever be stopped for: the
  worst allocation through a quiet poll fell from 21,058 ms to **1 ms**. No
  contract was touched — `poll_once`'s `seconds_in_range` admits 0, and
  `pause_seconds` keeps its `Quiet_floor_seconds` of 1, which is now what paces
  a quiet room. The price is the doorbell: the *first* message into a room that
  has gone silent can arrive up to a second late; everything after it is
  immediate again, because a page resets `quiet_polls`.

  The one-line change that would give the long poll back lives in another
  repository — mark `SIMPLE_WINHTTP.c_send` `blocking` — and
  `EVENT_POLLER.Poll_slice_seconds` says so where the next reader will look.
  **It has since landed (simple_winhttp 0.1.1), and the slice has been retired —
  see *The long poll is back*, below.**

### Changed

- **The long poll is back, and the doorbell with it** (`src/client/event_poller.e`,
  `apps/client/client_app.e`). `SIMPLE_WINHTTP.c_send` is marked
  `external "C blocking inline"` from simple_winhttp 0.1.1, so the runtime knows
  the thread has left Eiffel and a collection may run while an exchange is in
  flight. That removes the whole reason for the slice. `EVENT_POLLER.run` asks
  for `{CHAT_CLIENT}.Max_wait_seconds` again and `Poll_slice_seconds` is
  **retired** rather than set to the maximum: a "slice" whose only honest value
  is the whole is not a knob, and the one knob that survives is the one the class
  already had — `poll_once`'s own `a_wait_seconds` argument, whose
  `seconds_in_range` precondition still binds it to `[0, Max_wait_seconds]`. No
  contract changed; nothing in `src/` or `apps/` lost an assertion tag.

  What comes back is the doorbell. A message into a quiet room arrives on the
  round trip that carries it instead of up to `Quiet_floor_seconds` later, and a
  quiet room now costs one request per member per 25 s instead of one per second.
  What it costs is nothing measurable: with the real 25-second poll held open,
  the worst allocation on the GUI's processor is **4 ms live, 5 ms headless** on a
  clean build (25,144 ms against the unmarked library, in the same worktree).

  The law the slice was written for is not retired, only satisfied — it is
  restated in `EVENT_POLLER`'s class note and in `CLIENT_APP`'s: **no processor
  may sit inside an UNMARKED C external longer than the GUI can afford to wait
  for a collection.** A transport swapped in under `HTTP_TRANSPORT` must have its
  externals read before this window is trusted with it.

- **The freeze assault now measures the product, not the fixture**
  (`testing/slow_http_transport.e`, `testing/freeze_assault.e`,
  `testing/wiring_assault.e`). Two defects in the harness, both of which would
  have lied about the restored poll:

  1. `SLOW_HTTP_TRANSPORT.c_sleep` was a plain `external "C inline"`, because the
     transport it doubled was one too. Against the restored 25-second poll that
     failed at **1,481 ms** — a real stall, for a reason that was the fixture's
     and not the product's. It is now marked `blocking`, mirroring `c_send`'s
     exact form, so the double tells the truth about the transport that exists.
     The unmarked shape is not lost: `GC_PROBE` still holds it, beside an Eiffel
     sleep, as the law's own evidence.
  2. The allocation probes — `FREEZE_ASSAULT.worst_allocation_burst`, its frame
     burst, and `WIRING_ASSAULT`'s — allocated 200 × 1 KiB and **kept none of
     it**, so the collector was only ever provoked by whatever heap pressure the
     rest of the run happened to supply. Each now allocates 2 MiB a burst and
     retains 200 KiB of it in a live set that grows for the length of the test,
     the way simple_winhttp's own `testing/scoop/blocking_probe.e` does. Against
     the unfixed library that took the measured stall from 21,639 ms to
     25,144 ms — the whole poll instead of the part of it that happened to
     coincide with a collection.

  And one correction to the premise this branch opened on, because the
  measurement refused it. The probe's missing live set was **not** what made this
  suite report a green against the broken library. **The run location was.**
  `WIRING_ASSAULT` finds the server exe by a path relative to the project root;
  from anywhere else the live assault `SKIP`s — and passes on the skip. Same
  binary, built against simple_winhttp 0.1.0, hardening off:

  - from the **project root** — `FAIL`, worst allocation **21,639 ms**; suite 187 passed, 1 failed
  - from **`EIFGENs/…/F_code`** — `SKIP`, then `PASS`; suite **188 passed, 0 failed**

  So: **run this suite from the project root.** Nothing in the harness enforces
  that yet — making the skip fail, or resolving the exe against the executable's
  own location, would change the assault's contract and was left for a gate.
  Both libraries' numbers are in `.eiffel-workflow/evidence/phase4-freeze.txt`,
  PART 2.

  `test_a_blocking_c_call_on_another_processor_stops_the_allocator` is renamed
  `test_an_unmarked_c_call_…`: now that `blocking` is the name of the *safe*
  shape, the old name pointed at the wrong one.

### Added

- **`testing/freeze_assault.e`, `testing/gc_probe.e`,
  `testing/slow_http_transport.e`, `testing/slow_poll_host.e`** — the regression
  and the two probes that name the cause. A real `EVENT_POLLER` on its own SCOOP
  processor over a transport that waits the way the real one waits — inside C —
  while the root allocates, pumps and posts: every call must return inside a
  frame (red 892 ms, green 1 ms — and see *The long poll is back* for what those
  two numbers became once the probe stopped throwing its allocations away).
  Beside it, the same wait spent two ways on a bare processor: an Eiffel sleep
  costs the root 1 ms, an unmarked C call 7,931 ms.
- **`WIRING_ASSAULT.test_live_gui_latency_through_a_quiet_poll`** — the live
  bar, against the booted server exe: twenty distinct lines posted as fast as a
  composer could send them, then 140 heartbeats through a whole quiet poll, with
  every frame, every post and every allocation timed, and the pane's own bubbles
  walked to prove each line arrived whole, exactly once, in the order it was
  typed.

## [0.1.0] — 2026-09-02

The first installable release: a Windows installer that lays down both halves
of the system, so hosting the room no longer means building from source.

### Added

- **`installer/SimpleChat.iss`** — one Inno Setup 6 installer, two components.
  **Hosting requires an administrator install**: the server component and the
  `host` type carry `Check: IsAdminInstallMode`, so a per-user install offers
  neither and `/COMPONENTS=client,server` yields the client alone. That is
  deliberate - the server writes to `{commonappdata}`, registers a machine-wide
  logon task, and relies on an elevated install making `caddy.exe` unwritable
  by the standard user whose elevated task launches it.
  - `client` is always installed and cannot be unticked: `SimpleChat.exe`,
    `cairo.dll`, the 3,768-file Noto emoji artwork, the licences, a `README.txt`
    and a `client.toml` template placed where `CLIENT_CONFIG` reads it.
  - `server` is **off by default** — most installs are a friend who only wants
    to use the chat. It adds `SimpleChatServer.exe`, the console launchers, the
    hosting guide and a pinned Caddy. Re-running the installer with the box
    ticked promotes a client-only install to a host, which is also how a friend
    becomes a standby host.
  - Start Menu: `SimpleChat` for the window; a `SimpleChat Server` folder with
    Start server, Stop server, Create first admin, Create user, Server log,
    Edit server config, Back up the room, Restore from backup and the hosting
    guide. Optional desktop shortcut.
  - Optional logon scheduled task, registered only when asked for and removed
    on uninstall.
- **`installer/stage_payload.sh`** — assembles the payload from the two lean
  release builds, `simple_cairo`, `simple_shaping` and the templates. It fails
  rather than ship the emoji artwork without its licence.
- **`installer/THIRD-PARTY.md`** — Caddy **v2.11.4** (Apache-2.0) pinned by tag,
  URL, SHA-512 and SHA-256, verified against the upstream checksums file; the
  Noto artwork and cairo pins with their licences.
- **`installer/HOSTING-GUIDE.html`** — hosting written for a non-programmer:
  the two lines that turn hosting on, DuckDNS, router port forwarding, the
  CGNAT dead end and how to recognise it, backups, and the standby-host
  procedure.
- **`--create-user <username> [config.toml]`** on the server executable. There
  is no self-registration: the host mints every account. It mirrors
  `--create-admin` exactly — the same store-direct path over
  `CHAT_SERVICE.create_user`, the same prompting console — and refuses until an
  administrator exists, so the first account on a fresh database is always the
  admin's own.
- Both `--create-admin` and `--create-user` now prompt for a **display name**,
  defaulting to the username. It is read as UTF-8 (`line_read_text`), so a
  Hebrew or Greek name survives when the console is at code page 65001 — which
  the shipped wrappers set. Only the username, confined by the rules to
  a-z/0-9/underscore, ever travels on the command line.
- `SERVER_APP.is_acceptable_display_name` — the gate that discharges
  `CHAT_SERVICE.create_user`'s `valid_display` precondition before the call, so
  a person typing at a console is never a contract violation.
- Assaults: `ordinary_member_created_by_the_host` (the member path, the
  `has_admin` ordering rule and a Hebrew display name round-tripping through
  the store) and `server_app_display_name_gate` (the gate's own cases,
  including the bot marker and bidi overrides). 183 assaults, all green.
- A `CHANGELOG.md`, which the project did not have.

### Fixed

- **The client died instantly when launched from the Start Menu.** `SW_WINDOW`
  writes its session log to the RELATIVE name `sw_session.log`, so it lands in
  the working directory - and `open_write` on a folder the member cannot write
  RAISES an operating-system exception rather than returning quietly, which its
  own `is_open_write` guard never sees. With the shortcut's working directory
  set to the install folder under Program Files, the client failed at "root's
  creation" with *Permission denied* and the window never appeared: it flashed
  and vanished. A read-only install folder is the normal case for a per-machine
  install, so this was not an edge.
  `CLIENT_APP.settle_working_directory` now moves to `%APPDATA%\simple_chat`
  before anything opens a window, and the client shortcuts start there too.
  Nothing else wanted the working directory: `SW_SHAPING` resolves the emoji
  artwork beside the RUNNING EXECUTABLE, and `cairo.dll` is found on the
  executable's own search path.
- **UTF-8 display names were refused.** With stdin redirected from a BOM-less
  UTF-8 file, a Hebrew name arrived as its raw bytes and was taken one
  character per byte; `0x9C` among them is a C1 control, so the naming rule
  refused it - correctly. The rule was right; the decoding never happened. The
  reading path is now the pure function `SERVER_APP.decoded_text`, which
  rebuilds the bytes with `append_code` rather than trusting a conversion that
  depends on the runtime's dynamic type, decodes valid UTF-8, and leaves
  already-decoded text and legacy code pages alone. Real control characters are
  still refused: decoding is not permission.
- The uninstaller now sweeps `{app}\*.log`, so a log written at run time cannot
  keep the install folder alive after an otherwise clean uninstall.

- **The shipped default port is 8090, not 8080.** Apache, XAMPP, Tomcat and a
  dozen development tools squat on 8080, and a collision there is the commonest
  reason the server never comes up - found on Larry's own PC, where Apache held
  it. Both shipped templates move together; `SERVER_CONFIG`'s library default is
  left alone (contracts frozen - it is only the no-file fallback).
- **A port collision is now named, not silent.** `start_server.cmd` finds what
  holds the configured port before launching and prints the image name and PID
  plus the two lines to change; `run_server.cmd` does the same on the hidden
  scheduled-task path and writes the finding to `server.log`, the only place
  anyone looks after a silent failure at boot.
- **The host could not save `server.toml`.** An elevated install left it owned by
  Administrators and merely readable, so "Edit server config" opened Notepad on a
  file that could not be saved - and the port is the one setting most likely to
  need changing. `Permissions: users-modify` is granted on the config file and on
  `data\` and `backups\`, and deliberately NOT on `caddy.exe`, which stays
  admin-only so a standard user cannot rewrite the executable an elevated
  `/rl highest` logon task launches.

- **Every Windows tool is now called by full path.** `C:\Windows\System32` is
  not on the PATH on Larry's PC, so every launcher failed with *'chcp' is not
  recognized as an internal or external command* - and `tasklist`, `taskkill`,
  `findstr`, `find`, `powershell`, `wscript` and `notepad` would all have failed
  the same way, silently changing what each script did. All eight `.cmd` files
  now resolve through `%SystemRoot%\System32`, the VBS launches `%ComSpec%`
  rather than a bare `cmd`, and the Start Menu config shortcut uses
  `{sys}
otepad.exe`.
- **A capitalised username is converted, not refused.** Usernames are a-z only,
  and typing `Larry` got the bare refusal *the username must be 1..32 characters
  of a-z, 0-9 and underscore* with no hint of what to do. Both wrappers now
  lowercase it in pure batch (no external tool - see above) and echo the name
  being used. Capitals belong in the display name, which is prompted separately
  and accepts any language.

### Changed

- `RUNBOOK.md` §1 — the `--create-admin` invocation is corrected. It showed the
  config path before the flag and a password as an argument; `SERVER_APP.make`
  matches `--create-admin` on **argument 1**, takes the config path as argument
  3, and prompts for the password. As written it would have started the server
  instead of creating an account.

### Notes

- Contracts in `src/` were not touched. The new flag discharges
  `CHAT_SERVICE.create_user`'s existing preconditions; it does not change them.
- `data_dir` in the shipped `server.toml` is **relative** on purpose, and the
  launchers set the working folder. `CADDY_FRONT_DOOR` resolves both
  `caddy.exe` and the Caddyfile against the working directory, and
  `PATH.extended` refuses a rooted argument — a precondition a lean build
  would not catch. See `installer/README.md`.
- Uninstall keeps the room. There is no `[UninstallDelete]`: the data folder,
  `server.toml`, the backups and each member's `client.toml` all survive,
  matching the fleet's stance in `RixGPT.iss` and `RixQwen.iss`.
- Automatic replication between hosts and epoch fencing remain deferred
  (D-017). The standby is a cold, hand-fed copy, and the hosting guide states
  the one rule that keeps it safe: only one server runs at a time.
