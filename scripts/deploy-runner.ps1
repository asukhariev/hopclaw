# Deploys the HopClaw runner on the Windows VM:
#   1. Download the asukhariev/hopclaw repo as a zip
#   2. Extract to C:\hopclaw-runner\
#   3. npm install in runner/
#   4. Verify .env exists (caller writes it before running this)
#   5. Register a scheduled task that auto-starts the runner on system boot
#   6. Trigger the task immediately so it starts now too
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$root      = "C:\hopclaw-runner"
$repoZip   = "$env:TEMP\hopclaw-repo.zip"
$repoUrl   = "https://github.com/asukhariev/hopclaw/archive/refs/heads/main.zip"
$extracted = "$root\hopclaw-main"
$runnerDir = "$extracted\runner"
$envFile   = "$runnerDir\.env"
$nodeExe   = "C:\Program Files\nodejs\node.exe"
$npmCmd    = "C:\Program Files\nodejs\npm.cmd"

if (-not (Test-Path $nodeExe)) {
    Write-Host "ERROR: Node not installed at $nodeExe. Run install-node-detached.ps1 first."
    exit 1
}

Write-Host "=== 1. Download repo zip ==="
New-Item -ItemType Directory -Path $root -Force | Out-Null
if (Test-Path $extracted) {
    Remove-Item $extracted -Recurse -Force
}
Invoke-WebRequest -Uri $repoUrl -OutFile $repoZip
Write-Host "Got $repoZip ($((Get-Item $repoZip).Length) bytes)"

Write-Host "=== 2. Extract ==="
Expand-Archive -Path $repoZip -DestinationPath $root -Force
Write-Host "Extracted to $extracted"

Write-Host "=== 3. npm install ==="
Push-Location $runnerDir
& $npmCmd install --silent --no-audit --no-fund
Pop-Location
Write-Host "Deps installed."

Write-Host "=== 4. .env check ==="
if (-not (Test-Path $envFile)) {
    Write-Host "ERROR: $envFile missing. Caller must write it before running deploy-runner.ps1."
    exit 1
}
Write-Host "Found .env ($((Get-Item $envFile).Length) bytes)."

Write-Host "=== 5. Register scheduled task (auto-start at boot, restart on crash) ==="
$taskName = "HopClawRunner"
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
$action    = New-ScheduledTaskAction -Execute $nodeExe `
              -Argument "--env-file=$envFile $runnerDir\index.js" `
              -WorkingDirectory $runnerDir
$trigger   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet `
              -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
              -RestartCount 99 -RestartInterval (New-TimeSpan -Minutes 1) `
              -ExecutionTimeLimit (New-TimeSpan -Days 365)
Register-ScheduledTask -TaskName $taskName `
    -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "Scheduled task '$taskName' registered."

Write-Host "=== 6. Trigger now ==="
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 3
$task = Get-ScheduledTask -TaskName $taskName | Get-ScheduledTaskInfo
Write-Host "Last result: $($task.LastTaskResult) (0 = ok / still running)"

Write-Host ""
Write-Host "Runner started. Logs: C:\hopclaw-runner\hopclaw-main\runner\ (stdout/stderr to scheduled task history)"
Write-Host "View live: Event Viewer -> Windows Logs -> Application, OR redirect output in the index.js next iteration."
