param(
    [string]$Model = (Join-Path (Split-Path -Parent $PSScriptRoot) '20-model\models\bonsai2_27b_ternary_ptq1_native_mtp.ninfer'),
    [string]$EngineLink = (Join-Path (Split-Path -Parent $PSScriptRoot) '10-engine\model\bonsai2_27b_ternary_ptq1_native_mtp.ninfer'),
    [long]$ExpectedBytes = 6394697216,
    [string]$ExpectedSha256 = '5C4486C8A52687E3F62072C7DD2A320546D0E00D1C019BF137EB02CC944E21B8'
)
$ErrorActionPreference = 'Continue'

Write-Host ''
Write-Host '============================================================'
Write-Host '  NInfer v2 - model artifact check (bytes + SHA256 + hardlink)'
Write-Host '============================================================'
Write-Host ''

$fail = 0
foreach ($path in @($Model, $EngineLink)) {
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host ('[FAIL] missing: ' + $path)
        $fail = 1
        continue
    }
    $fi = Get-Item -LiteralPath $path
    Write-Host ('[info] ' + $path)
    Write-Host ('       bytes=' + $fi.Length + ' linkType=' + $fi.LinkType)
    if ($fi.Length -ne $ExpectedBytes) {
        Write-Host ('[FAIL] byte length ' + $fi.Length + ' != expected ' + $ExpectedBytes)
        $fail = 1
    }
}

if ($fail -eq 0) {
    Write-Host '[..] computing SHA256 of the canonical model (about 10-30 s for 6.4 GB) ...'
    $actual = (Get-FileHash -LiteralPath $Model -Algorithm SHA256).Hash.ToUpper()
    Write-Host ('[info] sha256=' + $actual)
    if ($actual -ne $ExpectedSha256.ToUpper()) {
        Write-Host '[FAIL] SHA256 does not match the expected value'
        $fail = 1
    } else {
        Write-Host '[ok] SHA256 matches'
    }
    $linkHash = (Get-FileHash -LiteralPath $EngineLink -Algorithm SHA256).Hash.ToUpper()
    if ($linkHash -ne $actual) {
        Write-Host '[FAIL] the engine-side hardlink points to different bytes'
        $fail = 1
    } else {
        Write-Host '[ok] the engine-side path is the same bytes (hardlink)'
    }
}

Write-Host ''
if ($fail -eq 0) {
    Write-Host 'MODELCHECK_VERDICT=OK'
    Write-Host 'MODELCHECK_BYTES=OK'
    Write-Host 'MODELCHECK_HASH=OK'
    exit 0
}
Write-Host 'MODELCHECK_VERDICT=FAIL'
exit 1
