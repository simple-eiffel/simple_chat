# Building the SimpleChat installer

`SimpleChat-Setup.exe` — one installer, two components: the chat window
(everyone) and the server (the host, and any standby host).

---

## Rebuild it

Three steps, from the project root. **Run the third one from PowerShell**, not
from Git Bash — see the warning below.

```bash
# 1. Build both release targets (~2 minutes; `release' makes lean + dbc each)
/d/prod/ec.sh release -config simple_chat.ecf -target simple_chat_server
/d/prod/ec.sh release -config simple_chat.ecf -target simple_chat_client

# 2. Stage installer/src/ from those builds, the shared libraries and the templates
installer/stage_payload.sh
```

```powershell
# 3. Compile (PowerShell)
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\SimpleChat.iss
```

Output: `installer/SimpleChat-Setup.exe` (~36 MB). Both `installer/src/` and
the setup executable are gitignored — the payload is built, never committed.

`stage_payload.sh` ships the **lean** executables (contracts compiled out — the
shipping build). The `_dbc` pair that the same `release` produces stays in
`F_code` for chasing defects and is deliberately not packaged.

### Scripted (silent) installs of a HOST

A silent install takes the installer's DEFAULT type, which is *client only*.
A host scripted with plain `/VERYSILENT` therefore gets a chat window and no
server, no `start_server.cmd`, no hosting guide - and the first sign-in looks
exactly like a server that is down. Name the type:

```powershell
Start-Process .\SimpleChat-Setup.exe -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/TYPE=host','/COMPONENTS=client,server' -Wait
```

`/TYPE=host` is not optional and `/COMPONENTS=client,server` is not a
belt-and-braces repeat of it: the type sets the default selection, the
components list is what actually goes down, and either one alone has been
enough to produce a client-only tree. Both. Every time.

Silent installs skip every post-install step (they are `skipifsilent` by
design): no first administrator is created, no window opens, and the hosting
guide does not open. After a **first** silent host install run
`create_admin.cmd` and `start_server.cmd` yourself. Found 2026-09-04 when an
agent scripted a reinstall for the host and got a client-only tree.

**One post-install step is NOT skipped, and it is the one an upgrade needs.**
A silent install over a **running** server has to stop that server to replace
its executable. Until 2026-09-04 that was the end of it: every starter was
`skipifsilent`, so `/VERYSILENT` left the room dark and said nothing, and the
host learned about it from his friends. Now:

- at `ssInstall`, before a file is copied, `StopServerFromAppDir` looks for a
  server running **from this install's own folder** — by path, never by image
  name — stops it, and remembers in `ServerWasRunning` that it did;
- a `[Run]` entry with `Check: ServerNeedsSilentRestart` launches
  `{app}\start_server_hidden.vbs` through `wscript` when, and only when,
  `ServerWasRunning and WizardSilent`.

So a silent **upgrade** puts the room back exactly as it found it, and a silent
**first** install — or an upgrade over a room the host had deliberately stopped —
starts nothing. Restarting a server nobody asked for is not an upgrade's
business.

The restart entry is deliberately `postinstall` even though no human will ever
see its checkbox: plain `[Run]` entries execute **before** `ssPostInstall`, and
`ssPostInstall` is where `server_root.cmd` is written. Started any earlier,
`run_server.cmd` would fall back to `%ProgramData%\SimpleChat` and a
verification build would restart a server against the **real room**.

It is also deliberately silent-only. On the interactive path the host already
has a visible, ticked *"Start the server now"*, and the finish briefing now
tells him plainly that the installer stopped a server that was running, so that
he knows what unticking it costs. Two automatic starters would race each other:
`wscript` returns the moment it has spawned `cmd`, well before
`SimpleChatServer.exe` exists, so the second starter would find neither a
process nor a bound port and would launch again. `start_server.cmd`'s own
guard — now path-scoped — is the backstop, not the design.

### Never drive the installer from Git Bash

MSYS rewrites leading-slash arguments into Windows paths. `/VERYSILENT` becomes
`C:/Program Files/Git/VERYSILENT`, is not recognised, and is **silently
ignored** — so a "silent" install runs the full interactive wizard. `ISCC
/DVERIFY=1` fails the same way, with the misleading *"You may not specify more
than one script filename"*. Only arguments containing `=` survive.

This cost a real incident on 2026-09-02; the whole story is in
`VERIFICATION-2026-09-02.md`. **Use PowerShell for ISCC, for Setup, and for the
uninstaller.**

---

## Verification builds

A test install must never share an identity with the real product. Compile with
the `VERIFY` define and everything collidable changes:

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DVERIFY=1 installer\SimpleChat.iss
```

| | real build | `/DVERIFY=1` |
|---|---|---|
| AppId | `{B7F42A19-…}` | `{9D4E7B15-…}` |
| AppName | `SimpleChat` | `SimpleChat (verify)` |
| install dir | `{autopf}\SimpleChat` | `{autopf}\SimpleChat-verify` |
| server root | `{commonappdata}\SimpleChat` | `{commonappdata}\SimpleChat-verify` |
| scheduled task | `SimpleChat Server` | `SimpleChat Server (verify)` |
| client config | `%APPDATA%\simple_chat` | `%APPDATA%\simple_chat-verify` |
| output | `SimpleChat-Setup.exe` | `SimpleChat-Setup-VERIFY.exe` |

Never ship a `/DVERIFY` build, and never aim a verification at the real names —
including `schtasks`.

---

## What the installer lays down

### Components

| Component | Default | Contents |
|---|---|---|
| `client` | always (`fixed`) | `SimpleChat.exe`, `cairo.dll`, 3,768 emoji PNGs, licences, `README.txt`, `client.toml` template |
| `server` | **off** | `SimpleChatServer.exe`, nine launchers, `HOSTING-GUIDE.html`, `caddy.exe`, `server.toml` template |

The server is unticked by default: most installs are a friend who only wants to
use the chat. `[Types]` lists the client-only type **first**, so it is the
default; ticking the server component switches to the custom type Inno adds
automatically.

**Promoting a client-only install to a host** — which is also how a friend
becomes a standby host — is just re-running the installer and ticking the box.
Inno restores the previously installed component selection on a reinstall, so
only the new one has to be ticked.

### The finish sequence — the order is the feature

For a **hosting** install, pressing Finish now runs three things, each waiting
for the one before it:

1. **Create the first administrator** — a console asks for a username and a
   password. Skipped when `{commonappdata}\SimpleChat\data\simple_chat.db`
   already exists, i.e. when this PC already has a room. The `Check` function is
   `RoomHasNoDatabase`, and `create_admin.cmd` carries the same test itself.
2. **Start the server** — and say whether it answered `/health`, or name the
   program holding the port if there is a collision.
3. **Open the chat window** — with something to sign in to.

The hosting guide opens last, behind the window; it is reference material, not a
step. A **client-only** install has no steps 1 or 2 and keeps "Open SimpleChat
now" exactly as before.

This order is Larry's call, and it comes from a real morning: on 2026-09-02 he
installed on a PC with no server running and no account, and the finish page did
the only thing it knew how to do — it opened the chat window, and he was met by a
sign-in that could not possibly work. For a host the window is the **last** thing
that should happen.

Inno processes `[Run]` entries in the order they are listed, and
`waituntilterminated` holds the next until the previous has ended, which is what
makes this a sequence rather than three things at once. All four entries carry
`runasoriginaluser`: the install is elevated, the Start Menu entries that run the
same scripts are not, and a server started elevated could not afterwards be
stopped by "Stop server", because a non-elevated `taskkill` cannot touch an
elevated process.

`start_server.cmd` takes **`/nopause`** for this. It prints everything it always
printed and holds the window open long enough to read, but does not wait for a
keypress — a `pause` there would stall the wizard behind a key nobody is present
to press. Without the switch, which is how the Start Menu entry runs it, it
pauses as it always has.

### The @claude checkbox

Under "Hosting:", with the server component:

> Add @claude to the room (uses this PC's Claude Code subscription; found on
> this PC: **yes**/**no**)

It starts **ticked only when a `claude` command is on the PATH of the installing
user** — searched across `PATH`, plus `%USERPROFILE%\.local\bin\claude*` and
`%APPDATA%\npm\claude.cmd`, which are the two places Claude Code installs itself
that an elevated process does not always inherit.

Two `[Tasks]` rows share the name `claudemember`, with mutually exclusive
`Check` functions, so exactly one is ever shown — the ticked one or the unticked
one. That is not a flourish: `WizardSelectTasks` called from `InitializeWizard`
is measurably a no-op (the wizard's task list is not built yet and `/TASKS` is
applied afterwards), so the declarative form is the only one that works. Both
rows answer to `WizardIsTaskSelected('claudemember')` and to
`/TASKS=claudemember`.

Ticked, it uncomments the `[[participants]]` block at the foot of `server.toml`
— **but only when the installer created that file**. An existing config is never
modified; that rule is not negotiable for a file the host is told to edit by
hand. The work is done in `[Code]` on the installed file rather than by shipping
a second template: one template instead of two that have to be kept in step, and
the host afterwards reads the same block in the same place under the same
explanation.

`SimpleChatServer.exe` needs `claude` on the PATH of the account that **starts**
the server, which is not necessarily the account that installed it — a logon
scheduled task runs as whoever logs on. The checkbox says so, and so does the
hosting guide.

### `server_root.cmd`

`[Code]` writes one generated file into `{app}`: a single
`set "SIMPLECHAT_ROOT=…"` naming the room's home folder.
`create_admin.cmd`, `start_server.cmd` and `run_server.cmd` read it; an
environment `SIMPLECHAT_ROOT` wins over it (that is how verification drives them
against a scratch room), and the old hard-coded `%ProgramData%\SimpleChat` is
still the fallback.

It exists because the wizard now runs two of those scripts **by itself**. Without
it a `/DVERIFY` build would have created an administrator in, and started a
server against, the real room — the exact collision the verify identity exists to
prevent. `[UninstallDelete]` sweeps it, since `[Files]` has no record of it and
one stray file keeps a whole install folder alive.

The other five launchers still name `%ProgramData%\SimpleChat` themselves, and
`stop_server.cmd` kills by image name, which no root can scope. A verify build's
Start Menu is therefore still aimed at the real room; do not run it.

### Where things land

| | |
|---|---|
| Programs | `{autopf}\SimpleChat` (per-machine, elevated) |
| Server working folder | `{commonappdata}\SimpleChat` |
| The room | `{commonappdata}\SimpleChat\data\simple_chat.db` |
| Front door | `{commonappdata}\SimpleChat\caddy.exe` |
| Per-member settings | `%APPDATA%\simple_chat\client.toml` |

`PrivilegesRequired=admin` follows the fleet precedent (`RixGPT.iss`,
`RixQwen.iss`). `PrivilegesRequiredOverridesAllowed=dialog commandline` is
added so a friend on a locked-down PC can still install the client per-user,
and so verification needs no UAC click.

### Two layout rules that are forced by the code, not chosen

1. **`caddy.exe` goes in the server's working folder.**
   `CADDY_FRONT_DOOR.make` resolves it as
   `current_working_path.extended ("caddy.exe")` — the **working directory**,
   not the folder beside the server executable. Every launcher `cd`s to
   `{commonappdata}\SimpleChat` first, and that is where `caddy.exe` is
   installed.

2. **`data_dir` must stay relative.** The same feature builds
   `current_working_path.extended (data_dir).extended ("Caddyfile")`, and
   `PATH.extended` carries the precondition `a_name_has_no_root`. An absolute
   `data_dir` violates it — *silently*, in a lean build, because contracts are
   compiled out. The shipped `server.toml` therefore says `data_dir = "data"`
   and the working folder is what places it somewhere writable. Program Files
   cannot be that folder: a standard user could not create the store there.

### Uninstall keeps the room

There is no `[UninstallDelete]`, deliberately. The data root, `server.toml`,
the backups and every member's `client.toml` carry `uninsneveruninstall`.
Neither `RixGPT.iss` nor `RixQwen.iss` deletes user data either, and an
uninstaller that can silently destroy a year of a family's conversation is not
worth the tidiness. `[Messages] ConfirmUninstall` says so plainly.

`[UninstallRun]` does remove the logon scheduled task and stop a running
server, in that order, before the files go.

### The stop is scoped to *this* install's server, by path

The stop used to be `taskkill /F /IM SimpleChatServer.exe`. On **2026-09-04**
that took a live room down twice in one afternoon: both times the uninstall
being run belonged to a **different** install of this same product — once a
client-only one, once a verification build — and both times it stopped the
server people were actually talking in.

**The verify identity could not have caught it.** The `/DVERIFY` block switches
every symbol two installs can collide over — `AppId`, `AppName`, `DirName`,
`ServerRoot`, `TaskName`, `ClientCfgDir`, `OutBase` — and `ServerExe` is not
among them and cannot be. It is the *same compiled binary* in both builds, and
that rename is what stops the client, the server and the test runner (all three
finalize to `simple_chat.exe`) from being three files with one name. The image
name is the one property of this product the verify identity must not switch,
and it was the one thing the uninstaller keyed on.

So the stop now matches on the full executable path, `{app}\SimpleChatServer.exe`,
which is per-install always — and carries `Components: server` as a second lock.
The component condition is **not** the fix: it would have skipped the
client-only case by accident, and a verify build *with* the server component
would still have killed the live room. The path is the fix.

The same correction went into `templates/stop_server.cmd`, whose own comment had
promised path scoping for caddy since it was written (*"only the copy that lives
in our own folder"*) while the code below it said `/IM caddy.exe`; and into
`templates/start_server.cmd`, whose "is it already running?" test answered about
**any** install's server, so a verification build could not be started at all
while the real room was up. All three now compare paths in PowerShell, because
`tasklist` and `taskkill` filter on an image name and cannot filter on a path.

Change the **template**, never `installer/src/server/*.cmd`: those are generated
by `stage_payload.sh`, which copies the templates and normalizes them to CRLF.

---

## Pins

`THIRD-PARTY.md` carries the Caddy release tag, URL, SHA-512 and SHA-256, the
Noto artwork and its licence, and cairo. `stage_payload.sh` deliberately does
**not** download Caddy: a build step that silently fetches "whatever is latest"
is how a pin rots. It refuses to run if the payload is missing and points at
the re-fetch commands.

## Files here

| | |
|---|---|
| `SimpleChat.iss` | the script |
| `stage_payload.sh` | assembles `src/` (gitignored) |
| `templates/` | config templates, the nine launchers, the hosting guide, `README.txt` |
| `THIRD-PARTY.md` | the pins and their licences |
| `VERIFICATION-2026-09-02.md` | verification record, and the incident that shaped the verify identity |
| `VERIFICATION-2026-09-03.md` | verification record for the finish sequence and the @claude checkbox |
