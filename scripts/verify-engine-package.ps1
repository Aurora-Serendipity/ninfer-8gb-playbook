param(
    [string]$Pkg = (Join-Path (Split-Path -Parent $PSScriptRoot) '10-engine')
)
$ErrorActionPreference = 'Continue'

Write-Host ''
Write-Host '============================================================'
Write-Host '  NInfer v2 - verify engine package (SHA256SUMS.txt)'
Write-Host ('  package: ' + $Pkg)
Write-Host '============================================================'
Write-Host ''

$sumFile = Join-Path $Pkg 'SHA256SUMS.txt'
if (-not (Test-Path $sumFile)) {
    Write-Host ('[FAIL] manifest not found: ' + $sumFile)
    exit 3
}

# Local patch L-01/L-02 intentionally changes these two files; their shipped hashes are pinned here.
$localDeviations = @{
    'launcher.py'   = 'AE367E8B8D86881BE538864D92DB3847A24466DD2F4CE0DE6E0833C7E40A2425'
    'profiles.json' = 'E0F30F3750737FBE6836A73DCF80B8AD22850D10B60EBFDB519FBE6946BE5C13'
}
$okCount = 0
$mismatchCount = 0
$missingCount = 0
$deviationCount = 0
$unparsedCount = 0

foreach ($line in (Get-Content $sumFile -Encoding UTF8)) {
    if ($line -notmatch '^([0-9A-Fa-f]{64})\s(?:  +)?(.+)$') { $unparsedCount++; continue }
    $expected = $Matches[1].ToUpper()
    $rel = $Matches[2].Trim()
    $path = Join-Path $Pkg $rel
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host ('MISSING  ' + $rel)
        $missingCount++
        continue
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpper()
    if ($actual -eq $expected) {
        $okCount++
    } elseif ($localDeviations.ContainsKey($rel)) {
        Write-Host ('DEVIATED ' + $rel + '  (local patch L-01/L-02)')
        $deviationCount++
    } else {
        Write-Host ('MISMATCH ' + $rel)
        Write-Host ('         expected ' + $expected)
        Write-Host ('         actual   ' + $actual)
        $mismatchCount++
    }
}

# The two patched files must still match their shipped hashes in the pristine backup.
$pristine = Join-Path (Split-Path -Parent $PSScriptRoot) '_migration-v2\pristine'
foreach ($rel in $localDeviations.Keys) {
    $backup = Join-Path $pristine ($rel + '.orig-dist')
    if (Test-Path -LiteralPath $backup) {
        $backupHash = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToUpper()
        if ($backupHash -eq $localDeviations[$rel]) {
            Write-Host ('[ok] pristine backup matches the shipped hash: ' + $rel)
        } else {
            Write-Host ('[FAIL] pristine backup hash mismatch: ' + $rel)
            $mismatchCount++
        }
    } else {
        Write-Host ('[warn] pristine backup not found for ' + $rel + ' (expected at ' + $backup + ')')
    }
}

Write-Host ''
Write-Host ('SUMMARY ok=' + $okCount + ' mismatch=' + $mismatchCount + ' missing=' + $missingCount + ' deviated=' + $deviationCount + ' unparsed=' + $unparsedCount)
if (($mismatchCount -eq 0) -and ($missingCount -eq 0)) {
    Write-Host 'RESULT: PASS'
    exit 0
}
Write-Host 'RESULT: FAIL'
exit 1
