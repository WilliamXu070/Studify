param(
    [string]$SpotifySourcePath = "$env:APPDATA\Spotify",
    [string]$Profile = 'default',
    [switch]$ForceRecreate,
    [switch]$Repatch,
    [switch]$OfflineMode,
    [switch]$ClientOffline,
    [switch]$NoClientOffline,
    [switch]$HardNetworkBlock,
    [switch]$NoStopExistingSpotify,
    [switch]$Online,
    [switch]$CleanupNetworkRules,
    [int]$ShellReadyWaitSeconds = 20,
    [int]$RemoteDebugPort = 0
)

$ErrorActionPreference = 'Stop'

if (-not $PSBoundParameters.ContainsKey('OfflineMode')) {
    $OfflineMode = $true
}

$networkBlock = -not ($Online -or $NoClientOffline)

$repoRoot = Split-Path -Parent $PSScriptRoot
$labRoot = Join-Path $repoRoot 'labs\spotx-lab'
$runner = Join-Path $PSScriptRoot 'Run-SpotxLab.ps1'
$workspaceRoot = Join-Path $repoRoot 'labs\spotx-lab\workspace'
$workspaceProfile = Join-Path $workspaceRoot $Profile
$workspaceSpotify = Join-Path $workspaceProfile 'spotify'
$workspaceLocalAppData = Join-Path $workspaceProfile 'localappdata'
$workspaceLocalSpotify = Join-Path $workspaceLocalAppData 'Spotify'
$workspaceBrowserData = Join-Path $workspaceLocalSpotify 'BrowserUserData'
$readyFlag = Join-Path $workspaceProfile '.spotxlab.ready'

function Stop-LabSpotifyProcesses {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspacePath
    )

    try {
        $resolvedWorkspace = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $WorkspacePath).Path).TrimEnd('\')
    }
    catch {
        return
    }

    $processes = Get-CimInstance Win32_Process -Filter "Name = 'Spotify.exe'" | Where-Object {
        $_.ExecutablePath -and $_.ExecutablePath.StartsWith($resolvedWorkspace, [System.StringComparison]::OrdinalIgnoreCase)
    }

    foreach ($process in @($processes)) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Stop-ExistingSpotifyProcesses {
    $processes = Get-CimInstance Win32_Process -Filter "Name = 'Spotify.exe'"
    foreach ($process in @($processes)) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }
    if ($processes) {
        Start-Sleep -Milliseconds 750
    }
}

function Test-SpotXLabAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SpotXLabFirewallRuleNames {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Profile
    )

    $safeProfile = $Profile -replace '[^A-Za-z0-9_.-]', '_'
    return @{
        Outbound = "SpotX Lab Spotify Block Out ($safeProfile)"
        Inbound  = "SpotX Lab Spotify Block In ($safeProfile)"
    }
}

function Remove-SpotXLabFirewallRules {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Profile
    )

    $ruleNames = Get-SpotXLabFirewallRuleNames -Profile $Profile
    foreach ($ruleName in $ruleNames.Values) {
        Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
    }
}

function Set-SpotXLabFirewallRules {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Profile,
        [Parameter(Mandatory = $true)]
        [string]$ProgramPath
    )

    if (-not (Get-Command New-NetFirewallRule -ErrorAction SilentlyContinue)) {
        throw "Windows Firewall cmdlets are unavailable. Run this on Windows with the NetSecurity module."
    }
    if (-not (Test-SpotXLabAdministrator)) {
        throw "Firewall isolation requires an elevated PowerShell/terminal. Re-run as Administrator, or pass -Online for a non-blocked lab launch."
    }

    Remove-SpotXLabFirewallRules -Profile $Profile

    $ruleNames = Get-SpotXLabFirewallRuleNames -Profile $Profile
    New-NetFirewallRule -DisplayName $ruleNames.Outbound -Direction Outbound -Program $ProgramPath -Action Block -Profile Any -Enabled True | Out-Null
}

function Test-SpotXLabFirewallRulesReady {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Profile,
        [Parameter(Mandatory = $true)]
        [string]$ProgramPath
    )

    if (-not (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue)) {
        return $false
    }

    $ruleNames = Get-SpotXLabFirewallRuleNames -Profile $Profile
    foreach ($ruleName in @($ruleNames.Outbound)) {
        $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Where-Object {
            $_.Enabled -eq 'True' -and $_.Action -eq 'Block'
        } | Select-Object -First 1
        if (-not $rule) {
            return $false
        }

        $app = $rule | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $app -or -not $app.Program -or
            -not $app.Program.Equals($ProgramPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }

    return $true
}

function Wait-SpotXLabWindow {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspacePath,
        [int]$MaxWaitSeconds = 45
    )

    try {
        $resolvedWorkspace = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $WorkspacePath).Path).TrimEnd('\')
    }
    catch {
        return $null
    }

    $deadline = (Get-Date).AddSeconds($MaxWaitSeconds)
    do {
        $candidate = Get-CimInstance Win32_Process -Filter "Name = 'Spotify.exe'" | Where-Object {
            $_.ExecutablePath -and $_.ExecutablePath.StartsWith($resolvedWorkspace, [System.StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1

        if ($candidate) {
            $process = Get-Process -Id $candidate.ProcessId -ErrorAction SilentlyContinue
            if ($process -and $process.MainWindowHandle -ne 0) {
                return $process
            }
        }

        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    return $null
}

function Set-SpotXLabPreference {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PrefsPath,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $line = "$Name=$Value"
    if (-not (Test-Path -LiteralPath $PrefsPath -PathType Leaf)) {
        Set-Content -LiteralPath $PrefsPath -Value $line -Encoding UTF8
        return
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]](Get-Content -LiteralPath $PrefsPath -Encoding UTF8))
    $updated = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ("^{0}=" -f [regex]::Escape($Name))) {
            $lines[$i] = $line
            $updated = $true
        }
    }
    if (-not $updated) {
        $lines.Add($line)
    }
    [System.IO.File]::WriteAllLines($PrefsPath, $lines, [System.Text.UTF8Encoding]::new($false))
}

function Get-SpotXLabPrefsPaths {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SpotifyPath
    )

    $paths = [System.Collections.Generic.List[string]]::new()
    $rootPrefs = Join-Path $SpotifyPath 'prefs'
    $paths.Add($rootPrefs)

    $usersPath = Join-Path $SpotifyPath 'Users'
    if (Test-Path -LiteralPath $usersPath -PathType Container) {
        $userPrefs = Get-ChildItem -LiteralPath $usersPath -Filter 'prefs' -Recurse -File -ErrorAction SilentlyContinue
        foreach ($prefs in @($userPrefs)) {
            if (-not $paths.Contains($prefs.FullName)) {
                $paths.Add($prefs.FullName)
            }
        }
    }

    return @($paths)
}

function Enable-SpotXLabClientOffline {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SpotifyPath
    )

    if (-not (Test-Path -LiteralPath $SpotifyPath -PathType Container)) {
        return
    }

    $storagePath = Join-Path $SpotifyPath 'Storage'
    if (-not (Test-Path -LiteralPath $storagePath -PathType Container)) {
        New-Item -ItemType Directory -Path $storagePath -Force | Out-Null
    }

    foreach ($prefsPath in @(Get-SpotXLabPrefsPaths -SpotifyPath $SpotifyPath)) {
        Set-SpotXLabPreference -PrefsPath $prefsPath -Name 'app.offline-mode' -Value 'true'
        Set-SpotXLabPreference -PrefsPath $prefsPath -Name 'network.proxy.mode' -Value '0'
        Set-SpotXLabPreference -PrefsPath $prefsPath -Name 'storage.last-location' -Value ('"{0}"' -f ($storagePath -replace '\\', '\\'))
    }
}

function Disable-SpotXLabClientOffline {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SpotifyPath
    )

    if (-not (Test-Path -LiteralPath $SpotifyPath -PathType Container)) {
        return
    }

    foreach ($prefsPath in @(Get-SpotXLabPrefsPaths -SpotifyPath $SpotifyPath)) {
        Set-SpotXLabPreference -PrefsPath $prefsPath -Name 'app.offline-mode' -Value 'false'
        Set-SpotXLabPreference -PrefsPath $prefsPath -Name 'network.proxy.mode' -Value '0'
    }
}

function Initialize-SpotXLabLocalAppData {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceLocalSpotifyPath
    )

    if (Test-Path -LiteralPath $WorkspaceLocalSpotifyPath -PathType Container) {
        return
    }

    $sourceLocalSpotify = Join-Path $env:LOCALAPPDATA 'Spotify'
    if (-not (Test-Path -LiteralPath $sourceLocalSpotify -PathType Container)) {
        return
    }

    $destinationParent = Split-Path -Parent $WorkspaceLocalSpotifyPath
    if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
    }

    Write-Host "Seeding lab LocalAppData from: $sourceLocalSpotify"
    Copy-Item -Path $sourceLocalSpotify -Destination $destinationParent -Recurse -Force -ErrorAction SilentlyContinue
}

function Start-SpotXLabSpotify {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$SpotifyExe,
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceProfilePath,
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceLocalAppDataPath,
        [string[]]$Arguments = @()
    )

    $startParams = @{
        FilePath         = $SpotifyExe.FullName
        WorkingDirectory = $SpotifyExe.DirectoryName
        PassThru         = $true
        WindowStyle      = 'Normal'
    }
    if ($Arguments.Count -gt 0) {
        $startParams['ArgumentList'] = $Arguments
    }

    $originalAppData = $env:APPDATA
    $originalLocalAppData = $env:LOCALAPPDATA
    try {
        $env:APPDATA = $WorkspaceProfilePath
        $env:LOCALAPPDATA = $WorkspaceLocalAppDataPath
        return Start-Process @startParams
    }
    finally {
        $env:APPDATA = $originalAppData
        $env:LOCALAPPDATA = $originalLocalAppData
    }
}

if ($CleanupNetworkRules) {
    if (-not (Test-SpotXLabAdministrator)) {
        throw "Firewall cleanup requires an elevated PowerShell/terminal."
    }
    Remove-SpotXLabFirewallRules -Profile $Profile
    Write-Host "Removed SpotX Lab firewall rules for profile '$Profile'."
    return
}

if (-not (Test-Path $runner)) {
    throw "Runner not found: $runner"
}
if (-not (Test-Path $SpotifySourcePath)) {
    throw "Spotify source not found: $SpotifySourcePath"
}

if (-not (Test-Path $workspaceRoot)) {
    New-Item -ItemType Directory -Path $workspaceRoot -Force | Out-Null
}

$instanceExists = Test-Path $workspaceSpotify -PathType Container
$needRecreate = $ForceRecreate -or -not $instanceExists -or $Repatch -or -not (Test-Path $readyFlag)

if ($needRecreate) {
    $runArgs = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $runner
        '-Profile'
        $Profile
        '-SpotifySourcePath'
        $SpotifySourcePath
        '-LabRoot'
        $labRoot
    )
    if ($OfflineMode) {
        $runArgs += '-OfflineMode'
    }
    if ($ForceRecreate) {
        $runArgs += '-ForceRecreate'
    }

    Write-Host "Starting SpotX one-click"
    Write-Host "Profile: $Profile"
    Write-Host "Source : $SpotifySourcePath"
    Write-Host "Workspace: $workspaceSpotify"
    Write-Host "Patch/prepare needed: $needRecreate (recreate=$ForceRecreate, repatch=$Repatch)"
    Write-Host "Invoking runner:"
    Write-Host ("  powershell.exe " + ($runArgs -join ' '))

    $runnerProc = Start-Process -FilePath 'powershell.exe' -ArgumentList $runArgs -Wait -PassThru -WindowStyle Normal
    if ($runnerProc.ExitCode -ne 0) {
        throw "Runner failed with exit code $($runnerProc.ExitCode). Open this file for details: $runner"
    }

    if (-not (Test-Path $workspaceSpotify -PathType Container)) {
        throw "Patched Spotify workspace not found after patch run: $workspaceSpotify"
    }

    Get-Date -Format o | Set-Content -LiteralPath $readyFlag
    Write-Host "Workspace prepared: $workspaceProfile"
}
else {
    Write-Host "Starting SpotX one-click (cache hit)"
    Write-Host "Profile: $Profile"
    Write-Host "Source : $SpotifySourcePath"
    Write-Host "Workspace: $workspaceSpotify"
    Write-Host "Reusing prepared workspace (skip SpotX patch)"
}

$spotifyExe = Get-ChildItem -Path $workspaceProfile -Filter 'Spotify.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $spotifyExe) {
    throw "Patched Spotify.exe not found under workspace: $workspaceProfile"
}

$hasMatchingNetworkRules = $false
if ($networkBlock) {
    $hasMatchingNetworkRules = Test-SpotXLabFirewallRulesReady -Profile $Profile -ProgramPath $spotifyExe.FullName
}

if ($networkBlock -and -not (Test-SpotXLabAdministrator) -and -not $hasMatchingNetworkRules) {
    throw "Firewall isolation requires an elevated PowerShell/terminal. Re-run as Administrator, or pass mode 'online' for a non-blocked lab launch."
}

if (-not $NoStopExistingSpotify) {
    Stop-ExistingSpotifyProcesses
}

Initialize-SpotXLabLocalAppData -WorkspaceLocalSpotifyPath $workspaceLocalSpotify
if (-not (Test-Path -LiteralPath $workspaceBrowserData -PathType Container)) {
    New-Item -ItemType Directory -Path $workspaceBrowserData -Force | Out-Null
}

Write-Host ('Launching: ' + $spotifyExe.FullName)

if ($ClientOffline) {
    Enable-SpotXLabClientOffline -SpotifyPath $spotifyExe.DirectoryName
    Write-Host "Spotify client offline mode enabled in lab prefs."
}
else {
    Disable-SpotXLabClientOffline -SpotifyPath $spotifyExe.DirectoryName
    Write-Host "Spotify client offline mode disabled in lab prefs."
}
if ($networkBlock) {
    if (Test-SpotXLabAdministrator) {
        Set-SpotXLabFirewallRules -Profile $Profile -ProgramPath $spotifyExe.FullName
        Write-Host "Firewall isolation enabled for lab Spotify only."
    }
    else {
        Write-Host "Reusing existing firewall isolation for lab Spotify only."
    }
}
else {
    if (Test-SpotXLabAdministrator) {
        Remove-SpotXLabFirewallRules -Profile $Profile
    }
    Write-Host "Network isolation disabled for this lab launch."
}

$launchArgs = @("--user-data-dir=$workspaceBrowserData")
if ($RemoteDebugPort -gt 0) {
    $launchArgs += "--remote-debugging-port=$RemoteDebugPort"
    $launchArgs += "--remote-allow-origins=http://127.0.0.1:$RemoteDebugPort"
    Write-Host "Remote debug port enabled on localhost:$RemoteDebugPort."
}
$spotifyProcess = Start-SpotXLabSpotify -SpotifyExe $spotifyExe -WorkspaceProfilePath $workspaceProfile -WorkspaceLocalAppDataPath $workspaceLocalAppData -Arguments $launchArgs
Write-Host ('Spotify started. PID=' + $spotifyProcess.Id)
