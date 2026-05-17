# Click at coords (in active RDP session), then capture screenshots.
param(
    [Parameter(Mandatory=$true)][int]$X,
    [Parameter(Mandatory=$true)][int]$Y,
    [string]$Tag = "click",
    [int]$CaptureCount = 2,
    [int]$WaitAfterClickSec = 3
)
$ErrorActionPreference = "Continue"

$taskName = "HopClawClickXY"
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
$arg = ("-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\hopclaw\click-coords.ps1 -X {0} -Y {1}" -f $X, $Y)
$action    = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arg
$principal = New-ScheduledTaskPrincipal -UserId "Administrator" -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null

Write-Host "Clicking ($X, $Y)..."
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds $WaitAfterClickSec

$ts  = Get-Date -Format "yyyyMMdd-HHmmss"
$dir = "C:\hopclaw\runs\$ts-$Tag"
New-Item -Path $dir -ItemType Directory -Force | Out-Null
for ($i = 1; $i -le $CaptureCount; $i++) {
    Start-ScheduledTask -TaskName "HopClawScreenshot"
    Start-Sleep -Seconds 2
    $src = "C:\hopclaw\screenshot.png"
    $dst = Join-Path $dir ("{0}-{1:D2}.png" -f $Tag, $i)
    if (Test-Path $src) {
        Copy-Item $src $dst -Force
        Write-Host "[$i/$CaptureCount] $dst ($((Get-Item $dst).Length) bytes)"
    }
    if ($i -lt $CaptureCount) { Start-Sleep -Seconds 2 }
}
Write-Host "Dir: $dir"
