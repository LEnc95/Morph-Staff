param(
  [string]$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$BehaviorPackName = "MorphStaff_BP",
  [string]$ResourcePackName = "MorphStaff_RP",
  [switch]$PreviewBuild
)

$ErrorActionPreference = "Stop"

$family = if ($PreviewBuild) { "Microsoft.MinecraftWindowsBeta_8wekyb3d8bbwe" } else { "Microsoft.MinecraftUWP_8wekyb3d8bbwe" }
$mojangRoot = Join-Path $env:LOCALAPPDATA "Packages/$family/LocalState/games/com.mojang"
$bpDest = Join-Path $mojangRoot "behavior_packs/$BehaviorPackName"
$rpDest = Join-Path $mojangRoot "resource_packs/$ResourcePackName"

$rpSource = Join-Path $RootDir "MorphStaff_RP"
if (-not (Test-Path -Path $rpSource -PathType Container)) {
  throw "Missing RP source folder: $rpSource"
}

$bpFolders = @("items", "recipes", "scripts")
$bpFiles = @("manifest.json", "pack_icon.png", "README.md")

New-Item -ItemType Directory -Force -Path $bpDest | Out-Null
New-Item -ItemType Directory -Force -Path $rpDest | Out-Null

foreach ($folder in $bpFolders) {
  $src = Join-Path $RootDir $folder
  if (Test-Path -Path $src -PathType Container) {
    Copy-Item -Path $src -Destination $bpDest -Recurse -Force
  }
}

foreach ($file in $bpFiles) {
  $src = Join-Path $RootDir $file
  if (Test-Path -Path $src -PathType Leaf) {
    Copy-Item -Path $src -Destination $bpDest -Force
  }
}

Copy-Item -Path (Join-Path $rpSource "*") -Destination $rpDest -Recurse -Force

Write-Host "Behavior pack deployed to: $bpDest"
Write-Host "Resource pack deployed to: $rpDest"
Write-Host "Enable both packs in your world before testing."
