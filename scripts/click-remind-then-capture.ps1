# Register an interactive-session click task for "Remind me later", trigger it,
# then capture 5 frames to see what main MR4 UI looks like underneath.
$ErrorActionPreference = "Continue"

# Register click task
$existing = Get-ScheduledTask -TaskName "HopClawClickRemind" -ErrorAction SilentlyContinue
if (-not $existing) {
    $action    = New-ScheduledTaskAction -Execute "powershell.exe" `
                  -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\hopclaw\click-button.ps1 -Name "Remind me later"'
    $principal = New-ScheduledTaskPrincipal -UserId "Administrator" -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName "HopClawClickRemind" -Action $action -Principal $principal -Force | Out-Null
    Write-Host "Registered HopClawClickRemind task."
}

Write-Host "Clicking 'Remind me later'..."
Start-ScheduledTask -TaskName "HopClawClickRemind"
Start-Sleep -Seconds 4

$ts  = Get-Date -Format "yyyyMMdd-HHmmss"
$dir = "C:\hopclaw\runs\$ts-mr4-main-ui"
New-Item -Path $dir -ItemType Directory -Force | Out-Null
Write-Host "Capture dir: $dir"

for ($i = 1; $i -le 5; $i++) {
    Start-ScheduledTask -TaskName "HopClawScreenshot"
    Start-Sleep -Seconds 2
    $src = "C:\hopclaw\screenshot.png"
    $dst = Join-Path $dir ("main-{0:D2}.png" -f $i)
    if (Test-Path $src) {
        Copy-Item $src $dst -Force
        Write-Host "[$i/5] $dst ($((Get-Item $dst).Length) bytes)"
    }
    if ($i -lt 5) { Start-Sleep -Seconds 2 }
}

Write-Host ""
Write-Host "MR4 windows:"
Get-Process noraxon.mr -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host ("  pid {0}  title=[{1}]" -f $_.Id, $_.MainWindowTitle)
}
