# Drive MR4 Database -> Export -> Excel SLK end-to-end.
# Validated on 2026-05-17 at 1440x900 native resolution.
#
# Sequence (each step proven manually):
#   1. Focus MR4 + Escape x2 (dismiss any popups)
#   2. Click Database tab            -> (1085, 48)
#   3. Escape (dismiss possible Save changes dialog)
#   4. Click first record row        -> (685, 192)
#   5. Click Export button           -> (1280, 505)
#   6. Click Excel SLK menu item     -> (1280, 244)
#   7. Type "exports" + click Select Folder -> (516, 468)
#   8. Enter on filename dialog
#   9. Wait for export to write
#   10. Enter on success dialog
#
# Markers:
#   C:\hopclaw\drive-export.ok  -> full path to new file
#   C:\hopclaw\drive-export.err -> error message
$ErrorActionPreference = "Continue"

$exportDir   = "C:\hopclaw\exports"
$markerOk    = "C:\hopclaw\drive-export.ok"
$markerErr   = "C:\hopclaw\drive-export.err"
$logFile     = "C:\hopclaw\drive-export.log"
$expectedW   = 1440
$expectedH   = 900

New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
Remove-Item $markerOk, $markerErr -ErrorAction SilentlyContinue
Start-Transcript -Path $logFile -Force | Out-Null

Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type @"
using System.Runtime.InteropServices;
public class W {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, int info);
}
"@

# Resolution guard
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
Write-Host "Screen: $($b.Width) x $($b.Height) (expected ${expectedW}x${expectedH})"
if ($b.Width -ne $expectedW -or $b.Height -ne $expectedH) {
    $msg = "resolution mismatch: got $($b.Width)x$($b.Height), need ${expectedW}x${expectedH}. Reconnect RDP at the expected resolution."
    Set-Content -Path $markerErr -Value $msg -Encoding ASCII
    Stop-Transcript | Out-Null
    exit 1
}

function FocusMR4 {
    $wsh = New-Object -ComObject WScript.Shell
    foreach ($t in @("Noraxon MR", "noraxon.mr", "MR 4")) {
        if ($wsh.AppActivate($t)) { Start-Sleep -Milliseconds 300; return }
    }
}

function Click([int]$x, [int]$y, [string]$label) {
    FocusMR4
    [W]::SetCursorPos($x, $y) | Out-Null
    Start-Sleep -Milliseconds 150
    [W]::mouse_event(0x0002, 0, 0, 0, 0)
    Start-Sleep -Milliseconds 60
    [W]::mouse_event(0x0004, 0, 0, 0, 0)
    Write-Host "  click ($x,$y) - $label"
}

function Send([string]$keys, [string]$label) {
    FocusMR4
    [System.Windows.Forms.SendKeys]::SendWait($keys)
    Write-Host "  send '$keys' - $label"
}

try {
    Write-Host ""
    Write-Host "STEP 1. Dismiss any open popup (Escape x2)"
    Send "{ESC}" "esc1"
    Start-Sleep -Milliseconds 300
    Send "{ESC}" "esc2"
    Start-Sleep -Milliseconds 300

    # Snapshot exports dir BEFORE
    $before = @{}
    Get-ChildItem $exportDir -ErrorAction SilentlyContinue | ForEach-Object { $before[$_.Name] = $_.LastWriteTimeUtc }
    Write-Host "  existing files: $($before.Count)"

    Write-Host ""
    Write-Host "STEP 2. Click Database tab"
    Click 1085 48 "Database tab"
    Start-Sleep -Seconds 1

    Write-Host ""
    Write-Host "STEP 3. Escape any save-changes popup that may appear"
    Send "{ESC}" "dismiss-save"
    Start-Sleep -Milliseconds 500

    Write-Host ""
    Write-Host "STEP 4. Click first record (Bilateral Gait)"
    Click 685 192 "record row"
    Start-Sleep -Milliseconds 500

    Write-Host ""
    Write-Host "STEP 5. Click Export button"
    Click 1280 505 "Export button"
    Start-Sleep -Seconds 1

    Write-Host ""
    Write-Host "STEP 6. Click Excel SLK menu item"
    Click 1280 244 "Excel SLK"
    Start-Sleep -Seconds 2

    Write-Host ""
    Write-Host "STEP 7. In folder picker: type 'exports' + click Select Folder"
    Send "exports" "type exports"
    Start-Sleep -Milliseconds 600
    Click 516 468 "Select Folder button"
    Start-Sleep -Seconds 2

    Write-Host ""
    Write-Host "STEP 8. Enter on filename dialog"
    Send "{ENTER}" "ok filename"
    Start-Sleep -Seconds 2

    Write-Host ""
    Write-Host "STEP 8.5. Enter for overwrite confirm (Yes default if file exists)"
    Send "{ENTER}" "overwrite-yes"
    Start-Sleep -Seconds 2

    Write-Host ""
    Write-Host "STEP 9. Wait for new file (max 60s)"
    $deadline = (Get-Date).AddSeconds(60)
    $newFile = $null
    while ((Get-Date) -lt $deadline) {
        $now = Get-ChildItem $exportDir -ErrorAction SilentlyContinue
        foreach ($f in $now) {
            $isNew = -not $before.ContainsKey($f.Name) -or $before[$f.Name] -ne $f.LastWriteTimeUtc
            if ($isNew -and $f.Length -gt 1000) {
                $newFile = $f
                break
            }
        }
        if ($newFile) { break }
        Start-Sleep -Seconds 2
    }

    Write-Host ""
    Write-Host "STEP 10. Enter on success dialog"
    Send "{ENTER}" "close success"
    Start-Sleep -Milliseconds 500

    if ($newFile) {
        Set-Content -Path $markerOk -Value $newFile.FullName -Encoding ASCII
        Write-Host ""
        Write-Host "SUCCESS: $($newFile.FullName) ($($newFile.Length) bytes)"
    } else {
        Set-Content -Path $markerErr -Value "no new file in $exportDir within 60s" -Encoding ASCII
        Write-Host "FAILURE: no new file"
    }
} catch {
    Set-Content -Path $markerErr -Value $_.Exception.Message -Encoding ASCII
    Write-Host "EXCEPTION: $($_.Exception.Message)"
}

Stop-Transcript | Out-Null
