# Find a UIA element by name across ALL processes and invoke it.
# Args from C:\hopclaw\click-args.txt format: "UIA <name> tag"
$argsFile = "C:\hopclaw\click-args.txt"
$raw = (Get-Content $argsFile -Raw).Trim()
$parts = $raw -split '\s+', 3
$mode = $parts[0]
if ($mode -ne "UIA") {
    "ERROR: expected UIA mode, got $mode" | Out-File C:\hopclaw\step-error.log
    exit 1
}
$name = $parts[1]
$Tag  = if ($parts.Length -gt 2) { $parts[2] } else { "uia" }

Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Windows.Forms,System.Drawing

$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::NameProperty, $name)
$elt = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
if (-not $elt) {
    "ERROR: UIA element '$name' not found" | Out-File C:\hopclaw\step-error.log
    exit 1
}

# Try Invoke first
$invoked = $false
try {
    $p = $elt.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $p.Invoke()
    $invoked = $true
} catch { }

# Fall back: click bounding rect center
if (-not $invoked) {
    Add-Type @"
using System.Runtime.InteropServices;
public class W2 {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, int info);
}
"@
    $r = $elt.Current.BoundingRectangle
    if ($r.Width -gt 0) {
        $cx = [int]($r.X + $r.Width / 2)
        $cy = [int]($r.Y + $r.Height / 2)
        [W2]::SetCursorPos($cx, $cy) | Out-Null
        Start-Sleep -Milliseconds 100
        [W2]::mouse_event(0x0002, 0, 0, 0, 0)
        Start-Sleep -Milliseconds 60
        [W2]::mouse_event(0x0004, 0, 0, 0, 0)
        "clicked-rect: $($r.X),$($r.Y) ${cx}x$cy" | Out-File C:\hopclaw\step-last.log
    }
}
Start-Sleep -Seconds 2

# Screenshot
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
$bmp.Save("C:\hopclaw\step-$Tag.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"invoked=$invoked name='$name'" | Out-File C:\hopclaw\step-last.log
