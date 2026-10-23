param(
    [ValidateSet('daily', 'longctx')]
    [string]$Tier = 'daily'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')

Write-Host ''
Write-Host '============================================================'
Write-Host ('  NInfer v2 - ONE-CLICK STOP (requested: ' + $Tier + ')')
Write-Host '============================================================'
Write-Host ''

if (-not (Test-TcpPort 8720)) {
    Write-Host '[skip] the launcher UI is not running, so nothing can be stopped through it.'
    if ((Test-TcpPort 8080) -or (Test-TcpPort 8081)) {
        Write-Host '[warn] ports 8080/8081 are still open. Start the UI (10-engine\启动器.bat) and stop from there, or close the engine window.'
        exit 1
    }
    exit 0
}

$state = Get-LauncherState
if ($null -eq $state) {
    Write-Host '[ERROR] cannot query the launcher state API on 8720.'
    exit 1
}
$running = [string]$state.selected_profile
$alive = ($state.engine.alive -or $state.gateway.alive -or (Test-TcpPort 8080) -or (Test-TcpPort 8081))
if (-not $alive) {
    Write-Host '[skip] the engine is not running. Nothing to stop.'
    exit 0
}

if ($running) { Write-Host ('[info] current profile: ' + $running) }
Write-Host '[..] stopping the engine and gateway (targets only pids recorded by the launcher) ...'
try {
    $res = Invoke-LauncherPost '/api/stop' $null
} catch {
    Write-Host ('[ERROR] stop request failed: ' + $_.Exception.Message)
    exit 1
}

$enginePids = @()
$gatewayPids = @()
foreach ($item in @($res.stopped)) {
    if ($item.role -eq 'engine') { $enginePids += $item.pid }
    if ($item.role -eq 'gateway') { $gatewayPids += $item.pid }
}
Write-Host ('[ok] stopped: engine pids=' + (($enginePids | ForEach-Object { [string]$_ }) -join ',') + ' gateway pids=' + (($gatewayPids | ForEach-Object { [string]$_ }) -join ','))

$deadline = (Get-Date).AddSeconds(20)
while ((Get-Date) -lt $deadline) {
    if (-not (Test-TcpPort 8080) -and -not (Test-TcpPort 8081)) { break }
    Start-Sleep -Milliseconds 500
}
$port8080 = Test-TcpPort 8080
$port8081 = Test-TcpPort 8081
$used = Get-GpuUsedMiB
Write-Host ''
Write-Host ('[check] port 8080 listening : ' + $port8080)
Write-Host ('[check] port 8081 listening : ' + $port8081)
Write-Host ('[check] GPU used now (MiB)  : ' + $used)
Write-Host '[note ] the launcher UI window stays open (it holds no GPU memory). Close that window to exit the launcher, or leave it for the next start.'
Write-Host ''
if ($port8080 -or $port8081) {
    Write-Host '[warn] a port is still open; check the UI (8720) or Task Manager.'
    exit 1
}
Write-Host '[done] the engine is stopped.'
exit 0
