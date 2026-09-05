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
setlocal EnableDelayedExpansion
set "SYS=%SystemRoot%\System32"
set "ROOT=%ProgramData%\SimpleChat"

REM Remember the console's code page and put it back on the way out.
for /f "tokens=2 delims=:" %%C in ('"%SYS%\chcp.com"') do set "OLDCP=%%C"
"%SYS%\chcp.com" 65001 >nul

cd /d "%ROOT%" || (echo Cannot enter %ROOT% & pause & exit /b 1)

echo.
echo   Create an account for someone
echo   -----------------------------
echo.

REM Since 0.3.2 the server executable decides the path itself: if the room is
REM RUNNING it asks for an administrator's username and password and makes the
REM account THROUGH the room (its own admin API, no second handle on the
REM database); if the room is stopped it opens the database directly, as it
REM always did. Nothing here needs to stop or start anything.
"%SYS%\tasklist.exe" /fi "IMAGENAME eq SimpleChatServer.exe" 2>nul | "%SYS%\find.exe" /i "SimpleChatServer.exe" >nul
if not errorlevel 1 (
    echo   The room is running, so you will first be asked to sign in as an
    echo   administrator ^(your own username and password^); the account is then
    echo   created through the room, with nothing stopped.
    echo.
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

REM Lowercase in PURE BATCH: the rules allow a-z only, and a capital is the
REM commonest first mistake ("Larry" -> refused outright). No external tool is
REM used, because System32 is not on this PC's PATH.
set "MEMBER=!MEMBER:A=a!" & set "MEMBER=!MEMBER:B=b!" & set "MEMBER=!MEMBER:C=c!" & set "MEMBER=!MEMBER:D=d!"
set "MEMBER=!MEMBER:E=e!" & set "MEMBER=!MEMBER:F=f!" & set "MEMBER=!MEMBER:G=g!" & set "MEMBER=!MEMBER:H=h!"
set "MEMBER=!MEMBER:I=i!" & set "MEMBER=!MEMBER:J=j!" & set "MEMBER=!MEMBER:K=k!" & set "MEMBER=!MEMBER:L=l!"
set "MEMBER=!MEMBER:M=m!" & set "MEMBER=!MEMBER:N=n!" & set "MEMBER=!MEMBER:O=o!" & set "MEMBER=!MEMBER:P=p!"
set "MEMBER=!MEMBER:Q=q!" & set "MEMBER=!MEMBER:R=r!" & set "MEMBER=!MEMBER:S=s!" & set "MEMBER=!MEMBER:T=t!"
set "MEMBER=!MEMBER:U=u!" & set "MEMBER=!MEMBER:V=v!" & set "MEMBER=!MEMBER:W=w!" & set "MEMBER=!MEMBER:X=x!"
set "MEMBER=!MEMBER:Y=y!" & set "MEMBER=!MEMBER:Z=z!"


if "!MEMBER!"=="" (
    echo.
    echo   No username given. Nothing was created.
    "%SYS%\chcp.com" %OLDCP% >nul
    echo.
    pause
    exit /b 1
)

echo.
echo   Using username: !MEMBER!
echo.
"%~dp0SimpleChatServer.exe" --create-user "!MEMBER!" server.toml

echo.
echo   Tell them their username and password, and the address of this room.
echo   They install SimpleChat, leave the hosting box unticked, and log in.
echo.
"%SYS%\chcp.com" %OLDCP% >nul
pause
