# Dump UIA tree of the MR4 process to discover element names + control types.
# Writes output to C:\hopclaw\uia-dump.txt (since Start-Transcript-style works here).
Start-Transcript -Path "C:\hopclaw\uia-dump.txt" -Force | Out-Null
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes

$mr4 = Get-Process noraxon.mr -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $mr4) { Write-Host "MR4 not running"; exit 1 }

$root = [System.Windows.Automation.AutomationElement]::RootElement
$pidCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $mr4.Id)

$all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $pidCond)
Write-Host "TOTAL elements in MR4 process: $($all.Count)"
Write-Host ""

# Look for "Database", "Export", and other interesting names — also dump everything with a name
$interesting = @("Database", "Export", "Bilateral", "Home", "Measure", "View", "Report")

Write-Host "=== Elements with names (top 80) ==="
$named = @()
foreach ($e in $all) {
    try {
        $n = $e.Current.Name
        if ($n -and $n.Length -gt 0 -and $n.Length -lt 100) {
            $ct = $e.Current.ControlType.LocalizedControlType
            $r = $e.Current.BoundingRectangle
            $named += [PSCustomObject]@{
                Name = $n
                Type = $ct
                X = [int]$r.X; Y = [int]$r.Y
                W = [int]$r.Width; H = [int]$r.Height
                Vis = (-not $e.Current.IsOffscreen)
            }
        }
    } catch { }
}
$named | Where-Object { $_.Vis -and $_.W -gt 0 } | Sort-Object Y, X | Select-Object -First 80 | Format-Table -AutoSize | Out-String | Write-Host

Write-Host ""
Write-Host "=== Elements whose Name matches interesting tokens ==="
$named | Where-Object {
    $row = $_
    $interesting | Where-Object { $row.Name -like "*$_*" }
} | Sort-Object Y, X | Format-Table -AutoSize | Out-String | Write-Host

Stop-Transcript | Out-Null
