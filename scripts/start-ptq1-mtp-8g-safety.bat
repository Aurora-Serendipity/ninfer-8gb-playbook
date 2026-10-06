@echo off
REM ============================================================
REM  start-ptq1-mtp-8g-safety.bat  --  MEASURED-GOOD tier fit PLUS the two
REM  B01 safety switches. This is a COPY of start-ptq1-mtp-8g.bat; that file
REM  is left byte-identical and remains the reference launcher.
REM  Model : ..\20-model\models\bonsai2_27b_ternary_ptq1_native_mtp.ninfer
REM  Engine: ..\10-engine\engine\ninfer-serve-89.exe
REM  Port  : 8095
REM
REM  WHY THE TWO EXTRA SWITCHES  -  from upstream's open bug ledger, item B01,
REM  which is their top unresolved P0:
REM    an over-pool prompt PLUS a large output lease makes the worker die with
REM    "Paged KV reservation invariant was violated"; after that, every request
REM    on that instance returns 503. Measured single-variable control on an
REM    8 GB card: request max_tokens clamped to 2048 survives, 8192 kills it.
REM  Both switches are ALREADY INSIDE this engine binary. The upstream ledger
REM  scanned the shipped exe and found them, and notes that no shipped
REM  launcher ever used them:
REM    --recover-invariant-failures  an invariant failure fails only the
REM                                  current request instead of killing the
REM                                  engine - this treats the zombie state
REM    --kv-lease-growth             when the pool is short, finish with a
REM                                  bounded completion instead of raising
REM                                  the invariant
REM  Layered safety on this box: --max-shared-prefixes 0 against the
REM  brick-on-resend path, --default-max-tokens 2048 against B01, and now
REM  these two. A client can still ask for more than the pool, so keep the
REM  request max_tokens at or below 4032; 2048 is what was measured safe.
REM  HONEST STATUS: --recover-invariant-failures is described upstream as
REM  directly treating the zombie state. --kv-lease-growth was marked
REM  "untested" in one doc and "one external case held" in a later ledger.
REM  Re-verify after any change. Record lives in ..\40-docs\notes\.
REM
REM  THIS FILE IS 100 PERCENT ASCII ON PURPOSE, INCLUDING COMMENTS.
REM  cmd parses a .bat in the OEM/ANSI codepage. A non-ASCII byte in a
REM  REM line stops being a comment and its fragments run as commands.
REM  A ")" inside a comment or a quoted echo also closes an enclosing
REM  "if not exist (...)" block early. Both traps were hit while
REM  building this; that is why the comments here are plain English.
REM  See ..\40-docs\notes\ for the full rationale.
REM
REM  WHAT THIS SCRIPT DOES
REM  This is a DOCUMENTED TIER FIT for a card with 8 GB VRAM, not a
REM  tuning tweak. The engine pack's own launcher was run verbatim and
REM  failed on this machine:
REM    requested Engine runtime reservation requires 1863978752 bytes,
REM    but only 1027604480 bytes are available for runtime capacity
REM  That is the failure the upstream docs name "tier fit, not an
REM  engine defect". The remedies below are the documented ones.
REM
REM  ARGV, AND WHY IT DIFFERS FROM THE SHIPPED LAUNCHER
REM    --kv-capacity 4032        shipped 17920. 4032 = 63 pages, the
REM                              smallest device pool the docs measured.
REM    --host-kv-mib 4096        shipped 16384. Shrink the host tier.
REM    --max-context 65536       shipped 262144. Keeps the capacity rule
REM                              true: host pages + device pages >=
REM                              logical-context pages.
REM    --default-max-tokens 2048 shipped 32768. The docs require
REM                              max_tokens <= device pool tokens.
REM    --gdn-state-fp16          added. Documented small-card lever.
REM    --no-cuda-graph           added. Measured: the per-profile CUDA
REM                              Graph driver-state allowance is what
REM                              kept 4032 from fitting.
REM  UNCHANGED and still verbatim: --kv-dtype k8v4, --max-concurrency 1,
REM  --max-shared-prefixes 0, --spec mtp, --draft-tokens 4,
REM  --default-reasoning-effort none, --prefill-chunk 1024, the sampling
REM  flags, and all six NINFER environment lines.
REM
REM  MEASURED RESULT ON THIS MACHINE
REM    engine ready; capacity 4,032 tokens, pages 63/1,024, runtime
REM    457.6 MiB, free 560.0 MiB.
REM    req#1 (counting corpus, 1000 in / 1000 out): TTFT 2.1 s,
REM    total 15.9 s, prefill 551.7 tok/s, decode 72.1 tok/s,
REM    mtp accepted 779/879 = 88.6 percent.
REM    KVMem: "content scoring ON by default" and "kvmem_score: SELECT".
REM
REM  USAGE
REM    Double-click it, or run it from a command prompt. Stop the engine
REM    with Ctrl+C in its console window.
REM ============================================================
setlocal
set "ROOT=%~dp0"
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
echo [note  ] 8 GB tier fit: kv-capacity 4032 / host-kv-mib 4096 / max-context 65536
echo [note  ] gdn-state-fp16 + no-cuda-graph are required to fit 8 GB VRAM
echo [note  ] content scorer defaults ON; NINFER_TERNARY_KVMEM=0 is the negative control
echo [note  ] ready when you see "engine ready" and a "capacity |" line

"%ENGINE%" "%MODEL%" ^
  --host 127.0.0.1 --port 8095 --model-id qwen3.8-27b ^
  --max-context 65536 --kv-capacity 4032 --kv-dtype k8v4 --host-kv-mib 4096 ^
  --prefill-chunk 1024 --spec mtp --draft-tokens 4 ^
  --default-max-tokens 2048 --default-reasoning-effort none --max-concurrency 1 ^
  --max-shared-prefixes 0 --gdn-state-fp16 --no-cuda-graph ^
  --recover-invariant-failures --kv-lease-growth ^
  --presence-penalty 0 --temperature 0.7 --top-p 0.9 --top-k 20

echo.
echo [engine exited] errorlevel=%ERRORLEVEL%
pause
exit /b 0

:nomodel
echo REFUSE: model file not found:
echo         %MODEL%
echo         Expected at ..\20-model\models\ next to this launcher folder.
pause
exit /b 3

:noengine
echo REFUSE: engine not found:
echo         %ENGINE%
echo         Expected at ..\10-engine\engine\ next to this launcher folder.
pause
exit /b 4
