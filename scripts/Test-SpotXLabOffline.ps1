param(
    [string]$Profile = 'default',
    [string]$SpotifySourcePath = "$env:APPDATA\Spotify",
    [string]$Probe = ("spotx offline probe " + (Get-Date -Format 'yyyyMMddHHmmss')),
    [switch]$Existing,
    [switch]$SkipClick,
    [int]$ClickXPercent = 40,
    [int]$ClickYPercent = 74
)

$ErrorActionPreference = 'Stop'

$launcher = Join-Path $PSScriptRoot 'Start-SpotXLab-OneClick.ps1'
$capture = Join-Path $PSScriptRoot 'Capture-SpotXLabWindow.ps1'
$repoRoot = Split-Path -Parent $PSScriptRoot
$screenshots = Join-Path $repoRoot "labs\spotx-lab\workspace\$Profile\screenshots"
if (-not (Test-Path -LiteralPath $screenshots -PathType Container)) {
    New-Item -ItemType Directory -Path $screenshots -Force | Out-Null
}

if (-not $Existing) {
    & $launcher -Profile $Profile -SpotifySourcePath $SpotifySourcePath
}

Start-Sleep -Seconds 10

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class SpotXLabInput {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
}
"@
Add-Type -AssemblyName System.Windows.Forms

function Get-SpotXLabWindowInfo {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process
    )

    if (-not $Process -or $Process.MainWindowHandle -eq 0) {
        return $null
    }

    $rect = New-Object SpotXLabInput+RECT
    if (-not [SpotXLabInput]::GetWindowRect($Process.MainWindowHandle, [ref]$rect)) {
        return $null
    }

    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -lt 1 -or $height -lt 1) {
        return $null
    }

    [pscustomobject]@{
        Process = $Process
        Area = $width * $height
    }
}

$repoRootResolved = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $repoRoot).Path)
$workspaceSpotify = Join-Path $repoRootResolved "labs\spotx-lab\workspace\$Profile\spotify"
$resolvedWorkspace = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $workspaceSpotify).Path).TrimEnd('\')

$labCandidates = @(Get-CimInstance Win32_Process -Filter "Name = 'Spotify.exe'" | Where-Object {
    $_.ExecutablePath -and $_.ExecutablePath.StartsWith($resolvedWorkspace, [System.StringComparison]::OrdinalIgnoreCase)
})

$process = @($labCandidates | ForEach-Object {
    Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
} | Where-Object { $_.MainWindowHandle -ne 0 } | ForEach-Object {
    Get-SpotXLabWindowInfo -Process $_
} | Where-Object { $_ } | Sort-Object Area -Descending | Select-Object -First 1).Process

if (-not $process -and $labCandidates.Count -gt 0) {
    $process = @(Get-Process Spotify -ErrorAction SilentlyContinue | Where-Object {
        $_.MainWindowHandle -ne 0
    } | ForEach-Object {
        Get-SpotXLabWindowInfo -Process $_
    } | Where-Object { $_ } | Sort-Object Area -Descending | Select-Object -First 1).Process
}

if (-not $process) {
    throw "No visible lab Spotify process found."
}

[void][SpotXLabInput]::ShowWindow($process.MainWindowHandle, 3)
[void][SpotXLabInput]::SetForegroundWindow($process.MainWindowHandle)
Start-Sleep -Milliseconds 800

if (-not $SkipClick) {
    $rect = New-Object SpotXLabInput+RECT
    if (-not [SpotXLabInput]::GetWindowRect($process.MainWindowHandle, [ref]$rect)) {
        throw "Could not read Spotify window bounds."
    }

    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    $x = $rect.Left + [int]($width * ($ClickXPercent / 100.0))
    $y = $rect.Top + [int]($height * ($ClickYPercent / 100.0))
    [void][SpotXLabInput]::SetCursorPos($x, $y)
    Start-Sleep -Milliseconds 150
    [SpotXLabInput]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    [SpotXLabInput]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}

Start-Sleep -Seconds 12

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outputPath = Join-Path $screenshots "offline-probe-$stamp.png"
& $capture -Profile $Profile -OutputPath $outputPath

Write-Host "Probe: $Probe"
Write-Host "Screenshot: $outputPath"
