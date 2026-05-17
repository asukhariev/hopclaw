# Find where MR4 stores its recordings (database, files, etc.)
$paths = @(
    "C:\ProgramData\Noraxon",
    "C:\Users\Administrator\AppData\Roaming\Noraxon",
    "C:\Users\Administrator\AppData\Local\Noraxon",
    "C:\Users\Administrator\Documents\Noraxon",
    "C:\Program Files\Noraxon\MR 4.0\Data",
    "C:\Users\Public\Noraxon"
)

Write-Host "=== Candidate paths ==="
foreach ($p in $paths) {
    if (Test-Path $p) {
        Write-Host "FOUND: $p"
        Get-ChildItem $p -Recurse -Depth 3 -ErrorAction SilentlyContinue |
            Select-Object FullName, @{N="Size";E={if($_.PSIsContainer){"<dir>"}else{$_.Length}}}, LastWriteTime |
            Format-Table -AutoSize | Out-String | Write-Host
    } else {
        Write-Host "missing: $p"
    }
}

Write-Host ""
Write-Host "=== MR4 install dir structure ==="
Get-ChildItem "C:\Program Files\Noraxon\MR 4.0" -Directory -ErrorAction SilentlyContinue |
    Select-Object Name | Format-Table | Out-String | Write-Host

Write-Host ""
Write-Host "=== Find any .sqlite, .db, .mdb files in C:\ ==="
Get-ChildItem "C:\" -Recurse -Include "*.sqlite","*.sqlite3","*.db","*.mdb" -ErrorAction SilentlyContinue 2>$null |
    Where-Object { $_.FullName -notmatch "Windows\\|node_modules|\.git" } |
    Select-Object FullName, Length, LastWriteTime |
    Format-Table -AutoSize | Out-String | Write-Host
