@echo off
REM One-click START for the NInfer v2 daily tier (8g-fast based: ctx 131072, output 4096, MTP).
REM ASCII only on purpose. The real logic is in start-tier.ps1 next to this file.
setlocal
cd /d "%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-tier.ps1" -Tier daily
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" pause
endlocal
exit /b %RC%
