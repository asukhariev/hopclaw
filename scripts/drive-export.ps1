# Drive MR4 Database -> Export -> Excel SLK end-to-end.
# Re-mapped on 2026-05-23 for HOP Studio lab PC at 1600x900 (MR 4.0.106).
# Original calibration: 1440x900 / MR 4.0.124.
#
# Sequence (each step proven manually):
#   1. Focus MR4 + Escape x2 (dismiss any popups)
#   2. Click Database tab            -> (1248, 47)
#   3. Escape (dismiss possible Save changes dialog)
#   4. Click first record row        -> (820, 193)
#   5. Click Export button           -> (1461, 458)
#   6. Click Excel SLK menu item     -> (1379, 539)
#   7. Type full path + click Select Folder -> (611, 464)
#   8. Enter on filename dialog
#   9. Wait for export to write
#   10. Enter on success dialog
#
# Markers:
#   C:\hopclaw\drive-export.ok  -> full path to new file
#   C:\hopclaw\drive-export.err -> error message
$ErrorActionPreference = "Continue"

$exportDir   = "C:\hopclaw\exports"
$desktopDir  = [Environment]::GetFolderPath("Desktop")
$markerOk    = "C:\hopclaw\drive-export.ok"
$markerErr   = "C:\hopclaw\drive-export.err"
$logFile     = "C:\hopclaw\drive-export.log"
$expectedW   = 1600
$expectedH   = 900
$scriptStart = Get-Date
# Per-run prefix prepended to MR4's default filename so concurrent/repeat
# exports don't overwrite each other. Format: yyMMdd_HHmmss_  (13 chars).
$uniquePrefix = (Get-Date -Format 'yyMMdd_HHmmss_')

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
    Click 1248 47 "Database tab"
    Start-Sleep -Seconds 1

    Write-Host ""
    Write-Host "STEP 3. Escape any save-changes popup that may appear"
    Send "{ESC}" "dismiss-save"
    Start-Sleep -Milliseconds 500

    Write-Host ""
    Write-Host "STEP 4. Click first record row"
    Click 820 193 "record row"
    Start-Sleep -Milliseconds 500

    Write-Host ""
    Write-Host "STEP 5. Click Export button"
    Click 1461 458 "Export button"
    Start-Sleep -Seconds 1

    Write-Host ""
    Write-Host "STEP 6. Click Excel SLK menu item"
    Click 1379 539 "Excel SLK"
    Start-Sleep -Seconds 2

    Write-Host ""
    Write-Host "STEP 7. In folder picker (Pasta auto-focused): type full path + Enter"
    Send "C:\hopclaw\exports" "type full path in Pasta field"
    Start-Sleep -Milliseconds 600
    Send "{ENTER}" "submit selection"
    Start-Sleep -Seconds 2

    Write-Host ""
    Write-Host "STEP 8. Filename dialog: prepend unique prefix + Enter"
    # Filename is typically auto-selected; {HOME} deselects and puts cursor at start
    Send "{HOME}" "cursor to start"
    Start-Sleep -Milliseconds 200
    Send $uniquePrefix "prepend $uniquePrefix"
    Start-Sleep -Milliseconds 400
    Send "{ENTER}" "ok filename"
    Start-Sleep -Seconds 2

    Write-Host ""
    Write-Host "STEP 8.5. Enter for overwrite confirm (Yes default if file exists)"
    Send "{ENTER}" "overwrite-yes"
    Start-Sleep -Seconds 2

    Write-Host ""
    Write-Host "STEP 9. Wait for new file (max 60s) in exports OR desktop fallback"
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

        # Desktop fallback: MR4 sometimes ignores the folder picker and saves
        # to last-used location (Desktop). Move any new .slk created since
        # script start into the exports dir.
        $stray = Get-ChildItem $desktopDir -Filter *.slk -ErrorAction SilentlyContinue |
                 Where-Object { $_.LastWriteTime -ge $scriptStart -and $_.Length -gt 1000 }
        foreach ($s in $stray) {
            $dest = Join-Path $exportDir $s.Name
            Write-Host "  desktop-fallback: moving $($s.Name) -> $exportDir"
            try {
                Move-Item -Path $s.FullName -Destination $dest -Force -ErrorAction Stop
                $newFile = Get-Item $dest
                break
            } catch {
                Write-Host "    move failed: $($_.Exception.Message)"
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
