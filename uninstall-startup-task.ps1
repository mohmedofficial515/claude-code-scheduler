<#
    Removes the logon launcher created by install-startup-task.ps1.
    (Does NOT stop a currently running watcher - use stop-watcher.ps1 for that.)
#>
$ErrorActionPreference = 'Stop'
$startupDir = [Environment]::GetFolderPath('Startup')
$vbsPath    = Join-Path $startupDir 'ClaudeSchedulerWatcher.vbs'

if (Test-Path $vbsPath) {
    Remove-Item $vbsPath -Force
    Write-Host "Removed logon launcher: $vbsPath" -ForegroundColor Green
} else {
    Write-Host "No logon launcher found at: $vbsPath" -ForegroundColor Yellow
}

# also clean up an old Task Scheduler task if one was ever created
$old = Get-ScheduledTask -TaskName 'ClaudeSchedulerWatcher' -ErrorAction SilentlyContinue
if ($old) {
    try { Unregister-ScheduledTask -TaskName 'ClaudeSchedulerWatcher' -Confirm:$false; Write-Host "Also removed old scheduled task." -ForegroundColor Green } catch {}
}
