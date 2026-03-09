param(
  [string]$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path,
  [string]$RunDir,
  [string]$ManualResultsPath,
  [string]$Tester = $env:USERNAME,
  [string]$MinecraftVersion,
  [string]$WorldName
)

$ErrorActionPreference = "Stop"

if (-not $RunDir -and -not $ManualResultsPath) {
  throw "Provide either -RunDir or -ManualResultsPath."
}

if (-not $ManualResultsPath) {
  $ManualResultsPath = Join-Path $RunDir "manual-results.json"
}

$templatePath = Join-Path $RootDir "tests/bedrock-manual-results.template.json"
if (-not (Test-Path -Path $ManualResultsPath -PathType Leaf)) {
  if (-not (Test-Path -Path $templatePath -PathType Leaf)) {
    throw "Manual results template not found: $templatePath"
  }

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ManualResultsPath) | Out-Null
  Copy-Item -Path $templatePath -Destination $ManualResultsPath -Force
}

$data = Get-Content -Raw -Path $ManualResultsPath | ConvertFrom-Json

if ($Tester -and [string]::IsNullOrWhiteSpace([string]$data.tester)) {
  $data.tester = $Tester
}
if ($MinecraftVersion -and [string]::IsNullOrWhiteSpace([string]$data.minecraftVersion)) {
  $data.minecraftVersion = $MinecraftVersion
}
if ($WorldName -and [string]::IsNullOrWhiteSpace([string]$data.worldName)) {
  $data.worldName = $WorldName
}
if ([string]::IsNullOrWhiteSpace([string]$data.executionDate)) {
  $data.executionDate = (Get-Date).ToString("yyyy-MM-dd")
}

$data | ConvertTo-Json -Depth 100 | Set-Content -Path $ManualResultsPath -Encoding UTF8

Write-Host "Manual results initialized: $ManualResultsPath"
Write-Host "tester=$($data.tester) minecraftVersion=$($data.minecraftVersion) worldName=$($data.worldName) executionDate=$($data.executionDate)"
