param(
  [string]$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$ResourcePackName = "MorphStaff_RP",
  [switch]$PreviewOnly,
  [switch]$StableOnly
)

$ErrorActionPreference = "Stop"

if ($PreviewOnly -and $StableOnly) {
  throw "Choose only one target switch: -PreviewOnly or -StableOnly."
}

$rpSource = Join-Path $RootDir "MorphStaff_RP"
if (-not (Test-Path -Path $rpSource -PathType Container)) {
  throw "Missing RP source folder: $rpSource"
}

function Deploy-RPToTarget {
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
    (Join-Path $mojangRoot "resource_packs/$ResourcePackName"),
    (Join-Path $mojangRoot "development_resource_packs/$ResourcePackName")
  )

  foreach ($dest in $destinations) {
    if (Test-Path -Path $dest) {
      Remove-Item -Path $dest -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -Path (Join-Path $rpSource "*") -Destination $dest -Recurse -Force
    Write-Host "[$Label] RP deployed: $dest"
  }
}

if ($PreviewOnly) {
  Deploy-RPToTarget -Label "Preview" -Family "Microsoft.MinecraftWindowsBeta_8wekyb3d8bbwe"
  return
}

if ($StableOnly) {
  Deploy-RPToTarget -Label "Stable" -Family "Microsoft.MinecraftUWP_8wekyb3d8bbwe"
  return
}

Deploy-RPToTarget -Label "Stable" -Family "Microsoft.MinecraftUWP_8wekyb3d8bbwe"
Deploy-RPToTarget -Label "Preview" -Family "Microsoft.MinecraftWindowsBeta_8wekyb3d8bbwe"
