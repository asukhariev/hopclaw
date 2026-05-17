Write-Host "=== C:\hopclaw\exports ==="
Get-ChildItem "C:\hopclaw\exports" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
Write-Host ""
Write-Host "=== C:\hopclaw root (recent 15m) ==="
Get-ChildItem "C:\hopclaw" -File |
    Where-Object { ((Get-Date) - $_.LastWriteTime).TotalMinutes -lt 15 } |
    Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
Write-Host ""
Write-Host "=== MR4 Data dir (recent 15m) ==="
Get-ChildItem "C:\Program Files\Noraxon\MR 4.0\Data" -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { ((Get-Date) - $_.LastWriteTime).TotalMinutes -lt 15 } |
    Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize
