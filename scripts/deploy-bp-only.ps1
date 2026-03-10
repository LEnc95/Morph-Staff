param(
  [string]$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$BehaviorPackName = "MorphStaff_BP",
  [switch]$PreviewOnly,
  [switch]$StableOnly
)

$ErrorActionPreference = "Stop"

if ($PreviewOnly -and $StableOnly) {
  throw "Choose only one target switch: -PreviewOnly or -StableOnly."
}

$bpFolders = @("items", "recipes", "scripts", "entities")
$bpFiles = @("manifest.json", "pack_icon.png", "README.md")

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

function Deploy-BPToTarget {
  param(
    [string]$Label,
    [string]$Family
  )

  $packageRoot = Join-Path $env:LOCALAPPDATA "Packages/$Family"
  if (-not (Test-Path -Path $packageRoot -PathType Container)) {
    Write-Warning "$Label target not installed: $packageRoot"
    return
  }

  $mojangRoot = Join-Path $packageRoot "LocalState/games/com.mojang"
  $destinations = @(
    (Join-Path $mojangRoot "behavior_packs/$BehaviorPackName"),
    (Join-Path $mojangRoot "development_behavior_packs/$BehaviorPackName")
  )

  foreach ($dest in $destinations) {
    if (Test-Path -Path $dest) {
      Remove-Item -Path $dest -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-BehaviorPackContents -Destination $dest
    Write-Host "[$Label] BP deployed: $dest"
  }
}

if ($PreviewOnly) {
  Deploy-BPToTarget -Label "Preview" -Family "Microsoft.MinecraftWindowsBeta_8wekyb3d8bbwe"
  return
}

if ($StableOnly) {
  Deploy-BPToTarget -Label "Stable" -Family "Microsoft.MinecraftUWP_8wekyb3d8bbwe"
  return
}

Deploy-BPToTarget -Label "Stable" -Family "Microsoft.MinecraftUWP_8wekyb3d8bbwe"
Deploy-BPToTarget -Label "Preview" -Family "Microsoft.MinecraftWindowsBeta_8wekyb3d8bbwe"
