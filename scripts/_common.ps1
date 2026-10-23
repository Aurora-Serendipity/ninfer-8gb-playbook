# Shared helpers for the NInfer v2 one-click launchers.
# ASCII only, Windows PowerShell 5.1 compatible. Dot-source this file from the tier scripts.
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$script:LaunchRoot = Split-Path -Parent $PSScriptRoot
$script:Pkg        = Join-Path $script:LaunchRoot '10-engine'
$script:Py         = Join-Path $script:Pkg 'runtime\python\python.exe'
$script:Launcher   = Join-Path $script:Pkg 'launcher.py'
$script:UiUrl      = 'http://127.0.0.1:8720'
$script:EngineUrl  = 'http://127.0.0.1:8080'
$script:GatewayUrl = 'http://127.0.0.1:8081'
$script:RedlineMiB = 7488
$script:TierProfiles = @{ 'daily' = '8g-daily'; 'longctx' = '8g-longctx' }
$script:TierLabels = @{ 'daily' = 'Daily tier (8g-fast based: ctx 131072, output 4096, MTP)'; 'longctx' = 'Long-context tier (8g-long based: ctx 262144, output 8192, no MTP)' }

function Test-TcpPort {
    param([int]$Port, [int]$TimeoutMs = 400)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $client.EndConnect($iar)
        return $true
    } catch {
        return $false
    } finally {
        if ($client) { $client.Close() }
    }
}

function Get-GpuUsedMiB {
    try {
        $out = & nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>$null
        if ($LASTEXITCODE -ne 0) { return -1 }
        return [int]($out.Trim())
    } catch {
        return -1
    }
}

function Get-LauncherState {
    try {
        return Invoke-RestMethod -Uri ($script:UiUrl + '/api/state') -Method Get -TimeoutSec 8
    } catch {
        return $null
    }
}

function Invoke-LauncherPost {
    param([string]$Path, $Body)
    if ($null -ne $Body) { $json = $Body | ConvertTo-Json -Depth 6 -Compress } else { $json = '{}' }
    return Invoke-RestMethod -Uri ($script:UiUrl + $Path) -Method Post -ContentType 'application/json' -Body $json -TimeoutSec 240
}

function Wait-Port {
    param([int]$Port, [int]$TimeoutSec = 30)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-TcpPort $Port) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return (Test-TcpPort $Port)
}

function Ensure-LauncherUi {
    if (Test-TcpPort 8720) { return $true }
    if (-not (Test-Path $script:Py)) { Write-Host ('[ERROR] bundled python not found: ' + $script:Py); return $false }
    if (-not (Test-Path $script:Launcher)) { Write-Host ('[ERROR] launcher.py not found: ' + $script:Launcher); return $false }
    Write-Host '[..] starting the launcher UI (minimized window) ...'
    Start-Process -FilePath $script:Py -ArgumentList @(('"' + $script:Launcher + '"'), '--no-browser') -WorkingDirectory $script:Pkg -WindowStyle Minimized | Out-Null
    if (-not (Wait-Port 8720 30)) { Write-Host '[ERROR] launcher UI did not listen on 8720 within 30 s'; return $false }
    Write-Host '[ok] launcher UI is up on http://127.0.0.1:8720'
    return $true
}

function Reset-EngineState {
    # Best-effort stop of whatever the launcher owns. Never kills processes it did not start.
    try { Invoke-LauncherPost '/api/stop' $null | Out-Null } catch { }
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-TcpPort 8080) -and -not (Test-TcpPort 8081)) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return ((-not (Test-TcpPort 8080)) -and (-not (Test-TcpPort 8081)))
}

function Invoke-Chat {
    param([string]$BaseUrl, [string]$Content, [int]$MaxTokens = 8, [int]$TimeoutSec = 180)
    $body = @{ model = 'j27b'; messages = @(@{ role = 'user'; content = $Content }); temperature = 0; max_tokens = $MaxTokens }
    $json = $body | ConvertTo-Json -Depth 8 -Compress
    return Invoke-RestMethod -Uri ($BaseUrl + '/v1/chat/completions') -Method Post -ContentType 'application/json' -Body $json -TimeoutSec $TimeoutSec
}

function Get-LatestEngineLog {
    return Get-ChildItem (Join-Path $script:Pkg 'logs\engine-*.log') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Write-TierSummary {
    param([string]$Tier)
    $profile = $script:TierProfiles[$Tier]
    $log = Get-LatestEngineLog
    $used = Get-GpuUsedMiB
    Write-Host ''
    Write-Host '============================================================'
    Write-Host ('  NInfer v2 engine is up: ' + $script:TierLabels[$Tier])
    Write-Host ('  profile      : ' + $profile)
    Write-Host '  engine       : http://127.0.0.1:8080   (model j27b)'
    Write-Host '  gateway      : http://127.0.0.1:8081/v1 (OpenAI base URL)'
    Write-Host '  control UI   : http://127.0.0.1:8720'
    if ($log) { Write-Host ('  engine log   : ' + $log.FullName) }
    Write-Host ('  GPU used now : ' + $used + ' MiB (redline ' + $script:RedlineMiB + ' MiB)')
    Write-Host '  stop with    : 21-launchers\stop-daily.bat  (or stop-long.bat)'
    Write-Host '============================================================'
}
