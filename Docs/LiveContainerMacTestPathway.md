# LiveContainer Mac Test Pathway

This is the repeat loop for testing the Studify overlay tweak on an iPhone through LiveContainer without reinstalling the IPA every time.

## Goal

Use the base Spotify IPA already imported into LiveContainer, then update only:

- `StudifyOverlay.dylib`
- `Orion.framework`
- optional `test.mp3`

The app process must be restarted after every dylib copy. A running iOS process does not reload a replaced dylib.

## Current Device Paths

These are the values used in the current setup:

```sh
DEVICE_ID="18A702BC-2DAA-5733-ACD8-079DEF96CC95"
LIVECONTAINER_BUNDLE_ID="com.kdt.livecontainer.25P4CVCPW5"
SPOTIFY_VIRTUAL_CONTAINER="Documents/Data/Application/6F12DF95-8B98-4013-A346-198A838334A1"
TWEAK_FOLDER="Documents/Tweaks/StudifySpotify"
TWEAK_FOLDER_ALIASES="Documents/Tweaks/StudifyOverlay"
```

The deploy script copies the overlay into both tweak folders by default because
older LiveContainer setup notes used `StudifyOverlay` as the app-specific folder
name. This keeps the phone-side setting from silently loading a stale folder.

This pathway applies only to Spotify launched from inside LiveContainer. The
directly installed bundle `com.spotify.client.25P4CVCPW5` has its own app data
container and does not consume LiveContainer's `Documents/Tweaks/...` payload.
For that direct app, build `Outputs/IPAS/StudifyFull-9.1.28-25P4CVCPW5.ipa`
with `./build-studify-full-ipa.sh` and install that IPA through the normal app
installation path. Then use
`Tools/StudifyLiveContainer/standalone-spotify-test.sh` for direct-app config
and log pulls.

The local audio proof file lives inside LiveContainer's virtual Spotify container:

```text
Documents/Data/Application/6F12DF95-8B98-4013-A346-198A838334A1/Documents/StudifyLibrary/audio/test.mp3
```

## Fast Path

From the repo root:

```sh
PROBE_MODE=0 COPY_SERVER_URL=0 STATE_BRIDGE=0 ./Tools/StudifyLiveContainer/restart-test.sh --no-build
```

That script:

1. Builds `StudifyOverlay`.
2. Runs the overlay artifact check even in `--no-build` mode.
3. Refuses to deploy if the dylib does not contain the stable offline-spoof safety marker.
4. Terminates LiveContainer before replacing the tweak files.
5. Copies `Outputs/StudifyOverlay/LiveContainer/StudifyOverlay/StudifyOverlay.dylib` into the LiveContainer tweak folder.
6. Copies `Outputs/StudifyOverlay/LiveContainer/StudifyOverlay/Orion.framework` into the same tweak folder.
7. Copies the dylib, `Orion.framework/Orion`, and `Orion.framework/Info.plist` back from the phone.
8. Compares the Mach-O payload hashes for binaries before the embedded code-signature region, because LiveContainer/iOS may re-sign copied binaries in-place.
9. Compares the exact SHA-256 hash for `Orion.framework/Info.plist`.
10. Verifies the copied phone dylib still contains the stable offline-spoof safety marker.
11. Copies `/private/tmp/studify-test.mp3` into the virtual Spotify Documents folder if that MP3 exists.
12. Writes `probe-mode.txt`, `probe-upload.txt`, and `state-bridge.txt` so stale phone state cannot re-enable the startup-crash bridge.
13. Relaunches LiveContainer.
14. Pulls `tmp/studify_overlay_debug.log` back to `/private/tmp/studify_overlay_debug_latest.log`.

The script should stop before launch if a stale or corrupted phone-side copy is detected.

## Manual Path

### 1. Build the overlay

```sh
./build-studify-overlay.sh
Tests/StudifyDiagnostics/overlay-artifact-check.sh
```

Expected result:

```text
overlay-artifact-check: ok
```

### 2. Copy the new dylib to LiveContainer

Terminate LiveContainer before copying so iOS cannot keep using an old loaded dylib while files are being replaced.

```sh
xcrun devicectl device copy to \
  --device 18A702BC-2DAA-5733-ACD8-079DEF96CC95 \
  --domain-type appDataContainer \
  --domain-identifier com.kdt.livecontainer.25P4CVCPW5 \
  --source Outputs/StudifyOverlay/LiveContainer/StudifyOverlay/StudifyOverlay.dylib \
  --destination Documents/Tweaks/StudifySpotify/StudifyOverlay.dylib \
  --json-output /private/tmp/studify-copy-dylib.json
```

This updates the tweak. It does not affect the base IPA.

### 3. Copy Orion.framework to LiveContainer

```sh
xcrun devicectl device copy to \
  --device 18A702BC-2DAA-5733-ACD8-079DEF96CC95 \
  --domain-type appDataContainer \
  --domain-identifier com.kdt.livecontainer.25P4CVCPW5 \
  --source Outputs/StudifyOverlay/LiveContainer/StudifyOverlay/Orion.framework \
  --destination Documents/Tweaks/StudifySpotify/Orion.framework \
  --json-output /private/tmp/studify-copy-orion.json
```

The tweak dylib depends on `@loader_path/Orion.framework/Orion`, so `Orion.framework` must sit beside `StudifyOverlay.dylib` in the same LiveContainer tweak folder.

### 4. Verify the phone copy

Copy the deployed files back and compare hashes:

```sh
xcrun devicectl device copy from \
  --device 18A702BC-2DAA-5733-ACD8-079DEF96CC95 \
  --domain-type appDataContainer \
  --domain-identifier com.kdt.livecontainer.25P4CVCPW5 \
  --source Documents/Tweaks/StudifySpotify/StudifyOverlay.dylib \
  --destination /private/tmp/studify-phone-StudifyOverlay.dylib

xcrun devicectl device copy from \
  --device 18A702BC-2DAA-5733-ACD8-079DEF96CC95 \
  --domain-type appDataContainer \
  --domain-identifier com.kdt.livecontainer.25P4CVCPW5 \
  --source Documents/Tweaks/StudifySpotify/Orion.framework/Orion \
  --destination /private/tmp/studify-phone-Orion

shasum -a 256 \
  Outputs/StudifyOverlay/LiveContainer/StudifyOverlay/StudifyOverlay.dylib \
  /private/tmp/studify-phone-StudifyOverlay.dylib \
  Outputs/StudifyOverlay/LiveContainer/StudifyOverlay/Orion.framework/Orion \
  /private/tmp/studify-phone-Orion
```

For Mach-O binaries, a full-file hash may differ after copying because LiveContainer/iOS can re-sign the file. Compare the payload before `LC_CODE_SIGNATURE`; the deploy script does this automatically.

If the payload hashes do not match, do not launch LiveContainer.

Also verify the stable safety marker exists:

```sh
strings /private/tmp/studify-phone-StudifyOverlay.dylib | grep 'Offline playable spoof groups skipped'
```

### 5. Copy the test MP3 if needed

Preferred location:

```sh
xcrun devicectl device copy to \
  --device 18A702BC-2DAA-5733-ACD8-079DEF96CC95 \
  --domain-type appDataContainer \
  --domain-identifier com.kdt.livecontainer.25P4CVCPW5 \
  --source /private/tmp/studify-test.mp3 \
  --destination Documents/Data/Application/6F12DF95-8B98-4013-A346-198A838334A1/Documents/StudifyLibrary/audio/test.mp3 \
  --json-output /private/tmp/studify-copy-test-mp3.json
```

Fallback location:

```sh
xcrun devicectl device copy to \
  --device 18A702BC-2DAA-5733-ACD8-079DEF96CC95 \
  --domain-type appDataContainer \
  --domain-identifier com.kdt.livecontainer.25P4CVCPW5 \
  --source /private/tmp/studify-test.mp3 \
  --destination Documents/Data/Application/6F12DF95-8B98-4013-A346-198A838334A1/Documents/test.mp3 \
  --json-output /private/tmp/studify-copy-test-mp3-fallback.json
```

### 6. Find LiveContainer PID

```sh
xcrun devicectl device info processes \
  --device 18A702BC-2DAA-5733-ACD8-079DEF96CC95 \
  --json-output /private/tmp/studify-processes.json
```

In the printed table, find the line ending with:

```text
LiveContainer.app/LiveContainer
```

The number at the start of that line is the PID.

### 7. Terminate LiveContainer

Replace `PID_HERE` with the PID from step 4:

```sh
xcrun devicectl device process terminate \
  --device 18A702BC-2DAA-5733-ACD8-079DEF96CC95 \
  --pid PID_HERE \
  --json-output /private/tmp/studify-terminate-livecontainer.json
```

Why this matters: replacing a dylib file is not enough. The old dylib stays loaded until the process exits.

### 8. Relaunch LiveContainer

Keep the iPhone unlocked before running this:

```sh
xcrun devicectl device process launch \
  --device 18A702BC-2DAA-5733-ACD8-079DEF96CC95 \
  com.kdt.livecontainer.25P4CVCPW5 \
  --activate \
  --json-output /private/tmp/studify-launch-livecontainer.json
```

If this fails with `Locked`, unlock the phone and run it again.

### 9. Open Spotify inside LiveContainer

On the iPhone:

1. Open LiveContainer if it is not already foregrounded.
2. Tap the imported Spotify app.
3. Go to a real playlist.
4. Tap an actual song row.

Expected phase 2 behavior:

- No Studify green overlay.
- No autoplay at launch.
- Playlist rows still open playlists.
- Song rows can trigger local `test.mp3` playback.
- Spotify's own play/pause/next/previous controls are observed by the bridge.

### 10. Pull the overlay log

```sh
xcrun devicectl device copy from \
  --device 18A702BC-2DAA-5733-ACD8-079DEF96CC95 \
  --domain-type appDataContainer \
  --domain-identifier com.kdt.livecontainer.25P4CVCPW5 \
  --source tmp/studify_overlay_debug.log \
  --destination /private/tmp/studify_overlay_debug_latest.log \
  --json-output /private/tmp/studify-pull-log.json
```

Then inspect:

```sh
tail -n 80 /private/tmp/studify_overlay_debug_latest.log
```

Good signs:

```text
Offline playable spoof groups skipped; runtime probe must confirm exact selectors before activation
Studify native playback bridge installed
Studify local audio ready at ...
Native playback bridge started title=...
Studify local audio playing ...
```

Bad signs:

```text
STUDIFY FAKE
Studify launch audio probe
Missing Documents/StudifyLibrary/audio/test.mp3
```

Those mean the old dylib is still loaded, autoplay code is still present, or the MP3 is missing from the virtual Spotify container.

## Mental Model

LiveContainer has two relevant storage areas:

- `Documents/Tweaks/StudifySpotify` or `Documents/Tweaks/StudifyOverlay`: where LiveContainer loads tweak dylibs/frameworks from. For Studify, the active app-specific folder must contain `StudifyOverlay.dylib` and `Orion.framework`.
- `Documents/Data/Application/<uuid>`: the virtual app container Spotify sees as its home directory.

The tweak file belongs in the tweak folder. Audio files belong in Spotify's virtual app container.

After copying the tweak, always terminate and relaunch LiveContainer. After copying only the MP3, a restart is not required because the player checks the file path at runtime.
