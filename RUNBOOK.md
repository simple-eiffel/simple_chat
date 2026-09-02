# RUNBOOK — the first conversation

The console smoke for Phase 4 Task 10: the window exists, the tests are green, and the
one thing no headless assault can prove is that the **pixels** are right. This is the
script for that. Everything below is typed at a Git Bash prompt in
`D:/prod/simple_chat` unless it says otherwise.

Allow about twenty minutes the first time — two builds at three to six minutes each.

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

dist/simple_chat_server.exe /c/Users/Public/simple_chat/server.toml --create-admin larry "Larry" "your real password here"
```

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
middle, the composer at the bottom. Type a line and press **Enter** (or click **Send**).

Your own line comes back **through the poller**, not from the composer — that is the
design, and it is also the proof: if the bubble appears on the right, the whole loop
(post → server → event log → long-poll → inbox → presenter → pane) ran.

---

## 4. Make `@claude` answer

Type, in the room:

```
@claude what is the Hebrew word for "remember"?
```

Two things should happen. First, an ephemeral status line under the thread —
`Claude is thinking…` — because the participant dispatcher publishes one while the
engine runs. Then a bubble from `Claude:` carrying the 🤖 marker its class invariant
requires. It runs on the host's own Claude Code subscription, sandboxed; expect a few
seconds.

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
