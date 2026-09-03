@echo off
REM ===========================================================================
REM run_server.cmd - the bare launcher. Everything else calls this one.
REM
REM THE UNDRAINED-PIPE RULE: the server's console output goes to a FILE, never
REM into a pipe. A console write into a pipe nobody is draining wedges the
REM server mid-request - /health keeps answering 200 while every login times
REM out. This was found the hard way; do not "improve" the redirect below into
REM a | more, a | tee, or a for /f loop.
REM
REM The working folder is the room's home folder, because the server resolves
REM data_dir relative to it, and because the Caddy front door looks for
REM caddy.exe in the working folder.
REM
REM This is also the path the logon scheduled task takes, through
REM start_server_hidden.vbs - with NO console to print to. So the port-collision
REM check writes its finding to server.log, which is the only place anyone will
REM look after a silent failure at boot.
REM ===========================================================================
setlocal
set "SYS=%SystemRoot%\System32"
set "PORT=8090"

REM --- WHICH ROOM? ----------------------------------------------------------
REM server_root.cmd is written by the installer and names the room's home
REM folder: the real one for a real install, the verify one for a /DVERIFY
REM build. The logon scheduled task has no environment to inherit, so reading
REM it from beside this script is what makes the task honest too. A
REM SIMPLECHAT_ROOT already in the environment wins - which is how start_server
REM passes a scratch root down at verification time. The old hard-coded default
REM is still the fallback.
if not defined SIMPLECHAT_ROOT if exist "%~dp0server_root.cmd" call "%~dp0server_root.cmd"
if not defined SIMPLECHAT_ROOT set "SIMPLECHAT_ROOT=%ProgramData%\SimpleChat"
set "ROOT=%SIMPLECHAT_ROOT%"

if not exist "%ROOT%" mkdir "%ROOT%"
if not exist "%ROOT%\data" mkdir "%ROOT%\data"

cd /d "%ROOT%" || exit /b 1

REM CMD'S /C QUOTE RULE - THE EXECUTABLE PATH IS DELIBERATELY BARE. `for /f
REM (' ... ')' runs its command through `cmd /c', and cmd strips the first and
REM last quote of any /c string that begins with a quote and holds more than
REM two, so the quoted form arrived as
REM     C:\Windows\System32\findstr.exe" /r /c:" *port
REM and was not a command at all: the port stayed at the default however
REM server.toml was edited. Measured 2026-09-03; see
REM installer\VERIFICATION-2026-09-03.md. Arguments still keep their quotes.
if exist "%ROOT%\server.toml" (
    for /f "tokens=2 delims==" %%P in ('%SYS%\findstr.exe /r /c:"^ *port *=" "%ROOT%\server.toml"') do (
        for /f "tokens=1" %%Q in ("%%P") do set "PORT=%%Q"
    )
)

echo. >> "%ROOT%\server.log"
echo ===== started %DATE% %TIME% ===== >> "%ROOT%\server.log"

REM --- port collision, named in the log rather than left as a mystery -------
REM Bare executable path, for the same reason as the findstr loop above: quoted,
REM this loop ran nothing at all, so the collision was never seen and the note
REM below never reached server.log.
set "HOLDER="
for /f "usebackq delims=" %%H in (`%SYS%\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$c = Get-NetTCPConnection -LocalPort %PORT% -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1; if ($c) { $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue; if ($p) { '{0} (PID {1})' -f $p.ProcessName, $c.OwningProcess } else { 'PID {0}' -f $c.OwningProcess } }"`) do set "HOLDER=%%H"

if defined HOLDER (
    echo LAUNCH REFUSED: port %PORT% is already in use by %HOLDER% >> "%ROOT%\server.log"
    echo   Two programs cannot share one port. Change `port' in >> "%ROOT%\server.log"
    echo   %ROOT%\server.toml to a free number, and local_port in >> "%ROOT%\server.log"
    echo   %%APPDATA%%\simple_chat\client.toml to the same number. >> "%ROOT%\server.log"
    exit /b 1
)

"%~dp0SimpleChatServer.exe" server.toml >> "%ROOT%\server.log" 2>&1
exit /b %ERRORLEVEL%
