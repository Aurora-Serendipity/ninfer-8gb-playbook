param(
    [ValidateSet('daily', 'longctx')]
    [string]$Tier = 'daily',
    [int]$OutputTokens = 0
)
$ErrorActionPreference = 'Continue'
. (Join-Path (Split-Path -Parent $PSScriptRoot) '21-launchers\_common.ps1')

$profile = $script:TierProfiles[$Tier]
$poolExpected = 12800
if ($Tier -eq 'longctx') { $poolExpected = 51200 }

Write-Host ''
Write-Host '============================================================'
Write-Host ('  NInfer v2 - basic acceptance (' + $Tier + ' / ' + $profile + ')')
Write-Host '============================================================'
Write-Host ''

$fail = 0
function Fail($msg) { Write-Host ('[FAIL] ' + $msg); $script:fail = 1 }
function Pass($msg) { Write-Host ('[ok]   ' + $msg) }

# 1. launcher state
$state = Get-LauncherState
if ($null -eq $state) { Fail 'launcher UI is not reachable on 8720'; }
else {
    Write-Host ('[info] selected_profile=' + [string]$state.selected_profile + ' engine_alive=' + [bool]$state.engine.alive + ' gateway_alive=' + [bool]$state.gateway.alive)
    if ([string]$state.selected_profile -ne $profile) { Fail ('the running profile is not ' + $profile) } else { Pass 'profile matches' }
    if (-not $state.engine.alive) { Fail 'engine process is not alive' } else { Pass 'engine process alive' }
    if (-not $state.gateway.alive) { Fail 'gateway process is not alive' } else { Pass 'gateway process alive' }
}

# 2. /v1/models
try {
    $models = Invoke-RestMethod -Uri ($script:EngineUrl + '/v1/models') -TimeoutSec 8
    Pass 'GET /v1/models returned 200'
    Write-Host ('       ' + ($models | ConvertTo-Json -Depth 5 -Compress))
} catch { Fail ('/v1/models unreachable: ' + $_.Exception.Message) }

# 3. GPU redline
$used = Get-GpuUsedMiB
if ($used -lt 0) { Fail 'nvidia-smi failed' }
elseif ($used -gt $script:RedlineMiB) { Fail ('GPU used ' + $used + ' MiB > redline ' + $script:RedlineMiB + ' MiB') }
else { Pass ('GPU used ' + $used + ' MiB <= redline ' + $script:RedlineMiB + ' MiB') }

# 4. real request
try {
    $r = Invoke-Chat $script:EngineUrl 'Reply with exactly: OK' 8 120
    $content = [string]$r.choices[0].message.content
    if ($content.Trim() -match 'OK') { Pass ('real request: "' + $content + '"') } else { Fail ('real request answer was "' + $content + '"') }
} catch { Fail ('real request failed: ' + $_.Exception.Message) }

# 5. 7*5 and +2
try {
    $a = Invoke-Chat $script:EngineUrl 'What is 7*5? Reply with the number only.' 32 120
    $ans1 = [string]$a.choices[0].message.content
    if ($ans1.Trim() -match '35') { Pass ('7*5 -> ' + $ans1.Trim()) } else { Fail ('7*5 answered "' + $ans1 + '"') }
    $body = @{ model = 'j27b'; messages = @(@{ role = 'user'; content = 'What is 7*5? Reply with the number only.' }, @{ role = 'assistant'; content = $ans1 }, @{ role = 'user'; content = 'Add 2 to that. Reply with the number only.' }); temperature = 0; max_tokens = 32 }
    $json = $body | ConvertTo-Json -Depth 8 -Compress
    $b = Invoke-RestMethod -Uri ($script:EngineUrl + '/v1/chat/completions') -Method Post -ContentType 'application/json' -Body $json -TimeoutSec 120
    $ans2 = [string]$b.choices[0].message.content
    if ($ans2.Trim() -match '37') { Pass ('+2 -> ' + $ans2.Trim()) } else { Fail ('+2 answered "' + $ans2 + '"') }
} catch { Fail ('arithmetic probe failed: ' + $_.Exception.Message) }

# 6. four distinct sequential requests (the old "only first request works" regression)
$okCount = 0
for ($i = 1; $i -le 4; $i++) {
    try {
        $r = Invoke-Chat $script:EngineUrl ('Reply with exactly the word OK, attempt number ' + $i + '. Nothing else.') 16 120
        $c = [string]$r.choices[0].message.content
        if ($c.Trim() -match 'OK') { $okCount++ }
    } catch { }
}
if ($okCount -eq 4) { Pass '4/4 distinct sequential requests' } else { Fail ('distinct sequential requests: ' + $okCount + '/4') }

# 7. capacity line from the latest engine log
$log = Get-LatestEngineLog
if ($log) {
    $capacity = (Select-String -Path $log.FullName -Pattern 'capacity \| KV' | Select-Object -Last 1).Line
    if ($capacity) {
        Write-Host ('[info] ' + $capacity.Trim())
        $flat = $capacity -replace ',', ''
        if ($flat -match [string]$poolExpected -and $capacity -match 'rk2v4-e8') { Pass 'capacity line matches the profile (pool + dtype)' }
        else { Fail ('capacity line does not match pool ' + $poolExpected + ' / rk2v4-e8') }
    } else { Fail 'capacity line not found in the engine log' }
    Write-Host ('[info] engine log: ' + $log.FullName)
} else { Fail 'no engine log found' }

# 8. optional forced long output (slow: 4096/8192 tokens)
if ($OutputTokens -gt 0) {
    Write-Host ('[..]   forced long output test, max_tokens=' + $OutputTokens + ' (this can take minutes) ...')
    try {
        $corpus = 'Count from 1 to 5000, one number per line. Keep counting, do not stop early.'
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-Chat $script:EngineUrl $corpus $OutputTokens 900
        $sw.Stop()
        $completion = $r.usage.completion_tokens
        Write-Host ('[info] completion=' + $completion + ' finish=' + $r.choices[0].finish_reason + ' elapsed=' + [math]::Round($sw.Elapsed.TotalSeconds,1) + ' s')
        if ($completion -ge [int]($OutputTokens * 0.9)) { Pass ('long output reached ' + $completion + ' tokens') }
        else { Fail ('long output only reached ' + $completion + ' tokens; upstream B35 lease may be limiting it') }
    } catch { Fail ('long output test failed: ' + $_.Exception.Message) }
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'RESULT: PASS'; exit 0 }
Write-Host 'RESULT: FAIL'
exit 1
