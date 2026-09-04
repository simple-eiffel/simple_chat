@echo off
REM ===========================================================================
REM stop_server.cmd - "Stop server" in the Start Menu.
REM
REM IT STOPS THE SERVER THAT BELONGS TO *THIS* INSTALL, MATCHED BY PATH.
REM
REM The server executable is deliberately named SimpleChatServer.exe: every
REM Eiffel target in this project finalizes to simple_chat.exe, so the client,
REM the server and the test runner would otherwise be three files with one
REM name, and a "%SYS%\taskkill.exe" on THAT name would be a loaded gun. That
REM rename is still what makes stopping the server safe at all - it is why
REM nothing of YOURS is ever in range.
REM
REM But a name is not an identity. On 2026-09-04 a kill by IMAGE NAME took a
REM live room down twice, because a SECOND install of this same product has a
REM SimpleChatServer.exe of exactly that name: a client-only install, or a
REM /DVERIFY verification build sitting in its own folder under its own AppId,
REM is a different product in every respect the installer can switch - except
REM the executable's name, which is the same compiled binary either way. So
REM "taskkill /F /IM SimpleChatServer.exe" reached across every install on the
REM PC and stopped the one somebody was actually talking in.
REM
REM Both stops below therefore match on the FULL EXECUTABLE PATH:
REM
REM   the server : "%~dp0SimpleChatServer.exe" - the copy beside THIS script
REM   caddy      : "%ROOT%\caddy.exe"          - the copy in THIS install's
REM                                              room folder, which is where
REM                                              CADDY_FRONT_DOOR looks for it
REM                                              and where the installer put it
REM
REM Another install's server, and any other caddy.exe on the PC, are left
REM alone. The path comparison is done in PowerShell because tasklist and
REM taskkill can filter on an image NAME and not on a path; the two paths are
REM handed over in the environment rather than on the command line, so a space
REM or a bracket in "C:\Program Files (x86)\..." cannot be re-parsed on the way.
REM ===========================================================================
setlocal
set "SYS=%SystemRoot%\System32"
set "PS=%SYS%\WindowsPowerShell\v1.0\powershell.exe"

REM --- WHICH ROOM? ----------------------------------------------------------
REM The same three-step answer run_server.cmd and start_server.cmd give: a
REM SIMPLECHAT_ROOT already in the environment wins, then server_root.cmd as
REM the installer wrote it beside this script, then the old hard-coded default.
REM It is needed here for caddy.exe alone - caddy lives in the room folder, not
REM beside this script.
if not defined SIMPLECHAT_ROOT if exist "%~dp0server_root.cmd" call "%~dp0server_root.cmd"
if not defined SIMPLECHAT_ROOT set "SIMPLECHAT_ROOT=%ProgramData%\SimpleChat"
set "ROOT=%SIMPLECHAT_ROOT%"

set "SERVER_EXE=%~dp0SimpleChatServer.exe"
set "CADDY_EXE=%ROOT%\caddy.exe"

echo.

REM Exit status IS the count of matching processes, so `errorlevel 1' means
REM "at least one server of ours is running".
"%PS%" -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
  "exit @(Get-Process -Name SimpleChatServer -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $env:SERVER_EXE }).Count" >nul 2>&1
if errorlevel 1 goto :stop_it

echo   The server is not running.
echo.
pause
exit /b 0

:stop_it
echo   Stopping the SimpleChat server...
"%PS%" -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
  "$p = @(Get-Process -Name SimpleChatServer -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $env:SERVER_EXE }); if ($p.Count -gt 0) { $p | Stop-Process -Force -ErrorAction SilentlyContinue; $p | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue }; exit 0" >nul 2>&1

REM Caddy, if the front door was on, is stopped by the server itself on the way
REM out. If it was orphaned by a hard kill, clear it up too - but only the copy
REM that lives in our own folder. That was always the intention written here;
REM until 2026-09-04 the code below it said /IM caddy.exe and did not honour it.
REM No parentheses around the second call: a caret continuation inside an
REM `if ( ... )' block is parsed with the whole block and does not survive the
REM quoting. A label is the plain way to write it.
"%PS%" -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
  "exit @(Get-Process -Name caddy -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $env:CADDY_EXE }).Count" >nul 2>&1
if not errorlevel 1 goto :stopped

echo   Stopping the Caddy front door...
"%PS%" -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
  "Get-Process -Name caddy -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $env:CADDY_EXE } | Stop-Process -Force -ErrorAction SilentlyContinue" >nul 2>&1

:stopped
echo   Stopped.
echo.
pause
