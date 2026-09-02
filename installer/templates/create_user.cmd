@echo off
REM ===========================================================================
REM create_user.cmd - "Create user" in the Start Menu.
REM
REM The host mints every account: there is no self-registration in SimpleChat,
REM by design. This is how you make an account for a friend.
REM
REM The server's own command is:
REM     SimpleChatServer.exe --create-user <username> [config.toml]
REM It asks for the display name and the password ITSELF, on this console.
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
echo   Create an account for someone
echo   -----------------------------
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

echo   The username is what they type to log in. It must be 1 to 32
echo   characters of a-z, 0-9 and underscore - no capitals, no spaces.
echo.
echo   You will then be asked for a display name (what the room shows -
echo   this one MAY have capitals, spaces and any language) and for their
echo   password twice.
echo.

set "MEMBER="
set /p "MEMBER=Username: "

if "%MEMBER%"=="" (
    echo.
    echo   No username given. Nothing was created.
    chcp %OLDCP% >nul
    echo.
    pause
    exit /b 1
)

echo.
"%~dp0SimpleChatServer.exe" --create-user "%MEMBER%" server.toml

echo.
echo   Tell them their username and password, and the address of this room.
echo   They install SimpleChat, leave the hosting box unticked, and log in.
echo.
chcp %OLDCP% >nul
pause
