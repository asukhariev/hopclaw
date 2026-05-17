Get-Process noraxon.mr -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host ("PID {0}  Title: [{1}]  Handle: {2}" -f $_.Id, $_.MainWindowTitle, $_.MainWindowHandle)
}
