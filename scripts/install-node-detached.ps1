# Install Node.js LTS detached from SSH so the install survives session drops.
# Uses a scheduled task that runs as SYSTEM and writes a marker file when done.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$markerOk   = "C:\hopclaw\node-install.ok"
$markerErr  = "C:\hopclaw\node-install.err"
$logFile    = "C:\hopclaw\node-install.log"

New-Item -ItemType Directory -Path "C:\hopclaw" -Force | Out-Null
Remove-Item $markerOk, $markerErr, $logFile -ErrorAction SilentlyContinue

# 1. Make sure MSI is present (download if not)
$msi = "$env:TEMP\node-lts.msi"
if (-not (Test-Path $msi) -or (Get-Item $msi).Length -lt 10000000) {
    Write-Host "Downloading Node.js LTS MSI..."
    $latest = (Invoke-RestMethod https://nodejs.org/dist/index.json) |
              Where-Object { $_.lts -ne $false } | Select-Object -First 1
    $url = "https://nodejs.org/dist/$($latest.version)/node-$($latest.version)-x64.msi"
    Write-Host "URL: $url"
    Invoke-WebRequest -Uri $url -OutFile $msi
    Write-Host "Downloaded $($latest.version)"
}

# 2. Write a small worker script the scheduled task will execute as SYSTEM
$worker = @"
`$ErrorActionPreference = 'Stop'
try {
    Start-Process msiexec.exe -ArgumentList '/i','$msi','/qn','/norestart','/L*v','$logFile' -Wait -NoNewWindow
    if (Test-Path 'C:\Program Files\nodejs\node.exe') {
        Set-Content '$markerOk' (Get-Date -Format 'o')
    } else {
        Set-Content '$markerErr' 'msiexec finished but node.exe missing'
    }
} catch {
    Set-Content '$markerErr' (`$_.Exception.Message)
}
"@
$workerPath = "C:\hopclaw\node-install-worker.ps1"
Set-Content -Path $workerPath -Value $worker -Encoding ASCII

# 3. Register a scheduled task that runs the worker ONCE immediately as SYSTEM
$taskName = "HopClawInstallNode"
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
$action    = New-ScheduledTaskAction -Execute "powershell.exe" `
              -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $workerPath"
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null

# 4. Trigger it immediately and return — install runs detached
Start-ScheduledTask -TaskName $taskName
Write-Host "Triggered detached Node install. Poll for $markerOk or $markerErr."
