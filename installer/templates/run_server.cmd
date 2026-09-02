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
REM The working folder is set to C:\ProgramData\SimpleChat because the server
REM resolves data_dir relative to it, and because the Caddy front door looks
REM for caddy.exe in the working folder.
REM
REM This is also the path the logon scheduled task takes, through
REM start_server_hidden.vbs - with NO console to print to. So the port-collision
REM check writes its finding to server.log, which is the only place anyone will
REM look after a silent failure at boot.
REM ===========================================================================
setlocal
set "ROOT=%ProgramData%\SimpleChat"
set "PORT=8090"

if not exist "%ROOT%" mkdir "%ROOT%"
if not exist "%ROOT%\data" mkdir "%ROOT%\data"

cd /d "%ROOT%" || exit /b 1

if exist "%ROOT%\server.toml" (
    for /f "tokens=2 delims==" %%P in ('findstr /r /c:"^ *port *=" "%ROOT%\server.toml"') do (
        for /f "tokens=1" %%Q in ("%%P") do set "PORT=%%Q"
    )
)

echo. >> "%ROOT%\server.log"
echo ===== started %DATE% %TIME% ===== >> "%ROOT%\server.log"

REM --- port collision, named in the log rather than left as a mystery -------
set "HOLDER="
for /f "usebackq delims=" %%H in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
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
