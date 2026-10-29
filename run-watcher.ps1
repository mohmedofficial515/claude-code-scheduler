<#
.SYNOPSIS
    Claude Code session scheduler - watcher.

    Runs a task (from task.md) in a fresh Claude Code session every time the
    5-hour usage window renews. Self-anchors to the window: after each run it
    sleeps for the window length (+ buffer) then runs again, forever.

.USAGE
    powershell -ExecutionPolicy Bypass -File .\run-watcher.ps1
    (or use start-watcher.ps1 to run it in the background)
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config.json"
)

$ErrorActionPreference = 'Stop'
$root     = $PSScriptRoot
$logDir   = Join-Path $root 'logs'
$stopFlag = Join-Path $root 'stop.flag'
$pidFile  = Join-Path $root 'watcher.pid'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

# ---------- logging ----------
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    $daily = Join-Path $logDir ("watcher-{0}.log" -f (Get-Date).ToString('yyyy-MM-dd'))
    Add-Content -Path $daily -Value $line -Encoding UTF8
}

# ---------- config ----------
if (-not (Test-Path $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

# ---------- resolve claude.exe ----------
function Resolve-ClaudePath {
    param($configured)
    if ($configured -and (Test-Path $configured)) { return $configured }
    $onPath = Get-Command claude -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $extRoot = Join-Path $env:USERPROFILE '.vscode\extensions'
    if (Test-Path $extRoot) {
        $cands = Get-ChildItem $extRoot -Directory -Filter 'anthropic.claude-code-*' -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'resources\native-binary\claude.exe' } |
            Where-Object { Test-Path $_ }
        if ($cands) {
            return ($cands | Sort-Object { (Get-Item $_).LastWriteTime } -Descending | Select-Object -First 1)
        }
    }
    throw "claude.exe not found. Set 'claudePath' in config.json."
}

$claude = Resolve-ClaudePath $cfg.claudePath
Write-Log "Claude binary: $claude"

$projectDir = $cfg.projectDir
if (-not (Test-Path $projectDir)) { throw "projectDir does not exist: $projectDir" }

$taskPath = $cfg.taskFile
if (-not [System.IO.Path]::IsPathRooted($taskPath)) { $taskPath = Join-Path $root $taskPath }

$windowHours     = [double]$cfg.windowHours
$bufferMinutes   = [double]$cfg.bufferMinutes
$heartbeatMin    = if ($cfg.heartbeatMinutes) { [double]$cfg.heartbeatMinutes } else { 30 }
$emptyRecheckMin = if ($cfg.emptyTaskRecheckMinutes) { [double]$cfg.emptyTaskRecheckMinutes } else { 10 }

# ---------- read + clean task ----------
function Get-TaskText {
    if (-not (Test-Path $taskPath)) { return '' }
    $raw = Get-Content $taskPath -Raw -Encoding UTF8
    if (-not $raw) { return '' }
    # strip HTML comments <!-- ... -->
    $clean = [regex]::Replace($raw, '(?s)<!--.*?-->', '')
    return $clean.Trim()
}

# ---------- build claude args ----------
# stream-json (+ --verbose, required in print mode) so we can read the
# rate_limit_event that carries the exact five_hour window reset time.
function Get-ClaudeArgs {
    $a = @('-p', '--output-format', 'stream-json', '--verbose')
    if ($cfg.permissionMode) { $a += @('--permission-mode', $cfg.permissionMode) }
    if ($cfg.model)          { $a += @('--model', $cfg.model) }
    if ($cfg.extraArgs)      { $a += @($cfg.extraArgs) }
    return $a
}

# ---------- run one session ----------
function Invoke-ClaudeTask {
    param([string]$Task)
    $stamp   = (Get-Date).ToString('yyyy-MM-dd_HHmmss')
    $runLog  = Join-Path $logDir ("run-$stamp.log")
    $cliArgs = Get-ClaudeArgs
    Write-Log "Starting new session. Run log: $runLog"
    Write-Log ("Command: claude {0}" -f ($cliArgs -join ' '))

    Push-Location $projectDir
    try {
        # pass the task via stdin to avoid quoting / arg-length issues
        $Task | & $claude @cliArgs *>&1 | Tee-Object -FilePath $runLog | Out-Null
        $exit = $LASTEXITCODE
    }
    finally { Pop-Location }

    # parse the stream-json events (one JSON object per line)
    $events = @()
    foreach ($ln in (Get-Content $runLog -Encoding UTF8)) {
        $t = $ln.Trim()
        if (-not $t) { continue }
        try { $events += ($t | ConvertFrom-Json) } catch { }
    }

    $res = $events | Where-Object { $_.type -eq 'result' } | Select-Object -First 1
    if ($res) {
        Write-Log ("Session done. exit=$exit is_error=$($res.is_error) turns=$($res.num_turns) cost=`$$($res.total_cost_usd) session=$($res.session_id)")
    } else {
        Write-Log "Session done. exit=$exit (no result event - see $runLog)" 'WARN'
    }

    # exact reset time of the 5-hour window (last five_hour rate_limit_event)
    $resetsAt = $null
    $rl = $events |
        Where-Object { $_.type -eq 'rate_limit_event' -and $_.rate_limit_info.rateLimitType -eq 'five_hour' } |
        Select-Object -Last 1
    if ($rl -and $rl.rate_limit_info.resetsAt) {
        try {
            $resetsAt = [DateTimeOffset]::FromUnixTimeSeconds([int64]$rl.rate_limit_info.resetsAt).LocalDateTime
        } catch { }
    }

    return @{ Exit = $exit; ResetsAt = $resetsAt }
}

# ---------- interruptible sleep until target ----------
function Wait-Until {
    param([datetime]$Target)
    $lastBeat = Get-Date
    while ((Get-Date) -lt $Target) {
        if (Test-Path $stopFlag) {
            Write-Log 'stop.flag detected - stopping watcher.' 'WARN'
            Remove-Item $stopFlag -Force -ErrorAction SilentlyContinue
            return $false
        }
        $now = Get-Date
        if (($now - $lastBeat).TotalMinutes -ge $heartbeatMin) {
            $remain = [math]::Round(($Target - $now).TotalMinutes, 1)
            Write-Log "Waiting... next run in $remain min (at $($Target.ToString('HH:mm')))."
            $lastBeat = $now
        }
        Start-Sleep -Seconds 30
    }
    return $true
}

# ---------- window mode: run each time the 5h window renews ----------
function Invoke-WindowLoop {
    $firstIteration = $true
    while ($true) {
        if (Test-Path $stopFlag) {
            Write-Log 'stop.flag detected before run - stopping.' 'WARN'
            Remove-Item $stopFlag -Force -ErrorAction SilentlyContinue
            break
        }

        if ($firstIteration -and -not $cfg.runAtStart) {
            $firstIteration = $false
            $next = (Get-Date).AddHours($windowHours).AddMinutes($bufferMinutes)
            Write-Log "runAtStart=false - first run at $($next.ToString('yyyy-MM-dd HH:mm'))."
            if (-not (Wait-Until $next)) { break }
        }
        $firstIteration = $false

        $task = Get-TaskText
        if ([string]::IsNullOrWhiteSpace($task)) {
            Write-Log "Task file is empty ($taskPath). Rechecking in $emptyRecheckMin min." 'WARN'
            $next = (Get-Date).AddMinutes($emptyRecheckMin)
            if (-not (Wait-Until $next)) { break }
            continue
        }

        $runStart = Get-Date
        $result = $null
        try {
            $result = Invoke-ClaudeTask -Task $task
        } catch {
            Write-Log "Error during run: $($_.Exception.Message)" 'ERROR'
        }

        if ($result -and $result.ResetsAt) {
            $next = ([datetime]$result.ResetsAt).AddMinutes($bufferMinutes)
            Write-Log "Window resets at $(([datetime]$result.ResetsAt).ToString('yyyy-MM-dd HH:mm:ss')) (from rate_limit_event)."
        } else {
            $next = $runStart.AddHours($windowHours).AddMinutes($bufferMinutes)
            Write-Log "No rate_limit_event found; self-anchoring to run start."
        }

        if ($next -le (Get-Date)) { $next = (Get-Date).AddMinutes(1) }

        Write-Log "Next run scheduled at $($next.ToString('yyyy-MM-dd HH:mm:ss'))."
        if (-not (Wait-Until $next)) { break }
    }
}

# ---------- datetime mode: run at a specific date/time (optionally repeating) ----------
function Get-NextOccurrence {
    param([datetime]$Base, [string]$Repeat, [int]$EveryN)
    $now = Get-Date
    if ($Repeat -eq 'none') { return $Base }
    switch ($Repeat) {
        'hourly' { $step = [TimeSpan]::FromHours(1) }
        'daily'  { $step = [TimeSpan]::FromDays(1) }
        'weekly' { $step = [TimeSpan]::FromDays(7) }
        default  { $step = [TimeSpan]::FromHours([math]::Max(1, $EveryN)) }
    }
    $t = $Base
    while ($t -le $now) { $t = $t.Add($step) }
    return $t
}

function Invoke-DatetimeLoop {
    $sch = $cfg.schedule
    if (-not $sch -or -not $sch.runAt) {
        Write-Log 'datetime mode but schedule.runAt is empty. Nothing to do.' 'ERROR'
        return
    }
    $repeat = if ($sch.repeat) { [string]$sch.repeat } else { 'none' }
    $everyN = if ($sch.everyNHours) { [int]$sch.everyNHours } else { 5 }
    try {
        $base = [datetime]::Parse([string]$sch.runAt, [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        Write-Log "Cannot parse schedule.runAt '$($sch.runAt)'." 'ERROR'
        return
    }
    Write-Log "Datetime mode. runAt=$($base.ToString('yyyy-MM-dd HH:mm')) repeat=$repeat everyN=$everyN"

    while ($true) {
        if (Test-Path $stopFlag) {
            Write-Log 'stop.flag detected before run - stopping.' 'WARN'
            Remove-Item $stopFlag -Force -ErrorAction SilentlyContinue
            break
        }
        if ($repeat -eq 'none') {
            $next = $base
            if ($base -le (Get-Date)) { $next = (Get-Date).AddSeconds(3) }
        } else {
            $next = Get-NextOccurrence -Base $base -Repeat $repeat -EveryN $everyN
        }
        Write-Log "Next run scheduled at $($next.ToString('yyyy-MM-dd HH:mm:ss'))."
        if (-not (Wait-Until $next)) { break }

        $task = Get-TaskText
        if ([string]::IsNullOrWhiteSpace($task)) {
            Write-Log "Task file is empty ($taskPath). Skipping this run." 'WARN'
        } else {
            try { Invoke-ClaudeTask -Task $task | Out-Null }
            catch { Write-Log "Error during run: $($_.Exception.Message)" 'ERROR' }
        }

        if ($repeat -eq 'none') { Write-Log 'One-shot schedule complete.'; break }
        Start-Sleep -Seconds 2
    }
}

# ================= main loop =================
if (Test-Path $stopFlag) { Remove-Item $stopFlag -Force -ErrorAction SilentlyContinue }

Write-Log '=================================================='
Write-Log 'Watcher started.'
Write-Log ("Window = {0}h + {1}min buffer" -f $windowHours, $bufferMinutes)
Write-Log ("Task file: {0}" -f $taskPath)
Write-Log ("Project dir: {0}" -f $projectDir)

# write PID file so external tools (the VS Code companion) can detect us reliably
Set-Content -Path $pidFile -Value $PID -Encoding ASCII
Write-Log ("PID: {0}" -f $PID)

$mode = if ($cfg.mode) { [string]$cfg.mode } else { 'window' }
Write-Log ("Mode: {0}" -f $mode)

try {
    if ($mode -eq 'datetime') { Invoke-DatetimeLoop } else { Invoke-WindowLoop }
}
finally {
    if (Test-Path $pidFile) { Remove-Item $pidFile -Force -ErrorAction SilentlyContinue }
}

Write-Log 'Watcher stopped.'
Write-Log '=================================================='
