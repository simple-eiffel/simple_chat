@echo off
REM ===========================================================================
REM create_admin.cmd - "Create first admin" in the Start Menu.
REM
REM The server's own command is:
REM     SimpleChatServer.exe --create-admin <username> [config.toml]
REM It asks for the display name and the password twice ITSELF, on this
REM console. This script only collects the username and runs it from the right
REM folder.
REM
REM It works once. The server refuses to mint a second first-admin, so there is
REM never a default account and never a default password.
REM
REM CODE PAGE 65001: set before the server is launched so a display name in
REM Hebrew, Greek or anything else non-English survives being typed. The
REM username never carries non-ASCII - the rules confine it to a-z, 0-9 and
REM underscore - so nothing non-ASCII is ever put on the command line, which
REM on Windows is where such things get mangled.
REM ===========================================================================
setlocal EnableDelayedExpansion
set "SYS=%SystemRoot%\System32"
set "ROOT=%ProgramData%\SimpleChat"

REM Remember the console's code page and put it back on the way out.
for /f "tokens=2 delims=:" %%C in ('"%SYS%\chcp.com"') do set "OLDCP=%%C"
"%SYS%\chcp.com" 65001 >nul

cd /d "%ROOT%" || (echo Cannot enter %ROOT% & pause & exit /b 1)

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
    pause
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


if "!ADMIN!"=="" (
    echo.
    echo   No username given. Nothing was created.
    "%SYS%\chcp.com" %OLDCP% >nul
    echo.
    pause
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

echo.
echo   Next: "Start server", then open SimpleChat and log in.
echo   To make accounts for your friends, use "Create user".
echo.
"%SYS%\chcp.com" %OLDCP% >nul
pause
