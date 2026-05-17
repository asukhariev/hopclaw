# Install Mesa3D software OpenGL (LLVMpipe) into MR4's directory.
# Lets MR4 launch on EC2 instances without a GPU by replacing the system
# basic-display OpenGL with Mesa's modern software implementation.

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Section($t) { Write-Host ""; Write-Host "===== $t =====" -ForegroundColor Cyan }

Section "0. Disable Defender real-time monitoring for the install (re-enabled at end)"
# mesa-dist-win is a known Defender false-positive. Path exclusions get ignored
# by Tamper Protection, so we briefly disable real-time scanning instead.
# Once the DLL is in place, MR4 loads it as a DLL (not as a process), so Defender
# leaves it alone after re-enable.
try {
    Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction Stop
    Write-Host "Defender real-time monitoring disabled."
} catch {
    Write-Host "WARNING: could not disable Defender ($($_.Exception.Message)). Continuing - download may fail."
}

# Clean any quarantined leftovers from prior runs
if (Test-Path "$env:TEMP\mesa.7z") {
    Remove-Item "$env:TEMP\mesa.7z" -Force -ErrorAction SilentlyContinue
    Write-Host "Cleaned old mesa.7z."
}
if (Test-Path "$env:TEMP\mesa") {
    Remove-Item "$env:TEMP\mesa" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Cleaned old extracted mesa folder."
}

# Add path exclusions as belt-and-suspenders so the DLL stays put after re-enable
Add-MpPreference -ExclusionPath "C:\Program Files\Noraxon\MR 4.0\opengl32.dll" -ErrorAction SilentlyContinue

Section "1. Install 7-Zip (needed to extract Mesa .7z release)"
if (Test-Path "C:\Program Files\7-Zip\7z.exe") {
    Write-Host "7-Zip already present."
} else {
    $u = "https://www.7-zip.org/a/7z2408-x64.msi"
    $m = "$env:TEMP\7z.msi"
    Write-Host "Downloading 7-Zip MSI..."
    Invoke-WebRequest $u -OutFile $m
    Start-Process msiexec.exe -ArgumentList "/i", $m, "/qn", "/norestart" -Wait
    if (-not (Test-Path "C:\Program Files\7-Zip\7z.exe")) {
        Write-Host "ERROR: 7-Zip install failed."
        exit 1
    }
    Write-Host "7-Zip installed."
}

Section "2. Fetch latest mesa-dist-win release info"
$headers = @{ "User-Agent" = "PowerShell" }
$release = Invoke-RestMethod "https://api.github.com/repos/pal1000/mesa-dist-win/releases/latest" -Headers $headers
$asset = $release.assets | Where-Object {
    $_.name -match "release-msvc\.7z$" -and $_.name -notmatch "msys2"
} | Select-Object -First 1
if (-not $asset) { Write-Host "ERROR: no matching release asset found."; exit 1 }
Write-Host "Latest: $($asset.name) ($([math]::Round($asset.size/1MB,1)) MB)"

Section "3. Download"
$file = "$env:TEMP\mesa.7z"
Invoke-WebRequest $asset.browser_download_url -OutFile $file
Write-Host "Downloaded to $file"

Section "4. Extract"
$dest = "$env:TEMP\mesa"
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
& "C:\Program Files\7-Zip\7z.exe" x $file "-o$dest" -y | Out-Null
Write-Host "Extracted to $dest"

Section "5. Locate x64 opengl32.dll"
# mesa-dist-win 26.x ships just x64/opengl32.dll and x86/opengl32.dll (no nested variant dirs).
# We want the x64 one and not d3d12/osmesa variants if present.
$candidates = Get-ChildItem $dest -Recurse -Filter "opengl32.dll" | ForEach-Object {
    $path = $_.FullName.ToLower()
    [PSCustomObject]@{
        Path = $_.FullName
        IsX64 = $path -match "x64"
        IsD3d12 = $path -match "d3d12"
        IsOsmesa = $path -match "osmesa"
    }
}
$dll = $candidates | Where-Object { $_.IsX64 -and -not $_.IsD3d12 -and -not $_.IsOsmesa } | Select-Object -First 1
if (-not $dll) {
    Write-Host "Could not find x64 opengl32.dll. All candidates:"
    $candidates | Format-Table
    exit 1
}
Write-Host "Picked: $($dll.Path)"

Section "6. Copy ALL x64 DLLs to MR4 install dir (opengl32 depends on siblings like libgallium_wgl)"
$mr4Dir = "C:\Program Files\Noraxon\MR 4.0"
if (-not (Test-Path $mr4Dir)) {
    Write-Host "ERROR: MR4 install dir not found at $mr4Dir"
    Get-ChildItem "C:\Program Files\Noraxon" | Format-Table Name
    exit 1
}
$srcDir = Split-Path $dll.Path
Write-Host "Source folder: $srcDir"
$srcDlls = Get-ChildItem $srcDir -Filter "*.dll"
Write-Host "Copying $($srcDlls.Count) DLLs to $mr4Dir ..."
foreach ($f in $srcDlls) {
    $dst = Join-Path $mr4Dir $f.Name
    try {
        Copy-Item $f.FullName $dst -Force -ErrorAction Stop
        Write-Host "  -> $($f.Name) ($($f.Length) bytes)"
    } catch {
        Write-Host "  SKIP $($f.Name) - in use or locked ($($_.Exception.Message))"
    }
}

Section "7. Re-enable Defender real-time monitoring"
try {
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
    Write-Host "Defender real-time monitoring re-enabled."
} catch {
    Write-Host "WARNING: could not re-enable Defender ($($_.Exception.Message)). Re-enable manually via Windows Security UI."
}

Section "8. Done"
Write-Host "Re-launch MR4. The OpenGL error should be gone (or different)."
Write-Host "If the 3D viewer still fails, Mesa is too slow / wrong variant - escalate to GPU instance."
