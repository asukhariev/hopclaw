# Mark stuck sessions as failed via the runner's own API.
# Reads runner .env for HOPAPP_URL + RUNNER_API_KEY.
$envFile = "C:\hopclaw-runner\hopclaw-main\runner\.env"
if (-not (Test-Path $envFile)) { Write-Host "no runner .env"; exit 1 }

$env_ = Get-Content $envFile | Where-Object { $_ -match "^[A-Z]+=" } |
    ForEach-Object {
        $parts = $_ -split "=", 2
        @{ Key = $parts[0]; Value = $parts[1] }
    }
$hopapp = ($env_ | Where-Object { $_.Key -eq "HOPAPP_URL" }).Value
$key    = ($env_ | Where-Object { $_.Key -eq "RUNNER_API_KEY" }).Value

$stuck = @("lrRoHf5glI", "v2hEGy_o9u")
foreach ($id in $stuck) {
    $body = @{
        session_id = $id
        status     = "failed"
        progress   = "Marked as failed during cleanup"
        error      = "Cleanup: session was stuck after drive-export failure"
    } | ConvertTo-Json
    try {
        $r = Invoke-RestMethod -Uri "$hopapp/api/runner/event" -Method Post `
            -Headers @{ "Authorization" = "Bearer $key"; "Content-Type" = "application/json" } `
            -Body $body
        Write-Host "Marked $id as failed: $($r.status)"
    } catch {
        Write-Host "Failed to mark $id : $($_.Exception.Message)"
    }
}
