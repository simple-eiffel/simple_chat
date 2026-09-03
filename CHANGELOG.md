# Changelog

All notable changes to simple_chat are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
