@echo off
REM ============================================================
REM  start-engine.bat  --  ONE-CLICK START for the local model
REM
REM  THIS FILE IS 100 PERCENT ASCII ON PURPOSE, INCLUDING COMMENTS.
REM  cmd parses a .bat in the OEM codepage: a non-ASCII byte inside a
REM  REM line stops being a comment and its fragments run as commands.
REM  A ")" inside a comment or an echo can also close an enclosing
REM  block early. The comments and echoes below avoid both traps.
REM
REM  WHAT IT DOES
REM    1. refuses to start a second copy when the engine is running
REM    2. checks the engine file, the model file and the launcher
REM    3. prints the GPU memory reading so a busy card is visible
REM    4. opens the measured-good launcher in its own window
REM    5. waits for the service and then sends ONE REAL REQUEST,
REM       because a 200 from /v1/models is NOT proof of a live service
REM
REM  HOW TO STOP
REM    run stop-engine.bat, or just close the window titled NInfer engine
REM ============================================================
setlocal
set "HERE=%~dp0"
set "ROOT=%HERE%.."
set "ENGINE=%ROOT%\10-engine\engine\ninfer-serve-89.exe"
set "MODEL=%ROOT%\20-model\models\bonsai2_27b_ternary_ptq1_native_mtp.ninfer"
set "LAUNCHER=%HERE%start-ptq1-mtp-8g-safety.bat"
set "PORT=8095"

echo ============================================================
echo   NInfer local model  --  START
echo ============================================================
echo.

tasklist /FI "IMAGENAME eq ninfer-serve-89.exe" 2>NUL | find /I "ninfer-serve-89.exe" >NUL
if not errorlevel 1 goto already

if not exist "%ENGINE%" goto noengine
if not exist "%MODEL%" goto nomodel
if not exist "%LAUNCHER%" goto nolauncher

echo [check] GPU memory in use right now, in MiB:
nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader
echo         the engine needs roughly 6.6 GB free. If it fails to start
echo         with a reservation error, close games or GPU apps and retry.
echo.

echo [start] opening the engine console in a new window...
start "NInfer engine" "%LAUNCHER%"
echo.

echo [wait ] waiting for http://127.0.0.1:%PORT%/v1/models ...
set /a tries=0
:wait
set /a tries+=1
curl.exe -s -o NUL --fail --max-time 5 http://127.0.0.1:%PORT%/v1/models
if not errorlevel 1 goto serving
if %tries% GEQ 60 goto notready
REM sleep about one second. "timeout" is NOT usable here: it aborts when
REM stdin is redirected, which breaks the poll when the script is called
REM from another script or with input redirected. ping always works.
ping -n 2 127.0.0.1 >NUL
goto wait

:serving
echo [ok   ] the port answered after about %tries% seconds.
echo.
echo [proof] one REAL request follows. A 200 from /v1/models alone is not proof.
set "BODY={\"model\":\"qwen3.8-27b\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: OK\"}],\"temperature\":0,\"max_tokens\":8}"
curl.exe -s http://127.0.0.1:%PORT%/v1/chat/completions -H "Content-Type: application/json" -d "%BODY%"
echo.
echo         If the text above contains content and OK, the service is really up.
echo.
echo [note ] the engine log is in the window titled NInfer engine.
echo [note ] stop the engine with stop-engine.bat, or close that window.
echo.
pause
exit /b 0

:notready
echo [warn ] no answer after 60 seconds. The engine window has the real reason.
echo         Things to check, in this order:
echo           1. the engine window said FATAL or worker crash
echo           2. another GPU app is holding memory
echo           3. you are already running an engine on this port
echo         Run stop-engine.bat, then start-engine.bat again.
echo.
pause
exit /b 2

:already
echo [skip ] the engine is ALREADY running. Nothing to do.
echo         To restart: run stop-engine.bat first, then this file again.
echo.
pause
exit /b 0

:noengine
echo [ERROR] engine file not found:
echo         %ENGINE%
echo.
pause
exit /b 3

:nomodel
echo [ERROR] model file not found:
echo         %MODEL%
echo.
pause
exit /b 4

:nolauncher
echo [ERROR] launcher not found:
echo         %LAUNCHER%
echo.
pause
exit /b 5
