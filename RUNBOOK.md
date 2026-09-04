# RUNBOOK — the first conversation

The console smoke for Phase 4 Task 10: the window exists, the tests are green, and the
one thing no headless assault can prove is that the **pixels** are right. This is the
script for that. Everything below is typed at a Git Bash prompt in
`D:/prod/simple_chat` unless it says otherwise.

Allow about twenty minutes the first time — two builds at three to six minutes each.

---

## 0a. If you installed with the installer instead

Steps 0 and 1 below build and mint by hand, from the source tree. **An installed
copy does both for you.** Since 0.1.2, finishing an install with the hosting box
ticked runs three things in order, each waiting for the one before it:

1. a console asks you to **create the first administrator** — skipped when this
   PC already has a room, i.e. when
   `C:\ProgramData\SimpleChat\data\simple_chat.db` is already there;
2. the **server starts**, and says whether it answered `/health`, or names the
   program holding the port;
3. the **chat window opens**, with the account you just made to sign in with.

The hosting guide opens last, behind the window. Any of the three can be unticked
on the installer's last page and done afterwards from the Start Menu, under
**SimpleChat Server**.

So from an installed copy, **skip to §2 (Start the client)** — you already have a
server and an account. The rest of §0 and §1 are for driving the source tree.

Two things worth knowing while you are in there:

- **`Start server` from the Start Menu pauses at the end; the installer's copy
  does not.** The installer passes `start_server.cmd /nopause`, which prints the
  same things and holds the window open long enough to read, then closes itself
  so the sequence can go on.
- **`@claude` may already be configured.** If you ticked the `@claude` box and
  the installer created `server.toml` for you, the `[[participants]]` block is
  already uncommented — §4 will just work. If you had a `server.toml` before, the
  installer left it alone on purpose, and §4's block is yours to uncomment.

---

## 0. Build both halves

```bash
cd /d/prod/simple_chat
/d/prod/ec.sh test -config simple_chat.ecf -target simple_chat_server
cp EIFGENs/simple_chat_server/F_code/simple_chat.exe /d/prod/simple_chat/dist/simple_chat_server.exe 2>/dev/null || \
  { mkdir -p dist && cp EIFGENs/simple_chat_server/F_code/simple_chat.exe dist/simple_chat_server.exe; }

/d/prod/ec.sh test -config simple_chat.ecf -target simple_chat_client
apps/client/stage_client.sh
```

`stage_client.sh` builds `dist/simple_chat_client/` and puts four things beside the exe:
`cairo.dll` (without it the client does not launch **at all** — an import library is
resolved at process start), `assets/noto-emoji/png/128/` (3,768 PNGs; without them the
robot is a box, but nothing crashes), `LICENSE-ASSETS.md`, and a `client.toml` template.

> **Every finalize wipes `F_code`.** Re-run `stage_client.sh` after every client build.

---

## 1. Start the server, with an account to log in with

The first time only, mint the first admin. Pick a real password; it is hashed with
PBKDF2 at 600,000 iterations and never stored in clear.

```bash
mkdir -p /c/Users/Public/simple_chat/data
cat > /c/Users/Public/simple_chat/server.toml <<'TOML'
port = 8080
data_dir = "C:/Users/Public/simple_chat/data"
TOML

dist/simple_chat_server.exe --create-admin larry C:/Users/Public/simple_chat/server.toml
```

The flag comes **first**: `SERVER_APP.make` matches `--create-admin` on argument 1 and
takes the config path as argument 3. Written the other way round, argument 1 is a path
that does not start with `--`, so the server would quietly *serve* instead of creating
anything. There is no password argument either — it prompts for a display name (press
Enter for the username) and then for the password twice.

**The password shows as dots, one per key.** It is read with `SIMPLE_CONSOLE.read_masked_line_default`
(simple_console 1.1.0), which clears `ENABLE_ECHO_INPUT` for the read and puts the
console mode back on every exit path; Backspace still edits and Enter still ends the
line. The display name is **not** hidden — you have to be able to see the name you are
giving yourself. When standard input is **redirected** from a file or a pipe (which is
how the shipped `.cmd` wrappers and the installer's verification script feed one in)
the line is read the ordinary way and no console mode is touched: there is no terminal
to hide it from. If standard input **ends** before a password arrives, the command
changes nothing and leaves with **exit status 1**, so a wrapper whose here-document ran
short is told so instead of being handed a silent success.

To add anyone else afterwards, same shape — there is no self-registration:

```bash
dist/simple_chat_server.exe --create-user nick C:/Users/Public/simple_chat/server.toml
```

If anyone forgets their password — including the only admin — reset it. Same
shape again, and no display name is asked for; the account already has one:

```bash
dist/simple_chat_server.exe --reset-password nick C:/Users/Public/simple_chat/server.toml
```

It prompts for the new password twice — showing each entry as dots, exactly as the two
create flags do — and **signs out every live session that
member holds** — which is the point: a password somebody else has learned is
taken away, not merely replaced. A username the room does not know, a username
that names a bot (bots have a token, not a password), two entries that differ,
or an entry below `password_minimum` is refused with a line saying so and a
**non-zero exit status**, so a wrapper can tell a refusal from a reset. Nothing
is changed on any of those paths.

**Stop the server first**, for all three flags. They open the SQLite store
directly and nothing sets a busy timeout, so a write racing the running
server's comes back `SQLITE_BUSY`; for a reset that means the new password
never lands, the old one still works, and the sessions the running server holds
are never revoked. The shipped launchers check for a running server and refuse.

Then run it. **Redirect its stdout to a file, never into a pipe** — a console write into
an undrained pipe wedges the server mid-request: `/health` keeps answering 200 and every
login times out. This was found the hard way.

```bash
cd /d/prod/simple_chat
cmd //c "dist\simple_chat_server.exe C:\Users\Public\simple_chat\server.toml > C:\Users\Public\simple_chat\server.log 2>&1" &
```

Check it is up before going on:

```bash
curl -s http://127.0.0.1:8080/health
# {"store":true,"last_event_id":0}
```

---

## 2. Start the client

From a **command prompt**, not from Explorer (so you can see anything it says):

```
cd D:\prod\simple_chat\dist\simple_chat_client
SimpleChat.exe
```

The login window comes up. The **Server** box is prefilled with whatever
`SERVICE_LOCATOR` found: with the server running on this PC that is
`http://127.0.0.1:8080`. Type the name and password you minted in step 1, leave
**Remember me on this PC** ticked, and press **Log in**.

*If the login is refused*, the reason appears on the line above the buttons — it is the
server's own message, not a guess. A refused address (plain `http://` to anywhere that
is not this machine) is refused before a byte leaves the PC.

---

## 3. Post

The room pane opens: room name and connection line across the top, bubbles in the
middle, the composer at the bottom. If a bot is in the room, the first thing in the
thread is a system bubble naming it — see step 4 below before you go looking for how
to talk to it.

Type a line and press **Enter** to send. The composer wraps as you type — it is not
the one-line field it used to be — and grows with what you type, up to five lines;
past that it scrolls internally instead of growing the window. **Shift+Enter** inserts
a newline in the message instead of sending it, so a multi-line question stays one
message. Enter with nothing typed, or with only Shift+Enter'd blank lines, sends
nothing.

Your own line comes back **through the poller**, not from the composer — that is the
design, and it is also the proof: if the bubble appears on the right, the whole loop
(post → server → event log → long-poll → inbox → presenter → pane) ran.

---

## 4. Make `@claude` answer

If the room has a bot member, the pane says so the moment it opens — a system bubble
at the top of the thread naming the bot's real `@username` from the roster (never a
name typed into the client), such as "Address the room's assistant by starting a line
with @claude." That bubble is the whole discoverability fix: before it existed, the
only way to learn the convention was to be told outside the app.

Type, in the room:

```
@claude what is the Hebrew word for "remember"?
```

The match is case-insensitive — `@Claude` and `@CLAUDE` work exactly as well as
`@claude` — so a capitalized start-of-sentence habit does not silently fail.

Two things should happen. First, an ephemeral status line under the thread —
`Claude is thinking…` — because the participant dispatcher publishes one while the
engine runs. Then a bubble from `Claude:` carrying the 🤖 marker its class invariant
requires. It runs on the host's own Claude Code subscription, sandboxed; expect a few
seconds.

### Where the handle may stand — the addressing rule

The handle does **not** have to start the line. A message addresses a participant when,
**anywhere in its text**, an `@` stands that is *not itself preceded by a handle
character* (`a-z`, `0-9`, `_`, `-`), the unbroken run of handle characters after it
**equals** that participant's handle or one of its `@`-shaped aliases, and that run
**ends the text or is followed by a character that is not a handle character**. Case
never matters.

| Message | Addresses `@claude`? |
| --- | --- |
| `@Claude what is 2+2` | yes — at the start |
| `hello @Claude what is 2+2` | yes — in the middle |
| `and times 3 @claude` | yes — at the end |
| `@claude:` / `@Claude,` / `so what @claude?` / `(@CLAUDE)` | yes — the mark after it is not a handle character |
| `hi @claudette` | **no** — the run is `claudette`, a different word |
| `hi @claude_bot` | **no** — `_` is a handle character, so the run is `claude_bot` |
| `write to bob@claude` | **no** — the `@` follows a handle character |
| a bot's own message naming `@claude` | **no** — bot-authored events are never requests, so nothing can loop |

Name **two** bots in one message and **both** answer, each exactly once, in the order
they are named. The same message delivered twice still answers once per bot.

A colon alias (`Claude:`, `ROBOT:`) keeps the older rule: it addresses only at the very
**start** of the message, because anywhere else it is an ordinary word.

The handle is taken **out of the question**: `hello @Claude what is 2+2` reaches the
engine as `hello what is 2+2`, and `so what @claude?` as `so what?`.

### Memory — `context_messages`

Each `[[participants]]` entry may say how many of the room's **most recent messages**
come with every request:

```toml
context_messages = 12    # optional, 0..50; 12 when not given
```

The dispatcher reads them from the room itself, oldest first, each prefixed by its
sender's display name — the bot's own replies included — and puts them in front of the
question, so a follow-up (`and its cube root?`) is answerable. It is read from the
store, not from anything the dispatcher remembers, so it survives a restart and holds
the room's last N messages whether or not the bot was there when they were posted.
`context_messages = 0` takes the window away and the prompt is exactly what it was
before. Tool participants (`bible_tool`, `shape_tool`) ignore the window: they answer a
lookup, not a conversation.

Under that, `@claude` also continues the room's **CLI session** with
`claude -p --resume <session id>`, kept per room, so one room never continues another's.
A turn that answered nothing drops the kept session and the next turn starts fresh on
the context window alone.

> **Known, on `main` as well as here:** the dispatcher answers the **first** `claude -p`
> of a server run and then freezes on the **second** — no child process is started, no
> error is logged, and the rest of the server keeps serving. Reproduced with two leading
> `@claude` turns on `main`'s own binary, and with a *second participant's first* call,
> so it is neither `--resume` nor the context window nor the addressing rule. Until it is
> fixed (it is below simple_chat, in the process/engine path), an on-going conversation
> cannot be demonstrated end to end — restarting the server restores one answer.
**Then ask it two more things, one straight after the other.** Until
`phase4/second-call-freeze` the dispatcher answered the *first* question of a
server run and never answered another — no child process, nothing in the log, the
rest of the server serving normally, so the only symptom was a bot that had
stopped talking. It was the answer's own post ringing the dispatcher back into
itself mid-drain; the bus no longer rings anyone for their own post. Three
questions in a row is the check, and spacing them out does **not** substitute for
it: the old defect fired on every answer, four seconds apart or two milliseconds.

If a bot ever does go quiet again, the log will now say so — `dispatcher: the
drain raised; the flag is cleared so the next wake drains again`, with the reason.
Silence used to be the whole of the evidence.

---

## 4b. Ask it for a summary, and go away and come back

Two features, one endpoint. Neither of them ever posts to the room.

**On demand.** Type, in the composer:

```
@claude sum last 10 minutes
```

That line is **not** posted. Nobody else in the room sees it, and no event is
stored. The summary comes back as a centred bubble in your window alone. Try
`@claude recap` and `@claude catch me up` too — and then check the other half of
the rule by typing `@claude can you write a summary of the roof job`, which **is**
a question and **should** appear in the room like any other message. The verb has
to be at the front, past the mention; that is the whole rule.

**On returning.** Click away to another window, leave it for five minutes while
someone (or `@claude`) puts at least five messages in the room, then click back.
A catch-up bubble appears, summarising exactly the gap. Both thresholds are in
`%APPDATA%\simple_chat\client.toml` — `catch_up_away_seconds` (default 300) and
`catch_up_minimum_messages` (default 5) — and setting either to 0 switches
catch-up off without touching the on-demand ask. Lower them both to try it
without the wait.

A summary spends `summaries_per_hour` (default 12, in `server.toml`), which is a
**separate** budget from `requests_per_hour`: catching up never costs you the
right to ask a question.

---

## 4c. The menu bar, and the keys

Across the top: **File**, **Edit**, **Room**, **Help** — each with its mnemonic letter
underlined (`F`, `E`, `R`, `H`).

- **Edit** — Cut `Ctrl+X`, Copy `Ctrl+C`, Paste `Ctrl+V`, Select All `Ctrl+A`. These are
  **window-wide** now: they work wherever the caret is, and they go to whichever half of
  the room you are looking at. Click in the composer and Copy takes the line you typed;
  click a bubble and the same Copy takes the bubble. Items grey live — with a bubble in
  focus, Cut and Paste are dead, because nothing removes text from a transcript or puts
  text into it. `Ctrl+Z` and `Ctrl+Y` are deliberately NOT accelerators, so the composer's
  own undo stack still has them. (Right-clicking the composer offers the same menu; it
  always did.)
- **Room** — *Summarize the room now* `Ctrl+M`, *Catch me up on what I missed* `Ctrl+U`.
  The typed forms still work and are spelled out under **Help > How to address the
  assistant**.
- **Help > About** names the version, the build date and the fleet this build was
  compiled against. All three come from `CHAT_VERSION`, the one place any of them
  is written — **and the installer declares the same number at**
  **`installer\SimpleChat.iss` line 48. Changing a version means changing both.**

**Selecting and copying a bubble.** Press and drag inside a bubble to select; double-click
takes a word; Escape clears; right-click offers Copy / Select Message / Select None. A
selection lives inside ONE bubble by design — a range spanning three speakers has no honest
text to hand the clipboard. With a bubble in focus, `Ctrl+A` takes the whole of that one
message.

**`Alt+F` opens File.** So do `Alt+E`, `Alt+R` and `Alt+H` — and once a menu is open, a bare
letter picks the item that underlines it (`Alt+F`, then `C` closes the room). Press `Esc` to
close a menu without picking anything. This needed simple_shell **1.9.3**, which delivers
Alt+letter at last; `Alt+F4` still closes the window and `Alt+Space` still opens the system
menu, because the shell deliberately leaves those to Windows.

**The per-message menu.** Right-click a bubble. Under the Copy items you get **Reply**,
eight emoji, **Edit** and **Delete**.

- **Reply** puts `Replying to <name>: <the first 60 characters>` above the composer. Type
  and press Return; the answer arrives carrying a one-line quote of what it answers.
- **An emoji** puts a chip under the bubble. Click the chip to take it back; click one
  somebody else started to join it. The number on it is how many people have it.
- **Edit** — your own messages only — loads the words that are ON SCREEN into the composer
  so you change them rather than retype them. Return sends the change; **Escape cancels**.
  The bubble then reads the new words with `edited` under them, and so does everyone
  else's copy of the room.
- **Delete** asks first, in the strip above the composer: *Delete this message? Choose
  Delete again to confirm.* The second Delete does it, and the bubble becomes `message
  deleted` **without moving** — the order of a thread is part of its record, and a bubble
  that vanished would silently rewrite who answered whom.

**Check the greying while you are here.** On somebody else's message Edit is grey and
Delete is live if you are an admin, grey if you are not — greyed, not hidden, on purpose.
On a tombstone every one of the four is dead and the emoji are not offered at all.

**If the chips draw as squares, look at the folder, not the code.** `SW_SHAPING` resolves
emoji artwork BESIDE THE RUNNING EXECUTABLE. Run the installed client, or an EIFGENs build
with `assets\noto-emoji` staged beside it. This has already cost one false alarm.

**Check the lines while you are here.** Ask `@claude` for a numbered list — "@claude give me
three steps for laying a course of block" — and look at the bubble. The steps must be on
three LINES, and there must be no empty box anywhere in the reply. Those boxes were every
newline being shaped as a glyph; the workaround that flattened a reply into one paragraph to
avoid them is retired, and this is the check that it was safe to retire.

---

## 5. THE ACCEPTANCE LINE — the reason this task waited a month

Post exactly this, and then **look at it**:

```
שלום 🤖 Χριστός
```

Three things have to be true on the screen, and all three are things cairo's toy text
API cannot do:

1. **The Hebrew is RIGHTMOST.** The line's first strong character is Hebrew, so UAX #9
   makes the paragraph right-to-left and puts the runs on the screen in the visual order
   *Greek, robot, Hebrew* — left to right. If the Hebrew is on the left, or the letters
   are in the wrong order, bidi is not running.
2. **The robot is a robot** — the Noto picture, not a box, not a question mark. If it is
   a box, the artwork is not beside the exe: re-run `stage_client.sh`.
3. **The Greek is intact** — `Χριστός`, with the tonos on the omicron, in a face that
   has polytonic Greek. Not tofu, not stripped accents.

Post a mixed line too, so the *bubble* is measured and not just the run:

```
Nick said שלום and then 🤖 answered Χριστός — all on one line
```

The bubble must be tall enough for the emoji: its height comes from
`layout.total_height`, never a line count times a constant.

---

## 6. Resize

Drag the window's right edge in and out, slowly and then fast.

- The bubbles must **re-wrap when the drag settles**, not on every frame (R10: shaped
  widgets keep their layouts while `is_resize_storm` holds).
- A message arriving *mid-drag* must still appear — a content change never waits.
- Nothing may flash black at the growing edge (the class brush is on the theme's ground).

Post a line while dragging if you have a second machine or a `curl` handy:

```bash
curl -s -X POST http://127.0.0.1:8080/rooms/1/messages \
  -H "Authorization: Bearer <a token>" -H "Content-Type: application/json" \
  -d '{"body":"arrived mid-drag"}'
```

---

## 7. Close and reopen — the remembered session

Close the window with the X. Then, from the same command prompt:

```
SimpleChat.exe
```

**No login window.** It should go straight to the room. That is `CLIENT_CONFIG.load_session`
unsealing the DPAPI blob and `CHAT_CLIENT.resume` proving it at `GET /me`.

Two things worth checking while you are here:

```bash
cat "$APPDATA/simple_chat/client.toml"
```

- there is a `session = "..."` line, and it is **Base64 of DPAPI ciphertext** — not 64
  hex digits. If you can read a token there, stop and tell me.
- `window_x` / `window_y` / `window_width` / `window_height` match where you left the
  window.

To prove the other half, untick **Remember me** on a later login: the client logs out on
close and the next launch asks for a password.

---

## 8. The tray, and unread

With the room window **behind** something else, have someone else (or `curl`) post a
line. You should get a balloon in the notification area and the tray tooltip should read
`(1) simple_chat`. Bring the window to the front: the count clears.

The count also appears in the window's own header strip, beside the room name. It is
**not** in the title bar — simple_shell publishes no `SetWindowText`, and simple_shell is
not this project's to change.

---

## 9. Shut down

Close the client window. Then:

```bash
taskkill //F //IM simple_chat_server.exe
```

(Or `taskkill //F //IM simple_chat.exe` if you ran the server straight out of `F_code` —
but be careful: *every* target of this system finalizes to `simple_chat.exe`.)

---

## What to report back

- Which of the three acceptance-line properties held, and which did not.
- Whether `@claude` answered, and how long it took.
- Anything the pane said on its error line.
- The contents of `C:\Users\Public\simple_chat\server.log` if the server misbehaved, and
  of `sw_session.log` (written beside the client exe) if the window did.
