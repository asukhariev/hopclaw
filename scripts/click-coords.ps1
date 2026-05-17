# Click at absolute screen coordinates via Win32 mouse_event.
# Usage: -X 615 -Y 22
param(
    [Parameter(Mandatory=$true)][int]$X,
    [Parameter(Mandatory=$true)][int]$Y
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class M {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, int info);
    public const uint LEFTDOWN = 0x0002;
    public const uint LEFTUP   = 0x0004;
}
"@

[M]::SetCursorPos($X, $Y) | Out-Null
Start-Sleep -Milliseconds 200
[M]::mouse_event([M]::LEFTDOWN, 0, 0, 0, 0)
Start-Sleep -Milliseconds 80
[M]::mouse_event([M]::LEFTUP,   0, 0, 0, 0)
Write-Host "Clicked at ($X, $Y)"
