$a = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\hopclaw\do-step-click.ps1"
$p = New-ScheduledTaskPrincipal -UserId "Administrator" -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName "HopClawStepClick" -Action $a -Principal $p -Force | Out-Null
"registered"
