# Studify Probe Flow

This flow is for discovering the real row-tap/playability/playback path. Probe
mode is observe-only: it does not force offline availability, does not return
fake playability, and does not start Studify local playback from row taps.

## Enable Probe Mode

`Tools/StudifyLiveContainer/restart-test.sh` now enables probe mode by copying
this file into the LiveContainer virtual Spotify container:

```text
Documents/StudifyLibrary/probe-mode.txt
```

with:

```text
on
```

Probe mode writes phone-local logs only. It does not need the Mac signal server
or `server-url.txt`. The restart script also writes:

```text
Documents/StudifyLibrary/probe-upload.txt
```

with:

```text
off
```

To skip this automatic probe-mode copy for a non-probe run:

```sh
PROBE_MODE=0 Tools/StudifyLiveContainer/restart-test.sh
```

With `PROBE_MODE=0`, the restart script writes `probe-mode.txt` with `off`
instead of merely skipping the copy, so stale probe-mode files from earlier
runs cannot keep the observe-only row-tap path active.

## Test Scenarios

Deploy/restart with a clean probe log:

```sh
Tools/StudifyLiveContainer/restart-test.sh --no-build
```

By default, overlay rebuilds use the clean Eevee base IPA at:

```text
/Users/williamxu/Downloads/EeveeSpotify-6.6.2-9.1.28.ipa
```

Override with `BASE_IPA=/path/to/base.ipa` if needed.

Run these one at a time:

```text
1. Online playlist row tap.
2. Offline unavailable playlist row tap.
3. Playlist download/offline button tap.
4. Mini-player play/pause/next/previous controls.
```

Each row tap starts a fresh 90 second probe session. Events include a monotonic
`sequence` in the phone-side JSONL so the path can be reconstructed in order.

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
premium-gate
prompt
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
