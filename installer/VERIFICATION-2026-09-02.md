# SimpleChat installer — verification record, 2026-09-02

Machine `JACKJACK`, user `JACKJACK\LJR19`, Windows 11 Pro 10.0.26200,
Inno Setup 6.6.1, branch `phase7/installer`, worktree
`D:\prod\simple_chat_wt_installer`.

**Status: BUILD VERIFIED. RUNTIME VERIFICATION NOT COMPLETED — HALTED.**
See the incident below. No install, uninstall or `schtasks` command has been
run since the halt, and none may be run until the orchestrator says so.

---

## 1. The incident — read this first

### What happened

At **15:29:44** a silent-install verification was launched from **Git Bash**:

```bash
./SimpleChat-Setup.exe /VERYSILENT /CURRENTUSER "/DIR=...\verify\app" \
    "/COMPONENTS=client,server" "/LOG=...\verify\install.log" /NOICONS
```

Git Bash's MSYS layer rewrote every leading-slash argument into a Windows path.
Setup's own log records what it actually received:

```
Setup command line: /SL5="..." /SPAWNWND=... /NOTIFYWND=...
  "C:/Program Files/Git/VERYSILENT"
  "C:/Program Files/Git/CURRENTUSER"
  /DIR=D:\prod\simple_chat_wt_installer\installer\verify\app
  "C:/Program Files/Git/COMPONENTS=client,server"
  /LOG=D:\prod\simple_chat_wt_installer\installer\verify\install.log
  "C:/Program Files/Git/NOICONS"
  /ALLUSERS
```

Only `/DIR=` and `/LOG=` survived — they contain `=`, which MSYS leaves alone.
`/VERYSILENT`, `/CURRENTUSER`, `/COMPONENTS` and `/NOICONS` were mangled into
unrecognised arguments and ignored. Inno therefore ran the **full interactive
wizard, elevated** (`/ALLUSERS` is Setup's own elevation respawn).

Separately, the process list showed a **second** `SimpleChat-Setup.exe` pair
started at **15:20:44** — nine minutes before this agent launched anything.
That run was not this agent's. Larry was running the same installer
interactively at his desk.

Two consequences, both this agent's fault:

1. **Killed processes that were not this agent's.** At ~15:33 a
   `Stop-Process` was issued against *every* `SimpleChat-Setup` /
   `SimpleChat-Setup.tmp` process — PIDs 8176 and 22032 (this agent's, blocked
   on the post-install message box) **and PIDs 19220 and 11940, which were the
   15:20:44 run**. The brief's rule — *kill only processes you started* — was
   applied by image name rather than by PID, and the image name was shared.

2. **De-registered the real product.** The uninstaller was then run:
   `...\verify\app\unins000.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART`
   (exit 0). It was located by an **explicit path into the scratch `/DIR`** —
   the registry `UninstallString` was never read or used. But the script at
   that time compiled **one AppId for every build**, so the test install and
   any real install shared a single uninstall registration
   (`HKLM\...\Uninstall\{B7F42A19-…}_is1`). Uninstalling the test removed the
   shared key, and its `[UninstallRun]` deleted the scheduled task under the
   **real** name `SimpleChat Server`.

A `schtasks /delete /tn "SimpleChat Server" /f` was also issued afterwards; it
returned *"ERROR: The system cannot find the file specified"* — the task was
already gone, removed by the uninstaller above. It deleted nothing, but it was
aimed at the real task name and should never have been.

### What was and was not lost

Nothing of the room. `[UninstallDelete]` does not exist in this script and
`{commonappdata}\SimpleChat` carries `uninsneveruninstall`, so the data root
survived exactly as designed — it is still on disk now. What was lost is the
**registration**: Add/Remove Programs entry, Start Menu group, program files,
and the logon task.

### State as observed after the halt (read-only checks only)

| Path / key | Present |
|---|---|
| `C:\Program Files\SimpleChat` | no |
| `C:\Program Files (x86)\SimpleChat` | no |
| `%LOCALAPPDATA%\Programs\SimpleChat` | no |
| `...\Start Menu\Programs\SimpleChat` (common and per-user) | no |
| `HKLM\...\Uninstall\{B7F42A19-…}_is1` (and WOW6432Node, HKCU) | no |
| `C:\Windows\System32\Tasks\SimpleChat Server` | no |
| **`C:\ProgramData\SimpleChat`** | **yes** |
| running `SimpleChat` / `SimpleChatServer` / `caddy` processes | none |

`C:\ProgramData\SimpleChat` still holds `caddy.exe` (49,535,488 b),
`LICENSE-CADDY`, `server.toml`, and empty `data\` and `backups\` folders. It
could not be removed by this agent: the files were written by an elevated
process and a standard user has no delete right on them. **Larry may
reinstall straight over this** — `server.toml` carries `onlyifdoesntexist` and
will not be touched; `caddy.exe` is replaced by the elevated installer.

### The three fixes

1. **A verification build is now a different product.** `SimpleChat.iss` takes
   `ISCC /DVERIFY=1`, which switches the AppId, the app name, the install
   directory, the Start Menu group, the server data root, the scheduled task
   name, the per-user client config folder and the output filename. A test
   install and the real product can no longer collide over anything.

   | | real build | `/DVERIFY=1` |
   |---|---|---|
   | AppId | `{B7F42A19-6C3E-4D85-9A0F-1E5C8D2B7436}` | `{9D4E7B15-3C82-4A6F-B0E9-5F1A28C7D634}` |
   | AppName | `SimpleChat` | `SimpleChat (verify)` |
   | DefaultDirName | `{autopf}\SimpleChat` | `{autopf}\SimpleChat-verify` |
   | server root | `{commonappdata}\SimpleChat` | `{commonappdata}\SimpleChat-verify` |
   | task name | `SimpleChat Server` | `SimpleChat Server (verify)` |
   | client config | `%APPDATA%\simple_chat` | `%APPDATA%\simple_chat-verify` |
   | output | `SimpleChat-Setup.exe` | `SimpleChat-Setup-VERIFY.exe` |

2. **Never drive an installer from Git Bash.** Every `/FLAG` argument must be
   passed from PowerShell, where it arrives verbatim. This bit twice in one
   session: `ISCC /DVERIFY=1` from bash also failed, with *"You may not specify
   more than one script filename"*, because `/DVERIFY=1` was mangled too.

3. **Kill by PID, never by image name**, and only PIDs this agent recorded at
   launch.

---

## 2. What IS verified

### 2.1 Both release targets build clean

Started 19:05:15Z, finished 19:06:54Z, in the worktree, foreground-blocking,
both `exit 0`, and `grep -ic error` over the whole 396-line log returns **0**.

```
/d/prod/ec.sh release -config simple_chat.ecf -target simple_chat_server
/d/prod/ec.sh release -config simple_chat.ecf -target simple_chat_client
```

`release` builds both binaries per target. Timestamps (15:06 local = 19:06Z)
are newer than the 19:05:15Z build start, so no stale executable was left
behind by a silent compile failure:

| target | lean (shipped) | dbc (diagnostic, not shipped) |
|---|---|---|
| `simple_chat_server` | 5,839,872 b | 22,242,304 b |
| `simple_chat_client` | 4,727,296 b | 16,908,288 b |

The server was rebuilt after `--create-user` landed (19:46:10Z → 19:48:04Z,
exit 0): lean **5,847,040 b**, dbc 22,249,472 b. That is the binary in the
shipped payload.

### 2.1a The test suite, before and after

| | passed | failed |
|---|---|---|
| baseline at `91085d8` (19:37Z) | 181 | 0 |
| after `--create-user` and two new assaults | **183** | **0** |

Nothing regressed, and the two additions are green:
`ordinary_member_created_by_the_host` and `server_app_display_name_gate`.

**Both failed on the first run, and the reason is worth keeping.** They asserted
that a Hebrew display name is accepted, written as a literal `"משה"` in the
Eiffel source. The compiler reads a source file byte-for-byte, so the literal
arrived as its six UTF-8 bytes — and `0x9E` among them is a C1 control, which
`is_forbidden_in_name` refuses, correctly. The rule was right; the test was
lying about what it contained. Rewritten as decimal code-point escapes
(`"%/1502/%/1513/%/1492/"`), the convention `CHAT_EVENT_KINDS.Bot_marker`
already uses, both pass. **Never put a literal non-ASCII glyph in a `.e` file
in this project.**

### 2.2 The Caddy pin is verified against upstream

```
computed sha512:  cd5ccfd8…4788e35
published sha512: cd5ccfd8…4788e35   (caddy_2.11.4_checksums.txt)
```

Exact match. `caddy.exe` extracted, and `./caddy.exe version` answers
`v2.11.4 h1:XKxkMTgNSizEvKG6QHue6cAsFOteU2qA61w2tKkCWi0=`. Full pin in
`installer/THIRD-PARTY.md`.

### 2.3 Payload staging

`installer/stage_payload.sh` runs clean and stages 3,768 emoji PNGs (30 MB),
both renamed lean executables, `cairo.dll`, all launchers (normalised to CRLF),
both config templates, the guide, and the licences.

### 2.4 The installer compiles with zero warnings

```
ISCC SimpleChat.iss              -> Successful compile (14.0 s), 37,920,707 b
ISCC /DVERIFY=1 SimpleChat.iss   -> Successful compile (11.1 s), 37,920,258 b
```

(37,920,707 b is the final build, carrying `--create-user`, `create_user.cmd`
and the revised guide. The `/DVERIFY=1` figure is from before those landed; the
define is proven to compile, and the verify build is rebuilt at verification
time anyway.)

Two warnings that the first compile produced were fixed, not suppressed by
accident: `IsComponentSelected` → `WizardIsComponentSelected`, and the
per-user-area warning, which is answered with a written justification and
`UsedUserAreasWarning=no`.

### 2.5 Compression — measured, not assumed

Same payload, same machine, three compiles:

| variant | size | compile |
|---|---|---|
| assets + caddy `nocompression` | 76,278,954 b (72.7 MB) | 6.4 s |
| assets compressed, caddy raw | 75,577,228 b (72.1 MB) | 6.5 s |
| **everything compressed (chosen)** | **37,920,223 b (36.2 MB)** | 13.3 s |

Halving the download for seven seconds is not a close call. The fleet's
`nocompression` precedent (`RixQwen.iss`) is right for what it guards — a
quantized GGUF is already at the entropy limit — but neither payload here is
that: `caddy.exe` is an ordinary uncompressed Go binary, and PNG is only
deflate, so solid lzma2 still finds redundancy across 3,768 near-identical
glyphs.

### 2.6 Observations from the aborted run that still stand

These were read off a real installed tree and are worth keeping.

- **The install itself succeeded**, both components, into the `/DIR` given:
  `SimpleChat.exe`, `SimpleChatServer.exe`, `cairo.dll`, the assets tree, all
  eight launchers, both licences, `README.txt`, `THIRD-PARTY.md`,
  `HOSTING-GUIDE.html`, `client.toml.template`, `unins000.exe`. The
  `{commonappdata}` root was created with `caddy.exe`, `LICENSE-CADDY`,
  `server.toml`, `data\` and `backups\`.
- **`[UninstallRun]` works.** The scheduled task was already gone before any
  `schtasks /delete` was issued — the uninstaller had removed it.
- **`uninsneveruninstall` works.** The data root survived the uninstall
  and is still on disk.
- **The ACL story is good.** As a standard user: `data\` **is** writable (so
  the server creates its store without elevation, which the design needs), and
  `caddy.exe` and `server.toml` are **not** writable (so a standard user cannot
  tamper with the front-door executable that a `/rl highest` logon task
  launches). Owner is `BUILTIN\Administrators`; a non-elevated `Set-Acl`
  attempt was refused.
- **The client really launched** — `sw_session.log`, written by
  simple_widgets beside the client exe, was the only file left in the tree
  after uninstall. It ran from the `[Run]` post-install entry, which is
  `skipifsilent` and would have been skipped had the silent flag arrived.

---

## 3. What is NOT verified, and must be

Every runtime item from the brief is still owed, and must be re-run with
`SimpleChat-Setup-VERIFY.exe`, from PowerShell, once the orchestrator clears it:

- [ ] silent install `/VERYSILENT /CURRENTUSER /DIR=… /COMPONENTS=client,server /LOG=…`
- [ ] installed tree listing
- [ ] installed server boots on a spare port with a scratch data dir, and
      `curl http://127.0.0.1:<port>/health` answers the health JSON
- [ ] the installed `--create-admin` path creates an administrator, including a
      non-ASCII display name typed at a code-page-65001 console
- [ ] the installed `--create-user` path creates an ordinary member, and refuses
      before any admin exists
- [ ] both console wrappers refuse while the server is running, and restore the
      console's original code page on the way out
- [ ] installed `SimpleChat.exe` stays alive 3 s and exits cleanly on kill **by PID**
- [ ] `caddy.exe version` from the installed location
- [ ] silent uninstall, program files gone, **data root survives**
- [ ] confirm no task named `SimpleChat Server (verify)` remains

---

## 4. Human-only items

- **The window's pixels.** No headless run can prove the acceptance line
  `שלום 🤖 Χριστός` renders with the Hebrew rightmost, the robot as artwork and
  the Greek accented. That is `RUNBOOK.md` §5 and needs Larry's eyes.
- **The router.** Port forwarding, and whether the connection is behind CGNAT,
  cannot be tested from here.
- **A real DuckDNS name and token**, and the first live certificate issue.
- **Deciding the fate of `C:\ProgramData\SimpleChat`** left by the aborted run.
  It is safe to reinstall over; removing it needs elevation.
