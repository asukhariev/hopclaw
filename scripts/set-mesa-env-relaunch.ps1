# Set Mesa env vars to force OpenGL 4.6 advertisement, kill MR4,
# then re-launch via scheduled task. Capture screenshots after.
$ErrorActionPreference = "Continue"

# 1. Set system env vars so child processes inherit them
[Environment]::SetEnvironmentVariable("MESA_GL_VERSION_OVERRIDE", "4.6FC", "Machine")
[Environment]::SetEnvironmentVariable("MESA_GLSL_VERSION_OVERRIDE", "460", "Machine")
[Environment]::SetEnvironmentVariable("GALLIUM_DRIVER", "llvmpipe", "Machine")
Write-Host "Set MESA_GL_VERSION_OVERRIDE=4.6FC"
Write-Host "Set MESA_GLSL_VERSION_OVERRIDE=460"
Write-Host "Set GALLIUM_DRIVER=llvmpipe"

# 2. Kill MR4
$procs = Get-Process noraxon.mr -ErrorAction SilentlyContinue
foreach ($p in $procs) {
    Write-Host "Killing MR4 pid $($p.Id)"
    Stop-Process -Id $p.Id -Force
}
Start-Sleep -Seconds 2

# 3. Re-launch via scheduled task (inherits new system env)
Write-Host "Re-launching MR4..."
Start-ScheduledTask -TaskName "HopClawLaunchMR4"

# 4. Capture 8 frames over ~40 sec (gives time for license dialog -> Start -> main UI)
$ts  = Get-Date -Format "yyyyMMdd-HHmmss"
$dir = "C:\hopclaw\runs\$ts-mesa-env-test"
New-Item -Path $dir -ItemType Directory -Force | Out-Null
Write-Host "Capture dir: $dir"

for ($i = 1; $i -le 8; $i++) {
    Start-ScheduledTask -TaskName "HopClawScreenshot"
    Start-Sleep -Seconds 2
    $src = "C:\hopclaw\screenshot.png"
    $dst = Join-Path $dir ("frame-{0:D2}.png" -f $i)
    if (Test-Path $src) {
        Copy-Item $src $dst -Force
        $sz = (Get-Item $dst).Length
        Write-Host "[$i/8] $dst ($sz bytes)"
    }
    # Send Enter at frame 2 (typical license dialog has appeared by then)
    if ($i -eq 2) {
        Write-Host "    -> sending Enter to dismiss license"
        Start-ScheduledTask -TaskName "HopClawSendEnter"
    }
    if ($i -lt 8) { Start-Sleep -Seconds 3 }
}

Write-Host ""
Write-Host "MR4 process state:"
Get-Process noraxon.mr -ErrorAction SilentlyContinue | Format-Table Id,ProcessName,StartTime
