param(
  [string]$PlaygroundRoot = (Join-Path $env:USERPROFILE "Documents/Playground"),
  [string]$BehaviorPackName = "MorphStaff_BP",
  [string]$ResourcePackName = "MorphStaff_RP"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -Path $PlaygroundRoot -PathType Container)) {
  Write-Host "Playground root not found: $PlaygroundRoot"
  exit 0
}

$targets = @(
  (Join-Path $PlaygroundRoot $BehaviorPackName),
  (Join-Path $PlaygroundRoot $ResourcePackName)
)

foreach ($path in $targets) {
  if (Test-Path -Path $path) {
    Remove-Item -Path $path -Recurse -Force
    Write-Host "Removed: $path"
  } else {
    Write-Host "Already missing: $path"
  }
}

$remaining = Get-ChildItem -Path $PlaygroundRoot -Directory | Where-Object { $_.Name -like "MorphStaff_*" }
if ($remaining.Count -eq 0) {
  Write-Host "No MorphStaff_* folders remain in: $PlaygroundRoot"
} else {
  Write-Host "Remaining MorphStaff_* folders:"
  $remaining | ForEach-Object { Write-Host " - $($_.FullName)" }
}
