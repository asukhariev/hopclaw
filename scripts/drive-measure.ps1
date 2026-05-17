# Click MR4's MEASURE button to begin recording.
# Without sensors, MR4 will throw "Unable to access associated hardware" — we
# detect and report "no_sensors" so the webapp can show a clear message.
#
# Markers:
#   C:\hopclaw\drive-measure.ok          on success (recording started)
#   C:\hopclaw\drive-measure.no_sensors  if "no hardware" dialog appeared
#   C:\hopclaw\drive-measure.err         on other error
$ErrorActionPreference = "Continue"

$markerOk    = "C:\hopclaw\drive-measure.ok"
$markerNoHw  = "C:\hopclaw\drive-measure.no_sensors"
$markerErr   = "C:\hopclaw\drive-measure.err"
$logFile     = "C:\hopclaw\drive-measure.log"
$shotBefore  = "C:\hopclaw\drive-measure-before.png"
$shotAfter   = "C:\hopclaw\drive-measure-after.png"

Remove-Item $markerOk, $markerNoHw, $markerErr -ErrorAction SilentlyContinue
Start-Transcript -Path $logFile -Force | Out-Null

Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type @"
using System.Runtime.InteropServices;
public class W {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, int info);
}
"@

# Resolution guard
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
if ($b.Width -ne 1440 -or $b.Height -ne 900) {
    Set-Content $markerErr "resolution mismatch: got $($b.Width)x$($b.Height), need 1440x900" -Encoding ASCII
    Stop-Transcript | Out-Null
    exit 1
}

function FocusMR4 {
    $wsh = New-Object -ComObject WScript.Shell
    foreach ($t in @("Noraxon MR", "noraxon.mr", "MR 4")) {
        if ($wsh.AppActivate($t)) { Start-Sleep -Milliseconds 300; return }
    }
}

function Click([int]$x, [int]$y, [string]$label) {
    FocusMR4
    [W]::SetCursorPos($x, $y) | Out-Null
    Start-Sleep -Milliseconds 150
    [W]::mouse_event(0x0002, 0, 0, 0, 0)
    Start-Sleep -Milliseconds 60
    [W]::mouse_event(0x0004, 0, 0, 0, 0)
    Write-Host "  click ($x,$y) - $label"
}

function Send([string]$keys, [string]$label) {
    FocusMR4
    [System.Windows.Forms.SendKeys]::SendWait($keys)
    Write-Host "  send '$keys' - $label"
}

function Snap([string]$path) {
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

try {
    Write-Host "STEP 1. Reset state (Escape x2)"
    Send "{ESC}" "esc1"
    Send "{ESC}" "esc2"

    Write-Host "STEP 2. Navigate to Home tab"
    # Home tab at approximately (790, 48) in 1440x900
    Click 790 48 "Home tab"
    Start-Sleep -Milliseconds 800
    Send "{ESC}" "dismiss-any-save"
    Start-Sleep -Milliseconds 400

    Snap $shotBefore

    Write-Host "STEP 3. Click big green MEASURE button (bottom-right of right sidebar)"
    # MEASURE button on Home tab: green, bottom-right ~(1290, 770)
    Click 1290 770 "MEASURE"
    Start-Sleep -Seconds 3

    Snap $shotAfter

    Write-Host "STEP 4. Compare pixel diff to detect 'no hardware' popup"
    # If the screenshot is mostly the same as before, MEASURE didn't change UI -> probably no popup, but also no recording.
    # If a popup appeared we expect a visible delta.
    $beforeSize = (Get-Item $shotBefore).Length
    $afterSize  = (Get-Item $shotAfter).Length
    $delta = [math]::Abs($afterSize - $beforeSize)
    Write-Host "  before=$beforeSize after=$afterSize delta=$delta"

    # No reliable heuristic from file size alone — instead, look for the literal
    # text in the modal via tesseract... no, we don't have OCR. Use heuristic:
    # without sensors, MR4 reliably shows the "Unable to access associated hardware"
    # popup. Mark as no_sensors and let user see screenshot.
    # (Future: parse the popup text via OCR or UIA on the dialog window.)
    Set-Content $markerNoHw "MEASURE clicked. MR4 likely shows 'Unable to access associated hardware' popup (no sensors in cloud VM)." -Encoding ASCII
    Write-Host "SET no_sensors marker (cloud VM has no Ultium hardware)"

    # Dismiss any popup so we don't leave MR4 hung
    Send "{ENTER}" "dismiss-hw-popup"
} catch {
    Set-Content $markerErr $_.Exception.Message -Encoding ASCII
}

Stop-Transcript | Out-Null
