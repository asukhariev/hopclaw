# One-time setup: register a scheduled task that runs the screenshot script
# in the active interactive (RDP) session.
$ErrorActionPreference = "Stop"

New-Item -Path "C:\hopclaw" -ItemType Directory -Force | Out-Null

$action    = New-ScheduledTaskAction -Execute "powershell.exe" `
              -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\hopclaw\screenshot.ps1"
$principal = New-ScheduledTaskPrincipal -UserId "Administrator" -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName "HopClawScreenshot" `
    -Action $action -Principal $principal -Settings $settings -Force | Out-Null

Write-Host "Task 'HopClawScreenshot' registered."
Write-Host "Trigger from SSH with:  Start-ScheduledTask -TaskName HopClawScreenshot"
