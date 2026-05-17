# Reads coords from C:\hopclaw\click-args.txt (format: "X Y tag")
# Focuses MR4, clicks, takes a screenshot to C:\hopclaw\step-{tag}.png
$argsFile = "C:\hopclaw\click-args.txt"
if (-not (Test-Path $argsFile)) {
    "ERROR: $argsFile missing" | Out-File C:\hopclaw\step-error.log
    exit 1
}
$raw = (Get-Content $argsFile -Raw).Trim()
# Supports two modes:
#   "X Y tag"     -> click at coords
#   "KEY <keys> tag" -> SendKeys (Windows Forms format, e.g. {ENTER}, n, %s)
$parts = $raw -split '\s+', 3
$mode = if ($parts[0] -eq "KEY") { "key" } else { "click" }
if ($mode -eq "key") {
    $keys = $parts[1]
    $Tag  = if ($parts.Length -gt 2) { $parts[2] } else { "key" }
} else {
    $X = [int]$parts[0]
    $Y = [int]$parts[1]
    $Tag = if ($parts.Length -gt 2) { $parts[2] } else { "click" }
}

Add-Type @"
using System.Runtime.InteropServices;
public class W {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, int info);
}
"@
Add-Type -AssemblyName System.Windows.Forms,System.Drawing

$wsh = New-Object -ComObject WScript.Shell
[void]$wsh.AppActivate("Noraxon MR")
Start-Sleep -Milliseconds 300

if ($mode -eq "key") {
    [System.Windows.Forms.SendKeys]::SendWait($keys)
} else {
    [W]::SetCursorPos($X, $Y) | Out-Null
    Start-Sleep -Milliseconds 150
    [W]::mouse_event(0x0002, 0, 0, 0, 0)
    Start-Sleep -Milliseconds 60
    [W]::mouse_event(0x0004, 0, 0, 0, 0)
}
Start-Sleep -Seconds 2

$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)

# Draw a marker at the click point so we can SEE where it landed
if ($mode -eq "click") {
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Red), 4
    $g.DrawEllipse($pen, $X - 20, $Y - 20, 40, 40)
    $g.DrawLine($pen, $X - 30, $Y, $X + 30, $Y)
    $g.DrawLine($pen, $X, $Y - 30, $X, $Y + 30)
    $pen.Dispose()
}

$path = "C:\hopclaw\step-$Tag.png"
$bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"clicked ($X,$Y) saved $path" | Out-File C:\hopclaw\step-last.log
