param(
  [string]$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path,
  [string]$RunDir,
  [string]$ManualResultsPath,
  [string[]]$LogPathOverride,
  [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"

if (-not $RunDir) {
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $RunDir = Join-Path $RootDir "artifacts/test-runs/$timestamp"
}

New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

$preflightScript = Join-Path $PSScriptRoot "preflight.ps1"
$runtimeScript = Join-Path $PSScriptRoot "collect-bedrock-logs.ps1"
$gateScript = Join-Path $PSScriptRoot "evaluate-gate.ps1"
$matrixPath = Join-Path $RootDir "tests/bedrock-manual-matrix.md"
$templatePath = Join-Path $RootDir "tests/bedrock-manual-results.template.json"

if (-not $ManualResultsPath) {
  $ManualResultsPath = Join-Path $RunDir "manual-results.json"
}

if (-not (Test-Path -Path $ManualResultsPath -PathType Leaf)) {
  if (Test-Path -Path $templatePath -PathType Leaf) {
    Copy-Item -Path $templatePath -Destination $ManualResultsPath -Force
  } else {
    '{"tester":"","minecraftVersion":"","worldName":"","scenarios":[]}' | Set-Content -Path $ManualResultsPath -Encoding UTF8
  }
}

Write-Host "Run directory: $RunDir"
Write-Host "Manual results path: $ManualResultsPath"

& $preflightScript -RootDir $RootDir -RunDir $RunDir -NoExit | Out-Null
& $runtimeScript -Mode Begin -RootDir $RootDir -RunDir $RunDir -LogPathOverride $LogPathOverride -NoExit

Write-Host ""
Write-Host "Manual test matrix: $matrixPath"
Write-Host "Update scenario statuses in: $ManualResultsPath"
Write-Host "Optional runtime log override env var: MORPHSTAFF_BEDROCK_LOG_PATHS"
Write-Host "Then continue to finalize runtime + gate checks."

if (-not $NonInteractive) {
  [void](Read-Host "After completing in-game tests and updating manual results, press Enter to continue")
}

& $runtimeScript -Mode End -RootDir $RootDir -RunDir $RunDir -LogPathOverride $LogPathOverride -NoExit | Out-Null
& $gateScript -RunDir $RunDir -ManualResultsPath $ManualResultsPath
$gateExit = $LASTEXITCODE
if ($null -eq $gateExit) {
  $gateExit = 0
}
exit $gateExit
