$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\hopclaw\dump-mr4-uia.ps1 -RedirectOutput C:\hopclaw\uia-dump.txt'
$principal = New-ScheduledTaskPrincipal -UserId "Administrator" -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName "HopClawDumpUIA" -Action $action -Principal $principal -Force | Out-Null
Write-Host registered
