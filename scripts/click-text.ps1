# HopClaw — find a button by its text (OCR) in the centered dialog area and click
# it. Used for the Save Data modal (Save & View / Save & Measure Again) where a
# fixed coordinate is risky. Local screen OCR only — nothing uploaded.
#   -Find  : substring the target line must contain (case-insensitive)
#   -Avoid : substring that disqualifies a line (e.g. "discard")
# Markers: clicktext.ok (clicked x,y) | clicktext.err
param([string]$Find = "", [string]$Avoid = "")
$ErrorActionPreference = "Continue"
$dir = "C:\hopclaw"
$ok = "$dir\clicktext.ok"; $err = "$dir\clicktext.err"
Remove-Item $ok, $err -ErrorAction SilentlyContinue

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, int i);
}
"@
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Storage.StorageFile, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($task, $resultType) { $netTask = $asTaskGeneric.MakeGenericMethod($resultType).Invoke($null, @($task)); $netTask.Wait(-1) | Out-Null; $netTask.Result }
$ocr = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if (-not $ocr) { Set-Content $err "no OCR" -Encoding ASCII; exit 1 }

# OCR a generous central region (where modal dialogs appear).
$rx = 450; $ry = 320; $rw = 700; $rh = 330
$bmp = New-Object System.Drawing.Bitmap $rw, $rh
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen((New-Object System.Drawing.Point $rx, $ry), [System.Drawing.Point]::Empty, (New-Object System.Drawing.Size $rw, $rh))
$p = "$dir\.clicktext.png"; $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($p)) ([Windows.Storage.StorageFile])
$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$sb = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$res = Await ($ocr.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])

$cx = -1; $cy = -1; $hit = ""
foreach ($ln in $res.Lines) {
  $t = $ln.Text.ToLower()
  if ($Find -and ($t -like "*$($Find.ToLower())*")) {
    if ($Avoid -and ($t -like "*$($Avoid.ToLower())*")) { continue }
    $minX = 99999; $maxX = 0; $ys = @()
    foreach ($w in $ln.Words) {
      if ($w.BoundingRect.X -lt $minX) { $minX = $w.BoundingRect.X }
      $rEdge = $w.BoundingRect.X + $w.BoundingRect.Width
      if ($rEdge -gt $maxX) { $maxX = $rEdge }
      $ys += ($w.BoundingRect.Y + $w.BoundingRect.Height / 2)
    }
    $cx = $rx + [int](($minX + $maxX) / 2); $cy = $ry + [int](($ys | Measure-Object -Average).Average); $hit = $ln.Text
    break
  }
}
if ($cx -ge 0) {
  [W]::SetCursorPos($cx, $cy) | Out-Null; Start-Sleep -Milliseconds 250
  [W]::mouse_event(0x0002, 0, 0, 0, 0); Start-Sleep -Milliseconds 60; [W]::mouse_event(0x0004, 0, 0, 0, 0)
  Set-Content $ok "clicked '$hit' at $cx,$cy" -Encoding ASCII
} else {
  Set-Content $err "text '$Find' not found in dialog region" -Encoding ASCII
}
