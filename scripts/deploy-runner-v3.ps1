# Deploy HopClaw runner + C:\hopclaw runtime scripts on the lab Windows box,
# WITHOUT SSH. Pulls the latest repo zip from GitHub, updates the runner
# (index.js), refreshes the PowerShell scripts in C:\hopclaw, and restarts the
# HopClawRunner scheduled task. The .env is preserved (staged or from the running
# runner). Run in an ELEVATED PowerShell:
#   $u='https://raw.githubusercontent.com/asukhariev/hopclaw/main/scripts/deploy-runner-v3.ps1'; iwr $u -OutFile $env:TEMP\d.ps1; & $env:TEMP\d.ps1
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$root      = "C:\hopclaw-runner"
$zip       = "$env:TEMP\hopclaw-repo.zip"
$url       = "https://github.com/asukhariev/hopclaw/archive/refs/heads/main.zip"
$ext       = Join-Path $root "hopclaw-main"
$run       = Join-Path $ext "runner"
$envFile   = Join-Path $run ".env"
$hop       = "C:\hopclaw"
$stagedEnv = "$hop\runner.env"
$node      = "C:\Program Files\nodejs\node.exe"
$npm       = "C:\Program Files\nodejs\npm.cmd"

if (-not (Test-Path $node)) { Write-Host "ERROR: Node not installed at $node"; exit 1 }

Write-Host "1. Preserve an existing .env"
$envSrc = $null
$envBak = "$env:TEMP\hopclaw.env.bak"
if (Test-Path $stagedEnv)            { $envSrc = $stagedEnv }
elseif (Test-Path "$run\.env")       { Copy-Item "$run\.env" $envBak -Force; $envSrc = $envBak }
elseif (Test-Path "$root\runner\.env") { Copy-Item "$root\runner\.env" $envBak -Force; $envSrc = $envBak }
if (-not $envSrc) { Write-Host "ERROR: no .env found (staged at $stagedEnv or in an existing runner). Place it first."; exit 1 }
Write-Host "   using .env from $envSrc"

Write-Host "2. Download + extract repo"
New-Item -ItemType Directory -Path $root -Force | Out-Null
if (Test-Path $ext) { Remove-Item $ext -Recurse -Force }
Invoke-WebRequest -Uri $url -OutFile $zip
Expand-Archive -Path $zip -DestinationPath $root -Force
Write-Host "   extracted to $ext"

Write-Host "3. Restore .env into runner/"
Copy-Item $envSrc $envFile -Force

Write-Host "4. Refresh C:\hopclaw runtime scripts"
New-Item -ItemType Directory -Path $hop -Force | Out-Null
foreach ($s in @("drive-measure.ps1", "click-text.ps1", "read-sensors.ps1")) {
  if (Test-Path "$ext\scripts\$s") { Copy-Item "$ext\scripts\$s" "$hop\$s" -Force; Write-Host "   copied $s" }
  else { Write-Host "   WARN: $s missing in repo" }
}

Write-Host "5. npm install (deps unchanged, but safe)"
Push-Location $run
& $npm install --silent --no-audit --no-fund 2>&1 | Select-Object -Last 3
Pop-Location

Write-Host "6. Re-register HopClawRunner task"
$taskName  = "HopClawRunner"
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
$action    = New-ScheduledTaskAction -Execute $node -Argument "--env-file=$envFile $run\index.js" -WorkingDirectory $run
$trigger   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
              -RestartCount 99 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 365)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

Write-Host "7. Kill old node, start fresh"
Get-Process node -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 6

Write-Host "8. Running node processes (expect exactly 1, fresh StartTime):"
Get-Process node -ErrorAction SilentlyContinue | Select-Object Id, StartTime | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "--- deploy-runner-v3 done ---"
