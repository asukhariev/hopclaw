# List subjects from an MR4 "OPENDATA" database's persons store.
# Each person is a folder under <Db>\persons\<id>\ with a UTF-8 "contents" file
# holding firstName / lastName / id. We match our customers by a 6-hex code
# embedded in firstName, so this is the live "is the subject in MR4?" check.
#
# Usage: powershell -File mr4-subjects.ps1 [-Db "<database folder>"] [-Json]
param(
  [string]$Db = "C:\Users\Admin\Desktop\Noraxon MR data HOP Lab",
  [switch]$Json
)
$personsDir = Join-Path $Db "persons"
if (-not (Test-Path $personsDir)) { Write-Output "NO_PERSONS_DIR: $personsDir"; exit 1 }

# Read even files MR4 holds open (the selected/just-created subject) by opening
# with FileShare.ReadWrite — a plain Get-Content fails on those and skips them.
function Read-Shared([string]$path) {
  try {
    $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
    $t = $sr.ReadToEnd(); $sr.Dispose(); $fs.Dispose(); return $t
  } catch { return $null }
}

$out = @()
Get-ChildItem $personsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  $c = Read-Shared (Join-Path $_.FullName "contents")
  if ($c) {
    $fn = [regex]::Match($c, 'firstName:\s*"([^"]*)"').Groups[1].Value
    $ln = [regex]::Match($c, 'lastName:\s*"([^"]*)"').Groups[1].Value
    $id = [regex]::Match($c, 'id:\s*"([^"]*)"').Groups[1].Value
    $out += [pscustomobject]@{ dir = $_.Name; firstName = $fn; lastName = $ln; id = $id }
  }
}
if ($Json) { $out | ConvertTo-Json -Compress }
else { $out | ForEach-Object { "first=[{0}] last=[{1}] id=[{2}]" -f $_.firstName, $_.lastName, $_.id } }
