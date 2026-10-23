@echo off
REM One-click START for the NInfer v2 long-context tier (8g-long based: ctx 262144, output 8192).
REM ASCII only on purpose. The real logic is in start-tier.ps1 next to this file.
setlocal
cd /d "%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-tier.ps1" -Tier longctx
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" pause
endlocal
exit /b %RC%
