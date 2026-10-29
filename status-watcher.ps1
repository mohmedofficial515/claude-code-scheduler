<#  Shows watcher status and the tail of today's log.  #>
$root = $PSScriptRoot
$proc = Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*run-watcher.ps1*' }

if ($proc) {
    Write-Host "Status: RUNNING (PID: $($proc.ProcessId -join ', '))" -ForegroundColor Green
} else {
    Write-Host "Status: STOPPED" -ForegroundColor Red
}

$today = Join-Path $root ("logs\watcher-{0}.log" -f (Get-Date).ToString('yyyy-MM-dd'))
if (Test-Path $today) {
    Write-Host "`n--- last 20 lines of today's log ---" -ForegroundColor Cyan
    Get-Content $today -Tail 20
} else {
    Write-Host "`nNo log for today yet: $today" -ForegroundColor DarkGray
}
