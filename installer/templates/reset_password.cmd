@echo off
REM ===========================================================================
REM reset_password.cmd - "Reset a password" in the Start Menu.
REM
REM Somebody forgot their password - possibly you. Before this existed the only
REM way back into a room whose admin was locked out was to delete
REM C:\ProgramData\SimpleChat\data\simple_chat.db* and lose every message in it.
REM
REM The server's own command is:
REM     SimpleChatServer.exe --reset-password <username> [config.toml]
REM It asks for the new password TWICE, on this console. It asks for no display
REM name: the account already has one, and nothing here renames anybody.
REM
REM EVERY LIVE SESSION of that member is signed out by the reset. That is the
REM point of it: a password somebody else has learned is taken away, not merely
REM replaced. Whoever it was has to log in again with the new one.
REM
REM CODE PAGE 65001: set for the same reason the other launchers set it, so a
REM password typed with a non-English character survives being read. The
REM username never carries non-ASCII - the rules confine it to a-z, 0-9 and
REM underscore - so nothing non-ASCII is ever put on the command line.
REM ===========================================================================
setlocal EnableDelayedExpansion
set "SYS=%SystemRoot%\System32"
set "ROOT=%ProgramData%\SimpleChat"

REM Remember the console's code page and put it back on the way out.
for /f "tokens=2 delims=:" %%C in ('"%SYS%\chcp.com"') do set "OLDCP=%%C"
"%SYS%\chcp.com" 65001 >nul

cd /d "%ROOT%" || (echo Cannot enter %ROOT% & pause & exit /b 1)

echo.
echo   Reset someone's password
echo   ------------------------
echo.

REM The store is SQLite in WAL mode, which does allow a second process to open
REM it - but nothing here sets a busy timeout, so a write that races the running
REM server's can come back SQLITE_BUSY. For a reset that is the worse case: the
REM new password would never land, the old one would still work, and the
REM sessions the running server is holding would never be signed out. Stopping
REM first is the reliable order.
"%SYS%\tasklist.exe" /fi "IMAGENAME eq SimpleChatServer.exe" 2>nul | "%SYS%\find.exe" /i "SimpleChatServer.exe" >nul
if not errorlevel 1 (
    echo   The server is RUNNING.
    echo.
    echo   Stop it first ^("Stop server" in the Start Menu^), reset the
    echo   password, then start it again. Resetting while the server is
    echo   running can fail silently on a database lock - and it would leave
    echo   the old password working and everyone still signed in.
    echo.
    "%SYS%\chcp.com" %OLDCP% >nul
    pause
    exit /b 1
)

echo   Whose password is this? Type the username they log in with - 1 to 32
echo   characters of a-z, 0-9 and underscore, no capitals, no spaces. It must
echo   be an account that already exists; this does not create anybody.
echo.
echo   You will then be asked for their NEW password twice. It shows on
echo   screen as you type it.
echo.
echo   Everyone signed in as that person is signed out by this. They log
echo   back in with the new password.
echo.

set "MEMBER="
set /p "MEMBER=Username: "

REM Lowercase in PURE BATCH: the rules allow a-z only, and a capital is the
REM commonest first mistake ("Larry" -> refused outright). No external tool is
REM used, because System32 is not on this PC's PATH. (create_user.cmd does the
REM same thing for the same reason.)
set "MEMBER=!MEMBER:A=a!" & set "MEMBER=!MEMBER:B=b!" & set "MEMBER=!MEMBER:C=c!" & set "MEMBER=!MEMBER:D=d!"
set "MEMBER=!MEMBER:E=e!" & set "MEMBER=!MEMBER:F=f!" & set "MEMBER=!MEMBER:G=g!" & set "MEMBER=!MEMBER:H=h!"
set "MEMBER=!MEMBER:I=i!" & set "MEMBER=!MEMBER:J=j!" & set "MEMBER=!MEMBER:K=k!" & set "MEMBER=!MEMBER:L=l!"
set "MEMBER=!MEMBER:M=m!" & set "MEMBER=!MEMBER:N=n!" & set "MEMBER=!MEMBER:O=o!" & set "MEMBER=!MEMBER:P=p!"
set "MEMBER=!MEMBER:Q=q!" & set "MEMBER=!MEMBER:R=r!" & set "MEMBER=!MEMBER:S=s!" & set "MEMBER=!MEMBER:T=t!"
set "MEMBER=!MEMBER:U=u!" & set "MEMBER=!MEMBER:V=v!" & set "MEMBER=!MEMBER:W=w!" & set "MEMBER=!MEMBER:X=x!"
set "MEMBER=!MEMBER:Y=y!" & set "MEMBER=!MEMBER:Z=z!"


if "!MEMBER!"=="" (
    echo.
    echo   No username given. Nothing was changed.
    "%SYS%\chcp.com" %OLDCP% >nul
    echo.
    pause
    exit /b 1
)

echo.
echo   Using username: !MEMBER!
echo.
"%~dp0SimpleChatServer.exe" --reset-password "!MEMBER!" server.toml

REM The server leaves a NON-ZERO exit status on every refusal - an unknown
REM username, a name that turns out to be a bot, two entries that differ, a
REM password below the minimum - and zero only when the password really
REM changed. Reading it here is the only way this script can tell the host the
REM truth about what just happened.
if errorlevel 1 (
    echo.
    echo   Nothing was changed. The message above says why.
    echo.
    "%SYS%\chcp.com" %OLDCP% >nul
    pause
    exit /b 1
)

echo.
echo   Tell them their new password. Anyone signed in as !MEMBER! has been
echo   signed out and must log in again.
echo.
"%SYS%\chcp.com" %OLDCP% >nul
pause
