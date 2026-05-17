# Single click at given coords, then take a screenshot. For step-by-step calibration.
param([Parameter(Mandatory=$true)][int]$X, [Parameter(Mandatory=$true)][int]$Y, [string]$Tag = "click")
Add-Type @"
using System.Runtime.InteropServices;
public class W {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, int info);
}
"@
Add-Type -AssemblyName System.Windows.Forms,System.Drawing

# Focus MR4 first
$wsh = New-Object -ComObject WScript.Shell
[void]$wsh.AppActivate("Noraxon MR")
Start-Sleep -Milliseconds 300

# Click
[W]::SetCursorPos($X, $Y) | Out-Null
Start-Sleep -Milliseconds 150
[W]::mouse_event(0x0002, 0, 0, 0, 0)
Start-Sleep -Milliseconds 60
[W]::mouse_event(0x0004, 0, 0, 0, 0)
Start-Sleep -Seconds 2

# Screenshot
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
$path = "C:\hopclaw\step-$Tag.png"
$bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"clicked ($X,$Y), saved $path"
