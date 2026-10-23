$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_common.ps1')

Write-Host ''
Write-Host '============================================================'
Write-Host '  NInfer v2 - HEALTHCHECK (a real request is the only proof)'
Write-Host '============================================================'
Write-Host ''

try {
    $models = Invoke-RestMethod -Uri ($script:EngineUrl + '/v1/models') -TimeoutSec 8
    Write-Host '[ok   ] GET /v1/models returned 200 (this alone is NOT proof of service)'
    Write-Host ('        ' + ($models | ConvertTo-Json -Depth 5 -Compress))
} catch {
    Write-Host ('[FAIL ] /v1/models is not reachable on 8080: ' + $_.Exception.Message)
    Write-Host '        start the engine first: 21-launchers\start-daily.bat  (or start-long.bat)'
    exit 1
}

Write-Host '[proof] sending one real request ...'
$content = ''
try {
    $r = Invoke-Chat $script:EngineUrl 'Reply with exactly: OK' 8 120
    $content = [string]$r.choices[0].message.content
    Write-Host ('        content = "' + $content + '" finish=' + $r.choices[0].finish_reason + ' usage=' + ($r.usage | ConvertTo-Json -Compress))
} catch {
    Write-Host ('[FAIL ] the real request failed: ' + $_.Exception.Message)
    exit 1
}

$uiState = Get-LauncherState
if ($null -ne $uiState) {
    Write-Host ('[info ] launcher UI profile: ' + [string]$uiState.selected_profile + ' | engine alive=' + [bool]$uiState.engine.alive + ' | gateway alive=' + [bool]$uiState.gateway.alive)
    Write-Host ('[info ] gateway base URL     : ' + $script:GatewayUrl + '/v1  (OpenAI compatible; note: GET /v1/models is not served by the gateway, use 8080 for liveness)')
}
Write-Host ('[info ] GPU used now (MiB)  : ' + (Get-GpuUsedMiB))

if ($content.Trim() -match 'OK') {
    Write-Host ''
    Write-Host '[PASS ] the engine is really serving.'
    exit 0
}
Write-Host '[WARN ] the answer did not contain OK; inspect the engine log via the UI (8720).'
exit 1
