<#
    Makes the watcher start automatically at every logon - WITHOUT admin rights.
    It drops a tiny hidden launcher (.vbs) into your personal Startup folder:
      %APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup

    Run once:
      powershell -ExecutionPolicy Bypass -File .\install-startup-task.ps1
    Remove later:
      powershell -ExecutionPolicy Bypass -File .\uninstall-startup-task.ps1

    (If you'd rather use Windows Task Scheduler instead, register a task whose
     action is start-watcher.ps1 with an "At log on" trigger - that needs an
     elevated/admin PowerShell.)
#>
$ErrorActionPreference = 'Stop'
$root  = $PSScriptRoot
$start = Join-Path $root 'start-watcher.ps1'
if (-not (Test-Path $start)) { throw "start-watcher.ps1 not found next to this script." }

$startupDir = [Environment]::GetFolderPath('Startup')
$vbsPath    = Join-Path $startupDir 'ClaudeSchedulerWatcher.vbs'

# VBS runs PowerShell fully hidden (window style 0), no console flash, no admin.
$inner = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""' + $start + '""'
$vbs   = @(
    'Set sh = CreateObject("WScript.Shell")',
    ('sh.Run "' + $inner + '", 0, False')
) -join [Environment]::NewLine

Set-Content -Path $vbsPath -Value $vbs -Encoding ASCII
Write-Host "Installed logon launcher:" -ForegroundColor Green
Write-Host "  $vbsPath" -ForegroundColor Green
Write-Host "The watcher will start hidden at every logon." -ForegroundColor Green
Write-Host "To start it right now: .\start-watcher.ps1" -ForegroundColor Cyan
Write-Host "To remove autostart:  .\uninstall-startup-task.ps1" -ForegroundColor Cyan
