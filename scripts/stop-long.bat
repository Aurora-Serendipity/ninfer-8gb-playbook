@echo off
REM One-click STOP for the NInfer v2 engine (works for either tier; the launcher stops what it owns).
setlocal
cd /d "%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop-tier.ps1" -Tier longctx
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" pause
endlocal
exit /b %RC%
