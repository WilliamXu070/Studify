# Gimme Love Offline Simulation

Date: 2026-05-30

This documents the working offline simulation path that made Spotify show/play
the recovered `Gimme Love` state without a server connection.

## Verified Seed

Use this fixed track as the simulation payload:

```text
title:  Gimme Love
artist: Vista Kicks
uri:    spotify:track:3CUovld1O1HdAOrkgMlvNx
```

The URI came from the successful probe run:

```text
00:20:26-00:20:28 user hit Gimme Love / Vista Kicks in the playlist
00:20:37 state bridge confirmed Gimme Love / Vista Kicks
          spotify:track:3CUovld1O1HdAOrkgMlvNx
```

## Runtime Mode

Run this as an offline simulation, not as probe mode.

Required phone-side state:

```text
Documents/StudifyLibrary/probe-mode.txt  = off
Documents/StudifyLibrary/probe-upload.txt = off
```

Do not copy or require `server-url.txt`. The flow is local to Spotify inside
LiveContainer.

Deploy with:

```sh
PROBE_MODE=0 COPY_SERVER_URL=0 Tools/StudifyLiveContainer/restart-test.sh --no-build
```

If CoreDevice process listing flakes, the script falls back to
`pymobiledevice3 processes pgrep` before copying. If CoreDevice copy itself
flakes, manual copy/verify is still valid as long as LiveContainer and the
virtual Spotify process are terminated before replacing the dylib.

## Current Click Flow

The simulation should be triggered by a user pressing a song row while Spotify
is in offline mode. Opening Spotify or merely detecting the offline page should
not publish the fake current track.

Expected path:

```text
User taps playlist song row
  -> window tap recognizer fires
  -> cachedOfflineModeActive must be true
  -> trackRow(startingAt:) finds a Spotify playlist row
  -> track(from:) extracts the pressed row's visible title/artist
  -> start(track:row:source: "passive row tap")
  -> source == "passive row tap" maps the pressed row to Gimme Love
  -> setFakeTrack(title:artist:uri:) publishes the seeded Spotify state
  -> local test.mp3 plays if present, otherwise seeded silent simulation returns playing=true
  -> row and mini-player visuals are updated
```

This means any offline playlist song press can initiate the same known-good
`Gimme Love` seed. The original pressed title/artist should still be logged as
`sourceTitle` / `sourceArtist` for debugging.

## Key Code Points

Main file:

```text
Overlay/StudifyOverlay/Sources/StudifyOverlay/StudifyFakePlaybackController.swift
```

Important pieces:

```text
studifySeededGimmeLoveTrack
studifySeededGimmeLoveURI
handleWindowTap(_:)
start(track:row:source:)
simulatedTrack(for:source:)
publishFakeSpotifyTrack(_:reason:)
startLocalAudioOrSeededSilence(for:)
```

State bridge:

```text
Overlay/StudifyOverlay/Sources/StudifyOverlay/StudifySpotifyStateBridge.x.swift
```

The state bridge should prefer the fake track in `bestSpotifyStateSummary()` so
logs and UI nudges report:

```text
title=Gimme Love artist=Vista Kicks uri=spotify:track:3CUovld1O1HdAOrkgMlvNx
```

## Expected Logs

On a successful offline row tap, `tmp/studify_overlay_debug.log` should include:

```text
Studify offline simulation mode active=true
Native playback bridge using seeded track for offline row press sourceTitle=...
Spotify state bridge fakeTrack set title=Gimme Love artist=Vista Kicks uri=spotify:track:3CUovld1O1HdAOrkgMlvNx reason=passive row tap
Native playback bridge published fake Spotify state title=Gimme Love artist=Vista Kicks uri=spotify:track:3CUovld1O1HdAOrkgMlvNx reason=passive row tap
Native playback bridge started title=Gimme Love artist=Vista Kicks source=passive row tap isPlaying=true
Native playback bridge reasserted fake Spotify state title=Gimme Love artist=Vista Kicks delay=...
```

If `Documents/StudifyLibrary/audio/test.mp3` exists, AVAudioPlayer should play
that file. If it is missing, the seeded Gimme Love path can still simulate
`isPlaying=true` for state/visual testing.

The delayed reassert lines matter. A row press lets Spotify's own tap/action
handler run at nearly the same time as Studify's gesture recognizer. Re-publishing
the same fake title/artist/URI shortly after the tap keeps the recovered
`Gimme Love` state from being overwritten by Spotify's delayed repaint.

## Manual Verification

After deploy:

```sh
Tools/StudifyLiveContainer/pull-probe-report.sh
```

For this non-probe simulation, the most useful file is:

```text
tmp/studify_overlay_debug.log
```

Confirm:

```text
probe mode disabled
no server upload URL needed
seeded URI is present in the dylib
state bridge fakeTrack log contains Gimme Love / Vista Kicks
```

## Why This Shape Worked

The earlier probe proved Spotify could expose and render the real current track
through `SPTPlayerTrackImplementation` selectors:

```text
trackTitle
artistName
URI
metadata
```

So the simulation does not need to solve the full playlist row URI problem yet.
It only needs to publish a known-good fake current track at the moment the user
performs an offline song-play intent.

The row tap is the correct trigger because it avoids fake state appearing just
from opening Spotify or scanning the page.

## Next Real Implementation

Replace the fixed Gimme Love seed with a local manifest lookup:

```text
pressed row title/artist or row URI
  -> manifest lookup
  -> spotifyTrackURI + local file path
  -> setFakeTrack(real title, real artist, real URI)
  -> play local file
```

Until the row/model URI path is discovered, this fixed seed is the smallest
working proof that the offline row-press intent can drive Spotify's UI state.
