# One-time: register HopClawDriveExport scheduled task in the interactive
# (RDP) session. The runner triggers this task with schtasks /Run to drive
# MR4's Export workflow.
$ErrorActionPreference = "Stop"

$taskName = "HopClawDriveExport"
$script   = "C:\hopclaw\drive-export.ps1"

if (-not (Test-Path $script)) {
    Write-Host "ERROR: $script missing. SCP it first."
    exit 1
}

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
$action    = New-ScheduledTaskAction -Execute "powershell.exe" `
              -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $script"
$principal = New-ScheduledTaskPrincipal -UserId "Administrator" -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null

Write-Host "Task '$taskName' registered."
Write-Host "Test manually:  Start-ScheduledTask -TaskName $taskName"
