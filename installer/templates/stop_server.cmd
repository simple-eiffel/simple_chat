@echo off
REM ===========================================================================
REM stop_server.cmd - "Stop server" in the Start Menu.
REM
REM Safe to run at any time. The server executable is deliberately named
REM SimpleChatServer.exe and nothing else on this PC is called that, so
REM stopping it by name cannot hit the chat window or anything of yours.
REM (Every Eiffel target in this project builds to simple_chat.exe, which is
REM why the installer renames them apart - a "%SYS%\taskkill.exe" on THAT name would be a
REM loaded gun.)
REM ===========================================================================
setlocal
set "SYS=%SystemRoot%\System32"

echo.
"%SYS%\tasklist.exe" /fi "IMAGENAME eq SimpleChatServer.exe" 2>nul | "%SYS%\find.exe" /i "SimpleChatServer.exe" >nul
if errorlevel 1 (
    echo   The server is not running.
    echo.
    pause
    exit /b 0
)

echo   Stopping the SimpleChat server...
"%SYS%\taskkill.exe" /F /IM SimpleChatServer.exe >nul 2>&1

REM Caddy, if the front door was on, is stopped by the server itself on the way
REM out. If it was orphaned by a hard kill, clear it up too - but only the copy
REM that lives in our own folder.
"%SYS%\tasklist.exe" /fi "IMAGENAME eq caddy.exe" 2>nul | "%SYS%\find.exe" /i "caddy.exe" >nul
if not errorlevel 1 (
    echo   Stopping the Caddy front door...
    "%SYS%\taskkill.exe" /F /IM caddy.exe >nul 2>&1
)

echo   Stopped.
echo.
pause
