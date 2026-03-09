param(
  [string]$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
)

$ErrorActionPreference = "Stop"

$runRoot = Join-Path $RootDir "artifacts/test-runs"
if (-not (Test-Path -Path $runRoot -PathType Container)) {
  Write-Host "No artifacts directory found: $runRoot"
  exit 1
}

$gateFiles = Get-ChildItem -Path $runRoot -Recurse -File -Filter "gate-summary.json" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending

if (-not $gateFiles -or $gateFiles.Count -eq 0) {
  Write-Host "No gate-summary.json files found under $runRoot"
  exit 1
}

foreach ($file in $gateFiles) {
  try {
    $summary = Get-Content -Raw -Path $file.FullName | ConvertFrom-Json
    if ([string]$summary.status -eq "PASS") {
      Write-Host "Latest PASS run: $($summary.runDir)"
      Write-Host "Gate summary: $($file.FullName)"
      exit 0
    }
  } catch {
    # Continue scanning.
  }
}

Write-Host "No PASS gate run found yet."
Write-Host "Most recent run: $($gateFiles[0].DirectoryName)"
exit 1
