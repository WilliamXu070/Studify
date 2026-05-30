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

## Server

The overlay currently posts to:

```text
http://172.18.147.149:8787/v1/jobs/playlist
```

Start the local server before testing:

```bash
node Tools/StudifySignalServer/server.js
```
