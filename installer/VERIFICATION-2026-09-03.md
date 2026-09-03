# SimpleChat installer — verification record, 2026-09-03

The **first-run finish sequence**: for a hosting install, pressing Finish now
creates the first administrator, starts the server and confirms it answers, and
only then opens the chat window.

Machine `JACKJACK`, user `JACKJACK\LJR19`, Windows 11 Pro 10.0.26200,
Inno Setup 6.6.1, branch `phase7/first-run`, worktree
`D:\prod\simple_chat_wt_firstrun`, payload the staged 0.1.1 build copied from
`D:\prod\simple_chat\installer\src\` (server `SimpleChatServer.exe`,
5,850,112 b).

**Every step below ran under the `/DVERIFY=1` identity, silently, from
PowerShell.** No window was opened on the desktop, no keystroke was synthesised,
and every console was driven with redirected stdin and stdout — Larry was typing
at this machine throughout. Nothing was killed except by PID, and every PID
killed is named in this file.

---

## 0. The rules this run was held to

Carried forward from `VERIFICATION-2026-09-02.md`, and all four honoured:

| | |
|---|---|
| A test install is a different product | every command used `SimpleChat-Setup-VERIFY.exe` |
| Never drive the installer from Git Bash | every `/FLAG` was passed from PowerShell |
| Kill by PID, never by image name | PIDs 41860, 31676, 50336, 20256, 36400, 11600 — all mine, all recorded at launch |
| Never touch the real identity | `C:\ProgramData\SimpleChat`, `C:\Program Files\SimpleChat`, `%APPDATA%\simple_chat` and the task `SimpleChat Server` were read for state and never written |

Guard readings, before and after everything below: `C:\ProgramData\SimpleChat`
**absent** (it was removed by Revo on Larry's PC, see the chronicle),
`C:\ProgramData\SimpleChat-verify` **absent**, `C:\Program Files\SimpleChat`
**absent**, `%APPDATA%\simple_chat` **present and unmodified**, no scheduled task
under either name, no `SimpleChatServer.exe` or `caddy.exe` running.

---

## 1. What the wizard now does, and what was measured about how

`[Run]` entries execute **in the order they are listed**, and `waituntilterminated`
holds the next one until the previous has ended (Inno Setup help, *[Run] and
[UninstallRun] sections*, under `Flags: waituntilterminated`). That is what makes
the finish page a sequence:

| order | entry | flags | Check |
|---|---|---|---|
| 1 | `{cmd} /c "{app}\create_admin.cmd"` | `postinstall skipifsilent waituntilterminated runasoriginaluser`, `Components: server` | `RoomHasNoDatabase` |
| 2 | `{cmd} /c "{app}\start_server.cmd" /nopause` | same flags, `Components: server` | — |
| 3 | `{app}\SimpleChat.exe` | `postinstall skipifsilent nowait runasoriginaluser`, `Components: client` | — |
| 4 | `{app}\HOSTING-GUIDE.html` | `shellexec postinstall skipifsilent nowait runasoriginaluser`, `Components: server` | — |

`runasoriginaluser` on all four. The load-bearing case is step 2: a server started
by the **elevated** installer could not afterwards be stopped by “Stop server”
from the Start Menu, because a non-elevated `taskkill` cannot touch an elevated
process.

**The postinstall entries cannot be exercised silently** — `skipifsilent` is what
they are for, and an interactive wizard cannot be driven without opening windows
on Larry's desktop. So §5 drives the three scripts by hand instead, and the
sequencing itself is left to §7's human check.

---

## 2. (i) The script compiles with zero warnings

```
ISCC /DVERIFY=1 installer\SimpleChat.iss   ->  exit 0
      Successful compile (13.250 sec)
      D:\prod\simple_chat_wt_firstrun\installer\SimpleChat-Setup-VERIFY.exe
      37,929,440 b
```

A case-insensitive search for `warning`, `hint` or `error` across the whole of
the compiler output returns **nothing**. The figures above are the final
compile, with every template change staged; an identical earlier compile of
3,912 lines was searched the same way, with the same result.

One error was fixed on the way, and it is worth recording because it will catch
the next person: **ISPP expands `{#Macro}` inside Pascal comments too.**
`{ True when {#ServerRoot}\server.toml ... }` became
`{ True when {commonappdata}\SimpleChat-verify\server.toml ... }`, and since
Pascal comments do not nest, the `}` of `{commonappdata}` closed the comment and
the rest of the sentence was compiled as code. Never put an ISPP macro in a
`{ }` comment.

---

## 3. (ii) A silent per-user client install, and its uninstall

`/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CURRENTUSER /NOICONS /DIR=… /COMPONENTS=client /LOG=…`

```
setup exit = 0
installed:  SimpleChat.exe 4,729,856 · cairo.dll 2,359,808 · README.txt ·
            THIRD-PARTY.md · LICENSE-ASSETS.md · LICENSE-SIMPLECHAT.txt ·
            client.toml.template · unins000.exe/.dat ·
            assets\noto-emoji\png\128: 3,768 files
uninstall key HKCU\…\{9D4E7B15-…}_is1  registered,  DisplayName "SimpleChat (verify)"
SimpleChatServer.exe present = False      (per-user: no server component, by design)
server_root.cmd written      = False      (no server component)
C:\ProgramData\SimpleChat-verify created = False
uninstall exit = 0 · install folder gone = True · uninstall key gone = True
%APPDATA%\simple_chat-verify KEPT = True  (uninsneveruninstall, as designed)
```

The 2026-09-02 leftover — a stray `sw_session.log` keeping `{app}` alive — did
not recur: the folder is gone entirely.

---

## 4. (iii) `/TASKS=claudemember`, and the `[Code]` paths behind it

A silent per-user install with `/COMPONENTS=client,server /TASKS=claudemember`:

```
setup exit = 0
log lines containing "Exception", "Runtime Error" or "Internal error" = 0
server.toml written anywhere            = False
C:\ProgramData\SimpleChat-verify exists = False
server_root.cmd written                 = False
log: "SimpleChat: /COMPONENTS asked for the server, but this is a per-user
      install, where the server component does not exist…"
```

So the `[Code]` path does not crash and writes no config where none was created.

**But a per-user install never reaches the interesting code**, because the
`claudemember` task's `Check` is only asked when the `server` component exists,
and that component only exists in an administrator install — which cannot be
started without a UAC prompt, i.e. a window. So the functions were exercised
directly, by a generated probe (`scratchpad\probe\codeprobe.iss`) that carries
**every `[Code]` line above `CurStepChanged` copied verbatim out of
`SimpleChat.iss`** and calls them against a scratch room:

```
SimpleChat: Claude Code found for the installing user - the @claude checkbox starts ticked.
PROBE claude-on-this-pc = 1
PROBE claude-missing    = 0
PROBE room-has-no-db    = 1
SimpleChat: wrote …\app\server_root.cmd
PROBE --- fresh config: the block must be written ---
SimpleChat: @claude enabled in …\room\server.toml (9 lines uncommented).
PROBE --- pre-existing config: it must be REFUSED ---
SimpleChat: @claude was asked for, but server.toml was already on this PC. An
existing config is never modified; the participants block is left commented in
place for the host to uncomment.
```

and the file it produced ends exactly as the template's commented block reads:

```toml
[[participants]]
handle = "@claude"
kind = "claude_code"
engine = "data/participants/claude"
bot_username = "claude_bot"
display_name = "Claude"
requests_per_hour = 5
max_characters = 1200
timeout_seconds = 120
```

**Why post-processing and not a second template.** One template instead of two
that have to be kept in step, and the block the host reads afterwards is the same
block, in the same place, under the same paragraph of explanation. A second
variant would have doubled the file that carries every hosting instruction in the
product for the sake of nine lines.

A separate measured finding that shaped the `[Tasks]` design:
**`WizardSelectTasks` called from `InitializeWizard` does nothing.** A throwaway
probe showed the wizard's task list is not built yet at that point and `/TASKS`
is applied afterwards, so the call is thrown away (`alpha=0 beta=0` before and
after, for `beta`, `*beta` and `*nosuchtask,beta` alike; no exception raised).
What does work — and is what shipped — is **two `[Tasks]` rows with the same
`Name` and mutually exclusive `Check` functions**: the ticked row when Claude
Code is on the PC, the unticked row when it is not. Measured: `F=1 → dup=1`,
`F=0 → dup=0`, one compile, no warning.

---

## 5. (iv) The three scripts, driven by hand against a scratch room

Scratch `{app}` and scratch room under the session scratchpad; `server_root.cmd`
written into the scratch `{app}` byte-for-byte as `WriteServerRootFile` writes it;
`port = 8097` in the scratch `server.toml`; the staged 0.1.1 `SimpleChatServer.exe`.

```
1a create_admin.cmd, empty username   exit 1  "No username given. Nothing was created."
                                      no "A=a", no store created
1b SimpleChatServer.exe --create-admin larry   exit 0  administrator "larry" created
2  create_admin.cmd, room now open    exit 0  "This room already has its first
                                      administrator."  no prompt, store untouched
3  start_server.cmd /nopause          exit 0  port : 8097 · "The server is up. It
                                      answered: {"store":true,...}" · PID 15252
                                      independent /health = 200 (same body)
4  start_server.cmd /nopause (again)  exit 0  "The server is already running."
5  stop_server.cmd                    exit 0  "Stopped."   0 servers left
6  decoy listener on 8097, then
   start_server.cmd /nopause          exit 1  "PORT 8097 IS ALREADY IN USE by
                                      pwsh (PID 17264)"   nothing launched
7  same server, @claude config        exit 0  /health 200 · "bot created id=2" ·
                                      "dispatcher: sandbox ensured"  · then stopped
```

Line 7 is the answer to *“the server must start with that config”*: it does, on a
PC where `claude` is on the PATH, and it creates the bot member and its sandbox
on first start.

### 5.1 Three defects this run found, all now fixed on this branch

**(a) Pressing Enter at the username prompt produced gibberish.**
`set /p` leaves the variable **undefined** on an empty line, and `!ADMIN:A=a!` on
an *undefined* variable does not expand to nothing — it expands to the literal
text `A=a`. The “No username given” guard sat *after* the lowercasing chain, so it
could never fire: the script printed `Using username: A=a` and then an error about
`a-z` and underscores. The guard now runs **before** the chain, with the old one
kept as a second net for an answer of nothing but spaces. This was on `main`, and
it is the first prompt the new finish sequence puts in front of a host.

**(b) The port was never read out of `server.toml`.** `for /f (' … ')` runs its
command through `cmd /c`, and cmd strips the first and last quote of any `/c`
string that begins with a quote and holds more than two. So

```
'"%SYS%\findstr.exe" /r /c:"^ *port *=" "%ROOT%\server.toml"'
```

arrived as `C:\Windows\System32\findstr.exe" /r /c:" *port` — not a command at
all. Reproduced in a plain console, both forms side by side, against a config
saying `port = 8097`:

```
QUOTED-FORM-PORT=[8090]        <- the shipped form: silently the default
UNQUOTED-FORM-PORT=[8097]      <- the fix
```

The same shape defeated the **port-collision** loop in both `start_server.cmd`
and `run_server.cmd`, which is worse: quoted, it ran nothing, so a collision was
never detected and the server was launched at a door already taken. Both files
now leave the executable path bare (System32 has no space in it) and keep the
quotes on every argument. §5's lines 3 and 6 are that fix working.

**(c) `timeout.exe` does not return when stdin is redirected or `NUL`.** It wedged
two verification runs. The `/nopause` hold is now `ping -n N 127.0.0.1`, the batch
sleep that has no opinion about stdin. It cannot be cut short by a keypress — a
fair trade for a step that must never wedge the installer.

### 5.2 One thing that cannot be driven, and is not a defect

**`chcp 65001` breaks `set /p` when stdin is redirected.** Isolated to two lines:

```
A: [default cp] got=[larry]
B: [chcp 65001] got=[]
```

It is cmd's own behaviour, it is unchanged from `main`, and it does not touch a
human typing at a real console — which is why the code page is there at all
(a display name in Hebrew or Greek has to survive being typed). It only means the
username prompt cannot be fed from a file, so §5 line 1b makes the administrator
by driving the executable directly, exactly as `VERIFICATION-2026-09-02.md` §5.2
did.

---

## 6. A hazard this change made urgent, and how it is closed

Until now every launcher said `set "ROOT=%ProgramData%\SimpleChat"` outright.
That was survivable while a human ran them from the Start Menu. It stops being
survivable the moment **the wizard runs two of them by itself**: a `/DVERIFY`
build would have created an administrator in, and started a server against, the
**real** room — the exact class of collision the verify identity exists to
prevent.

So `[Code]` now writes `{app}\server_root.cmd`, one line naming the room's home
folder, and `create_admin.cmd`, `start_server.cmd` and `run_server.cmd` read it.
An environment `SIMPLECHAT_ROOT` wins over it, which is how §5 drove them against
a scratch room; the old hard-coded path is still the fallback. `[UninstallDelete]`
sweeps the generated file, because `[Files]` has no record of it and one stray
file keeps a whole install folder alive.

**Still open, and deliberately left for Larry:** the other five launchers
(`create_user`, `reset_password`, `backup_room`, `restore_backup`, `view_log`)
still name `%ProgramData%\SimpleChat` themselves, and `stop_server.cmd` kills by
image name, which no root can scope. A verify build's *Start Menu* is therefore
still aimed at the real room. Nothing in this branch runs them, but the next
person to touch these files should finish the job.

---

## 7. What only Larry can check

- **The sequence as a sequence.** That step 2's console appears only after step
  1's has closed, and the window only after both, cannot be proved without
  running the wizard interactively — which is a window on his desktop.
- **The three checkboxes on the finish page**: their wording, and that (a) and
  (b) are ticked when shown.
- **The @claude checkbox** in an administrator install: that it reads
  *“found on this PC: yes”* and starts ticked, and that after Finish the
  `[[participants]]` block is uncommented in `C:\ProgramData\SimpleChat\server.toml`.
- **The reworked finish message**, which now says what is about to happen rather
  than listing three chores.
- Everything still owed from `VERIFICATION-2026-09-02.md` §4: the window's
  pixels, the router, a real DuckDNS name and the first live certificate.
