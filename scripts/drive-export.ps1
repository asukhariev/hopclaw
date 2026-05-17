# Drive the MR4 Database -> Export -> CSV sequence end-to-end in the active
# (interactive) RDP session. Triggered by the HopClaw runner via a scheduled
# task with LogonType=Interactive (otherwise SendKeys/UI Automation can't
# reach the user's desktop).
#
# Writes a marker file when done:
#   C:\hopclaw\drive-export.ok   on success (contents = full file path)
#   C:\hopclaw\drive-export.err  on failure (contents = error message)
$ErrorActionPreference = "Continue"
$VerbosePreference     = "Continue"

$exportDir = "C:\hopclaw\exports"
$markerOk  = "C:\hopclaw\drive-export.ok"
$markerErr = "C:\hopclaw\drive-export.err"
$logFile   = "C:\hopclaw\drive-export.log"

New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
Remove-Item $markerOk, $markerErr, $logFile -ErrorAction SilentlyContinue
Start-Transcript -Path $logFile -Force | Out-Null

function Section($t) { Write-Host ""; Write-Host "===== $t =====" -ForegroundColor Cyan }

Add-Type -AssemblyName System.Windows.Forms,UIAutomationClient,UIAutomationTypes

# Win32 helpers for click-by-coords + force-foreground
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, int info);
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    public const uint LEFTDOWN = 0x0002;
    public const uint LEFTUP   = 0x0004;
    public const int  SW_MAXIMIZE = 3;
}
"@

function Click([int]$x, [int]$y) {
    [W]::SetCursorPos($x, $y) | Out-Null
    Start-Sleep -Milliseconds 150
    [W]::mouse_event([W]::LEFTDOWN, 0, 0, 0, 0)
    Start-Sleep -Milliseconds 60
    [W]::mouse_event([W]::LEFTUP,   0, 0, 0, 0)
    Start-Sleep -Milliseconds 250
    Write-Host "  click ($x, $y)"
}

function FocusMR4 {
    # Try several known title fragments
    $wsh = New-Object -ComObject WScript.Shell
    foreach ($title in @("Noraxon MR", "noraxon.mr", "MR 4.0")) {
        if ($wsh.AppActivate($title)) {
            Write-Host "  activated window: '$title'"
            Start-Sleep -Milliseconds 300
            return $true
        }
    }
    Write-Host "  WARNING: could not activate MR4 by title"
    return $false
}

function InvokeButtonByName([string]$name) {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $name)
    $elt = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if (-not $elt) { Write-Host "  NOT FOUND: '$name'"; return $false }
    try {
        $p = $elt.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $p.Invoke()
        Write-Host "  invoked: '$name'"
        Start-Sleep -Milliseconds 400
        return $true
    } catch {
        Write-Host "  could not invoke '$name': $($_.Exception.Message)"
        return $false
    }
}

try {
    Section "0. Snapshot existing exports"
    $before = @{}
    Get-ChildItem $exportDir -ErrorAction SilentlyContinue | ForEach-Object { $before[$_.Name] = $true }
    Write-Host "  $($before.Count) files already in $exportDir"

    Section "1. Dismiss any blocking popups (Escape x3)"
    FocusMR4 | Out-Null
    [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
    Start-Sleep -Milliseconds 200
    [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
    Start-Sleep -Milliseconds 200

    Section "2. Click Database tab (top-right of window)"
    # Coords for 1920x1080 maximized MR4: Database tab text center ~ (1497, 64)
    FocusMR4 | Out-Null
    Click 1497 64

    Section "3. Click the first record in middle pane"
    # First record row ~ (1100, 216) at 1920x1080
    FocusMR4 | Out-Null
    Click 1100 216

    Section "4. Click Export button in right sidebar"
    # Right sidebar "Export" button ~ (1828, 686) at 1920x1080
    FocusMR4 | Out-Null
    Click 1828 686
    Start-Sleep -Milliseconds 500

    Section "5. Click 'Export Data to Single CSV Files' in dropdown (UIA by name)"
    if (-not (InvokeButtonByName "Export Data to Single CSV Files")) {
        # Fall back: dropdown items are at predictable positions below Export button
        # "Export Data to Single CSV Files" is the 12th item in the menu we saw
        # Each menu item is ~22px tall; menu top is below the Export button
        # Approximate: x=1700, y=950 (guess; UIA should work, this is fallback)
        Write-Host "  falling back to coord click for menu item"
        Click 1700 950
    }

    Section "6. Filename dialog -> Enter (accept default record name)"
    Start-Sleep -Seconds 1
    FocusMR4 | Out-Null
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

    Section "7. 'Choose directory' folder picker -> type path + Alt+S (Select Folder)"
    Start-Sleep -Seconds 2
    # Type the path into the Folder: text field
    # The path field is usually focused initially. If not, Tab a few times.
    [System.Windows.Forms.SendKeys]::SendWait("$exportDir")
    Start-Sleep -Milliseconds 300
    # Alt+S is the underlined shortcut for "Select Folder"
    [System.Windows.Forms.SendKeys]::SendWait("%s")
    Start-Sleep -Seconds 1

    Section "8. Overwrite confirm (if appears) -> Enter (Yes is default)"
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Start-Sleep -Seconds 2

    Section "9. Wait for 'Please wait...' to finish (poll for new file, max 60s)"
    $deadline = (Get-Date).AddSeconds(60)
    $newFile = $null
    while ((Get-Date) -lt $deadline) {
        $candidates = Get-ChildItem $exportDir -ErrorAction SilentlyContinue |
            Where-Object { -not $before.ContainsKey($_.Name) -and $_.Length -gt 1000 }
        if ($candidates) {
            $newFile = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            Write-Host "  new file detected: $($newFile.Name) ($($newFile.Length) bytes)"
            break
        }
        Start-Sleep -Seconds 2
    }

    Section "10. Success dialog ('N record(s) exported.') -> Enter"
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Start-Sleep -Milliseconds 500

    if ($newFile) {
        Set-Content -Path $markerOk -Value $newFile.FullName -Encoding ASCII
        Write-Host ""
        Write-Host "SUCCESS: $($newFile.FullName)"
    } else {
        Set-Content -Path $markerErr -Value "no new file appeared in $exportDir within 60s" -Encoding ASCII
        Write-Host ""
        Write-Host "FAILURE: no new file appeared"
    }
} catch {
    Set-Content -Path $markerErr -Value $_.Exception.Message -Encoding ASCII
    Write-Host "EXCEPTION: $($_.Exception.Message)"
}

Stop-Transcript | Out-Null
