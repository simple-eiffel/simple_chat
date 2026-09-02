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
| `server` | **off** | `SimpleChatServer.exe`, eight launchers, `HOSTING-GUIDE.html`, `caddy.exe`, `server.toml` template |

The server is unticked by default: most installs are a friend who only wants to
use the chat. `[Types]` lists the client-only type **first**, so it is the
default; ticking the server component switches to the custom type Inno adds
automatically.

**Promoting a client-only install to a host** — which is also how a friend
becomes a standby host — is just re-running the installer and ticking the box.
Inno restores the previously installed component selection on a reinstall, so
only the new one has to be ticked.

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
| `templates/` | config templates, the eight launchers, the hosting guide, `README.txt` |
| `THIRD-PARTY.md` | the pins and their licences |
| `VERIFICATION-2026-09-02.md` | verification record, and the incident that shaped the verify identity |
