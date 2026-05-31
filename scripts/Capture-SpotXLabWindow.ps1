param(
    [string]$Profile = 'default',
    [string]$OutputPath,
    [int]$MaxWaitSeconds = 45,
    [switch]$NoMaximize
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$workspaceSpotify = Join-Path $repoRoot "labs\spotx-lab\workspace\$Profile\spotify"

if (-not $OutputPath) {
    $screenshots = Join-Path $repoRoot "labs\spotx-lab\workspace\$Profile\screenshots"
    if (-not (Test-Path -LiteralPath $screenshots -PathType Container)) {
        New-Item -ItemType Directory -Path $screenshots -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputPath = Join-Path $screenshots "spotify-$stamp.png"
}

$resolvedWorkspace = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $workspaceSpotify).Path).TrimEnd('\')

$deadline = (Get-Date).AddSeconds($MaxWaitSeconds)
$targetProcess = $null
do {
    $labCandidates = @(Get-CimInstance Win32_Process -Filter "Name = 'Spotify.exe'" | Where-Object {
        $_.ExecutablePath -and $_.ExecutablePath.StartsWith($resolvedWorkspace, [System.StringComparison]::OrdinalIgnoreCase)
    })
    $candidate = $labCandidates | Select-Object -First 1

    if ($candidate) {
        $process = @($labCandidates | ForEach-Object {
            Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
        } | Where-Object { $_.MainWindowHandle -ne 0 }) | Select-Object -First 1
        if ($process -and $process.MainWindowHandle -ne 0) {
            $targetProcess = $process
            break
        }

        $visibleSpotify = Get-Process Spotify -ErrorAction SilentlyContinue | Where-Object {
            $_.MainWindowHandle -ne 0
        } | Select-Object -First 1
        if ($visibleSpotify) {
            $targetProcess = $visibleSpotify
            break
        }
    }

    Start-Sleep -Milliseconds 500
} while ((Get-Date) -lt $deadline)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class SpotXLabWindowCapture {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, int nFlags);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
}
"@

function Get-SpotXLabWindowInfo {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process
    )

    if (-not $Process -or $Process.MainWindowHandle -eq 0) {
        return $null
    }

    $rect = New-Object SpotXLabWindowCapture+RECT
    if (-not [SpotXLabWindowCapture]::GetWindowRect($Process.MainWindowHandle, [ref]$rect)) {
        return $null
    }

    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -lt 1 -or $height -lt 1) {
        return $null
    }

    [pscustomobject]@{
        Process = $Process
        Hwnd = $Process.MainWindowHandle
        Rect = $rect
        Width = $width
        Height = $height
        Area = $width * $height
    }
}

function Get-SpotXLabWindowInfoFromHandle {
    param(
        [Parameter(Mandatory = $true)]
        [IntPtr]$Hwnd,
        [int]$ProcessId
    )

    $rect = New-Object SpotXLabWindowCapture+RECT
    if (-not [SpotXLabWindowCapture]::GetWindowRect($Hwnd, [ref]$rect)) {
        return $null
    }

    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -lt 1 -or $height -lt 1) {
        return $null
    }

    $title = New-Object System.Text.StringBuilder 512
    [void][SpotXLabWindowCapture]::GetWindowText($Hwnd, $title, $title.Capacity)

    [pscustomobject]@{
        Process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        ProcessId = $ProcessId
        Hwnd = $Hwnd
        Rect = $rect
        Width = $width
        Height = $height
        Area = $width * $height
        Visible = [SpotXLabWindowCapture]::IsWindowVisible($Hwnd)
        Title = $title.ToString()
    }
}

function Get-SpotXLabTopLevelWindowInfos {
    $spotifyProcessIds = @(Get-Process Spotify -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    $infos = New-Object System.Collections.Generic.List[object]
    $callback = [SpotXLabWindowCapture+EnumWindowsProc]{
        param([IntPtr]$windowHandle, [IntPtr]$lParam)

        [uint32]$ownerProcessId = 0
        [void][SpotXLabWindowCapture]::GetWindowThreadProcessId($windowHandle, [ref]$ownerProcessId)
        if ($spotifyProcessIds -contains [int]$ownerProcessId) {
            $info = Get-SpotXLabWindowInfoFromHandle -Hwnd $windowHandle -ProcessId ([int]$ownerProcessId)
            if ($info) {
                $infos.Add($info)
            }
        }

        return $true
    }
    [void][SpotXLabWindowCapture]::EnumWindows($callback, [IntPtr]::Zero)
    return @($infos | Sort-Object Area -Descending)
}

if (-not $targetProcess) {
    throw "No visible lab Spotify window found for profile '$Profile'."
}

$targetInfo = Get-SpotXLabWindowInfo -Process $targetProcess
$visibleInfos = @(Get-SpotXLabTopLevelWindowInfos | Where-Object { $_.Visible })

if ($visibleInfos.Count -gt 0 -and (-not $targetInfo -or $targetInfo.Area -lt 100000)) {
    $targetInfo = $visibleInfos[0]
}

$hwnd = $targetInfo.Hwnd
if ($NoMaximize) {
    [void][SpotXLabWindowCapture]::ShowWindow($hwnd, 9)
}
else {
    [void][SpotXLabWindowCapture]::ShowWindow($hwnd, 3)
}
[void][SpotXLabWindowCapture]::SetForegroundWindow($hwnd)
Start-Sleep -Milliseconds 1000

$rect = New-Object SpotXLabWindowCapture+RECT
if (-not [SpotXLabWindowCapture]::GetWindowRect($hwnd, [ref]$rect)) {
    throw "Could not read Spotify window bounds."
}

$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
if ($width -lt 1 -or $height -lt 1) {
    throw "Spotify window has invalid bounds: ${width}x${height}."
}
if ($width -lt 640 -or $height -lt 360) {
    throw "Spotify window is not restored enough to capture: ${width}x${height}. Restore/close the stale Spotify window and retry."
}

$bitmap = New-Object System.Drawing.Bitmap $width, $height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$hdc = $graphics.GetHdc()
$printed = $false
try {
    $printed = [SpotXLabWindowCapture]::PrintWindow($hwnd, $hdc, 2)
}
finally {
    $graphics.ReleaseHdc($hdc)
    $graphics.Dispose()
}

function Test-SpotXLabBitmapMostlyBlack {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Bitmap]$Bitmap
    )

    $dark = 0
    $total = 0
    $xStep = [Math]::Max([int]($Bitmap.Width / 24), 1)
    $yStep = [Math]::Max([int]($Bitmap.Height / 16), 1)
    for ($x = 0; $x -lt $Bitmap.Width; $x += $xStep) {
        for ($y = 0; $y -lt $Bitmap.Height; $y += $yStep) {
            $pixel = $Bitmap.GetPixel($x, $y)
            if (($pixel.R + $pixel.G + $pixel.B) -lt 30) {
                $dark++
            }
            $total++
        }
    }

    return ($total -gt 0 -and ($dark / $total) -gt 0.98)
}

if (-not $printed -or (Test-SpotXLabBitmapMostlyBlack -Bitmap $bitmap)) {
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
    }
    finally {
        $graphics.Dispose()
    }
}

$outDir = Split-Path -Parent $OutputPath
if ($outDir -and -not (Test-Path -LiteralPath $outDir -PathType Container)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose()

Write-Host "Screenshot: $OutputPath"
