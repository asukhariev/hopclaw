# HopClaw — select an EXISTING MR4 subject by its unique code (1600x900).
#
# The Subject control is a scrolling, non-filtering combobox whose list items
# aren't copyable (clipboard read-back fails). So we use Windows' built-in OCR:
# open the dropdown, scroll to the top, then page down reading each view with
# OCR until a row contains our 6-hex code, click that row, and OCR the Subject
# field to verify the code is now selected. Matching by code (not the full name)
# is OCR-robust, and reading the live list covers in-memory (unflushed) subjects.
#
# Target: C:\hopclaw\subject.select = "<name> <code>"  (code = last token)
# Markers: select-subject.ok | select-subject.err ; debug: select-trace.txt, *.png
$ErrorActionPreference = "Continue"
$dir = "C:\hopclaw"
$log = "$dir\select-subject.log"; $ok = "$dir\select-subject.ok"; $err = "$dir\select-subject.err"
Remove-Item $ok, $err -ErrorAction SilentlyContinue
Start-Transcript -Path $log -Force | Out-Null

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, int d, int i);
}
"@

$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
if ($b.Width -ne 1600 -or $b.Height -ne 900) {
  Set-Content $err "resolution mismatch: $($b.Width)x$($b.Height)" -Encoding ASCII; Stop-Transcript | Out-Null; exit 1
}

# ── Windows.Media OCR (WinRT) ────────────────────────────────────────────────
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Storage.StorageFile, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($task, $resultType) {
  $netTask = $asTaskGeneric.MakeGenericMethod($resultType).Invoke($null, @($task))
  $netTask.Wait(-1) | Out-Null; $netTask.Result
}
$ocrEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if (-not $ocrEngine) { Set-Content $err "no OCR language pack available" -Encoding ASCII; Stop-Transcript | Out-Null; exit 1 }

# Screenshot a SCREEN REGION, OCR it -> lines of [pscustomobject]@{Text;Y;X} with
# Y/X mapped back to screen coords. Cropping to the dropdown makes OCR ~10x faster.
function OcrRegion([int]$rx, [int]$ry, [int]$rw, [int]$rh) {
  $p = "$dir\.ocr.png"
  $bmp = New-Object System.Drawing.Bitmap $rw, $rh
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen((New-Object System.Drawing.Point $rx, $ry), [System.Drawing.Point]::Empty, (New-Object System.Drawing.Size $rw, $rh))
  $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
  $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($p)) ([Windows.Storage.StorageFile])
  $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $sb = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $res = Await ($ocrEngine.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])
  $out = @()
  foreach ($ln in $res.Lines) {
    $ys = @(); $xs = @()
    foreach ($w in $ln.Words) { $ys += ($w.BoundingRect.Y + $w.BoundingRect.Height / 2); $xs += $w.BoundingRect.X }
    $out += [pscustomobject]@{ Text = $ln.Text; Y = $ry + [int](($ys | Measure-Object -Average).Average); X = $rx + [int](($xs | Measure-Object -Minimum).Minimum) }
  }
  return $out
}

function FocusMR4 { $w = New-Object -ComObject WScript.Shell; foreach ($t in @("Noraxon MR", "noraxon.mr", "MR 4")) { if ($w.AppActivate($t)) { Start-Sleep -Milliseconds 300; return } } }
function Click([int]$x, [int]$y, [string]$l) { FocusMR4; [W]::SetCursorPos($x, $y) | Out-Null; Start-Sleep -Milliseconds 200; [W]::mouse_event(0x0002, 0, 0, 0, 0); Start-Sleep -Milliseconds 60; [W]::mouse_event(0x0004, 0, 0, 0, 0); Write-Host "  click ($x,$y) $l"; Start-Sleep -Milliseconds 800 }
function ClickNoFocus([int]$x, [int]$y, [string]$l) { [W]::SetCursorPos($x, $y) | Out-Null; Start-Sleep -Milliseconds 200; [W]::mouse_event(0x0002, 0, 0, 0, 0); Start-Sleep -Milliseconds 60; [W]::mouse_event(0x0004, 0, 0, 0, 0); Write-Host "  click-nf ($x,$y) $l"; Start-Sleep -Milliseconds 700 }
function Scroll([int]$ticks) { [W]::SetCursorPos(1450, 600) | Out-Null; Start-Sleep -Milliseconds 120; [W]::mouse_event(0x0800, 0, 0, (120 * $ticks), 0); Start-Sleep -Milliseconds 350 }
function Send([string]$k) { FocusMR4; [System.Windows.Forms.SendKeys]::SendWait($k); Start-Sleep -Milliseconds 300 }
function Snap([string]$n) { $p = "$dir\select-$n.png"; $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height; $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size); $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose() }

$target = ""
if (Test-Path "$dir\subject.select") { $target = (Get-Content "$dir\subject.select" -Raw).Trim() }
if (-not $target) { Set-Content $err "no subject.select target" -Encoding ASCII; Stop-Transcript | Out-Null; exit 1 }
$code = ($target -split '\s+')[-1]
Write-Host "SELECT TARGET: '$target'  code='$code'"
# OCR garbles short codes (spaces, a<->8, etc.), so match the whole "name code"
# string fuzzily (Levenshtein similarity) — tolerant of a few char errors but
# still specific to this subject.
function NoSpace([string]$s) { return ($s -replace '\s', '').ToLower() }
function Lev([string]$a, [string]$b) {
  $n = $a.Length; $m = $b.Length
  if ($n -eq 0) { return $m }; if ($m -eq 0) { return $n }
  $prev = New-Object 'int[]' ($m + 1)
  $cur = New-Object 'int[]' ($m + 1)
  for ($j = 0; $j -le $m; $j++) { $prev[$j] = $j }
  for ($i = 1; $i -le $n; $i++) {
    $cur[0] = $i
    for ($j = 1; $j -le $m; $j++) {
      $cost = if ($a[$i - 1] -eq $b[$j - 1]) { 0 } else { 1 }
      $min = $prev[$j] + 1
      $t = $cur[$j - 1] + 1; if ($t -lt $min) { $min = $t }
      $t = $prev[$j - 1] + $cost; if ($t -lt $min) { $min = $t }
      $cur[$j] = $min
    }
    $tmp = $prev; $prev = $cur; $cur = $tmp
  }
  return $prev[$m]
}
function Sim([string]$a, [string]$b) {
  $a = NoSpace $a; $b = NoSpace $b
  $L = [Math]::Max($a.Length, $b.Length); if ($L -eq 0) { return 0.0 }
  return (1.0 - (Lev $a $b) / $L)
}
$targetNS = NoSpace $target
$THRESH = 0.80   # list match: strict (pick the right row among ~34)
$VTHRESH = 0.58  # verify: looser (single noisy field read; just confirm it's ours, not a neighbor)

# Dropdown rows live roughly between y=465 and y=755; the Subject field ~y=441.
$trace = New-Object System.Collections.Generic.List[string]
try {
  Send "{ESC}"; Click 948 47 "Home tab"
  Click 1455 441 "open dropdown"; Start-Sleep -Milliseconds 400
  Scroll 25   # scroll list to the very top (wheel up)
  Start-Sleep -Milliseconds 300

  $clickedY = 0
  for ($page = 0; $page -lt 14; $page++) {
    $rows = OcrRegion 1326 458 280 302
    foreach ($r in $rows) { $trace.Add(("p$page y$($r.Y): [$($r.Text)] sim=$([math]::Round((Sim $r.Text $target),2))")) }
    $best = ($rows | ForEach-Object { [pscustomobject]@{ Row = $_; S = (Sim $_.Text $target) } } | Sort-Object S -Descending | Select-Object -First 1)
    if ($best -and $best.S -ge $THRESH) { Write-Host ("  match '{0}' sim={1:N2} y={2}" -f $best.Row.Text, $best.S, $best.Row.Y); ClickNoFocus 1450 $best.Row.Y "subject row"; $clickedY = $best.Row.Y; break }
    Scroll -3   # page down
  }
  ($trace -join "`r`n") | Set-Content "$dir\select-trace.txt" -Encoding UTF8

  if ($clickedY -gt 0) {
    Start-Sleep -Milliseconds 900; Snap "selected"
    # verify: the Subject field (~y441) should now fuzzy-match the target.
    $vbest = (OcrRegion 1320 414 296 52 | ForEach-Object { [pscustomobject]@{ T = $_.Text; S = (Sim $_.Text $target) } } | Sort-Object S -Descending | Select-Object -First 1)
    if ($vbest -and $vbest.S -ge $VTHRESH) { Set-Content $ok ("selected+verified '$target' (field='$($vbest.T)' sim=$([math]::Round($vbest.S,2)))") -Encoding ASCII; Write-Host "VERIFIED" }
    else { Set-Content $err ("clicked but verify failed for '$target' (best='$($vbest.T)')") -Encoding ASCII; Write-Host "VERIFY FAILED" }
  }
  else {
    Send "{ESC}"; Snap "notfound"; Set-Content $err "not found in dropdown: '$target'" -Encoding ASCII; Write-Host "NOT FOUND"
  }
} catch {
  Set-Content $err $_.Exception.Message -Encoding ASCII
}
Stop-Transcript | Out-Null
