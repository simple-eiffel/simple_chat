@echo off
REM ===========================================================================
REM backup_room.cmd - "Back up the room" in the Start Menu.
REM
REM Makes a dated copy of the room - accounts, rooms, messages, the lot - into
REM     C:\ProgramData\SimpleChat\backups\<date>_<time>\
REM That folder is what you send to your standby host.
REM
REM WHY IT STOPS FIRST: the database is kept in SQLite's WAL mode, so at any
REM moment some committed messages may still be sitting in the companion file
REM simple_chat.db-wal rather than in simple_chat.db. Copying a live database
REM is how people lose the last hour of a conversation. This script refuses to
REM run while the server is up, and copies the whole file set together so the
REM copy is internally consistent.
REM ===========================================================================
setlocal
set "ROOT=%ProgramData%\SimpleChat"
set "DATADIR=%ROOT%\data"

echo.
echo   Back up the room
echo   ----------------
echo.

tasklist /fi "IMAGENAME eq SimpleChatServer.exe" 2>nul | find /i "SimpleChatServer.exe" >nul
if not errorlevel 1 (
    echo   The server is RUNNING.
    echo.
    echo   Stop it first ^("Stop server" in the Start Menu^), then run this
    echo   again. Copying a live database can silently lose the most recent
    echo   messages, so this will not do it.
    echo.
    pause
    exit /b 1
)

if not exist "%DATADIR%\simple_chat.db" (
    echo   There is no room to back up yet: %DATADIR%\simple_chat.db
    echo   does not exist. Start the server once and create an admin first.
    echo.
    pause
    exit /b 1
)

for /f %%S in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HHmmss"') do set "STAMP=%%S"
set "DEST=%ROOT%\backups\%STAMP%"

mkdir "%DEST%" 2>nul

copy /y "%DATADIR%\simple_chat.db" "%DEST%\" >nul
if exist "%DATADIR%\simple_chat.db-wal" copy /y "%DATADIR%\simple_chat.db-wal" "%DEST%\" >nul
if exist "%DATADIR%\simple_chat.db-shm" copy /y "%DATADIR%\simple_chat.db-shm" "%DEST%\" >nul

echo   Backed up to:
echo     %DEST%
echo.
dir /b "%DEST%"
echo.
echo   Send that WHOLE FOLDER to your standby host - all of the files in it,
echo   not just simple_chat.db. They put it in place with "Restore from
echo   backup" on their PC.
echo.
start "" explorer.exe "%DEST%"
pause
