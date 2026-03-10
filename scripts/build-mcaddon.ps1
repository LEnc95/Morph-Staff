param(
  [string]$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$OutDir = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "dist"),
  [string]$Name
)

$ErrorActionPreference = "Stop"

function Get-DefaultBuildName {
  param([string]$PackRoot)

  $manifestPath = Join-Path $PackRoot "manifest.json"
  if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
    throw "Missing behavior pack manifest: $manifestPath"
  }

  $manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json
  $version = @($manifest.header.version) -join "."
  if ([string]::IsNullOrWhiteSpace($version)) {
    throw "Unable to derive version from manifest header.version."
  }

  return "MorphStaff-v$version"
}

function Remove-IfExists {
  param([string]$PathToRemove)
  if (Test-Path -Path $PathToRemove) {
    Remove-Item -Path $PathToRemove -Recurse -Force
  }
}

function New-CleanDir {
  param([string]$PathToCreate)
  Remove-IfExists -PathToRemove $PathToCreate
  New-Item -ItemType Directory -Force -Path $PathToCreate | Out-Null
}

$bpSourcePaths = @("manifest.json", "pack_icon.png", "README.md", "items", "recipes", "scripts", "entities")
$rpSourceDir = Join-Path $RootDir "MorphStaff_RP"

if (-not (Test-Path -Path $rpSourceDir -PathType Container)) {
  throw "Missing RP folder: $rpSourceDir"
}

if (-not $Name) {
  $Name = Get-DefaultBuildName -PackRoot $RootDir
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$tmpRoot = Join-Path $OutDir "__tmp_build"
$bpStage = Join-Path $tmpRoot "bp"
$rpStage = Join-Path $tmpRoot "rp"
$addonStage = Join-Path $tmpRoot "addon"

New-CleanDir -PathToCreate $bpStage
New-CleanDir -PathToCreate $rpStage
New-CleanDir -PathToCreate $addonStage

foreach ($entry in $bpSourcePaths) {
  $src = Join-Path $RootDir $entry
  if (Test-Path -Path $src) {
    Copy-Item -Path $src -Destination $bpStage -Recurse -Force
  }
}

Copy-Item -Path (Join-Path $rpSourceDir "*") -Destination $rpStage -Recurse -Force

$bpZip = Join-Path $tmpRoot "$Name.bp.zip"
$rpZip = Join-Path $tmpRoot "$Name.rp.zip"
$bpPack = Join-Path $OutDir "$Name.bp.mcpack"
$rpPack = Join-Path $OutDir "$Name.rp.mcpack"
$addonZip = Join-Path $tmpRoot "$Name.zip"
$addonPack = Join-Path $OutDir "$Name.mcaddon"

Remove-IfExists -PathToRemove $bpZip
Remove-IfExists -PathToRemove $rpZip
Remove-IfExists -PathToRemove $bpPack
Remove-IfExists -PathToRemove $rpPack
Remove-IfExists -PathToRemove $addonZip
Remove-IfExists -PathToRemove $addonPack

Compress-Archive -Path (Join-Path $bpStage "*") -DestinationPath $bpZip -Force
Move-Item -Path $bpZip -Destination $bpPack -Force

Compress-Archive -Path (Join-Path $rpStage "*") -DestinationPath $rpZip -Force
Move-Item -Path $rpZip -Destination $rpPack -Force

Copy-Item -Path $bpPack -Destination $addonStage -Force
Copy-Item -Path $rpPack -Destination $addonStage -Force

Compress-Archive -Path (Join-Path $addonStage "*") -DestinationPath $addonZip -Force
Move-Item -Path $addonZip -Destination $addonPack -Force

Write-Host "Built:"
Write-Host " - $bpPack"
Write-Host " - $rpPack"
Write-Host " - $addonPack"
