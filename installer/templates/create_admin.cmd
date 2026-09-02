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
setlocal
set "ROOT=%ProgramData%\SimpleChat"

REM Remember the console's code page and put it back on the way out.
for /f "tokens=2 delims=:" %%C in ('chcp') do set "OLDCP=%%C"
chcp 65001 >nul

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
tasklist /fi "IMAGENAME eq SimpleChatServer.exe" 2>nul | find /i "SimpleChatServer.exe" >nul
if not errorlevel 1 (
    echo   The server is RUNNING.
    echo.
    echo   Stop it first ^("Stop server" in the Start Menu^), create the
    echo   account, then start it again. Creating an account while the server
    echo   is running can fail silently on a database lock.
    echo.
    chcp %OLDCP% >nul
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

if "%ADMIN%"=="" (
    echo.
    echo   No username given. Nothing was created.
    chcp %OLDCP% >nul
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

"%~dp0SimpleChatServer.exe" --create-admin "%ADMIN%" server.toml

echo.
echo   Next: "Start server", then open SimpleChat and log in.
echo   To make accounts for your friends, use "Create user".
echo.
chcp %OLDCP% >nul
pause
