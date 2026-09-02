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
REM ===========================================================================
setlocal
set "ROOT=%ProgramData%\SimpleChat"

if not exist "%ROOT%" mkdir "%ROOT%"
if not exist "%ROOT%\data" mkdir "%ROOT%\data"

cd /d "%ROOT%" || exit /b 1

echo. >> "%ROOT%\server.log"
echo ===== started %DATE% %TIME% ===== >> "%ROOT%\server.log"

"%~dp0SimpleChatServer.exe" server.toml >> "%ROOT%\server.log" 2>&1
exit /b %ERRORLEVEL%
