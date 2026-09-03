@echo off
REM ===========================================================================
REM create_admin.cmd - "Create first admin" in the Start Menu, and STEP 1 of
REM the installer's finish sequence.
REM
REM The server's own command is:
REM     SimpleChatServer.exe --create-admin <username> [config.toml]
REM It asks for the display name and the password twice ITSELF, on this
REM console. This script only collects the username and runs it from the right
REM folder.
REM
REM It works once. The server refuses to mint a second first-admin, so there is
REM never a default account and never a default password. But it refuses only
REM AFTER asking for a display name and a password twice, and a wizard step
REM whose one possible ending is a refusal is a dead end - so this script tests
REM for the room's store FIRST and leaves quietly when it is already there.
REM The installer's [Run] entry carries the same test as its Check; this is the
REM second lock, and the one the Start Menu shortcut needs.
REM
REM CODE PAGE 65001: set before the server is launched so a display name in
REM Hebrew, Greek or anything else non-English survives being typed. The
REM username never carries non-ASCII - the rules confine it to a-z, 0-9 and
REM underscore - so nothing non-ASCII is ever put on the command line, which
REM on Windows is where such things get mangled.
REM ===========================================================================
setlocal EnableDelayedExpansion
set "SYS=%SystemRoot%\System32"

REM --- WHICH ROOM? ----------------------------------------------------------
REM server_root.cmd is written by the installer and names the room's home
REM folder: the real one for a real install, the verify one for a /DVERIFY
REM build. That is what keeps a test install from ever creating an account in
REM the real room. A SIMPLECHAT_ROOT already in the environment wins over both,
REM which is how this script is driven against a scratch root at verification
REM time. The old hard-coded default is still the fallback, so a hand-copied
REM script keeps working.
if not defined SIMPLECHAT_ROOT if exist "%~dp0server_root.cmd" call "%~dp0server_root.cmd"
if not defined SIMPLECHAT_ROOT set "SIMPLECHAT_ROOT=%ProgramData%\SimpleChat"
set "ROOT=%SIMPLECHAT_ROOT%"

REM --- is this room already open? -------------------------------------------
REM The store is the only honest witness: an administrator exists only inside
REM it, and nothing but the server ever creates it.
if exist "%ROOT%\data\simple_chat.db" (
    echo.
    echo   This room already has its first administrator.
    echo.
    echo   Nothing was changed. To make an account for somebody else use
    echo   "Create user"; to give an existing member a new password use
    echo   "Reset a password". Both are in the Start Menu.
    echo.
    call :hold 6
    exit /b 0
)

REM Remember the console's code page and put it back on the way out.
for /f "tokens=2 delims=:" %%C in ('"%SYS%\chcp.com"') do set "OLDCP=%%C"
"%SYS%\chcp.com" 65001 >nul

if not exist "%ROOT%" mkdir "%ROOT%"
if not exist "%ROOT%\data" mkdir "%ROOT%\data"
cd /d "%ROOT%" || (echo Cannot enter %ROOT% & call :hold 12 & exit /b 1)

echo.
echo   Create the first administrator
echo   ------------------------------
echo   This is the account you will log into the chat window with.
echo   It can only be done once, before anyone else has an account.
echo.

REM The store is SQLite in WAL mode, which does allow a second process to open
REM it - but nothing here sets a busy timeout, so a write that races the
REM running server's can come back SQLITE_BUSY and the account is simply not
REM created. Stopping first is the reliable order.
"%SYS%\tasklist.exe" /fi "IMAGENAME eq SimpleChatServer.exe" 2>nul | "%SYS%\find.exe" /i "SimpleChatServer.exe" >nul
if not errorlevel 1 (
    echo   The server is RUNNING.
    echo.
    echo   Stop it first ^("Stop server" in the Start Menu^), create the
    echo   account, then start it again. Creating an account while the server
    echo   is running can fail silently on a database lock.
    echo.
    "%SYS%\chcp.com" %OLDCP% >nul
    call :hold 12
    exit /b 1
)

echo   The username is what you type to log in. It must be 1 to 32
echo   characters of a-z, 0-9 and underscore - no capitals, no spaces.
echo.
echo   You will then be asked for a display name (what the room shows -
echo   this one MAY have capitals, spaces and any language) and for your
echo   password twice.
echo.

set "ADMIN="
set /p "ADMIN=Username: "

REM EMPTINESS IS TESTED HERE, BEFORE THE LOWERCASING - AND THAT ORDER IS THE
REM WHOLE POINT. `set /p' leaves the variable UNDEFINED when the answer is an
REM empty line, and !ADMIN:A=a! on an UNDEFINED variable does not expand to
REM nothing: it expands to the literal text  A=a . The guard used to sit AFTER
REM the chain below, where it could never fire - pressing Enter at this prompt
REM printed "Using username: A=a" and then an error about a-z and underscores,
REM which tells the host nothing about what they actually did. Measured
REM 2026-09-03; see installer\VERIFICATION-2026-09-03.md.
if not defined ADMIN (
    echo.
    echo   No username given. Nothing was created.
    echo.
    "%SYS%\chcp.com" %OLDCP% >nul
    call :hold 10
    exit /b 1
)

REM Lowercase in PURE BATCH: the rules allow a-z only, and a capital is the
REM commonest first mistake ("Larry" -> refused outright). No external tool is
REM used, because System32 is not on this PC's PATH.
set "ADMIN=!ADMIN:A=a!" & set "ADMIN=!ADMIN:B=b!" & set "ADMIN=!ADMIN:C=c!" & set "ADMIN=!ADMIN:D=d!"
set "ADMIN=!ADMIN:E=e!" & set "ADMIN=!ADMIN:F=f!" & set "ADMIN=!ADMIN:G=g!" & set "ADMIN=!ADMIN:H=h!"
set "ADMIN=!ADMIN:I=i!" & set "ADMIN=!ADMIN:J=j!" & set "ADMIN=!ADMIN:K=k!" & set "ADMIN=!ADMIN:L=l!"
set "ADMIN=!ADMIN:M=m!" & set "ADMIN=!ADMIN:N=n!" & set "ADMIN=!ADMIN:O=o!" & set "ADMIN=!ADMIN:P=p!"
set "ADMIN=!ADMIN:Q=q!" & set "ADMIN=!ADMIN:R=r!" & set "ADMIN=!ADMIN:S=s!" & set "ADMIN=!ADMIN:T=t!"
set "ADMIN=!ADMIN:U=u!" & set "ADMIN=!ADMIN:V=v!" & set "ADMIN=!ADMIN:W=w!" & set "ADMIN=!ADMIN:X=x!"
set "ADMIN=!ADMIN:Y=y!" & set "ADMIN=!ADMIN:Z=z!"


REM Second net: a line of nothing but spaces survives `if not defined'.
if "!ADMIN!"=="" (
    echo.
    echo   No username given. Nothing was created.
    "%SYS%\chcp.com" %OLDCP% >nul
    echo.
    call :hold 10
    exit /b 1
)

echo.
echo   NOTE: the password will be visible as you type it. There is no echo
echo   suppression on a plain Eiffel console in this version. Nobody but you
echo   is looking at this screen; the password itself is never stored - only a
echo   PBKDF2 hash at 600,000 iterations.
echo.

echo   Using username: !ADMIN!
echo.
"%~dp0SimpleChatServer.exe" --create-admin "!ADMIN!" server.toml
set "MADE=%ERRORLEVEL%"

echo.
echo   The installer starts the server next, then opens the chat window, and
echo   you sign in with the account above. (Started this from the Start Menu
echo   instead? Then "Start server" is your next step.)
echo.
echo   To make accounts for your friends, use "Create user".
echo.
"%SYS%\chcp.com" %OLDCP% >nul
pause
exit /b %MADE%

REM --- hold the window open long enough to read, then get out of the way ----
REM Used on every path a human did NOT ask for by typing something. The wizard
REM runs this script itself now, and a `pause' on such a path would stall the
REM whole finish sequence behind a keypress nobody is there to give.
REM
REM PING, NOT TIMEOUT: timeout.exe wants a console it can read a keypress from
REM and does not return at all when stdin is redirected or NUL - it wedged a
REM verification run on 2026-09-03. ping to the loopback is the batch sleep
REM that has no opinion about stdin.
:hold
"%SYS%\PING.EXE" -n %1 127.0.0.1 >nul 2>&1
exit /b 0
