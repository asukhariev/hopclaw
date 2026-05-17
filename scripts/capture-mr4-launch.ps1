# Launches MR4 fresh in the interactive RDP session and snaps a sequence
# of screenshots through its boot, so we can see exactly what happens
# without the user needing to interact.
$ErrorActionPreference = "Continue"

$ts  = Get-Date -Format "yyyyMMdd-HHmmss"
$dir = "C:\hopclaw\runs\$ts-mr4-launch"
New-Item -Path $dir -ItemType Directory -Force | Out-Null
Write-Host "Capture run: $dir"

# Kill any existing MR4 process for a clean cold start
Get-Process noraxon.mr -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "Killing existing MR4 pid $($_.Id)"
    Stop-Process -Id $_.Id -Force
}
Start-Sleep -Seconds 2

# Find MR4 .exe
$mr4Exe = "C:\Program Files\Noraxon\MR 4.0\noraxon.mr.exe"
if (-not (Test-Path $mr4Exe)) {
    Write-Host "ERROR: $mr4Exe not found. Listing folder:"
    Get-ChildItem "C:\Program Files\Noraxon\MR 4.0" -Filter "*.exe" -ErrorAction SilentlyContinue | Format-Table Name
    exit 1
}

# Register / refresh the "launch MR4" task so it runs in the interactive (RDP) session
$launchAction    = New-ScheduledTaskAction -Execute $mr4Exe
$launchPrincipal = New-ScheduledTaskPrincipal -UserId "Administrator" -LogonType Interactive -RunLevel Highest
$launchSettings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "HopClawLaunchMR4" `
    -Action $launchAction -Principal $launchPrincipal -Settings $launchSettings -Force | Out-Null

Write-Host "Launching MR4..."
Start-ScheduledTask -TaskName "HopClawLaunchMR4"

# Capture sequence: 6 frames, ~5 sec apart, total ~30 sec
for ($i = 1; $i -le 6; $i++) {
    Start-ScheduledTask -TaskName "HopClawScreenshot"
    Start-Sleep -Seconds 2
    $src = "C:\hopclaw\screenshot.png"
    $dst = Join-Path $dir ("seq-{0:D2}.png" -f $i)
    if (Test-Path $src) {
        Copy-Item $src $dst -Force
        $sz = (Get-Item $dst).Length
        Write-Host "[$i/6] $dst ($sz bytes)"
    } else {
        Write-Host "[$i/6] MISSING screenshot"
    }
    if ($i -lt 6) { Start-Sleep -Seconds 3 }
}

Write-Host ""
Write-Host "Output dir: $dir"
Write-Host "MR4 process state:"
Get-Process noraxon.mr -ErrorAction SilentlyContinue | Format-Table Id,ProcessName,StartTime
