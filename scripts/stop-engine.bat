@echo off
REM ============================================================
REM  stop-engine.bat  --  ONE-CLICK STOP for the local model
REM
REM  THIS FILE IS 100 PERCENT ASCII ON PURPOSE, INCLUDING COMMENTS.
REM  See start-engine.bat for the two cmd traps this avoids.
REM
REM  WHAT IT DOES
REM    1. looks for the engine process and shows it to you first
REM    2. asks once, Y or N, and defaults to YES after 10 seconds
REM    3. stops the process named ninfer-serve-89.exe
REM    4. re-checks the process list, port 8095 and the GPU memory
REM
REM  The engine keeps no state on disk, so stopping it cannot lose data.
REM  Model and engine files are never touched.
REM ============================================================
setlocal
set "PORT=8095"

echo ============================================================
echo   NInfer local model  --  STOP
echo ============================================================
echo.

tasklist /FI "IMAGENAME eq ninfer-serve-89.exe" 2>NUL | find /I "ninfer-serve-89.exe" >NUL
if errorlevel 1 goto notrunning

echo [find ] process to stop:
tasklist /FI "IMAGENAME eq ninfer-serve-89.exe"
echo.
echo [ask  ] press Y to stop it, N to cancel. Auto-yes in 10 seconds.
choice /C YN /T 10 /D Y /M "Stop the engine now"
if errorlevel 2 goto cancelled

echo.
echo [stop ] killing ninfer-serve-89.exe ...
taskkill /IM ninfer-serve-89.exe /F
REM sleep about three seconds; "timeout" aborts when stdin is redirected.
ping -n 4 127.0.0.1 >NUL
echo.

echo [check] process after stop:
tasklist /FI "IMAGENAME eq ninfer-serve-89.exe" 2>NUL | find /I "ninfer-serve-89.exe" >NUL
if errorlevel 1 echo         none - the engine is stopped
if not errorlevel 1 echo         STILL RUNNING - run this file again as administrator

echo [check] port %PORT% listening:
netstat -ano | find ":%PORT%" | find /I "LISTENING" >NUL
if errorlevel 1 echo         no - the port is free
if not errorlevel 1 echo         yes - something still holds the port

echo [check] GPU memory in use now, in MiB:
nvidia-smi --query-gpu=memory.used --format=csv,noheader
echo.
echo [done ] You can close this window.
echo.
pause
exit /b 0

:notrunning
echo [skip ] the engine is not running. Nothing to stop.
echo.
pause
exit /b 0

:cancelled
echo [cancel] nothing was stopped.
echo.
pause
exit /b 0
