# Studify Probe Flow

This flow is for discovering the real row-tap/playability/playback path. Probe
mode is observe-only: it does not force offline availability, does not return
fake playability, and does not start Studify local playback from row taps.

## Enable Probe Mode

On the device/LiveContainer app documents folder, create:

```text
Documents/StudifyLibrary/probe-mode.txt
```

with:

```text
on
```

If needed, also point the overlay at the Mac signal server:

```text
Documents/StudifyLibrary/server-url.txt
```

example:

```text
http://192.168.1.25:8787
```

Then restart the app so the overlay reloads.

## Run Server

On the Mac:

```sh
node Tools/StudifySignalServer/server.js
```

Open the printed dashboard URL. Probe events appear in the `Probe Stream`
section.

## Test Scenarios

Deploy/restart with a clean probe log:

```sh
Tools/StudifyLiveContainer/restart-test.sh --no-build
```

Run these one at a time:

```text
1. Online playlist row tap.
2. Offline unavailable playlist row tap.
3. Playlist download/offline button tap.
4. Mini-player play/pause/next/previous controls.
```

Each row tap starts a fresh 90 second probe session. Events include a monotonic
`#sequence` in the dashboard so the path can be reconstructed in order.

Immediately after the iPhone shows the prompt/playback result, pull and
summarize the phone-side logs:

```sh
Tools/StudifyLiveContainer/pull-probe-report.sh
```

The report calls out whether the trace saw the Spotify free-tier/Premium gate,
whether row/tap probes fired, and whether any native method candidates returned.

## Events To Look For

```text
probe-session started
native-playback press-path
native-method return
uicontrol sendAction
uiapplication sendAction
offline-pathway class-found
```

The most important fields are in `native-playback press-path`:

```text
uriCandidates
slots
selectors
nearestControl
viewChain
responderChain
rowResponderChain
gestures
```

`uriCandidates` is the key result. A useful trace should show a stable
`spotify:track:...` URI from a row/model/viewModel object, not just title and
artist text from labels.

## Interpreting Results

If `uriCandidates` is `none`, inspect `slots`, `selectors`, and responder chains
to decide which object needs deeper probing.

If `native-method return` never appears after a row tap, the current candidate
availability selectors are not on the active path for that scenario.

If only `uicontrol`/`uiapplication` events appear, the interaction is still being
observed from the UI shell and has not reached a confirmed Spotify row/playback
object yet.

## Build

```sh
./build-studify-overlay.sh
```

Latest outputs:

```text
Outputs/StudifyOverlay/LiveContainer/StudifyOverlay/
Outputs/StudifyOverlay/StudifyOverlay-LiveContainer.zip
```
