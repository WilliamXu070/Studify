param(
    [string]$Profile = 'default',
    [string]$PlaylistName = 'Kale wll def like',
    [string]$PlaylistUri,
    [string]$SpotifySourcePath = "$env:APPDATA\Spotify",
    [int]$RemoteDebugPort = 9223,
    [int]$TimeoutSeconds = 90,
    [switch]$NoLaunch,
    [switch]$Repatch
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Net.Http

Add-Type @"
using System;
using System.Net.WebSockets;
using System.Text;
using System.Threading;

public static class SpotXLabSeedCdp {
    public static string Eval(string webSocketUrl, string expression) {
        using (var socket = new ClientWebSocket()) {
            socket.ConnectAsync(new Uri(webSocketUrl), CancellationToken.None).GetAwaiter().GetResult();
            var payload = "{\"id\":1,\"method\":\"Runtime.evaluate\",\"params\":{\"expression\":" + JsonString(expression) + ",\"returnByValue\":true,\"awaitPromise\":true}}";
            var bytes = Encoding.UTF8.GetBytes(payload);
            socket.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, CancellationToken.None).GetAwaiter().GetResult();

            var buffer = new byte[1024 * 1024];
            var builder = new StringBuilder();
            while (true) {
                var result = socket.ReceiveAsync(new ArraySegment<byte>(buffer), CancellationToken.None).GetAwaiter().GetResult();
                if (result.MessageType == WebSocketMessageType.Close) break;
                builder.Append(Encoding.UTF8.GetString(buffer, 0, result.Count));
                if (result.EndOfMessage) {
                    var text = builder.ToString();
                    if (text.Contains("\"id\":1")) return text;
                    builder.Clear();
                }
            }
        }
        return "";
    }

    private static string JsonString(string value) {
        var builder = new StringBuilder();
        builder.Append('"');
        foreach (var ch in value) {
            switch (ch) {
                case '\\': builder.Append("\\\\"); break;
                case '"': builder.Append("\\\""); break;
                case '\r': builder.Append("\\r"); break;
                case '\n': builder.Append("\\n"); break;
                case '\t': builder.Append("\\t"); break;
                default: builder.Append(ch); break;
            }
        }
        builder.Append('"');
        return builder.ToString();
    }
}
"@

function Get-RepoRoot {
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}

function Get-SeedSlug {
    param([string]$Value)
    $slug = ($Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if (-not $slug) { return 'playlist' }
    return $slug
}

function Get-CdpWebSocketUrl {
    param([int]$Port)
    $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/list" -TimeoutSec 5
    $target = @($targets | Where-Object {
        $_.type -eq 'page' -and $_.webSocketDebuggerUrl
    } | Select-Object -First 1)[0]
    if (-not $target) {
        throw "No Spotify DevTools page found on localhost:$Port."
    }
    return $target.webSocketDebuggerUrl
}

function Disable-OfflineFixtureForSeeding {
    param([string]$Profile)

    $workspaceProfile = Join-Path (Join-Path $repoRoot 'labs\spotx-lab\workspace') $Profile
    if (-not (Test-Path -LiteralPath $workspaceProfile -PathType Container)) {
        New-Item -ItemType Directory -Path $workspaceProfile -Force | Out-Null
    }

    $fixturePath = Join-Path $workspaceProfile 'offline-fixtures.json'
    $backupPath = Join-Path $workspaceProfile 'offline-fixtures.before-seed.json'
    if (Test-Path -LiteralPath $fixturePath -PathType Leaf) {
        Copy-Item -LiteralPath $fixturePath -Destination $backupPath -Force
    }

    $disabledFixture = [ordered]@{
        enabled = $false
        forceOffline = $false
        showMarkers = $false
        probe = $false
        deepElementPatch = $false
        patchNetworkData = $false
        tracks = @()
        disabledForOnlineSeedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    $json = $disabledFixture | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($fixturePath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-CdpJson {
    param(
        [string]$WebSocketUrl,
        [string]$Expression
    )
    $raw = [SpotXLabSeedCdp]::Eval($WebSocketUrl, $Expression)
    $response = $raw | ConvertFrom-Json
    if ($response.exceptionDetails) {
        $description = $null
        if ($response.exceptionDetails.exception -and $response.exceptionDetails.exception.description) {
            $description = $response.exceptionDetails.exception.description
        }
        if (-not $description) {
            $description = $response.exceptionDetails.text
        }
        throw $description
    }
    $value = $response.result.result.value
    if (-not $value) {
        return $response
    }
    return $value | ConvertFrom-Json
}

function Wait-Cdp {
    param(
        [int]$Port,
        [int]$TimeoutSeconds
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            return Get-CdpWebSocketUrl -Port $Port
        }
        catch {
            Start-Sleep -Milliseconds 750
        }
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for Spotify DevTools on localhost:$Port."
}

$repoRoot = Get-RepoRoot
$seedRoot = Join-Path $repoRoot "labs\spotx-lab\workspace\$Profile\seed-cache"
$null = New-Item -ItemType Directory -Path $seedRoot -Force

if (-not $NoLaunch) {
    Disable-OfflineFixtureForSeeding -Profile $Profile
    $launcher = Join-Path $PSScriptRoot 'Start-SpotXLab-OneClick.ps1'
    $launchArgs = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $launcher,
        '-Profile',
        $Profile,
        '-SpotifySourcePath',
        $SpotifySourcePath,
        '-Online',
        '-Probe',
        '-RemoteDebugPort',
        $RemoteDebugPort
    )
    if ($Repatch) {
        $launchArgs += '-Repatch'
    }
    Write-Host "Launching lab Spotify online for cache seeding..."
    & powershell.exe @launchArgs
}

$webSocketUrl = Wait-Cdp -Port $RemoteDebugPort -TimeoutSeconds $TimeoutSeconds

$playlistNameJson = ($PlaylistName | ConvertTo-Json -Compress)
$playlistUriValue = ''
if ($PlaylistUri) {
    $playlistUriValue = $PlaylistUri
}
$playlistUriJson = ($playlistUriValue | ConvertTo-Json -Compress)

$openExpression = @"
(() => {
  const playlistName = $playlistNameJson;
  const playlistUri = $playlistUriJson;
  const norm = (v) => String(v || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
  const wanted = norm(playlistName);
  const wantedId = (playlistUri.match(/playlist[:/]([^:?/#]+)/i) || [])[1] || '';
  const candidates = Array.from(document.querySelectorAll('[role="row"], [role="group"], a, button, [data-encore-id="listRow"]'));
  const match = candidates.find((el) => {
    const text = norm(el.innerText || el.textContent || '');
    const refs = [el.id || '', el.getAttribute('aria-labelledby') || '', el.getAttribute('href') || ''].join(' ');
    return (wanted && text.includes(wanted)) || (wantedId && refs.includes(wantedId));
  });
  if (!match) {
    return JSON.stringify({ opened: false, reason: 'playlist-not-found', visibleText: document.body.innerText.slice(0, 1200) });
  }
  match.scrollIntoView({ block: 'center' });
  const target = match.closest('[role="row"]') || match.closest('[role="group"]') || match;
  for (const item of [target, match]) {
    item.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, cancelable: true, pointerType: 'mouse', button: 0 }));
    item.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, button: 0 }));
    item.dispatchEvent(new PointerEvent('pointerup', { bubbles: true, cancelable: true, pointerType: 'mouse', button: 0 }));
    item.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, button: 0 }));
    item.click();
  }
  return JSON.stringify({ opened: true, clickedText: (target.innerText || target.textContent || '').trim().slice(0, 200) });
})()
"@

$openDeadline = (Get-Date).AddSeconds($TimeoutSeconds)
$openResult = $null
do {
    $openResult = Invoke-CdpJson -WebSocketUrl $webSocketUrl -Expression $openExpression
    if ($openResult.opened) {
        break
    }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $openDeadline)

if (-not $openResult -or -not $openResult.opened) {
    $reason = if ($openResult) { $openResult.reason } else { 'no-result' }
    throw "Could not open playlist '$PlaylistName': $reason"
}

Write-Host "Opened playlist candidate: $($openResult.clickedText)"

$captureExpression = @"
(async () => {
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const getFiber = (el) => {
    const key = Object.getOwnPropertyNames(el).find((name) => name.startsWith('__reactFiber$'));
    return key ? el[key] : null;
  };
  const getTrackProps = (fiber) => {
    let node = fiber;
    for (let i = 0; node && i < 32; i += 1, node = node.return) {
      const props = node.memoizedProps || node.pendingProps;
      if (props && typeof props.uri === 'string' && props.uri.startsWith('spotify:track:')) {
        return props;
      }
    }
    return null;
  };
  const parseRow = (row, index) => {
    const props = getTrackProps(getFiber(row)) || {};
    const lines = (row.innerText || row.textContent || '').split(/\n+/).map((line) => line.trim()).filter(Boolean);
    const numericFirst = lines[0] && /^\d+$/.test(lines[0]);
    const rowNumber = numericFirst ? Number(lines[0]) : index + 1;
    const offset = numericFirst ? 1 : 0;
    const hasExplicitMarker = lines[offset + 1] === 'E';
    const artistLine = hasExplicitMarker ? lines[offset + 2] : lines[offset + 1];
    const albumLine = hasExplicitMarker ? lines[offset + 3] : lines[offset + 2];
    return {
      index: rowNumber,
      uri: props.uri || '',
      title: props.name || props.title || lines[offset] || '',
      artists: Array.isArray(props.artists) ? props.artists.map((artist) => artist.name || artist.title || artist).filter(Boolean) : ((artistLine || '').split(',').map((artist) => artist.trim()).filter(Boolean)),
      album: props.albumName || props.album || albumLine || '',
      duration: lines[lines.length - 1] || '',
      contextUri: props.contextUri || '',
      isPlayable: props.isPlayable,
      isActive: props.isActive,
      isLocked: props.isLocked,
      keys: Object.keys(props).filter((key) => /uri|play|avail|download|offline|lock|name|title|artist|album/i.test(key)).slice(0, 80)
    };
  };
  const scrollChild = document.querySelector('.main-view-container__scroll-node-child');
  const scrollHosts = [
    scrollChild && scrollChild.parentElement,
    ...Array.from(document.querySelectorAll('[data-overlayscrollbars-viewport], main, #main-view')),
    ...Array.from(document.querySelectorAll('*')).filter((el) => el.scrollHeight > el.clientHeight + 120),
  ].filter(Boolean);
  const host = scrollHosts.find((el) => el.scrollHeight > el.clientHeight && typeof el.scrollTop === 'number');
  const captured = new Map();
  let staleRounds = 0;
  if (host) host.scrollTop = 0;
  await sleep(900);
  for (let i = 0; i < 80; i += 1) {
    const rows = document.querySelectorAll('[data-testid="tracklist-row"]');
    const before = captured.size;
    Array.from(rows).map(parseRow).filter((track) => track.uri || track.title).forEach((track) => {
      captured.set(track.uri || (String(track.index) + ':' + String(track.title || '')), track);
    });
    if (captured.size === before) {
      staleRounds += 1;
    } else {
      staleRounds = 0;
    }
    if (!host || host.scrollTop + host.clientHeight >= host.scrollHeight - 8) {
      if (staleRounds >= 2) break;
    } else {
      host.scrollTop = Math.min(host.scrollHeight, host.scrollTop + host.clientHeight * 0.85);
      host.dispatchEvent(new Event('scroll', { bubbles: true }));
    }
    if (staleRounds >= 4) break;
    await sleep(250);
  }
  const tracks = Array.from(captured.values()).sort((a, b) => a.index - b.index);
  return JSON.stringify({
    capturedAt: new Date().toISOString(),
    href: location.href,
    title: document.title,
    playlistName: $playlistNameJson,
    playlistUri: $playlistUriJson,
    trackCount: tracks.length,
    tracks,
    bodyText: document.body.innerText.slice(0, 1000)
  });
})()
"@

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$seed = $null
do {
    $seed = Invoke-CdpJson -WebSocketUrl $webSocketUrl -Expression $captureExpression
    if ($seed.trackCount -gt 0) {
        break
    }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)

if (-not $seed -or $seed.trackCount -le 0) {
    throw "Timed out waiting for track rows for '$PlaylistName'."
}

$slug = Get-SeedSlug -Value $PlaylistName
$seedPath = Join-Path $seedRoot "$slug.json"
$seed | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $seedPath -Encoding UTF8

Write-Host "Seeded playlist cache:"
Write-Host "  $seedPath"
Write-Host "Tracks captured: $($seed.trackCount)"
$seed.tracks | Select-Object -First 10 index, uri, title, album, isPlayable | Format-Table -AutoSize
