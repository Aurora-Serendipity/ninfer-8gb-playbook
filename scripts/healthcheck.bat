@echo off
REM Healthcheck for the NInfer v2 engine: sends ONE REAL REQUEST (a 200 from /v1/models is not proof).
setlocal
cd /d "%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0healthcheck.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" pause
endlocal
exit /b %RC%
