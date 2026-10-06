# check-model.ps1 -- verify the model file by size and SHA256.
#
# Read-only: hashes the file and compares. Never writes, never deletes.
#
# WHY THIS EXISTS
#   The engine pack in this tree does not ship the modelor its MODELS.txt
#   manifest: the model travels as a SEPARATE delivery. So there is no
#   upstream sha256 on this machine to compare against. What can be
#   checked, and is checked here:
#     1. the byte count, against the one figure the upstream tutorial
#        states for this exact artifact (6,394,697,216 bytes), and
#     2. the sha256 against the value this deployment recorded when the
#        file was first placed, so a later corruption is still caught.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\check-model.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\check-model.ps1 -ExpectedSha256 <hex>

param(
  [string]$Model = (Join-Path (Split-Path $PSScriptRoot -Parent) '20-model\models\bonsai2_27b_ternary_ptq1_native_mtp.ninfer'),
  [long]$ExpectedBytes = 6394697216,
  [string]$ExpectedSha256 = '5C4486C8A52687E3F62072C7DD2A320546D0E00D1C019BF137EB02CC944E21B8'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Model)) {
  "MODELCHECK_VERDICT=MISSING"
  "MODELCHECK_PATH=$Model"
  exit 3
}

$item = Get-Item -LiteralPath $Model
$ok = $true

"MODELCHECK_PATH=$($item.FullName)"
"MODELCHECK_BYTES=$($item.Length)"
"MODELCHECK_BYTES_EXPECTED=$ExpectedBytes"
if ($item.Length -ne $ExpectedBytes) { $ok = $false; "MODELCHECK_SIZE=FAIL" } else { "MODELCHECK_SIZE=OK" }

"MODELCHECK_HASHING=started (this takes a few seconds on 6.4 GB)"
$sha = (Get-FileHash -LiteralPath $Model -Algorithm SHA256).Hash
"MODELCHECK_SHA256=$sha"
"MODELCHECK_SHA256_EXPECTED=$ExpectedSha256"
if ($sha -ne $ExpectedSha256) { $ok = $false; "MODELCHECK_HASH=FAIL" } else { "MODELCHECK_HASH=OK" }

if ($ok) {
  "MODELCHECK_VERDICT=OK"
} else {
  "MODELCHECK_VERDICT=FAIL"
  "MODELCHECK_REASON=size or hash mismatch -- re-download, do not start the engine"
}
if ($ok) { exit 0 } else { exit 1 }
