@echo off
REM ===========================================================================
REM restore_backup.cmd - "Restore from backup" in the Start Menu.
REM
REM Puts a backup folder made by "Back up the room" into place as THE room.
REM This is what a standby host does with the copy the primary host sent, and
REM what the old primary does when it comes back from a failure.
REM
REM It refuses while the server is running, and it always sets the current
REM database aside first (into backups\replaced_<date>_<time>\) - so a restore
REM onto the wrong PC is never the end of the story.
REM ===========================================================================
setlocal EnableExtensions
set "ROOT=%ProgramData%\SimpleChat"
set "DATADIR=%ROOT%\data"

echo.
echo   Restore the room from a backup
echo   ------------------------------
echo.

tasklist /fi "IMAGENAME eq SimpleChatServer.exe" 2>nul | find /i "SimpleChatServer.exe" >nul
if not errorlevel 1 (
    echo   The server is RUNNING. Stop it first ^("Stop server" in the Start
    echo   Menu^), then run this again.
    echo.
    pause
    exit /b 1
)

echo   Give the folder that holds the backup - the one with simple_chat.db
echo   inside it. You can drag the folder onto this window instead of typing.
echo.
echo   Your backups are under: %ROOT%\backups
echo.

set "SRC="
set /p "SRC=Backup folder: "

REM Strip surrounding quotes if the folder was dragged in.
if defined SRC set "SRC=%SRC:"=%"

if not defined SRC (
    echo.
    echo   Nothing given. Nothing was changed.
    echo.
    pause
    exit /b 1
)

if not exist "%SRC%\simple_chat.db" (
    echo.
    echo   There is no simple_chat.db in:
    echo     %SRC%
    echo   Nothing was changed.
    echo.
    pause
    exit /b 1
)

echo.
echo   About to REPLACE the room on this PC with the copy in:
echo     %SRC%
echo.
echo   Every account, room and message currently on this PC will be set aside
echo   and the backup will take its place.
echo.
set "YES="
set /p "YES=Type  yes  to go ahead: "
if /i not "%YES%"=="yes" (
    echo.
    echo   Nothing was changed.
    echo.
    pause
    exit /b 1
)

if not exist "%DATADIR%" mkdir "%DATADIR%"

REM Set the current room aside, whole, before touching anything.
if exist "%DATADIR%\simple_chat.db" (
    for /f %%S in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HHmmss"') do set "STAMP=%%S"
    call :setaside
)

del /q "%DATADIR%\simple_chat.db" 2>nul
del /q "%DATADIR%\simple_chat.db-wal" 2>nul
del /q "%DATADIR%\simple_chat.db-shm" 2>nul

copy /y "%SRC%\simple_chat.db" "%DATADIR%\" >nul
if exist "%SRC%\simple_chat.db-wal" copy /y "%SRC%\simple_chat.db-wal" "%DATADIR%\" >nul
if exist "%SRC%\simple_chat.db-shm" copy /y "%SRC%\simple_chat.db-shm" "%DATADIR%\" >nul

echo.
echo   Restored. The room now holds what that backup held.
echo.
echo   Start the server when you are ready to take over
echo   ^("Start server" in the Start Menu^).
echo.
echo   REMEMBER THE RULE: only ONE of you runs a server at a time. Whoever was
echo   the primary must NOT start their server again until they have restored
echo   from a copy of YOURS - until then they are a client only, like everyone
echo   else. Two servers running at once means two different rooms drifting
echo   apart, and nothing merges them back.
echo.
pause
exit /b 0

:setaside
set "ASIDE=%ROOT%\backups\replaced_%STAMP%"
mkdir "%ASIDE%" 2>nul
copy /y "%DATADIR%\simple_chat.db" "%ASIDE%\" >nul
if exist "%DATADIR%\simple_chat.db-wal" copy /y "%DATADIR%\simple_chat.db-wal" "%ASIDE%\" >nul
if exist "%DATADIR%\simple_chat.db-shm" copy /y "%DATADIR%\simple_chat.db-shm" "%ASIDE%\" >nul
echo   The room that was here has been set aside in:
echo     %ASIDE%
goto :eof
