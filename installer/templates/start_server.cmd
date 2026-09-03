@echo off
REM ===========================================================================
REM start_server.cmd - "Start server" in the Start Menu, and STEP 2 of the
REM installer's finish sequence.
REM
REM Starts the server hidden, waits for it to come up, and tells you whether
REM it is answering. Closing this window does NOT stop the server.
REM
REM     start_server.cmd            pauses at the end, as a Start Menu entry
REM                                 should: a human asked for this deliberately.
REM     start_server.cmd /nopause   holds the window open long enough to read
REM                                 and then closes itself.
REM
REM /nopause exists for the installer. The wizard runs this script with
REM `waituntilterminated', so the next step - opening the chat window - does not
REM begin until this one has ended; a `pause' there would stall the whole finish
REM sequence behind a keypress. It changes nothing else: the /health answer is
REM still printed, and a port collision is still named.
REM
REM PORT COLLISION IS CHECKED FIRST. Apache, XAMPP, Tomcat and a dozen dev
REM tools sit on 8080, and a collision is the commonest reason the server does
REM not come up. Left to itself the server fails into server.log and the only
REM symptom is a chat window that cannot connect - so this names the program
REM holding the port and the two lines to change, before launching anything.
REM ===========================================================================
setlocal
set "SYS=%SystemRoot%\System32"
set "PORT=8090"

set "NOPAUSE="
if /i "%~1"=="/nopause" set "NOPAUSE=1"

REM --- WHICH ROOM? ----------------------------------------------------------
REM server_root.cmd is written by the installer and names the room's home
REM folder: the real one for a real install, the verify one for a /DVERIFY
REM build. That is what keeps a test install from ever starting a server
REM against the real room. A SIMPLECHAT_ROOT already in the environment wins
REM over both, which is how this script is driven against a scratch root at
REM verification time - and run_server.cmd, which this launches through the
REM .vbs, inherits it. The old hard-coded default is still the fallback.
if not defined SIMPLECHAT_ROOT if exist "%~dp0server_root.cmd" call "%~dp0server_root.cmd"
if not defined SIMPLECHAT_ROOT set "SIMPLECHAT_ROOT=%ProgramData%\SimpleChat"
set "ROOT=%SIMPLECHAT_ROOT%"

REM Read the port out of server.toml so every check below asks the right door.
REM
REM CMD'S /C QUOTE RULE - THE EXECUTABLE PATH IS DELIBERATELY BARE.
REM `for /f (' ... ')' runs its command through `cmd /c', and cmd strips the
REM first and last quote of any /c string that begins with a quote and holds
REM more than two. So the quoted form
REM     '"%SYS%\findstr.exe" /r /c:"^ *port *=" "%ROOT%\server.toml"'
REM arrived as   C:\Windows\System32\findstr.exe" /r /c:" *port   - not a
REM command at all. The loop set nothing, the port silently stayed at the
REM default, and a host who had changed it got a health probe and a collision
REM check aimed at the wrong door. Measured 2026-09-03; see
REM installer\VERIFICATION-2026-09-03.md. System32 has no space in its path, so
REM leaving it bare costs nothing, and every ARGUMENT still keeps its quotes.
if exist "%ROOT%\server.toml" (
    for /f "tokens=2 delims==" %%P in ('%SYS%\findstr.exe /r /c:"^ *port *=" "%ROOT%\server.toml"') do (
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
    call :hold 4
    exit /b 0
)

REM --- is anything else already holding our port? -------------------------
REM Bare executable path, for the same reason as the findstr loop above: quoted,
REM this loop ran nothing at all, so a port collision was never detected and the
REM server was launched into a door that was already taken.
set "HOLDER="
for /f "usebackq delims=" %%H in (`%SYS%\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
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
    call :hold 15
    exit /b 1
)

"%SYS%\wscript.exe" "%~dp0start_server_hidden.vbs"

echo   Waiting for it to answer...
"%SYS%\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ok=$false; for($i=0;$i -lt 20;$i++){ try { $r=Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Uri ('http://127.0.0.1:%PORT%/health'); if($r.StatusCode -eq 200){ Write-Host ''; Write-Host '   The server is up. It answered:'; Write-Host ('   ' + $r.Content); $ok=$true; break } } catch { Start-Sleep -Milliseconds 500 } }; if(-not $ok){ Write-Host ''; Write-Host '   The server did not answer.'; Write-Host '   Open \"Server log\" in the Start Menu to see why.' ; exit 1 }"
set "ANSWERED=%ERRORLEVEL%"

if not "%ANSWERED%"=="0" (
    echo.
    call :hold 15
    exit /b 1
)

echo.
echo   Leave it running. Use "Stop server" in the Start Menu to stop it.
echo.
call :hold 5
exit /b 0

REM --- pause, or hold the window open long enough to read -------------------
REM Without /nopause this is the plain `pause' a Start Menu entry has always
REM had. With it the window stays up for about %1 seconds and then the script
REM ends by itself, so the wizard can move on to the next step.
REM
REM PING, NOT TIMEOUT. timeout.exe wants a console it can read a keypress from;
REM given a redirected or NUL stdin it does not return at all - it wedged a
REM verification run on 2026-09-03. ping to the loopback is the batch sleep that
REM has no opinion about stdin. It cannot be cut short by a keypress, which is a
REM fair trade for a step that must never wedge the installer.
:hold
if not defined NOPAUSE (
    pause
    exit /b 0
)
"%SYS%\PING.EXE" -n %1 127.0.0.1 >nul 2>&1
exit /b 0
