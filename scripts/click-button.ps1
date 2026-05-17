# Click a button by Name via UI Automation. Works across windows/processes.
# Usage: pass button name as first arg, falls back to "OK" if missing.
param([string]$Name = "OK")

Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes

$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::NameProperty, $Name)
$buttons = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)

Write-Host "Found $($buttons.Count) elements named '$Name'"
$clicked = $false
foreach ($b in $buttons) {
    $ct = $b.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::ControlTypeProperty)
    if ($ct -ne [System.Windows.Automation.ControlType]::Button) { continue }
    try {
        $pattern = $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $pattern.Invoke()
        Write-Host "Clicked button '$Name' (pid $($b.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::ProcessIdProperty)))"
        $clicked = $true
        break
    } catch {
        Write-Host "Could not invoke: $($_.Exception.Message)"
    }
}
if (-not $clicked) { Write-Host "No invokeable button '$Name' found" }
