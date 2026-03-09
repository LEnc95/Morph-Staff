param(
  [ValidateSet("Begin", "End")]
  [string]$Mode,
  [string]$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path,
  [string]$RunDir,
  [switch]$NoExit
)

$ErrorActionPreference = "Stop"

if (-not $RunDir) {
  throw "RunDir is required."
}

New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

$snapshotPath = Join-Path $RunDir "runtime-snapshot.json"
$runtimeJsonPath = Join-Path $RunDir "runtime-results.json"
$runtimeReportPath = Join-Path $RunDir "runtime-report.md"

function Get-BedrockLogFiles {
  $candidateDirs = @(
    (Join-Path $env:LOCALAPPDATA "Packages/Microsoft.MinecraftUWP_8wekyb3d8bbwe/LocalState/logs"),
    (Join-Path $env:LOCALAPPDATA "Packages/Microsoft.MinecraftUWP_8wekyb3d8bbwe/LocalState/games/com.mojang/logs"),
    (Join-Path $env:LOCALAPPDATA "Packages/Microsoft.MinecraftWindowsBeta_8wekyb3d8bbwe/LocalState/logs"),
    (Join-Path $env:LOCALAPPDATA "Packages/Microsoft.MinecraftWindowsBeta_8wekyb3d8bbwe/LocalState/games/com.mojang/logs")
  )

  $files = @()
  foreach ($dir in $candidateDirs) {
    if (-not (Test-Path -Path $dir -PathType Container)) {
      continue
    }

    $files += Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue |
      Where-Object {
        $_.Extension -in @(".log", ".txt") -or $_.Name -match '(?i)content|latest|debug|script'
      }
  }

  return $files | Sort-Object FullName -Unique
}

function Get-AppendedText {
  param(
    [string]$Path,
    [long]$StartOffset
  )

  $file = Get-Item -Path $Path -ErrorAction Stop
  if ($StartOffset -lt 0) { $StartOffset = 0 }
  if ($StartOffset -gt $file.Length) { $StartOffset = 0 }

  $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
  try {
    $stream.Seek($StartOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
    $reader = New-Object System.IO.StreamReader($stream)
    return $reader.ReadToEnd()
  } finally {
    $stream.Dispose()
  }
}

function Build-InitialRuntimeResult {
  [ordered]@{
    status = "PENDING"
    blockers = @()
    warnings = @()
    inspectedFiles = @()
    matchedLines = @()
    generatedAt = (Get-Date).ToString("o")
    runDir = $RunDir
  }
}

if ($Mode -eq "Begin") {
  $files = Get-BedrockLogFiles

  $snapshot = [ordered]@{
    capturedAt = (Get-Date).ToString("o")
    files = @{}
  }

  foreach ($file in $files) {
    $snapshot.files[$file.FullName] = [ordered]@{
      length = [int64]$file.Length
      lastWriteTimeUtc = $file.LastWriteTimeUtc.ToString("o")
    }
  }

  $snapshot | ConvertTo-Json -Depth 100 | Set-Content -Path $snapshotPath -Encoding UTF8

  $result = Build-InitialRuntimeResult
  $result.inspectedFiles = @($files.FullName)
  $result | ConvertTo-Json -Depth 100 | Set-Content -Path $runtimeJsonPath -Encoding UTF8

  $beginLines = @(
    "# Runtime Report",
    "",
    "- Status: **PENDING**",
    "- Snapshot captured: $($snapshot.capturedAt)",
    "- Log files detected: $($files.Count)",
    "",
    "Run Bedrock + execute manual test matrix, then run collect step in End mode."
  )
  $beginLines -join [Environment]::NewLine | Set-Content -Path $runtimeReportPath -Encoding UTF8

  Write-Host "Runtime snapshot created at $snapshotPath"
  if (-not $NoExit) { exit 0 }
  return
}

if (-not (Test-Path -Path $snapshotPath -PathType Leaf)) {
  throw "Missing runtime snapshot. Run with -Mode Begin first."
}

$snapshot = Get-Content -Raw -Path $snapshotPath | ConvertFrom-Json
$files = Get-BedrockLogFiles

$result = Build-InitialRuntimeResult
$result.inspectedFiles = @($files.FullName)

$blockerRegex = [regex]'(?i)(ReferenceError|TypeError|SyntaxError|RangeError|Exception|Unhandled|Failed to|Cannot find|No such|stack trace|script runtime error|pack load failed|module failed)'
$warningRegex = [regex]'(?i)(warning|warn|deprecated|fallback)'
$packRegex = [regex]'(?i)(morphstaff|wooden_staff|scripts/main\.js|@minecraft/server|behavior[_\s-]?pack|proxy|invisibility)'

$matched = New-Object System.Collections.Generic.List[string]

foreach ($file in $files) {
  $path = $file.FullName
  $startOffset = 0

  if ($snapshot.files.PSObject.Properties.Name -contains $path) {
    $startOffset = [int64]$snapshot.files.$path.length
  }

  $text = ""
  try {
    $text = Get-AppendedText -Path $path -StartOffset $startOffset
  } catch {
    $result.warnings += "Could not read log file ${path}: $($_.Exception.Message)"
    continue
  }

  if ([string]::IsNullOrWhiteSpace($text)) {
    continue
  }

  $lines = $text -split "`r?`n"
  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }

    $isRelevant = $packRegex.IsMatch($line) -or $blockerRegex.IsMatch($line)
    if (-not $isRelevant) {
      continue
    }

    $normalized = "[$([System.IO.Path]::GetFileName($path))] $line"
    $matched.Add($normalized)

    if ($blockerRegex.IsMatch($line)) {
      $result.blockers += $normalized
    } elseif ($warningRegex.IsMatch($line)) {
      $result.warnings += $normalized
    }
  }
}

if ($files.Count -eq 0) {
  $result.blockers += "No Bedrock log files were discovered under expected LocalState paths."
}

$result.matchedLines = @($matched | Select-Object -First 200)
$result.generatedAt = (Get-Date).ToString("o")
$result.status = if ($result.blockers.Count -eq 0) { "PASS" } else { "FAIL" }

$result | ConvertTo-Json -Depth 100 | Set-Content -Path $runtimeJsonPath -Encoding UTF8

$report = @()
$report += "# Runtime Report"
$report += ""
$report += "- Status: **$($result.status)**"
$report += "- Generated: $($result.generatedAt)"
$report += "- Inspected log files: $($result.inspectedFiles.Count)"
$report += ""
$report += "## Blockers"
if ($result.blockers.Count -eq 0) {
  $report += "- None"
} else {
  foreach ($b in $result.blockers) {
    $report += "- $b"
  }
}
$report += ""
$report += "## Warnings"
if ($result.warnings.Count -eq 0) {
  $report += "- None"
} else {
  foreach ($w in $result.warnings) {
    $report += "- $w"
  }
}
$report += ""
$report += "## Matched Log Lines (Top 200)"
if ($result.matchedLines.Count -eq 0) {
  $report += "- None"
} else {
  foreach ($line in $result.matchedLines) {
    $report += "- $line"
  }
}

$report -join [Environment]::NewLine | Set-Content -Path $runtimeReportPath -Encoding UTF8

Write-Host "Runtime report: $runtimeReportPath"

if (-not $NoExit) {
  if ($result.status -eq "FAIL") {
    exit 1
  }
  exit 0
}
