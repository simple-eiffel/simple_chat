@echo off
REM ===========================================================================
REM start_server.cmd - "Start server" in the Start Menu.
REM
REM Starts the server hidden, waits for it to come up, and tells you whether
REM it is answering. Closing this window does NOT stop the server.
REM
REM PORT COLLISION IS CHECKED FIRST. Apache, XAMPP, Tomcat and a dozen dev
REM tools sit on 8080, and a collision is the commonest reason the server does
REM not come up. Left to itself the server fails into server.log and the only
REM symptom is a chat window that cannot connect - so this names the program
REM holding the port and the two lines to change, before launching anything.
REM ===========================================================================
setlocal
set "SYS=%SystemRoot%\System32"
set "ROOT=%ProgramData%\SimpleChat"
set "PORT=8090"

REM Read the port out of server.toml so every check below asks the right door.
if exist "%ROOT%\server.toml" (
    for /f "tokens=2 delims==" %%P in ('"%SYS%\findstr.exe" /r /c:"^ *port *=" "%ROOT%\server.toml"') do (
        for /f "tokens=1" %%Q in ("%%P") do set "PORT=%%Q"
    )
)

echo.
echo   Starting the SimpleChat server
echo   -----------------------------
echo   folder : %ROOT%
echo   config : %ROOT%\server.toml
echo   log    : %ROOT%\server.log
echo   port   : %PORT%
echo.

"%SYS%\tasklist.exe" /fi "IMAGENAME eq SimpleChatServer.exe" 2>nul | "%SYS%\find.exe" /i "SimpleChatServer.exe" >nul
if not errorlevel 1 (
    echo   The server is already running. Nothing to do.
    echo.
    pause
    exit /b 0
)

REM --- is anything else already holding our port? -------------------------
set "HOLDER="
for /f "usebackq delims=" %%H in (`"%SYS%\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command ^
  "$c = Get-NetTCPConnection -LocalPort %PORT% -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1; if ($c) { $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue; if ($p) { '{0} (PID {1})' -f $p.ProcessName, $c.OwningProcess } else { 'PID {0}' -f $c.OwningProcess } }"`) do set "HOLDER=%%H"

if defined HOLDER (
    echo   PORT %PORT% IS ALREADY IN USE by %HOLDER%
    echo.
    echo   The server was NOT started. Two programs cannot share one port, so
    echo   it would only have failed into the log.
    echo.
    echo   Pick a free port instead - change these TWO lines, then try again:
    echo.
    echo     1. %ROOT%\server.toml
    echo          port = 8091
    echo        ^("Edit server config" in the Start Menu^)
    echo.
    echo     2. %%APPDATA%%\simple_chat\client.toml
    echo          local_port = 8091
    echo.
    echo   Any free number between 1024 and 65535 will do; they must MATCH.
    echo.
    pause
    exit /b 1
)

"%SYS%\wscript.exe" "%~dp0start_server_hidden.vbs"

echo   Waiting for it to answer...
"%SYS%\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ok=$false; for($i=0;$i -lt 20;$i++){ try { $r=Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Uri ('http://127.0.0.1:%PORT%/health'); if($r.StatusCode -eq 200){ Write-Host ''; Write-Host '   The server is up. It answered:'; Write-Host ('   ' + $r.Content); $ok=$true; break } } catch { Start-Sleep -Milliseconds 500 } }; if(-not $ok){ Write-Host ''; Write-Host '   The server did not answer.'; Write-Host '   Open \"Server log\" in the Start Menu to see why.' ; exit 1 }"

echo.
echo   Leave it running. Use "Stop server" in the Start Menu to stop it.
echo.
pause
