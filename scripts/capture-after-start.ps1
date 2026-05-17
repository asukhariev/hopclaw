# Triggers the SendEnter task (clicks Start on the MR4 license dialog),
# then captures 4 screenshots over 16 seconds to see the post-Start state.
$ErrorActionPreference = "Continue"

# Register the SendEnter task if not already
$existing = Get-ScheduledTask -TaskName "HopClawSendEnter" -ErrorAction SilentlyContinue
if (-not $existing) {
    $action    = New-ScheduledTaskAction -Execute "powershell.exe" `
                  -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\hopclaw\send-enter-to-mr4.ps1"
    $principal = New-ScheduledTaskPrincipal -UserId "Administrator" -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName "HopClawSendEnter" -Action $action -Principal $principal -Force | Out-Null
    Write-Host "Registered HopClawSendEnter task."
}

Write-Host "Sending ENTER to MR4 dialog..."
Start-ScheduledTask -TaskName "HopClawSendEnter"
Start-Sleep -Seconds 8

$ts  = Get-Date -Format "yyyyMMdd-HHmmss"
$dir = "C:\hopclaw\runs\$ts-mr4-after-start"
New-Item -Path $dir -ItemType Directory -Force | Out-Null
Write-Host "Capture dir: $dir"

for ($i = 1; $i -le 4; $i++) {
    Start-ScheduledTask -TaskName "HopClawScreenshot"
    Start-Sleep -Seconds 2
    $src = "C:\hopclaw\screenshot.png"
    $dst = Join-Path $dir ("after-{0:D2}.png" -f $i)
    if (Test-Path $src) {
        Copy-Item $src $dst -Force
        Write-Host "[$i/4] $dst ($((Get-Item $dst).Length) bytes)"
    } else {
        Write-Host "[$i/4] MISSING"
    }
    if ($i -lt 4) { Start-Sleep -Seconds 3 }
}

Write-Host ""
Write-Host "MR4 process state:"
Get-Process noraxon.mr -ErrorAction SilentlyContinue | Format-Table Id,ProcessName,StartTime
