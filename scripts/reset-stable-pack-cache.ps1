param(
  [string]$Family = "Microsoft.MinecraftUWP_8wekyb3d8bbwe",
  [switch]$AlsoPreview
)

$ErrorActionPreference = "Stop"

function Reset-PackCacheForFamily {
  param([string]$TargetFamily)

  $minecraftPeDir = Join-Path $env:LOCALAPPDATA "Packages/$TargetFamily/LocalState/games/com.mojang/minecraftpe"
  if (-not (Test-Path -Path $minecraftPeDir -PathType Container)) {
    Write-Warning "Minecraft package path not found for family: $TargetFamily"
    return
  }

  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $backupDir = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "artifacts/mc-cache-backup/$TargetFamily/$timestamp"
  New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

  $globalResourcePacks = Join-Path $minecraftPeDir "global_resource_packs.json"
  $validKnownPacks = Join-Path $minecraftPeDir "valid_known_packs.json"

  if (Test-Path -Path $globalResourcePacks -PathType Leaf) {
    Copy-Item -Path $globalResourcePacks -Destination (Join-Path $backupDir "global_resource_packs.json") -Force
  }

  if (Test-Path -Path $validKnownPacks -PathType Leaf) {
    Copy-Item -Path $validKnownPacks -Destination (Join-Path $backupDir "valid_known_packs.json") -Force
  }

  "[]" | Set-Content -Path $globalResourcePacks -Encoding Ascii

  if (Test-Path -Path $validKnownPacks -PathType Leaf) {
    Remove-Item -Path $validKnownPacks -Force
  }

  Write-Host "[$TargetFamily] backup: $backupDir"
  Write-Host "[$TargetFamily] reset global_resource_packs.json and removed valid_known_packs.json"
}

Reset-PackCacheForFamily -TargetFamily $Family

if ($AlsoPreview) {
  Reset-PackCacheForFamily -TargetFamily "Microsoft.MinecraftWindowsBeta_8wekyb3d8bbwe"
}
