# HopClaw — drive MR4 "create & link Subject" flow (1600x900).
#
# OBSERVE-ONLY by default: Home -> open Subject dropdown -> type the target name
# (to see the type-ahead) -> Escape -> open "New" subject dialog -> Escape, with
# a screenshot after each step. NOTHING is created in this mode.
#
# CREATE is gated behind C:\hopclaw\subject.go (like measure.go gates MEASURE):
# when present, the New dialog is filled (first-name field) and OK is clicked,
# creating + selecting the subject. The final screenshot is the "proof".
#
# Target name: read from C:\hopclaw\subject.name (e.g. "André Silva 3f9c1a").
# MR4's quick New-Subject dialog only has a "first name" field, so the whole
# "<name> <code>" string goes there (confirmed from Joana's lab intake).
#
# Markers:  drive-subject.ok | drive-subject.err
# Shots:    subject-0-home.png .. subject-5-created.png
$ErrorActionPreference = "Continue"
$dir = "C:\hopclaw"
$log = "$dir\drive-subject.log"
$ok  = "$dir\drive-subject.ok"
$err = "$dir\drive-subject.err"
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
function Send([string]$keys, [string]$label) {
  FocusMR4; [System.Windows.Forms.SendKeys]::SendWait($keys)
  Write-Host "  send '$keys' - $label"; Start-Sleep -Milliseconds 300
}
# Type literal text, escaping SendKeys metacharacters ( + ^ % ~ ( ) { } [ ] ).
function TypeText([string]$text, [string]$label) {
  FocusMR4
  $esc = [regex]::Replace($text, '([+^%~(){}\[\]])', '{$1}')
  [System.Windows.Forms.SendKeys]::SendWait($esc)
  Write-Host "  type '$text' - $label"; Start-Sleep -Milliseconds 400
}
function Snap([string]$name) {
  $p = "$dir\subject-$name.png"
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
  $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
  Write-Host "  snap -> $p"
}

# Target subject name (the whole "<name> <code>" string goes in first-name).
$name = "Probe Subject zz0000"
if (Test-Path "$dir\subject.name") { $name = (Get-Content "$dir\subject.name" -Raw).Trim() }
$armed = Test-Path "$dir\subject.go"
Write-Host "TARGET NAME: '$name'  (armed=$armed)"

# Coordinates (1600x900), verified from the observe run:
#   Home tab (948,47); Subject dropdown (1455,441); Subject 'New' (1350,468);
#   New-Subject dialog: First Name value cell (940,257); green Ok (1129,772).
$firstNameX = 940; $firstNameY = 257
$okX = 1129; $okY = 772
if (Test-Path "$dir\subject.ok.xy") {
  $xy = (Get-Content "$dir\subject.ok.xy" -Raw).Trim() -split '[, ]+'
  if ($xy.Count -ge 2) { $okX = [int]$xy[0]; $okY = [int]$xy[1] }
}

try {
  Write-Host "STEP 1: Home (Escape + Home tab)"; Send "{ESC}" "esc"; Click 948 47 "Home tab"; Snap "0-home"
  Write-Host "STEP 2: open Subject dropdown (1455,441)"; Click 1455 441 "Subject dropdown"; Snap "1-dropdown"
  Write-Host "STEP 3: type name into type-ahead"; TypeText $name "type-ahead search"; Snap "2-typeahead"
  Write-Host "STEP 4: close dropdown (Escape)"; Send "{ESC}" "close dropdown"
  Write-Host "STEP 5: open New-subject dialog (1350,468)"; Click 1350 468 "Subject New"; Snap "3-newdialog"

  if ($armed) {
    Write-Host "STEP 6: [ARMED] focus First Name field ($firstNameX,$firstNameY)"; Click $firstNameX $firstNameY "First Name field"
    Write-Host "STEP 7: [ARMED] type name into First Name"; TypeText $name "first name"
    # Commit the inline cell editor before clicking OK — otherwise the grid
    # swallows the first click on OK (it just ends the edit) and the dialog stays open.
    Write-Host "STEP 8: [ARMED] commit cell (Tab)"; Send "{TAB}" "commit"; Snap "4-typed"
    Write-Host "STEP 9: [ARMED] click OK ($okX,$okY)"; Click $okX $okY "OK"
    Start-Sleep -Milliseconds 700; Click $okX $okY "OK (confirm)"
    Start-Sleep -Milliseconds 1000; Snap "5-created"
    Set-Content $ok "subject created+selected: '$name'" -Encoding ASCII
  } else {
    Write-Host "STEP 6: cancel dialog (Escape) [observe-only]"; Send "{ESC}" "cancel dialog"; Snap "4-cancelled"
    Set-Content $ok "observe complete (name='$name'); NOTHING created (create subject.go to arm)" -Encoding ASCII
  }
  Write-Host "DONE"
} catch {
  Set-Content $err $_.Exception.Message -Encoding ASCII
}
Stop-Transcript | Out-Null
