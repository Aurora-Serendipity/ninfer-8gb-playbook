@echo off
REM Open the NInfer v2 control UI. Starts the launcher if it is not running yet.
setlocal
cd /d "%~dp0"
start "NInfer launcher" "%~dp0..\10-engine\runtime\python\python.exe" "%~dp0..\10-engine\launcher.py" --no-browser
ping -n 3 127.0.0.1 >NUL
start "" "http://127.0.0.1:8720"
endlocal
exit /b 0
