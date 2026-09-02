@echo off
REM ===========================================================================
REM view_log.cmd - "Server log" in the Start Menu. Opens it in Notepad,
REM creating an empty one if the server has never run.
REM ===========================================================================
setlocal
set "ROOT=%ProgramData%\SimpleChat"
if not exist "%ROOT%" mkdir "%ROOT%"
if not exist "%ROOT%\server.log" (
    echo (the server has not written anything yet)> "%ROOT%\server.log"
)
start "" notepad.exe "%ROOT%\server.log"
