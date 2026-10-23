param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('daily', 'longctx')]
    [string]$Tier
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

$profile = $script:TierProfiles[$Tier]
Write-Host ''
Write-Host '============================================================'
Write-Host ('  NInfer v2 - ONE-CLICK START (' + $Tier + ')')
Write-Host '============================================================'
Write-Host ''

$gpuLine = & nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host '[ERROR] nvidia-smi failed: no usable NVIDIA GPU / driver.'
    exit 1
}
Write-Host ('[check] GPU memory in use now (MiB): ' + $gpuLine)

if (-not (Ensure-LauncherUi)) { exit 1 }

$state = Get-LauncherState
if ($null -eq $state) {
    Write-Host '[ERROR] launcher state API is not reachable on 8720.'
    exit 1
}

if ($state.engine.alive -or $state.gateway.alive) {
    $current = [string]$state.selected_profile
    if ($current -eq $profile) {
        Write-Host ('[skip] the engine is ALREADY running with profile ' + $profile + '. Nothing to do.')
        Write-TierSummary $Tier
        exit 0
    }
    Write-Host ('[info] another profile is running (' + $current + '); stopping it before switching ...')
    if (-not (Reset-EngineState)) {
        Write-Host '[ERROR] could not stop the running engine; close it in the UI (8720) and retry.'
        exit 1
    }
} else {
    if ((Test-TcpPort 8080) -or (Test-TcpPort 8081)) {
        Write-Host '[warn] ports 8080/8081 are busy but the launcher owns no engine; trying to stop ...'
        Reset-EngineState | Out-Null
    }
}

Write-Host ('[..] preflight for profile ' + $profile + ' ...')
try {
    $pre = Invoke-LauncherPost '/api/preflight' @{ profile_id = $profile }
} catch {
    Write-Host ('[ERROR] preflight request failed: ' + $_.Exception.Message)
    exit 1
}
if (-not $pre.ok) {
    Write-Host '[ERROR] preflight refused:'
    foreach ($issue in @($pre.issues)) {
        if ($issue) {
            Write-Host ('   - ' + $issue.code + ': ' + $issue.message)
            if ($issue.remediation) { Write-Host ('     fix: ' + $issue.remediation) }
        }
    }
    exit 2
}
Write-Host ('[ok] budget gate: engine=' + $pre.budget.effective_mib + ' MiB, redline=' + $pre.budget.redline_mib + ' MiB')

Write-Host '[..] starting the engine (weights load + device profile; 10-60 s is normal) ...'
try {
    $res = Invoke-LauncherPost '/api/start' @{ profile_id = $profile }
} catch {
    Write-Host ('[ERROR] start request failed: ' + $_.Exception.Message)
    Reset-EngineState | Out-Null
    exit 3
}
if (-not $res.ok) {
    Write-Host '[ERROR] engine did not start:'
    if ($res.error) { Write-Host ('   code=' + $res.error.code + ' message=' + $res.error.message) }
    if ($res.tail) {
        Write-Host '   --- engine log tail ---'
        foreach ($line in @($res.tail)) { Write-Host ('   ' + $line) }
    }
    Reset-EngineState | Out-Null
    exit 3
}

Write-Host '[ok] engine and gateway are up.'
Write-TierSummary $Tier
Write-Host ''
Write-Host '[proof] sending ONE REAL REQUEST (a 200 from /v1/models alone is not proof) ...'
$content = ''
try {
    $r = Invoke-Chat $script:EngineUrl 'Reply with exactly: OK' 8 120
    $content = [string]$r.choices[0].message.content
    Write-Host ('[proof] content = "' + $content + '" finish=' + $r.choices[0].finish_reason)
} catch {
    Write-Host ('[warn] the real request failed: ' + $_.Exception.Message)
    Write-Host '       the engine may still be warming up; check the UI log view.'
    exit 4
}
if ($content.Trim() -notmatch 'OK') {
    Write-Host '[warn] the answer did not contain OK; check the UI log view before using it.'
    exit 4
}
Write-Host ''
Write-Host '[done] the service is REALLY serving. You can close this window.'
exit 0
