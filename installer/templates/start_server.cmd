@echo off
REM ===========================================================================
REM start_server.cmd - "Start server" in the Start Menu.
REM
REM Starts the server hidden, waits for it to come up, and tells you whether
REM it is answering. Closing this window does NOT stop the server.
REM ===========================================================================
setlocal
set "ROOT=%ProgramData%\SimpleChat"
set "PORT=8080"

REM Read the port out of server.toml so the check below asks the right door.
if exist "%ROOT%\server.toml" (
    for /f "tokens=2 delims==" %%P in ('findstr /r /c:"^ *port *=" "%ROOT%\server.toml"') do (
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

tasklist /fi "IMAGENAME eq SimpleChatServer.exe" 2>nul | find /i "SimpleChatServer.exe" >nul
if not errorlevel 1 (
    echo   The server is already running. Nothing to do.
    echo.
    pause
    exit /b 0
)

wscript.exe "%~dp0start_server_hidden.vbs"

echo   Waiting for it to answer...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ok=$false; for($i=0;$i -lt 20;$i++){ try { $r=Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Uri ('http://127.0.0.1:%PORT%/health'); if($r.StatusCode -eq 200){ Write-Host ''; Write-Host '   The server is up. It answered:'; Write-Host ('   ' + $r.Content); $ok=$true; break } } catch { Start-Sleep -Milliseconds 500 } }; if(-not $ok){ Write-Host ''; Write-Host '   The server did not answer.'; Write-Host '   Open \"Server log\" in the Start Menu to see why.' ; exit 1 }"

echo.
echo   Leave it running. Use "Stop server" in the Start Menu to stop it.
echo.
pause
