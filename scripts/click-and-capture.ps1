# Click a button/tab by Name via UI Automation, then capture screenshots.
# Usage: -Name "Database" -CaptureCount 3 -CaptureDir "C:\hopclaw\runs\..."
param(
    [Parameter(Mandatory=$true)][string]$Name,
    [int]$CaptureCount = 3,
    [int]$WaitAfterClickSec = 3,
    [int]$IntervalSec = 2,
    [string]$Tag = "step"
)
$ErrorActionPreference = "Continue"

# Register a one-off click task with our parametrized name
$taskName = "HopClawClick_" + ($Name -replace '[^A-Za-z0-9]','')
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false | Out-Null }

$arg = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\hopclaw\click-button.ps1 -Name "' + $Name + '"'
$action    = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arg
$principal = New-ScheduledTaskPrincipal -UserId "Administrator" -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null

Write-Host "Clicking '$Name' (task $taskName)..."
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds $WaitAfterClickSec

$ts  = Get-Date -Format "yyyyMMdd-HHmmss"
$dir = "C:\hopclaw\runs\$ts-$Tag"
New-Item -Path $dir -ItemType Directory -Force | Out-Null
Write-Host "Capture dir: $dir"

for ($i = 1; $i -le $CaptureCount; $i++) {
    Start-ScheduledTask -TaskName "HopClawScreenshot"
    Start-Sleep -Seconds 2
    $src = "C:\hopclaw\screenshot.png"
    $dst = Join-Path $dir ("{0}-{1:D2}.png" -f $Tag, $i)
    if (Test-Path $src) {
        Copy-Item $src $dst -Force
        Write-Host "[$i/$CaptureCount] $dst ($((Get-Item $dst).Length) bytes)"
    }
    if ($i -lt $CaptureCount) { Start-Sleep -Seconds $IntervalSec }
}
Write-Host "Done. Dir: $dir"
