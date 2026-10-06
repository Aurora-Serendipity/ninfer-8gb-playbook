@echo off
REM ============================================================
REM  healthcheck.bat
REM  Tells you whether the engine is REALLY serving.
REM
REM  The upstream docs are explicit about this: a 200 from /v1/models is
REM  NOT proof of service -- after a worker crash it still answers 200.
REM  The only valid liveness check is a real request. This script sends
REM  one short request and prints the answer.
REM
REM  Requires: the engine started with start-ptq1-mtp-8g.bat (port 8095).
REM  ASCII-only on purpose.
REM ============================================================
setlocal
set "PORT=8095"
if not "%~1"=="" set "PORT=%~1"
set "BODY={\"model\":\"qwen3.8-27b\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: OK\"}],\"temperature\":0,\"max_tokens\":8}"

echo [check] port %PORT% -- /v1/models status code:
curl.exe -s -o NUL -w "%%{http_code}\n" http://127.0.0.1:%PORT%/v1/models

echo [check] real request (the only valid liveness proof):
curl.exe -s http://127.0.0.1:%PORT%/v1/chat/completions ^
  -H "Content-Type: application/json" ^
  -d "%BODY%"
echo.
echo [done ] if you saw an answer above, the engine is serving.
pause
exit /b 0
