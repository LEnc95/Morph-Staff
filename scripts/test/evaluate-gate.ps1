param(
  [string]$RunDir,
  [string]$ManualResultsPath,
  [string]$PreflightResultsPath,
  [string]$RuntimeResultsPath,
  [switch]$NoExit
)

$ErrorActionPreference = "Stop"

if (-not $RunDir) {
  throw "RunDir is required."
}

if (-not $PreflightResultsPath) {
  $PreflightResultsPath = Join-Path $RunDir "preflight-results.json"
}
if (-not $RuntimeResultsPath) {
  $RuntimeResultsPath = Join-Path $RunDir "runtime-results.json"
}
if (-not $ManualResultsPath) {
  $ManualResultsPath = Join-Path $RunDir "manual-results.json"
}

$summaryPath = Join-Path $RunDir "gate-summary.md"
$summaryJsonPath = Join-Path $RunDir "gate-summary.json"

function Read-JsonIfExists {
  param([string]$Path)
  if (-not (Test-Path -Path $Path -PathType Leaf)) {
    return $null
  }
  return (Get-Content -Raw -Path $Path | ConvertFrom-Json)
}

function IsBlank {
  param([string]$Value)
  return [string]::IsNullOrWhiteSpace($Value)
}

$blockers = @()
$warnings = @()

$preflight = Read-JsonIfExists -Path $PreflightResultsPath
if ($null -eq $preflight) {
  $blockers += "Missing preflight results: $PreflightResultsPath"
} else {
  foreach ($b in @($preflight.blockers)) { $blockers += "[preflight] $b" }
  foreach ($w in @($preflight.warnings)) { $warnings += "[preflight] $w" }
}

$runtime = Read-JsonIfExists -Path $RuntimeResultsPath
if ($null -eq $runtime) {
  $blockers += "Missing runtime results: $RuntimeResultsPath"
} else {
  foreach ($b in @($runtime.blockers)) { $blockers += "[runtime] $b" }
  foreach ($w in @($runtime.warnings)) { $warnings += "[runtime] $w" }
}

$requiredScenarioIds = @(
  "S01","S02","S03","S04","S05","S06","S07","S08","S09","S10","S11","S12"
)

$manual = Read-JsonIfExists -Path $ManualResultsPath
if ($null -eq $manual) {
  $blockers += "Missing manual results file: $ManualResultsPath"
} else {
  if (IsBlank -Value ([string]$manual.tester)) {
    $blockers += "[manual] tester is required in manual results."
  }
  if (IsBlank -Value ([string]$manual.minecraftVersion)) {
    $blockers += "[manual] minecraftVersion is required in manual results."
  }
  if (IsBlank -Value ([string]$manual.worldName)) {
    $blockers += "[manual] worldName is required in manual results."
  }

  $scenarioById = @{}
  foreach ($scenario in @($manual.scenarios)) {
    if ($scenario.id) {
      $scenarioById[[string]$scenario.id] = $scenario
    }
  }

  foreach ($id in $requiredScenarioIds) {
    if (-not $scenarioById.ContainsKey($id)) {
      $blockers += "[manual] Missing required scenario result: $id"
      continue
    }

    $status = ([string]$scenarioById[$id].status).ToUpperInvariant()
    if ($status -ne "PASS") {
      $name = [string]$scenarioById[$id].name
      $notes = [string]$scenarioById[$id].notes
      $blockers += "[manual] $id ($name) is $status. Notes: $notes"
    }

    if ($status -eq "PASS" -and $id -in @("S10", "S11", "S12")) {
      $notes = [string]$scenarioById[$id].notes
      if (IsBlank -Value $notes) {
        $blockers += "[manual] $id requires notes when PASS (document observations/evidence)."
      }
    }
  }
}

$status = if ($blockers.Count -eq 0) { "PASS" } else { "FAIL" }

$summary = [ordered]@{
  status = $status
  generatedAt = (Get-Date).ToString("o")
  runDir = $RunDir
  blockers = $blockers
  warnings = $warnings
  requiredManualScenarioIds = $requiredScenarioIds
  inputs = [ordered]@{
    preflight = $PreflightResultsPath
    runtime = $RuntimeResultsPath
    manual = $ManualResultsPath
  }
}

$summary | ConvertTo-Json -Depth 100 | Set-Content -Path $summaryJsonPath -Encoding UTF8

$lines = @()
$lines += "# Gate Summary"
$lines += ""
$lines += "- Status: **$status**"
$lines += "- Generated: $($summary.generatedAt)"
$lines += "- Run dir: $RunDir"
$lines += ""
$lines += "## Inputs"
$lines += "- Preflight: $PreflightResultsPath"
$lines += "- Runtime: $RuntimeResultsPath"
$lines += "- Manual: $ManualResultsPath"
$lines += ""
$lines += "## Blockers"
if ($blockers.Count -eq 0) {
  $lines += "- None"
} else {
  foreach ($b in $blockers) {
    $lines += "- $b"
  }
}
$lines += ""
$lines += "## Warnings"
if ($warnings.Count -eq 0) {
  $lines += "- None"
} else {
  foreach ($w in $warnings) {
    $lines += "- $w"
  }
}

$lines -join [Environment]::NewLine | Set-Content -Path $summaryPath -Encoding UTF8
Write-Host "Gate summary: $summaryPath"

if (-not $NoExit) {
  if ($status -eq "FAIL") { exit 1 }
  exit 0
}

$summary
