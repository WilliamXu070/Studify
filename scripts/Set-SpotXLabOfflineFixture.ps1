param(
    [string]$Profile = 'default',
    [string]$Title,
    [string[]]$Artist = @(),
    [string]$Album,
    [string]$Uri,
    [string]$Id,
    [string]$Isrc,
    [switch]$Append,
    [switch]$ShowMarkers,
    [switch]$Probe,
    [switch]$NoProbe,
    [switch]$DeepElementPatch,
    [switch]$PatchNetworkData,
    [switch]$NoForceOffline
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$fixturePath = Join-Path $repoRoot "labs\spotx-lab\workspace\$Profile\offline-fixtures.json"
$fixtureDir = Split-Path -Parent $fixturePath
if (-not (Test-Path -LiteralPath $fixtureDir -PathType Container)) {
    New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null
}

$track = [ordered]@{
    downloadState = 'downloaded'
}

if ($Title) { $track.title = $Title }
if ($Artist.Count -gt 0) { $track.artists = @($Artist) }
if ($Album) { $track.album = $Album }
if ($Uri) { $track.uri = $Uri }
if ($Id) { $track.id = $Id }
if ($Isrc) { $track.isrc = $Isrc }

if (-not ($Title -or $Uri -or $Id -or $Isrc)) {
    throw "Provide at least one of -Title, -Uri, -Id, or -Isrc."
}

if ($Append -and (Test-Path -LiteralPath $fixturePath -PathType Leaf)) {
    $existing = Get-Content -LiteralPath $fixturePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $tracks = @($existing.tracks) + @([pscustomobject]$track)
}
else {
    $tracks = @([pscustomobject]$track)
}

$fixture = [ordered]@{
    enabled = $true
    forceOffline = -not $NoForceOffline
    showMarkers = [bool]$ShowMarkers
    probe = [bool]$Probe -and -not $NoProbe
    deepElementPatch = [bool]$DeepElementPatch
    patchNetworkData = [bool]$PatchNetworkData
    tracks = $tracks
}

$json = $fixture | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($fixturePath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))

Write-Host "Wrote offline fixture:"
Write-Host "  $fixturePath"
Write-Host "Repatch and launch with:"
Write-Host "  .\scripts\Start-SpotXLab-OneClick.ps1 -Profile $Profile -SpotifySourcePath `"`$env:APPDATA\Spotify`" -ClientOffline -Repatch"
