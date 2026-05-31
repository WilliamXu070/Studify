param(
    [Parameter(HelpMessage = 'Profile name to load from labs/spotx-lab/profiles.')]
    [string]$Profile = 'default',

    [Parameter(HelpMessage = 'Absolute or relative path to the repository root.')]
    [string]$RepoRoot,

    [Parameter(HelpMessage = 'Lab workspace root path.')]
    [string]$LabRoot = '',

    [Parameter(HelpMessage = 'Source Spotify installation to clone into the lab instance.')]
    [string]$SpotifySourcePath = (Join-Path $env:APPDATA 'Spotify'),

    [Parameter(HelpMessage = 'Explicit workspace Spotify folder for this run.')]
    [string]$SpotifyPath,

    [Parameter(HelpMessage = 'Recreate the workspace files even if they already exist.')]
    [switch]$ForceRecreate,

    [Parameter(HelpMessage = 'Prepare workspace only and do not run SpotX installer script.')]
    [switch]$PrepareOnly,

    [Parameter(HelpMessage = 'Launch Spotify after patching so you can test UI/features immediately.')]
    [switch]$StartSpotify,

    [Parameter(HelpMessage = 'Run SpotX patcher in offline mode.')]
    [switch]$OfflineMode,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraRunArgs
)

$ErrorActionPreference = 'Stop'

$scriptPath = if ($PSCommandPath) {
    $PSCommandPath
} elseif ($MyInvocation.MyCommand.Path) {
    $MyInvocation.MyCommand.Path
} else {
    $null
}

$scriptDir = if ($scriptPath) { Split-Path -Path $scriptPath -Parent } else { $PSScriptRoot }
$scriptDir = if ($scriptDir) { $scriptDir } else { (Get-Location).Path }

$resolvedScriptDir = try {
    (Resolve-Path -LiteralPath $scriptDir).Path
} catch {
    $scriptDir
}

$repoRoot = if ($RepoRoot) {
    try { (Resolve-Path -LiteralPath $RepoRoot).Path } catch { $RepoRoot }
} else {
    try { (Resolve-Path -LiteralPath (Join-Path $resolvedScriptDir '..')).Path } catch { $resolvedScriptDir }
}

if (-not $LabRoot) {
    $LabRoot = Join-Path $repoRoot 'labs\spotx-lab'
}

function Stop-LabSpotifyProcesses {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspacePath
    )

    try {
        $resolvedWorkspace = (Resolve-Path -LiteralPath $WorkspacePath).Path
        $resolvedWorkspace = [System.IO.Path]::GetFullPath($resolvedWorkspace).TrimEnd('\')
    }
    catch {
        return
    }

    $processes = Get-CimInstance Win32_Process -Filter "Name = 'Spotify.exe'" | Where-Object {
        $_.ExecutablePath -and $_.ExecutablePath.StartsWith($resolvedWorkspace, [System.StringComparison]::OrdinalIgnoreCase)
    }

    if (-not $processes) {
        return
    }

    $pids = @($processes | ForEach-Object { $_.ProcessId })
    Write-Host "Stopping lab Spotify processes before workspace recreate: $($pids -join ', ')"
    $pids | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 500
}

$runScript = Join-Path $repoRoot 'run.ps1'
$labRootResolved = Resolve-Path -LiteralPath $LabRoot -ErrorAction SilentlyContinue
$labRoot = if ($labRootResolved) {
    $labRootResolved.Path
}
else {
    Join-Path $repoRoot 'labs\\spotx-lab'
}

$profilePath = Join-Path $labRoot "profiles\\$Profile.json"
if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
    throw "Profile not found: $profilePath"
}

$profileData = Get-Content -Path $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json

$workspaceRoot = Join-Path $labRoot 'workspace'
$instanceRoot = Join-Path $workspaceRoot $Profile
$instanceSpotify = if ($SpotifyPath) { $SpotifyPath } else { Join-Path $instanceRoot 'spotify' }
$instanceAssets = Join-Path $instanceRoot 'resources'
$instancePatchSource = Join-Path $instanceRoot $profileData.runParameters.patchesPath
$instanceOfflineFixtures = Join-Path $instanceRoot 'offline-fixtures.json'

if ($ForceRecreate -and (Test-Path -LiteralPath $instanceRoot -PathType Container)) {
    Stop-LabSpotifyProcesses -WorkspacePath $instanceSpotify
    Remove-Item -LiteralPath $instanceRoot -Recurse -Force
}

if (-not (Test-Path -LiteralPath $instanceRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $instanceRoot -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $instanceSpotify -PathType Container)) {
    if (-not (Test-Path -LiteralPath $SpotifySourcePath -PathType Container)) {
        throw "Spotify source path does not exist: $SpotifySourcePath"
    }
    New-Item -ItemType Directory -Path $instanceSpotify -Force | Out-Null
    Copy-Item -Path (Join-Path $SpotifySourcePath '*') -Destination $instanceSpotify -Recurse -Force
}

if (-not (Test-Path -LiteralPath $instanceAssets -PathType Container)) {
    New-Item -ItemType Directory -Path $instanceAssets -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $instanceOfflineFixtures -PathType Leaf)) {
    $defaultFixtures = Join-Path $labRoot 'fixtures\offline-fixtures.default.json'
    if (Test-Path -LiteralPath $defaultFixtures -PathType Leaf) {
        Copy-Item -LiteralPath $defaultFixtures -Destination $instanceOfflineFixtures -Force
    }
    else {
        '{"enabled":false,"tracks":[]}' | Set-Content -LiteralPath $instanceOfflineFixtures -Encoding UTF8
    }
}

$labHelpersSource = Join-Path $labRoot 'helpers'
$labPatchSource = Join-Path $labRoot $profileData.runParameters.patchesPath
$instancePatchDir = Split-Path -Parent $instancePatchSource

if (-not (Test-Path -LiteralPath $instancePatchDir -PathType Container)) {
    New-Item -ItemType Directory -Path $instancePatchDir -Force | Out-Null
}

Copy-Item -LiteralPath $labPatchSource -Destination $instancePatchSource -Force

$useLocalResources = $true
if ($profileData.runParameters -and $profileData.runParameters.PSObject.Properties.Name -contains 'enableLocalAssets') {
    $useLocalResources = [bool]$profileData.runParameters.enableLocalAssets
}

if ($useLocalResources) {
    $existingAssets = Get-ChildItem -Path $instanceAssets -Force
    if ($existingAssets) {
        $existingAssets | Remove-Item -Recurse -Force
    }
    Copy-Item -Path (Join-Path $labHelpersSource '*') -Destination $instanceAssets -Recurse -Force
}

if ($PrepareOnly) {
    Write-Host "Lab workspace prepared:"
    Write-Host "  Profile: $Profile"
    Write-Host "  Spotify: $instanceSpotify"
    Write-Host "  Patches: $instancePatchSource"
    Write-Host "  Assets:  $instanceAssets"
    Write-Host "  Offline fixtures: $instanceOfflineFixtures"
    if ($StartSpotify) {
        Write-Host "  StartSpotify: not applicable in prepare mode"
    }
    return
}

$runParams = @{
    SpotifyPath         = $instanceSpotify
    CustomPatchesPath   = $instancePatchSource
    OfflineFixturesPath = $instanceOfflineFixtures
}

if ($useLocalResources) {
    $runParams['LocalResourcesPath'] = $instanceAssets
}

if ($StartSpotify) {
    $runParams['start_spoti'] = $true
}
if ($OfflineMode) {
    $runParams['OfflineMode'] = $true
}

$extraParams = @()
if ($profileData.extraArgs) {
    $extraParams += $profileData.extraArgs
}
if ($ExtraRunArgs) {
    $extraParams += $ExtraRunArgs
}

$runArgList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runScript)
foreach ($pair in $runParams.GetEnumerator()) {
    $runArgList += "-$($pair.Key)"
    if (-not ($pair.Value -is [bool])) {
        $runArgList += $pair.Value
    }
}

foreach ($extraArg in $extraParams) {
    $runArgList += $extraArg
}

Write-Host "Running SpotX patcher..."
& powershell.exe @runArgList
$runExitCode = $LASTEXITCODE
if ($runExitCode -ne 0) {
    throw "run.ps1 exited with code $runExitCode."
}
