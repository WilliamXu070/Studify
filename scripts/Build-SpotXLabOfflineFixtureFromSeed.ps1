param(
    [string]$Profile = 'default',
    [string]$SeedPath,
    [string]$PlaylistName,
    [switch]$ShowMarkers,
    [switch]$Probe,
    [switch]$NoProbe,
    [switch]$DeepElementPatch,
    [switch]$PatchNetworkData,
    [switch]$NoForceOffline
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}

function Get-SeedSlug {
    param([string]$Value)
    $slug = ($Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if (-not $slug) { return 'playlist' }
    return $slug
}

function Resolve-SeedPath {
    param(
        [string]$RepoRoot,
        [string]$Profile,
        [string]$SeedPath,
        [string]$PlaylistName
    )

    if ($SeedPath) {
        return (Resolve-Path -LiteralPath $SeedPath).Path
    }

    $seedRoot = Join-Path $RepoRoot "labs\spotx-lab\workspace\$Profile\seed-cache"
    if (-not (Test-Path -LiteralPath $seedRoot -PathType Container)) {
        throw "Seed cache folder not found: $seedRoot"
    }

    if ($PlaylistName) {
        $namedPath = Join-Path $seedRoot ("{0}.json" -f (Get-SeedSlug -Value $PlaylistName))
        if (Test-Path -LiteralPath $namedPath -PathType Leaf) {
            return (Resolve-Path -LiteralPath $namedPath).Path
        }
    }

    $latest = Get-ChildItem -LiteralPath $seedRoot -Filter '*.json' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latest) {
        throw "No seed cache JSON files found under: $seedRoot"
    }

    return $latest.FullName
}

function Convert-SeedTrack {
    param(
        [Parameter(Mandatory = $true)]
        $Track,
        [string]$SourcePlaylist
    )

    if (-not $Track.uri -and -not $Track.title) {
        return $null
    }

    $artists = @()
    if ($Track.artists) {
        $artists = @($Track.artists | Where-Object { $_ })
    }

    $converted = [ordered]@{
        downloadState = 'downloaded'
        sourcePlaylist = $SourcePlaylist
    }

    if ($Track.title) { $converted.title = $Track.title }
    if ($artists.Count -gt 0) { $converted.artists = $artists }
    if ($Track.album) { $converted.album = $Track.album }
    if ($Track.uri) { $converted.uri = $Track.uri }
    if ($Track.contextUri) { $converted.contextUri = $Track.contextUri }
    if ($Track.duration) { $converted.duration = $Track.duration }

    return [pscustomobject]$converted
}

if ($Probe -and $NoProbe) {
    throw "Pass only one of -Probe or -NoProbe."
}

$repoRoot = Get-RepoRoot
$resolvedSeedPath = Resolve-SeedPath -RepoRoot $repoRoot -Profile $Profile -SeedPath $SeedPath -PlaylistName $PlaylistName
$seed = Get-Content -LiteralPath $resolvedSeedPath -Raw -Encoding UTF8 | ConvertFrom-Json

$sourcePlaylist = $PlaylistName
if (-not $sourcePlaylist) {
    $sourcePlaylist = $seed.playlistName
}
if (-not $sourcePlaylist) {
    $sourcePlaylist = [System.IO.Path]::GetFileNameWithoutExtension($resolvedSeedPath)
}

$tracks = @()
foreach ($track in @($seed.tracks)) {
    $converted = Convert-SeedTrack -Track $track -SourcePlaylist $sourcePlaylist
    if ($converted) {
        $tracks += $converted
    }
}

if ($tracks.Count -le 0) {
    throw "Seed has no usable tracks: $resolvedSeedPath"
}

$fixture = [ordered]@{
    enabled = $true
    forceOffline = -not $NoForceOffline
    showMarkers = [bool]$ShowMarkers
    probe = [bool]$Probe -and -not $NoProbe
    deepElementPatch = [bool]$DeepElementPatch
    patchNetworkData = [bool]$PatchNetworkData
    renderSeededPlaylistFallback = $true
    playlistName = $sourcePlaylist
    playlistUri = $seed.playlistUri
    seedPath = $resolvedSeedPath
    seededAt = $seed.capturedAt
    builtAt = (Get-Date).ToUniversalTime().ToString('o')
    tracks = $tracks
}

$fixturePath = Join-Path $repoRoot "labs\spotx-lab\workspace\$Profile\offline-fixtures.json"
$fixtureDir = Split-Path -Parent $fixturePath
if (-not (Test-Path -LiteralPath $fixtureDir -PathType Container)) {
    New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null
}

$json = $fixture | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($fixturePath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))

Write-Host "Built offline fixture from seed:"
Write-Host "  Seed   : $resolvedSeedPath"
Write-Host "  Fixture: $fixturePath"
Write-Host "Tracks marked downloaded: $($tracks.Count)"
$tracks | Select-Object -First 12 title, uri, album | Format-Table -AutoSize
Write-Host ""
Write-Host "Offline launch:"
Write-Host "  .\scripts\Start-SpotXLab-OneClick.bat $Profile `"%APPDATA%\Spotify`" offline noprobe"
