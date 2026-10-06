@echo off
REM ============================================================
REM  start-ptq1-mtp-verbatim.bat
REM  The engine pack's own argv, byte-for-byte, kept for reference.
REM
REM  DO NOT USE THIS ON THIS MACHINE. It is here so the shipped
REM  configuration stays reproducible and so the difference between
REM  "as shipped" and "as fitted" is visible instead of being folklore.
REM
REM  Run on this machine (RTX 4060 Laptop, 8188 MiB VRAM) it exits with:
REM    requested Engine runtime reservation requires 1863978752 bytes,
REM    but only 1027604480 bytes are available for runtime capacity
REM
REM  Use ..\21-launchers\start-ptq1-mtp-8g.bat instead. That one starts.
REM
REM  Only the paths were changed here (the shipped .bat lives next to its
REM  own engine and models folders; in this tree those moved). Every
REM  argument below is copied verbatim from the shipped launcher, and the
REM  shipped file itself is preserved unmodified at:
REM    ..\40-docs\pack\start-ptq1-mtp.bat
REM
REM  ASCII-only on purpose, same reason as everywhere else in this tree.
REM ============================================================
setlocal
set "PACKROOT=%~dp0.."
set "ENGINE=%PACKROOT%\10-engine\engine\ninfer-serve-89.exe"
if not defined MODEL set "MODEL=%PACKROOT%\20-model\models\bonsai2_27b_ternary_ptq1_native_mtp.ninfer"
if not exist "%ENGINE%" goto noengine
if not exist "%MODEL%" goto nomodel

set "CUDA_BIN=%PACKROOT%\10-engine\engine"
set "PATH=%CUDA_BIN%;%CUDA_BIN%\x64;%PATH%"
set "NINFER_KV_WINDOW=16384"
set "NINFER_KV_RETRIEVE=8192"
set "NINFER_KV_RING=1"
set "NINFER_HOST_PAGEABLE=1"
set "NINFER_KV_REUSE_HOSTBACKED=1"
set "NINFER_TERNARY_PTQ1_FAST=1"

echo [engine] %ENGINE%
echo [model ] %MODEL%
echo [note  ] VERBATIM shipped argv -- expected to FAIL on an 8 GB card
echo [note  ] content scorer defaults ON; NINFER_TERNARY_KVMEM=0 is the negative control

"%ENGINE%" "%MODEL%" ^
  --host 127.0.0.1 --port 8095 --model-id qwen3.8-27b ^
  --max-context 262144 --kv-capacity 17920 --kv-dtype k8v4 --host-kv-mib 16384 ^
  --prefill-chunk 1024 --spec mtp --draft-tokens 4 ^
  --default-max-tokens 32768 --default-reasoning-effort none --max-concurrency 1 ^
  --max-shared-prefixes 0 ^
  --presence-penalty 0 --temperature 0.7 --top-p 0.9 --top-k 20

echo.
echo [engine exited] errorlevel=%ERRORLEVEL%
pause
exit /b 0

:nomodel
echo REFUSE: model file not found: %MODEL%
pause
exit /b 3

:noengine
echo REFUSE: engine not found: %ENGINE%
pause
exit /b 4
