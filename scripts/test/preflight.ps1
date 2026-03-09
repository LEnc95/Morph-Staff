param(
  [string]$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path,
  [string]$RunDir,
  [switch]$NoExit
)

$ErrorActionPreference = "Stop"

if (-not $RunDir) {
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $RunDir = Join-Path $RootDir "artifacts/test-runs/$timestamp"
}

New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

function New-Result {
  [ordered]@{
    status = "PASS"
    blockers = @()
    warnings = @()
    checks = @()
    generatedAt = (Get-Date).ToString("o")
    rootDir = $RootDir
    runDir = $RunDir
  }
}

function Add-Check {
  param(
    $Result,
    [string]$Name,
    [bool]$Passed,
    [string]$Details,
    [string]$Severity = "blocker"
  )

  $entry = [ordered]@{
    name = $Name
    passed = $Passed
    severity = $Severity
    details = $Details
  }
  $Result.checks += $entry

  if (-not $Passed) {
    if ($Severity -eq "warning") {
      $Result.warnings += $Details
    } else {
      $Result.blockers += $Details
    }
  }
}

function Select-Detail {
  param(
    [bool]$Condition,
    [string]$TrueText,
    [string]$FalseText
  )

  if ($Condition) { return $TrueText }
  return $FalseText
}

function Read-JsonFile {
  param([string]$Path)

  $raw = Get-Content -Raw -Path $Path
  return $raw | ConvertFrom-Json
}

function Test-JsonFile {
  param(
    [string]$Path,
    $Result,
    [string]$Label
  )

  try {
    [void](Read-JsonFile -Path $Path)
    Add-Check -Result $Result -Name "JSON: $Label" -Passed $true -Details "$Label parsed successfully."
  } catch {
    Add-Check -Result $Result -Name "JSON: $Label" -Passed $false -Details "$Label failed JSON parse: $($_.Exception.Message)"
  }
}

function Get-LocalImports {
  param([string]$Content)

  $imports = @()
  $patternFrom = [regex]'(?m)^\s*import\s+[^;]*?from\s+["'']([^"'']+)["'']\s*;?'
  $patternSideEffect = [regex]'(?m)^\s*import\s+["'']([^"'']+)["'']\s*;?'

  foreach ($m in $patternFrom.Matches($Content)) {
    $imports += $m.Groups[1].Value
  }
  foreach ($m in $patternSideEffect.Matches($Content)) {
    $imports += $m.Groups[1].Value
  }

  return $imports | Select-Object -Unique
}

function Resolve-ImportPath {
  param(
    [string]$FromFile,
    [string]$Specifier
  )

  if (-not ($Specifier.StartsWith("./") -or $Specifier.StartsWith("../"))) {
    return $null
  }

  $baseDir = Split-Path -Parent $FromFile
  $candidate = Join-Path $baseDir $Specifier

  if ([System.IO.Path]::GetExtension($candidate)) {
    if (Test-Path -Path $candidate -PathType Leaf) {
      return (Resolve-Path $candidate).Path
    }
    return $null
  }

  $jsCandidate = "$candidate.js"
  if (Test-Path -Path $jsCandidate -PathType Leaf) {
    return (Resolve-Path $jsCandidate).Path
  }

  $indexCandidate = Join-Path $candidate "index.js"
  if (Test-Path -Path $indexCandidate -PathType Leaf) {
    return (Resolve-Path $indexCandidate).Path
  }

  return $null
}

function Test-ImportGraph {
  param(
    [string]$EntryFile,
    $Result
  )

  $visited = New-Object System.Collections.Generic.HashSet[string]
  $toVisit = New-Object System.Collections.Generic.Stack[string]
  $missing = @()

  $toVisit.Push((Resolve-Path $EntryFile).Path)

  while ($toVisit.Count -gt 0) {
    $file = $toVisit.Pop()
    if (-not $visited.Add($file)) {
      continue
    }

    $content = Get-Content -Raw -Path $file
    $imports = Get-LocalImports -Content $content

    foreach ($specifier in $imports) {
      if (-not ($specifier.StartsWith("./") -or $specifier.StartsWith("../"))) {
        continue
      }

      $resolved = Resolve-ImportPath -FromFile $file -Specifier $specifier
      if (-not $resolved) {
        $missing += "Unresolved import '$specifier' from $file"
        continue
      }
      if (-not $visited.Contains($resolved)) {
        $toVisit.Push($resolved)
      }
    }
  }

  if ($missing.Count -eq 0) {
    Add-Check -Result $Result -Name "Script import graph" -Passed $true -Details "All local imports reachable from scripts/main.js resolve."
  } else {
    $detail = ($missing | Select-Object -Unique) -join " | "
    Add-Check -Result $Result -Name "Script import graph" -Passed $false -Details $detail
  }
}

$result = New-Result

$manifestPath = Join-Path $RootDir "manifest.json"
$itemPath = Join-Path $RootDir "items/wooden_staff.item.json"
$recipePath = Join-Path $RootDir "recipes/wooden_staff.recipe.json"
$configPath = Join-Path $RootDir "scripts/config.js"
$readmePath = Join-Path $RootDir "README.md"
$entryScriptPath = Join-Path $RootDir "scripts/main.js"

$requiredFiles = @($manifestPath, $itemPath, $recipePath, $configPath, $readmePath, $entryScriptPath)
foreach ($file in $requiredFiles) {
  $exists = Test-Path -Path $file -PathType Leaf
  Add-Check -Result $result -Name "Required file: $file" -Passed $exists -Details (Select-Detail -Condition $exists -TrueText "$file exists." -FalseText "$file is missing.")
}

if ($result.blockers.Count -eq 0) {
  Test-JsonFile -Path $manifestPath -Result $result -Label "manifest.json"
  Test-JsonFile -Path $itemPath -Result $result -Label "items/wooden_staff.item.json"
  Test-JsonFile -Path $recipePath -Result $result -Label "recipes/wooden_staff.recipe.json"

  $manifest = Read-JsonFile -Path $manifestPath
  $itemJson = Read-JsonFile -Path $itemPath
  $recipeJson = Read-JsonFile -Path $recipePath

  $headerVersion = @($manifest.header.version)
  $moduleVersions = @($manifest.modules | ForEach-Object { @($_.version) -join "." })
  $headerVersionKey = $headerVersion -join "."
  $moduleVersionAligned = ($moduleVersions | Where-Object { $_ -ne $headerVersionKey }).Count -eq 0
  Add-Check -Result $result -Name "Manifest version alignment" -Passed $moduleVersionAligned -Details (Select-Detail -Condition $moduleVersionAligned -TrueText "Header and module versions align at $headerVersionKey." -FalseText "Header version $headerVersionKey does not align with module versions: $($moduleVersions -join ', ').")

  $uuidRegex = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  $uuids = @($manifest.header.uuid) + @($manifest.modules | ForEach-Object { $_.uuid })
  $invalidUuids = @($uuids | Where-Object { -not ($_ -match $uuidRegex) })
  Add-Check -Result $result -Name "Manifest UUID format" -Passed ($invalidUuids.Count -eq 0) -Details (Select-Detail -Condition ($invalidUuids.Count -eq 0) -TrueText "All manifest UUIDs are valid." -FalseText "Invalid UUIDs: $($invalidUuids -join ', ').")

  $scriptModule = $manifest.modules | Where-Object { $_.type -eq "script" } | Select-Object -First 1
  if ($null -eq $scriptModule) {
    Add-Check -Result $result -Name "Script module present" -Passed $false -Details "manifest.json does not define a script module."
  } else {
    $entry = [string]$scriptModule.entry
    $entryExists = $entry -and (Test-Path -Path (Join-Path $RootDir $entry) -PathType Leaf)
    Add-Check -Result $result -Name "Script entry exists" -Passed $entryExists -Details (Select-Detail -Condition $entryExists -TrueText "Script entry '$entry' exists." -FalseText "Script entry '$entry' does not exist.")
  }

  $itemId = [string]$itemJson.'minecraft:item'.description.identifier
  $recipeId = [string]$recipeJson.'minecraft:recipe_shapeless'.result.item
  $configRaw = Get-Content -Raw -Path $configPath
  $configMatch = [regex]::Match($configRaw, 'staffItemId\s*:\s*"([^"]+)"')
  $configId = if ($configMatch.Success) { $configMatch.Groups[1].Value } else { "" }

  Add-Check -Result $result -Name "Item/Recipe ID match" -Passed ($itemId -eq $recipeId -and $itemId -ne "") -Details (Select-Detail -Condition ($itemId -eq $recipeId -and $itemId -ne "") -TrueText "Item and recipe both use '$itemId'." -FalseText "Item id '$itemId' and recipe id '$recipeId' do not match.")
  Add-Check -Result $result -Name "Config staff item ID match" -Passed ($configId -eq $itemId -and $configId -ne "") -Details (Select-Detail -Condition ($configId -eq $itemId -and $configId -ne "") -TrueText "config.js staffItemId matches '$itemId'." -FalseText "config.js staffItemId '$configId' does not match item id '$itemId'.")

  Test-ImportGraph -EntryFile $entryScriptPath -Result $result

  $dependency = $manifest.dependencies | Where-Object { $_.module_name -eq "@minecraft/server" } | Select-Object -First 1
  $manifestApiVersion = if ($dependency) { [string]$dependency.version } else { "" }
  Add-Check -Result $result -Name "Manifest API dependency present" -Passed ([string]::IsNullOrWhiteSpace($manifestApiVersion) -eq $false) -Details (Select-Detail -Condition ([string]::IsNullOrWhiteSpace($manifestApiVersion) -eq $false) -TrueText "manifest.json pins @minecraft/server $manifestApiVersion." -FalseText "manifest.json is missing @minecraft/server dependency.")

  $readmeRaw = Get-Content -Raw -Path $readmePath
  $readmeVersionMatch = [regex]::Match($readmeRaw, '@minecraft/server\s*`?:\s*`?([0-9]+\.[0-9]+\.[0-9]+)')
  if (-not $readmeVersionMatch.Success) {
    Add-Check -Result $result -Name "README API version declaration" -Passed $false -Details "README.md does not declare @minecraft/server version in expected format."
  } else {
    $readmeVersion = $readmeVersionMatch.Groups[1].Value
    $aligned = ($manifestApiVersion -eq $readmeVersion)
    Add-Check -Result $result -Name "README/Manifest API version alignment" -Passed $aligned -Details (Select-Detail -Condition $aligned -TrueText "README and manifest both declare @minecraft/server $manifestApiVersion." -FalseText "README declares @minecraft/server $readmeVersion but manifest pins $manifestApiVersion.")
  }
}

if ($result.blockers.Count -gt 0) {
  $result.status = "FAIL"
}

$preflightJsonPath = Join-Path $RunDir "preflight-results.json"
$preflightMdPath = Join-Path $RunDir "preflight-report.md"

$result | ConvertTo-Json -Depth 100 | Set-Content -Path $preflightJsonPath -Encoding UTF8

$lines = @()
$lines += "# Preflight Report"
$lines += ""
$lines += "- Status: **$($result.status)**"
$lines += "- Generated: $($result.generatedAt)"
$lines += "- Root: $($result.rootDir)"
$lines += ""
$lines += "## Checks"
foreach ($check in $result.checks) {
  $icon = if ($check.passed) { "PASS" } else { "FAIL" }
  $lines += "- [$icon] **$($check.name)**: $($check.details)"
}
$lines += ""
$lines += "## Blockers"
if ($result.blockers.Count -eq 0) {
  $lines += "- None"
} else {
  foreach ($b in $result.blockers) {
    $lines += "- $b"
  }
}
$lines += ""
$lines += "## Warnings"
if ($result.warnings.Count -eq 0) {
  $lines += "- None"
} else {
  foreach ($w in $result.warnings) {
    $lines += "- $w"
  }
}

$lines -join [Environment]::NewLine | Set-Content -Path $preflightMdPath -Encoding UTF8

Write-Host "Preflight report: $preflightMdPath"

if (-not $NoExit) {
  if ($result.status -eq "FAIL") {
    exit 1
  }
  exit 0
}

$result
