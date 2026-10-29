<#
    Stops the watcher gracefully: creates stop.flag so the script exits within
    ~30s (or immediately if it was waiting). If it doesn't stop, it is killed.
#>
$root     = $PSScriptRoot
$stopFlag = Join-Path $root 'stop.flag'

New-Item -ItemType File -Path $stopFlag -Force | Out-Null
Write-Host "stop.flag created - watcher will stop within seconds..." -ForegroundColor Yellow

Start-Sleep -Seconds 35

$still = Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*run-watcher.ps1*' }

if ($still) {
    Write-Host "Still running - forcing termination..." -ForegroundColor Red
    $still | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Write-Host "Stopped." -ForegroundColor Green
} else {
    Write-Host "Watcher stopped." -ForegroundColor Green
}
if (Test-Path $stopFlag) { Remove-Item $stopFlag -Force -ErrorAction SilentlyContinue }
$pidFile = Join-Path $root 'watcher.pid'
if (Test-Path $pidFile) { Remove-Item $pidFile -Force -ErrorAction SilentlyContinue }
