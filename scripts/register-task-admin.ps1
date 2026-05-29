$ErrorActionPreference = "Stop"
$taskName = "HopClawDriveExport"
$script   = "C:\hopclaw\drive-export.ps1"
if (-not (Test-Path $script)) { Write-Host "ERROR: $script missing."; exit 1 }
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
$action    = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $script"
$principal = New-ScheduledTaskPrincipal -UserId "Admin" -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "Task registered."
