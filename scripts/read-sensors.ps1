# HopClaw — read MR4 device/sensor-connection status from the post-activation
# screen. After "Activating hardware…", MR4 shows a modal dialog:
#   "Could not find the following sensors: e0115, e0128"
# if any are missing. We OCR the dialog region and report the missing IDs so the
# app can tell staff exactly what to connect.
#
#   -Path <png>   OCR a saved frame (for testing against a captured burst frame)
#   (no -Path)    capture + OCR the live screen
# Output: C:\hopclaw\sensors.json = { connected, missing:[...], raw } and prints RESULT.
param([string]$Path = "")
$ErrorActionPreference = "Continue"
$dir = "C:\hopclaw"

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
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
if (-not $ocrEngine) { Write-Host "ERR: no OCR language pack"; exit 1 }

# Source bitmap: a saved frame, or a fresh full-screen capture.
if ($Path) {
  $src = [System.Drawing.Bitmap]::FromFile($Path)
} else {
  $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $src = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($src)
  $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size); $g.Dispose()
}

# Crop to the centered modal-dialog region (1600x900 layout) and upscale 3x so
# the small sensor-ID text OCRs cleanly -> fast, accurate.
$rx = 560; $ry = 330; $rw = 520; $rh = 230; $scale = 3
$crop = New-Object System.Drawing.Bitmap ($rw * $scale), ($rh * $scale)
$cg = [System.Drawing.Graphics]::FromImage($crop)
$cg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$cg.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, ($rw * $scale), ($rh * $scale)), (New-Object System.Drawing.Rectangle $rx, $ry, $rw, $rh), [System.Drawing.GraphicsUnit]::Pixel)
$cg.Dispose(); $src.Dispose()
$cp = "$dir\.sensors-ocr.png"
$crop.Save($cp, [System.Drawing.Imaging.ImageFormat]::Png); $crop.Dispose()

$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($cp)) ([Windows.Storage.StorageFile])
$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$sb = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$res = Await ($ocrEngine.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])
$text = ($res.Lines | ForEach-Object { $_.Text }) -join " "
Write-Host "OCR TEXT: [$text]"

# Normalize an OCR'd sensor ID: drop spaces and fix the usual digit confusions
# (IDs are 'e' + digits, e.g. e0115). The leading letter is preserved.
function NormalizeId([string]$s) {
  $t = ($s -replace "\s", "").ToLower()
  if ($t.Length -lt 2) { return $t }
  $head = $t.Substring(0, 1)
  $body = ($t.Substring(1) -replace "o", "0" -replace "l", "1" -replace "i", "1" -replace "\|", "1" -replace "s", "5" -replace "b", "8")
  return ($head + $body)
}

# Parse "could not find ... sensors: <ids>" -> missing device IDs.
$missing = @()
$connected = $true
if ($text -match "(?i)could not find.*?sensors?\s*:?\s*(.+)") {
  $connected = $false
  $tail = ($Matches[1] -split "(?i)\bclose\b|\bok\b")[0]
  $missing = ($tail -split "[,;]") | ForEach-Object { (NormalizeId $_.Trim()) } | Where-Object { $_ -match "^\w?\d{2,6}$" }
}
$obj = [pscustomobject]@{ connected = $connected; missing = @($missing); raw = $text }
$json = $obj | ConvertTo-Json -Compress
Set-Content "$dir\sensors.json" $json -Encoding ASCII
Write-Host "RESULT: $json"
