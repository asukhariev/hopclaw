# HopClaw — drive MR4 measure-start flow (1600x900).
# NAV-ONLY by default: Escape -> Home -> Gait tile -> protocol row, with a
# screenshot after each step. MEASURE is only clicked when measure.go exists,
# so the default run never starts a real recording.
#
# Target protocol: read from C:\hopclaw\measure.target ("gait" | "running"),
# default "gait". Both live under the Gait tile's protocol list.
#
# Markers:  drive-measure.ok | drive-measure.err
# Shots:    measure-0-reset.png .. measure-4-after-measure.png
$ErrorActionPreference = "Continue"
$dir = "C:\hopclaw"
$log = "$dir\drive-measure.log"
$ok  = "$dir\drive-measure.ok"
$err = "$dir\drive-measure.err"
Remove-Item $ok, $err -ErrorAction SilentlyContinue
Remove-Item "$dir\measure-burst-*.png" -ErrorAction SilentlyContinue
Start-Transcript -Path $log -Force | Out-Null

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, int i);
}
"@

$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
if ($b.Width -ne 1600 -or $b.Height -ne 900) {
  Set-Content $err "resolution mismatch: $($b.Width)x$($b.Height), need 1600x900" -Encoding ASCII
  Stop-Transcript | Out-Null; exit 1
}

function FocusMR4 {
  $w = New-Object -ComObject WScript.Shell
  foreach ($t in @("Noraxon MR", "noraxon.mr", "MR 4")) { if ($w.AppActivate($t)) { Start-Sleep -Milliseconds 300; return } }
}
function Click([int]$x, [int]$y, [string]$label) {
  FocusMR4
  [W]::SetCursorPos($x, $y) | Out-Null; Start-Sleep -Milliseconds 200
  [W]::mouse_event(0x0002, 0, 0, 0, 0); Start-Sleep -Milliseconds 60; [W]::mouse_event(0x0004, 0, 0, 0, 0)
  Write-Host "  click ($x,$y) - $label"; Start-Sleep -Milliseconds 800
}
function Send([string]$keys, [string]$label) {
  FocusMR4; [System.Windows.Forms.SendKeys]::SendWait($keys)
  Write-Host "  send '$keys' - $label"; Start-Sleep -Milliseconds 300
}
function Snap([string]$name) {
  $p = "$dir\measure-$name.png"
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
  $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
  Write-Host "  snap -> $p"
}

$target = "gait"
if (Test-Path "$dir\measure.target") { $target = (Get-Content "$dir\measure.target" -Raw).Trim().ToLower() }
$protocolY = if ($target -eq "running") { 255 } else { 209 }
Write-Host "TARGET: $target (protocol row y=$protocolY)"

try {
  if (Test-Path "$dir\clicktext.go") {
    # CLICKTEXT: find a dialog button by its text (OCR) and click it. Used for the
    # Save Data modal (Save & View / Save & Measure Again).
    $ctFind = ""; $ctAvoid = ""
    if (Test-Path "$dir\clicktext.find") { $ctFind = (Get-Content "$dir\clicktext.find" -Raw).Trim() }
    if (Test-Path "$dir\clicktext.avoid") { $ctAvoid = (Get-Content "$dir\clicktext.avoid" -Raw).Trim() }
    Write-Host "CLICKTEXT: find='$ctFind' avoid='$ctAvoid'"
    & "$dir\click-text.ps1" -Find $ctFind -Avoid $ctAvoid
    if (Test-Path "$dir\clicktext.ok") { Set-Content $ok ("clicktext: " + (Get-Content "$dir\clicktext.ok" -Raw).Trim()) -Encoding ASCII }
    else {
      $ctErr = "clicktext failed"
      if (Test-Path "$dir\clicktext.err") { $ctErr = (Get-Content "$dir\clicktext.err" -Raw).Trim() }
      Set-Content $err $ctErr -Encoding ASCII
    }
  } elseif (Test-Path "$dir\next.go") {
    # NEXT-only: click the bottom-right primary button (NEXT on the calibration
    # screens — same coord as MEASURE). No navigation. Used to drive
    # Calibrate Left Insole -> NEXT -> Calibrate Right Insole -> NEXT.
    Write-Host "NEXT-ONLY: click (1462,873)"; Click 1462 873 "NEXT"; Start-Sleep -Milliseconds 1200
    Set-Content $ok "next click done" -Encoding ASCII
  } else {
    Write-Host "STEP 1: reset (Escape x2)"; Send "{ESC}" "esc1"; Send "{ESC}" "esc2"
    Write-Host "STEP 2: Home tab (948,47)"; Click 948 47 "Home tab"
    Write-Host "STEP 3: Gait tile (396,642)"; Click 396 642 "Gait tile"
    Write-Host "STEP 4: protocol row (1460,$protocolY)"; Click 1460 $protocolY "protocol-$target"

    # MEASURE is gated: only click it when explicitly armed via measure.go
    if (Test-Path "$dir\measure.go") {
      Write-Host "STEP 5: MEASURE (1462,873) [ARMED]"; Click 1462 873 "MEASURE"
      # Brief settle so MR4 lands on the measurement screen. The slow ~20s wait is
      # gone, so launch stays fast. Sensor status is read ONLY when explicitly
      # requested via readsensors.go (the Devices "check" command) — never on a
      # plain launch, which is what kept "Starting…" slow.
      Start-Sleep -Seconds 3
      if (Test-Path "$dir\readsensors.go") {
        Write-Host "STEP 6: read device status (requested)"; try { & "$dir\read-sensors.ps1" } catch { Write-Host "read-sensors err: $_" }
      }
      Set-Content $ok "measure flow complete (target=$target, MEASURE clicked)" -Encoding ASCII
    } else {
      Write-Host "STEP 5: MEASURE skipped (nav-only; create measure.go to arm)"
      Set-Content $ok "navigation complete (target=$target); MEASURE NOT clicked (nav-only)" -Encoding ASCII
    }
  }
  Write-Host "DONE"
} catch {
  Set-Content $err $_.Exception.Message -Encoding ASCII
}
Stop-Transcript | Out-Null
