# Deploy HopClaw runner on the lab Windows VM. v2: copies the staged .env
# from C:\hopclaw\runner.env (placed there by the operator via scp).
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$root      = "C:\hopclaw-runner"
$zip       = "$env:TEMP\hopclaw-repo.zip"
$url       = "https://github.com/asukhariev/hopclaw/archive/refs/heads/main.zip"
$ext       = Join-Path $root "hopclaw-main"
$run       = Join-Path $ext "runner"
$envFile   = Join-Path $run ".env"
$stagedEnv = "C:\hopclaw\runner.env"

if (-not (Test-Path "C:\Program Files\nodejs\node.exe")) {
    Write-Host "ERROR: Node not installed."
    exit 1
}
if (-not (Test-Path $stagedEnv)) {
    Write-Host "ERROR: staged .env missing at $stagedEnv"
    exit 1
}

Write-Host "1. Download repo zip"
New-Item -ItemType Directory -Path $root -Force | Out-Null
if (Test-Path $ext) { Remove-Item $ext -Recurse -Force }
Invoke-WebRequest -Uri $url -OutFile $zip
Write-Host "   got $((Get-Item $zip).Length) bytes"

Write-Host "2. Extract"
Expand-Archive -Path $zip -DestinationPath $root -Force
Write-Host "   extracted to $ext"

Write-Host "3. Copy staged .env into runner/"
Copy-Item $stagedEnv $envFile -Force
Write-Host "   .env in place ($((Get-Item $envFile).Length) bytes)"

Write-Host "4. npm install (~30 sec)"
Push-Location $run
& "C:\Program Files\nodejs\npm.cmd" install --silent --no-audit --no-fund 2>&1 | Select-Object -Last 5
Pop-Location
Write-Host "   done"

Write-Host "5. Register scheduled task"
$taskName = "HopClawRunner"
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
$action    = New-ScheduledTaskAction -Execute "C:\Program Files\nodejs\node.exe" `
              -Argument "--env-file=$envFile $run\index.js" `
              -WorkingDirectory $run
$trigger   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet `
              -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
              -RestartCount 99 -RestartInterval (New-TimeSpan -Minutes 1) `
              -ExecutionTimeLimit (New-TimeSpan -Days 365)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "   task '$taskName' registered."

Write-Host "6. Trigger now"
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 5
$info = Get-ScheduledTask -TaskName $taskName | Get-ScheduledTaskInfo
Write-Host "   LastRunTime: $($info.LastRunTime)"
Write-Host "   LastTaskResult: $($info.LastTaskResult)"

Write-Host "7. Node processes"
Get-Process node -ErrorAction SilentlyContinue | Select-Object Id, ProcessName, StartTime | Format-Table
