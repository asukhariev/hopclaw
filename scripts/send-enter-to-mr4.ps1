# Activate the MR4 window and send Enter (clicks the default button — Start).
Add-Type -AssemblyName System.Windows.Forms
$wshell = New-Object -ComObject WScript.Shell

# Try a few likely window titles
$titles = @("Upgrade license", "Noraxon MR", "noraxon.mr", "MR")
foreach ($t in $titles) {
    if ($wshell.AppActivate($t)) {
        Write-Host "Activated window matching: $t"
        break
    }
}

Start-Sleep -Milliseconds 400
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Write-Host "Sent: ENTER"
