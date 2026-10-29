<#
    Starts the watcher in the background (hidden window) so it keeps running
    after you close the terminal. Run once. Use stop-watcher.ps1 to stop it.
#>
$root     = $PSScriptRoot
$watcher  = Join-Path $root 'run-watcher.ps1'
$stopFlag = Join-Path $root 'stop.flag'

if (Test-Path $stopFlag) { Remove-Item $stopFlag -Force -ErrorAction SilentlyContinue }

# prevent double-start
$existing = Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*run-watcher.ps1*' }
if ($existing) {
    Write-Host "Watcher already running (PID: $($existing.ProcessId -join ', ')). To stop: .\stop-watcher.ps1" -ForegroundColor Yellow
    return
}

$psExe = (Get-Process -Id $PID).Path   # same PowerShell host as current
$p = Start-Process -FilePath $psExe `
    -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File', "`"$watcher`"") `
    -WindowStyle Hidden -PassThru

Write-Host "Watcher started in background (PID: $($p.Id))." -ForegroundColor Green
Write-Host "Logs: $(Join-Path $root 'logs')" -ForegroundColor Green
Write-Host "To stop: .\stop-watcher.ps1" -ForegroundColor Green
