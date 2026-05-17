# HopClaw — Windows VM bootstrap
#
# Run this ONCE inside the Windows 11 VM after Windows is installed and the
# UTM shared folder is mounted. It installs Node.js LTS and OpenClaw.
#
# MR3 is NOT installed by this script — install MR3 by hand from the shared
# folder first (see ../notes/vm-setup.md). MR3's installer is GUI-only.
#
# Usage (in an elevated PowerShell — right-click → "Run as administrator"):
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\bootstrap.ps1
#
# Idempotent — safe to re-run.

$ErrorActionPreference = "Stop"

function Section($title) {
    Write-Host ""
    Write-Host "===== $title =====" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
Section "1. Check we're admin"
# ---------------------------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "ERROR: This script must run as Administrator." -ForegroundColor Red
    Write-Host "Close this window, right-click PowerShell, choose 'Run as administrator', try again."
    exit 1
}
Write-Host "OK — running as Administrator."

# ---------------------------------------------------------------------------
Section "2. Check winget"
# ---------------------------------------------------------------------------
$winget = Get-Command winget -ErrorAction SilentlyContinue
if (-not $winget) {
    Write-Host "winget not found. On Windows 11 it should be present out of the box."
    Write-Host "Install it from the Microsoft Store: search 'App Installer'."
    exit 1
}
Write-Host "winget found: $($winget.Source)"

# ---------------------------------------------------------------------------
Section "3. Install Node.js LTS"
# ---------------------------------------------------------------------------
$nodeInstalled = Get-Command node -ErrorAction SilentlyContinue
if ($nodeInstalled) {
    $nodeVersion = node --version
    Write-Host "Node.js already installed: $nodeVersion"
} else {
    Write-Host "Installing Node.js LTS via winget..."
    winget install --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements --silent
    # Refresh PATH for this session so `node` and `npm` resolve below
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: node still not on PATH after install. Open a new PowerShell window and re-run."
        exit 1
    }
    Write-Host "Node.js installed: $(node --version)"
    Write-Host "npm: $(npm --version)"
}

# ---------------------------------------------------------------------------
Section "4. Install OpenClaw globally"
# ---------------------------------------------------------------------------
$openclawInstalled = npm list -g openclaw 2>$null | Select-String "openclaw@"
if ($openclawInstalled) {
    Write-Host "OpenClaw already installed: $openclawInstalled"
} else {
    Write-Host "Installing OpenClaw..."
    npm install -g openclaw
    Write-Host "OpenClaw installed: $(openclaw --version)"
}

# ---------------------------------------------------------------------------
Section "5. OpenClaw onboard (install daemon)"
# ---------------------------------------------------------------------------
Write-Host "Running: openclaw onboard --install-daemon"
Write-Host "(follow any prompts — daemon registration usually needs one confirm)"
openclaw onboard --install-daemon

# ---------------------------------------------------------------------------
Section "6. Discover the shared folder"
# ---------------------------------------------------------------------------
Write-Host "Looking for the Mac-side hopclaw/ folder mounted via UTM/SPICE..."
Write-Host "If nothing shows below, open File Explorer manually and check:"
Write-Host "  - This PC → Network → SPICE share"
Write-Host "  - Or a mapped drive letter (Z:, Y:, etc.)"
Get-PSDrive -PSProvider FileSystem | Format-Table Name, Root, Description

# ---------------------------------------------------------------------------
Section "Done"
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "  1. Confirm you can read the shared hopclaw/ folder from Windows."
Write-Host "  2. If MR3 isn't installed yet → install it now from the shared folder."
Write-Host "  3. Capture the 5 reference screenshots into hopclaw/references/ (see references/README.md)."
Write-Host "  4. Ping Claude on the Mac to write the interface map + OpenClaw prompt."
