param(
  [string]$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$Name,
  [switch]$ForceCloseMinecraft,
  [switch]$SkipFolderDeploy,
  [switch]$LaunchStable,
  [switch]$LaunchPreview
)

$ErrorActionPreference = "Stop"

if ($LaunchStable -and $LaunchPreview) {
  throw "Choose only one launch target: -LaunchStable or -LaunchPreview."
}

function Stop-MinecraftProcesses {
  $processNames = @(
    "Minecraft.Windows",
    "Minecraft",
    "Minecraft.WindowsBeta"
  )

  foreach ($name in $processNames) {
    Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  }

  Write-Host "Closed Minecraft processes."
}

function Get-RunningMinecraftProcesses {
  $processNames = @(
    "Minecraft.Windows",
    "Minecraft",
    "Minecraft.WindowsBeta"
  )

  $running = @()
  foreach ($name in $processNames) {
    $running += @(Get-Process -Name $name -ErrorAction SilentlyContinue)
  }

  return @($running | Sort-Object ProcessName, Id -Unique)
}

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

function Start-MinecraftLaunchTarget {
  param([string]$Aumid)

  Start-Process "shell:AppsFolder\$Aumid"
}

if (-not $Name) {
  $Name = Get-DefaultBuildName -PackRoot $RootDir
}

if ($ForceCloseMinecraft) {
  Stop-MinecraftProcesses
} else {
  $runningMinecraft = Get-RunningMinecraftProcesses
  if ($runningMinecraft.Count -gt 0) {
    $details = $runningMinecraft | ForEach-Object { "$($_.ProcessName)#$($_.Id)" }
    throw "Minecraft is currently running ($($details -join ', ')). Close it first, or rerun with -ForceCloseMinecraft."
  }
}

$buildScript = Join-Path $RootDir "scripts/build-mcaddon.ps1"
if (-not (Test-Path -Path $buildScript -PathType Leaf)) {
  throw "Missing build script: $buildScript"
}

$deployScript = Join-Path $RootDir "scripts/deploy-prod.ps1"
if (-not $SkipFolderDeploy -and -not (Test-Path -Path $deployScript -PathType Leaf)) {
  throw "Missing deploy script: $deployScript"
}

& powershell -ExecutionPolicy Bypass -File $buildScript -RootDir $RootDir -Name $Name

if (-not $SkipFolderDeploy) {
  & powershell -ExecutionPolicy Bypass -File $deployScript -RootDir $RootDir
}

$addonPath = Join-Path $RootDir "dist/$Name.mcaddon"
if (-not (Test-Path -Path $addonPath -PathType Leaf)) {
  throw "Expected add-on package not found: $addonPath"
}

Start-Process $addonPath
Write-Host "Import launched: $addonPath"

if ($LaunchStable) {
  Start-Sleep -Seconds 2
  Start-MinecraftLaunchTarget -Aumid "MICROSOFT.MINECRAFTUWP_8wekyb3d8bbwe!Game"
  Write-Host "Launched Minecraft Stable."
} elseif ($LaunchPreview) {
  Start-Sleep -Seconds 2
  Start-MinecraftLaunchTarget -Aumid "Microsoft.MinecraftWindowsBeta_8wekyb3d8bbwe!Game"
  Write-Host "Launched Minecraft Preview."
}
