# Studify Overlay Architecture

Studify should be developed as a separate overlay tweak loaded on top of a base Eevee Spotify IPA.

## Layers

1. Base Spotify app
   - A clean Spotify IPA is ideal.
   - A stock Eevee IPA can also be used as the base during early experiments.

2. Base Eevee tweak
   - Provides the existing premium/lyrics/settings behavior.
   - Should stay as close to upstream Eevee as possible.

3. Studify overlay tweak
   - Lives in `Overlay/StudifyOverlay`.
   - Contains only Studify-specific behavior: download button interception, server signaling, local playback experiments, and diagnostics.
   - Builds as `StudifyOverlay.dylib`.

## Why This Shape

Keeping Studify separate means a broken Studify experiment can be removed by disabling the app-specific LiveContainer tweak folder instead of rebuilding the full Eevee IPA.

It also avoids editing upstream Eevee files every time the download/server logic changes.

## Build

```bash
./build-studify-overlay.sh
```

Outputs:

```text
Outputs/StudifyOverlay/StudifyOverlayLatest.deb
Outputs/StudifyOverlay/LiveContainer/StudifyOverlay/
Outputs/StudifyOverlay/StudifyOverlay-LiveContainer.zip
```

For the separately installed Spotify bundle, build a full injected IPA instead:

```bash
./build-studify-full-ipa.sh /Users/williamxu/Downloads/EeveeSpotify-6.6.2-9.1.28.ipa
```

Default output:

```text
Outputs/IPAS/StudifyFull-9.1.28-25P4CVCPW5.ipa
```

The full IPA helper uses the latest `StudifyOverlayLatest.deb`, forces the
current standalone bundle id `com.spotify.client.25P4CVCPW5`, and verifies that
the embedded overlay contains the recovered offline seed marker.

## LiveContainer Use

Recommended setup:

1. Import a base Eevee Spotify IPA into LiveContainer.
2. Keep it private.
3. Open `Tweaks`.
4. Create an app-specific folder named `StudifyOverlay`.
5. Import the contents of `Outputs/StudifyOverlay/LiveContainer/StudifyOverlay`.
6. Long-press the Spotify app in LiveContainer.
7. Open `Settings`.
8. Set `Tweak Folder` to `StudifyOverlay`.
9. Launch Spotify.

The Mac deploy helper also mirrors the same payload into
`Documents/Tweaks/StudifySpotify` for newer runbooks. The active LiveContainer
setting may use either folder as long as the folder contains the latest
`StudifyOverlay.dylib` and `Orion.framework`.

Expected banners:

```text
STUDIFY OVERLAY LOADED
STUDIFY OVERLAY UICONTROL ACTIVE
STUDIFY OVERLAY HOOK FIRED
STUDIFY OVERLAY POST STARTED
STUDIFY OVERLAY SERVER ACCEPTED
```

## Important Rule

Do not load the Studify overlay on top of a Studify-modified Eevee IPA unless you intentionally want duplicate hooks.

The clean target stack is:

```text
Stock Eevee IPA + StudifyOverlay tweak folder
```

not:

```text
Studify-patched Eevee IPA + StudifyOverlay tweak folder
```

The direct iOS app bundle `com.spotify.client.25P4CVCPW5` is a different
deployment shape from LiveContainer's inner Spotify. Launching that bundle does
not read `Documents/Tweaks/...` from LiveContainer's data container; use the
full IPA artifact when testing the direct app.

For direct-app diagnostics, use:

```bash
PROBE_MODE=0 STATE_BRIDGE=0 Tools/StudifyLiveContainer/standalone-spotify-test.sh
```

It targets the standalone app data container, not LiveContainer's virtual
container, and pulls `/tmp/studify_standalone_overlay_debug_latest.log` plus
`/tmp/studify_standalone_probe_events_latest.jsonl`.

After a manual row tap in the direct app, use `--pull-only` so the helper does
not clear the evidence logs before copying them.

## Server

The overlay currently posts to:

```text
http://172.18.147.149:8787/v1/jobs/playlist
```

Start the local server before testing:

```bash
node Tools/StudifySignalServer/server.js
```
