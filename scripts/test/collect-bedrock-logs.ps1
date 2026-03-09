param(
  [ValidateSet("Begin", "End")]
  [string]$Mode,
  [string]$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path,
  [string]$RunDir,
  [string[]]$LogPathOverride,
  [string]$LogPathOverrideEnvVar = "MORPHSTAFF_BEDROCK_LOG_PATHS",
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

function Split-PathList {
  param([string]$Raw)

  if ([string]::IsNullOrWhiteSpace($Raw)) {
    return @()
  }

  return @($Raw.Split(";") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Resolve-OverridePaths {
  param(
    [string[]]$CliOverrides,
    [string]$EnvVarName
  )

  $entries = @()
  if ($CliOverrides) {
    $entries += @($CliOverrides | Where-Object { $_ -and $_.Trim() })
  }

  if ($EnvVarName) {
    $raw = [Environment]::GetEnvironmentVariable($EnvVarName)
    $entries += @(Split-PathList -Raw $raw)
  }

  $resolvedFiles = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
  $resolvedDirs = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
  $missing = New-Object System.Collections.Generic.List[string]

  foreach ($entry in $entries) {
    $trimmed = $entry.Trim()
    if (-not $trimmed) {
      continue
    }

    if (-not (Test-Path -Path $trimmed)) {
      $missing.Add($trimmed)
      continue
    }

    try {
      $item = Get-Item -LiteralPath $trimmed -ErrorAction Stop
      if ($item.PSIsContainer) {
        [void]$resolvedDirs.Add($item.FullName)
      } else {
        [void]$resolvedFiles.Add($item.FullName)
      }
    } catch {
      $missing.Add($trimmed)
    }
  }

  return [ordered]@{
    files = @($resolvedFiles)
    dirs = @($resolvedDirs)
    missing = @($missing)
  }
}

function Get-DefaultLogDirectories {
  $localStateRoots = @(
    (Join-Path $env:LOCALAPPDATA "Packages/Microsoft.MinecraftUWP_8wekyb3d8bbwe/LocalState"),
    (Join-Path $env:LOCALAPPDATA "Packages/Microsoft.MinecraftWindowsBeta_8wekyb3d8bbwe/LocalState")
  )

  $candidates = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)

  foreach ($root in $localStateRoots) {
    $dirOptions = @(
      (Join-Path $root "logs"),
      (Join-Path $root "games/com.mojang/logs"),
      (Join-Path $root "games/com.mojang/minecraftpe"),
      (Join-Path $root "games/com.mojang/minecraftpe/logs")
    )

    foreach ($dir in $dirOptions) {
      if (Test-Path -Path $dir -PathType Container) {
        [void]$candidates.Add((Resolve-Path $dir).Path)
      }
    }
  }

  return @($candidates)
}

function Get-BedrockLogDiscovery {
  param(
    [string[]]$CliOverrides,
    [string]$EnvVarName
  )

  $override = Resolve-OverridePaths -CliOverrides $CliOverrides -EnvVarName $EnvVarName
  $defaultDirs = @(Get-DefaultLogDirectories)

  $dirSet = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($dir in $defaultDirs) { [void]$dirSet.Add($dir) }
  foreach ($dir in $override.dirs) { [void]$dirSet.Add($dir) }
  $inspectedDirs = @($dirSet)

  $fileSet = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
  $notes = New-Object System.Collections.Generic.List[string]

  foreach ($filePath in $override.files) {
    [void]$fileSet.Add($filePath)
  }

  $preferredPattern = '(?i)(content|latest|debug|script|nonasserterrorlog|errorlog|output_log)'

  foreach ($dir in $inspectedDirs) {
    $dirFiles = @(Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue)
    if ($dirFiles.Count -eq 0) {
      continue
    }

    $preferred = @($dirFiles | Where-Object {
      $_.Extension -in @(".log", ".txt") -or $_.Name -match $preferredPattern
    })

    if ($preferred.Count -gt 0) {
      foreach ($f in $preferred) {
        [void]$fileSet.Add($f.FullName)
      }
      continue
    }
  }

  if ($fileSet.Count -eq 0 -and $inspectedDirs.Count -gt 0) {
    $fallbackCandidates = @()
    foreach ($dir in $inspectedDirs) {
      $fallbackCandidates += @(Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue)
    }

    if ($fallbackCandidates.Count -gt 0) {
      $latest = $fallbackCandidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
      [void]$fileSet.Add($latest.FullName)
      $notes.Add("Using latest-file fallback: $($latest.FullName)")
    }
  }

  return [ordered]@{
    files = @($fileSet | Sort-Object)
    inspectedDirectories = $inspectedDirs | Sort-Object
    usedOverrides = @($override.files + $override.dirs | Sort-Object)
    missingOverrides = @($override.missing | Sort-Object)
    discoveryNotes = @($notes)
  }
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
    inspectedDirectories = @()
    inspectedFiles = @()
    usedOverrides = @()
    missingOverrides = @()
    discoveryNotes = @()
    matchedLines = @()
    generatedAt = (Get-Date).ToString("o")
    runDir = $RunDir
  }
}

$discovery = Get-BedrockLogDiscovery -CliOverrides $LogPathOverride -EnvVarName $LogPathOverrideEnvVar

if ($Mode -eq "Begin") {
  $snapshot = [ordered]@{
    capturedAt = (Get-Date).ToString("o")
    files = @{}
    inspectedDirectories = $discovery.inspectedDirectories
    usedOverrides = $discovery.usedOverrides
    missingOverrides = $discovery.missingOverrides
    discoveryNotes = $discovery.discoveryNotes
  }

  foreach ($filePath in $discovery.files) {
    try {
      $file = Get-Item -LiteralPath $filePath -ErrorAction Stop
      $snapshot.files[$file.FullName] = [ordered]@{
        length = [int64]$file.Length
        lastWriteTimeUtc = $file.LastWriteTimeUtc.ToString("o")
      }
    } catch {
      # Best-effort: file may rotate between discovery and snapshot.
    }
  }

  $snapshot | ConvertTo-Json -Depth 100 | Set-Content -Path $snapshotPath -Encoding UTF8

  $result = Build-InitialRuntimeResult
  $result.inspectedDirectories = $discovery.inspectedDirectories
  $result.inspectedFiles = @($snapshot.files.Keys)
  $result.usedOverrides = $discovery.usedOverrides
  $result.missingOverrides = $discovery.missingOverrides
  $result.discoveryNotes = $discovery.discoveryNotes
  $result | ConvertTo-Json -Depth 100 | Set-Content -Path $runtimeJsonPath -Encoding UTF8

  $beginLines = @(
    "# Runtime Report",
    "",
    "- Status: **PENDING**",
    "- Snapshot captured: $($snapshot.capturedAt)",
    "- Log directories inspected: $($result.inspectedDirectories.Count)",
    "- Log files detected: $($result.inspectedFiles.Count)",
    "",
    "Run Bedrock + execute manual test matrix, then run collect step in End mode."
  )

  if ($result.missingOverrides.Count -gt 0) {
    $beginLines += ""
    $beginLines += "Override paths not found:"
    foreach ($m in $result.missingOverrides) {
      $beginLines += "- $m"
    }
  }

  if ($result.discoveryNotes.Count -gt 0) {
    $beginLines += ""
    $beginLines += "Discovery notes:"
    foreach ($n in $result.discoveryNotes) {
      $beginLines += "- $n"
    }
  }

  $beginLines -join [Environment]::NewLine | Set-Content -Path $runtimeReportPath -Encoding UTF8

  Write-Host "Runtime snapshot created at $snapshotPath"
  if (-not $NoExit) { exit 0 }
  return
}

if (-not (Test-Path -Path $snapshotPath -PathType Leaf)) {
  throw "Missing runtime snapshot. Run with -Mode Begin first."
}

$snapshot = Get-Content -Raw -Path $snapshotPath | ConvertFrom-Json

$result = Build-InitialRuntimeResult
$result.inspectedDirectories = $discovery.inspectedDirectories
$result.inspectedFiles = $discovery.files
$result.usedOverrides = $discovery.usedOverrides
$result.missingOverrides = $discovery.missingOverrides
$result.discoveryNotes = $discovery.discoveryNotes

$blockerRegex = [regex]'(?i)(ReferenceError|TypeError|SyntaxError|RangeError|Exception|Unhandled|Failed to|Cannot find|No such|stack trace|script runtime error|pack load failed|module failed)'
$warningRegex = [regex]'(?i)(warning|warn|deprecated|fallback)'
$packRegex = [regex]'(?i)(morphstaff|wooden_staff|scripts/main\.js|@minecraft/server|behavior[_\s-]?pack|proxy|invisibility)'

$matched = New-Object System.Collections.Generic.List[string]
$bytesAppended = [int64]0

foreach ($path in $discovery.files) {
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

  $bytesAppended += [Text.Encoding]::UTF8.GetByteCount($text)

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

if ($discovery.files.Count -eq 0) {
  $result.blockers += "No Bedrock log files were discovered. Provide -LogPathOverride or set $LogPathOverrideEnvVar to a known log file/directory path."
}

if ($result.missingOverrides.Count -gt 0) {
  foreach ($m in $result.missingOverrides) {
    $result.warnings += "Override path not found: $m"
  }
}

if ($bytesAppended -eq 0 -and $discovery.files.Count -gt 0) {
  $result.warnings += "No new log content was detected since snapshot; run tests in-game between Begin and End steps."
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
$report += "- Inspected directories: $($result.inspectedDirectories.Count)"
$report += "- Inspected log files: $($result.inspectedFiles.Count)"
$report += "- New bytes scanned: $bytesAppended"
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
$report += "## Discovery Notes"
if ($result.discoveryNotes.Count -eq 0) {
  $report += "- None"
} else {
  foreach ($n in $result.discoveryNotes) {
    $report += "- $n"
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
