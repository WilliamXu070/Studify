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
PROBE_MODE=0 COPY_SERVER_URL=0 STATE_BRIDGE=0 Tools/StudifyLiveContainer/restart-test.sh --no-build
```

If CoreDevice process listing flakes, the script falls back to
`pymobiledevice3 processes pgrep` before copying. If CoreDevice copy itself
flakes, manual copy/verify is still valid as long as LiveContainer and the
virtual Spotify process are terminated before replacing the dylib.

If testing the direct installed Spotify bundle
`com.spotify.client.25P4CVCPW5`, do not expect LiveContainer logs or tweak
folders to apply. Build the standalone artifact instead:

```sh
./build-studify-full-ipa.sh /Users/williamxu/Downloads/EeveeSpotify-6.6.2-9.1.28.ipa
```

That produces `Outputs/IPAS/StudifyFull-9.1.28-25P4CVCPW5.ipa` with the same
recovered offline seed behavior embedded in the app.

After installing or launching the direct bundle, use:

```sh
PROBE_MODE=0 STATE_BRIDGE=0 Tools/StudifyLiveContainer/standalone-spotify-test.sh
```

This writes the same `Documents/StudifyLibrary` state files into the standalone
Spotify app data container, clears `tmp/studify_overlay_debug.log`, launches the
direct app, and pulls logs to `/private/tmp/studify_standalone_*`.

After manually tapping a song row in the direct app, do not rerun the setup mode
because it clears logs. Pull evidence with:

```sh
Tools/StudifyLiveContainer/standalone-spotify-test.sh --pull-only
```

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
  -> track(from:) extracts the pressed row's visible title/artist, or falls back to the fixed seed if row text extraction is weak
  -> start(track:row:source: "passive row tap")
  -> source == "passive row tap" maps the pressed row to Gimme Love
  -> setFakeTrack(title:artist:uri:) publishes the seeded Spotify state
  -> local test.mp3 plays if present, otherwise seeded silent simulation returns playing=true
  -> row and mini-player visuals are updated
```

This means any offline playlist song press can initiate the same known-good
`Gimme Love` seed. The original pressed title/artist should still be logged as
`sourceTitle` / `sourceArtist` for debugging.

Spotify playback controls are also treated as explicit user playback intents.
If a play/pause/next/previous button arrives before a row press has established
`currentTrack`, the controller seeds `Gimme Love` first, then runs the control
intent against that fake current track. This recovers the earlier probe-seeding
behavior without publishing fake state just from opening Spotify.

When `state-bridge.txt` is `off`, direct mini-player mutation is enabled by
default as the safe visual fallback. When the state bridge is explicitly enabled
for debugging, state-first mode remains the default unless
`StudifyAllowDirectMiniPlayerMutation` is set.

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
seedOfflinePlaybackIntentIfNeeded(reason:)
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

If the first user intent is a Spotify playback control instead of a row, expect:

```text
Native playback bridge seeded offline user intent title=Gimme Love artist=Vista Kicks uri=spotify:track:3CUovld1O1HdAOrkgMlvNx reason=passive spotify control ...
Passive playback control probe intent=...
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
Tools/StudifyLiveContainer/verify-offline-seed-log.js
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

The verifier should pass only when logs prove all of these happened:

```text
overlay loaded
offline row/control intent was captured
Gimme Love / Vista Kicks was published
spotify:track:3CUovld1O1HdAOrkgMlvNx was used
playback state became playing
fake state was reasserted or held after the tap
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
