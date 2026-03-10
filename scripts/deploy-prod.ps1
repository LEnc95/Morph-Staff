param(
  [string]$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$BehaviorPackName = "MorphStaff_BP",
  [string]$ResourcePackName = "MorphStaff_RP",
  [Alias("PreviewBuild")]
  [switch]$PreviewOnly,
  [switch]$StableOnly,
  [switch]$SkipDevelopment
)

$ErrorActionPreference = "Stop"

$rpSource = Join-Path $RootDir "MorphStaff_RP"
if (-not (Test-Path -Path $rpSource -PathType Container)) {
  throw "Missing RP source folder: $rpSource"
}

$bpFolders = @("items", "recipes", "scripts", "entities")
$bpFiles = @("manifest.json", "pack_icon.png", "README.md")

if ($PreviewOnly -and $StableOnly) {
  throw "Choose only one target switch: -PreviewOnly or -StableOnly."
}

$targets = @()
if ($PreviewOnly) {
  $targets += @{ Label = "Preview"; Family = "Microsoft.MinecraftWindowsBeta_8wekyb3d8bbwe" }
} elseif ($StableOnly) {
  $targets += @{ Label = "Stable"; Family = "Microsoft.MinecraftUWP_8wekyb3d8bbwe" }
} else {
  $targets += @{ Label = "Stable"; Family = "Microsoft.MinecraftUWP_8wekyb3d8bbwe" }
  $targets += @{ Label = "Preview"; Family = "Microsoft.MinecraftWindowsBeta_8wekyb3d8bbwe" }
}

function Copy-BehaviorPackContents {
  param([string]$Destination)

  foreach ($folder in $bpFolders) {
    $src = Join-Path $RootDir $folder
    if (Test-Path -Path $src -PathType Container) {
      Copy-Item -Path $src -Destination $Destination -Recurse -Force
    }
  }

  foreach ($file in $bpFiles) {
    $src = Join-Path $RootDir $file
    if (Test-Path -Path $src -PathType Leaf) {
      Copy-Item -Path $src -Destination $Destination -Force
    }
  }
}

function Deploy-PackPair {
  param(
    [string]$Label,
    [string]$MojangRoot,
    [string]$BehaviorFolderName,
    [string]$ResourceFolderName,
    [string]$Flavor
  )

  $bpDest = Join-Path $MojangRoot "$BehaviorFolderName/$BehaviorPackName"
  $rpDest = Join-Path $MojangRoot "$ResourceFolderName/$ResourcePackName"

  if (Test-Path -Path $bpDest) {
    Remove-Item -Path $bpDest -Recurse -Force
  }
  if (Test-Path -Path $rpDest) {
    Remove-Item -Path $rpDest -Recurse -Force
  }

  New-Item -ItemType Directory -Force -Path $bpDest | Out-Null
  New-Item -ItemType Directory -Force -Path $rpDest | Out-Null

  Copy-BehaviorPackContents -Destination $bpDest
  Copy-Item -Path (Join-Path $rpSource "*") -Destination $rpDest -Recurse -Force

  Write-Host "[$Label][$Flavor] Behavior pack deployed to: $bpDest"
  Write-Host "[$Label][$Flavor] Resource pack deployed to: $rpDest"
}

function Deploy-ToTarget {
  param(
    [string]$Label,
    [string]$Family
  )

  $packageRoot = Join-Path $env:LOCALAPPDATA "Packages/$Family"
  if (-not (Test-Path -Path $packageRoot -PathType Container)) {
    Write-Warning "$Label target not installed: $packageRoot"
    return $false
  }

  $mojangRoot = Join-Path $packageRoot "LocalState/games/com.mojang"

  Deploy-PackPair -Label $Label -MojangRoot $mojangRoot -BehaviorFolderName "behavior_packs" -ResourceFolderName "resource_packs" -Flavor "standard"

  if (-not $SkipDevelopment) {
    Deploy-PackPair -Label $Label -MojangRoot $mojangRoot -BehaviorFolderName "development_behavior_packs" -ResourceFolderName "development_resource_packs" -Flavor "development"
  }

  return $true
}

$successCount = 0
foreach ($target in $targets) {
  if (Deploy-ToTarget -Label $target.Label -Family $target.Family) {
    $successCount++
  }
}

if ($successCount -eq 0) {
  throw "No deploy targets were available."
}

if (-not $PreviewOnly -and -not $StableOnly) {
  Write-Host "Deployed to all detected targets (Stable + Preview when installed)."
}

if (-not $SkipDevelopment) {
  Write-Host "Development pack folders were also synced to avoid stale UUID/version conflicts."
}

Write-Host "Fully close Minecraft and relaunch before testing."
Write-Host "Enable both packs in your world before testing."
