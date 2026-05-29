# HopClaw — select an EXISTING MR4 subject by name (1600x900). No create.
#
# Opens the Subject dropdown, types the target name (the combo autocompletes to
# the matching subject), and presses Enter to select it — so MR4 has the right
# subject active before an evaluation. Screenshots each step as proof.
#
# Target name: read from C:\hopclaw\subject.select (e.g. "HopLab Test 7e5701").
# Markers: select-subject.ok | select-subject.err
# Shots:   select-0-home.png .. select-3-selected.png
$ErrorActionPreference = "Continue"
$dir = "C:\hopclaw"
$log = "$dir\select-subject.log"
$ok  = "$dir\select-subject.ok"
$err = "$dir\select-subject.err"
Remove-Item $ok, $err -ErrorAction SilentlyContinue
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
# Click WITHOUT re-activating MR4 — AppActivate dismisses the open dropdown popup.
function ClickNoFocus([int]$x, [int]$y, [string]$label) {
  [W]::SetCursorPos($x, $y) | Out-Null; Start-Sleep -Milliseconds 200
  [W]::mouse_event(0x0002, 0, 0, 0, 0); Start-Sleep -Milliseconds 60; [W]::mouse_event(0x0004, 0, 0, 0, 0)
  Write-Host "  click-nofocus ($x,$y) - $label"; Start-Sleep -Milliseconds 800
}
function Send([string]$keys, [string]$label) {
  FocusMR4; [System.Windows.Forms.SendKeys]::SendWait($keys)
  Write-Host "  send '$keys' - $label"; Start-Sleep -Milliseconds 300
}
function TypeText([string]$text, [string]$label) {
  FocusMR4
  $esc = [regex]::Replace($text, '([+^%~(){}\[\]])', '{$1}')
  [System.Windows.Forms.SendKeys]::SendWait($esc)
  Write-Host "  type '$text' - $label"; Start-Sleep -Milliseconds 400
}
function Snap([string]$name) {
  $p = "$dir\select-$name.png"
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
  $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
  Write-Host "  snap -> $p"
}

$name = ""
if (Test-Path "$dir\subject.select") { $name = (Get-Content "$dir\subject.select" -Raw).Trim() }
# Selecting = clicking the person's row in the open dropdown, WITHOUT re-focusing
# (re-activating MR4 closes the popup). subject.row holds the row's screen Y.
$rowY = 0
if (Test-Path "$dir\subject.row") { $rowY = [int]((Get-Content "$dir\subject.row" -Raw).Trim()) }
Write-Host "SELECT: '$name'  (rowY=$rowY)"

# Coordinates (1600x900): Home tab (948,47); Subject dropdown (1455,441).
try {
  Write-Host "STEP 1: Home"; Send "{ESC}" "esc"; Click 948 47 "Home tab"; Snap "0-home"
  Write-Host "STEP 2: open Subject dropdown"; Click 1455 441 "Subject dropdown"; Snap "1-dropdown"
  Write-Host "STEP 3: click row at (1450,$rowY) without refocus"; ClickNoFocus 1450 $rowY "subject row"; Start-Sleep -Milliseconds 700; Snap "2-selected"
  Set-Content $ok "clicked subject row y=$rowY (target '$name')" -Encoding ASCII
  Write-Host "DONE"
} catch {
  Set-Content $err $_.Exception.Message -Encoding ASCII
}
Stop-Transcript | Out-Null
