param(
  [string]$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$BehaviorPackName = "MorphStaff_BP",
  [string]$ResourcePackName = "MorphStaff_RP",
  [switch]$CleanKnownTestPacks
)

$ErrorActionPreference = "Stop"

$rpSource = Join-Path $RootDir "MorphStaff_RP"
if (-not (Test-Path -Path $rpSource -PathType Container)) {
  throw "Missing RP source folder: $rpSource"
}

$bpFolders = @("items", "recipes", "scripts", "entities")
$bpFiles = @("manifest.json", "pack_icon.png", "README.md")

$oldPackNames = @(
  "MorphStaff",
  "MorphStaff_BP",
  "MorphStaff_RP"
)

$knownTestNames = @(
  "AAA_Local_Test",
  "AAB_V3_Test",
  "ZZ_DiagBP",
  "ZZ_ScriptDiag"
)

if ($CleanKnownTestPacks) {
  $oldPackNames += $knownTestNames
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

function Get-RoamingMojangRoots {
  $roots = @()
  $minecraftBedrockRoot = Join-Path $env:APPDATA "Minecraft Bedrock"
  if (-not (Test-Path -Path $minecraftBedrockRoot -PathType Container)) {
    return @()
  }

  $roots += (Join-Path $minecraftBedrockRoot "games/com.mojang")
  $roots += (Join-Path $minecraftBedrockRoot "Users/Shared/games/com.mojang")

  $usersRoot = Join-Path $minecraftBedrockRoot "Users"
  if (Test-Path -Path $usersRoot -PathType Container) {
    $roots += Get-ChildItem -Path $usersRoot -Directory | ForEach-Object {
      Join-Path $_.FullName "games/com.mojang"
    }
  }

  $roots += (Join-Path $env:APPDATA "games/com.mojang")
  return @($roots | Where-Object { Test-Path -Path $_ -PathType Container } | Select-Object -Unique)
}

function Remove-PackFoldersMatchingNames {
  param(
    [string]$ParentDir
  )

  if (-not (Test-Path -Path $ParentDir -PathType Container)) {
    return
  }

  $toDelete = Get-ChildItem -Path $ParentDir -Directory | Where-Object {
    $name = $_.Name
    foreach ($prefix in $oldPackNames) {
      if ($name -eq $prefix -or $name -like "$prefix(*)") {
        return $true
      }
    }

    return $false
  }

  foreach ($dir in $toDelete) {
    Remove-Item -Path $dir.FullName -Recurse -Force
    Write-Host "Removed stale folder: $($dir.FullName)"
  }
}

function Deploy-ToMojangRoot {
  param([string]$MojangRoot)

  $bpParent = Join-Path $MojangRoot "behavior_packs"
  $rpParent = Join-Path $MojangRoot "resource_packs"
  $devBpParent = Join-Path $MojangRoot "development_behavior_packs"
  $devRpParent = Join-Path $MojangRoot "development_resource_packs"

  foreach ($parent in @($bpParent, $rpParent, $devBpParent, $devRpParent)) {
    Remove-PackFoldersMatchingNames -ParentDir $parent
  }

  $bpTargets = @(
    (Join-Path $bpParent $BehaviorPackName),
    (Join-Path $devBpParent $BehaviorPackName)
  )
  $rpTargets = @(
    (Join-Path $rpParent $ResourcePackName),
    (Join-Path $devRpParent $ResourcePackName)
  )

  foreach ($bpDest in $bpTargets) {
    New-Item -ItemType Directory -Force -Path $bpDest | Out-Null
    Copy-BehaviorPackContents -Destination $bpDest
    Write-Host "Roaming BP deployed: $bpDest"
  }

  foreach ($rpDest in $rpTargets) {
    New-Item -ItemType Directory -Force -Path $rpDest | Out-Null
    Copy-Item -Path (Join-Path $rpSource "*") -Destination $rpDest -Recurse -Force
    Write-Host "Roaming RP deployed: $rpDest"
  }
}

$roots = Get-RoamingMojangRoots
if ($roots.Count -eq 0) {
  Write-Warning "No Roaming Minecraft Bedrock roots found."
  exit 0
}

foreach ($root in $roots) {
  Write-Host ""
  Write-Host "Deploying Roaming packs to: $root"
  Deploy-ToMojangRoot -MojangRoot $root
}

Write-Host ""
Write-Host "Roaming deploy complete."
