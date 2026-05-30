#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

DYLIB="Outputs/StudifyOverlay/LiveContainer/StudifyOverlay/StudifyOverlay.dylib"
ZIP="Outputs/StudifyOverlay/StudifyOverlay-LiveContainer.zip"

fail() {
  echo "overlay-artifact-check: FAIL: $*" >&2
  exit 1
}

[ -f "$DYLIB" ] || fail "missing dylib: $DYLIB"
[ -f "$ZIP" ] || fail "missing zip: $ZIP"

STRINGS="$(strings "$DYLIB")"

grep -Fq "STUDIFY OVERLAY HOOK FIRED" <<< "$STRINGS" || fail "missing hook-fired marker"
grep -Fq "STUDIFY OVERLAY POST STARTED" <<< "$STRINGS" || fail "missing POST marker"
grep -Fq "sendAction:to:forEvent:" <<< "$STRINGS" || fail "missing UIControl selector"
grep -Fq "Studify native playback bridge installed" <<< "$STRINGS" || fail "missing native bridge install marker"
grep -Fq "Native playback bridge started" <<< "$STRINGS" || fail "missing native bridge playback marker"
grep -Fq "Native playback bridge using seeded track for offline row press" <<< "$STRINGS" || fail "missing row-press seed marker"
grep -Fq "Native playback bridge reasserted fake Spotify state" <<< "$STRINGS" || fail "missing row-press reassert marker"
grep -Fq "spotify:track:3CUovld1O1HdAOrkgMlvNx" <<< "$STRINGS" || fail "missing seeded Gimme Love URI"
grep -Fq "Fast Spotify row visual applied offline-only" <<< "$STRINGS" || fail "missing fast Spotify row visual marker"
grep -Fq "Studify.FastPlayIndicatorBar" <<< "$STRINGS" || fail "missing fast play indicator animation marker"
grep -Fq "Native mini player visual applied offline-only" <<< "$STRINGS" || fail "missing native mini-player visual marker"
grep -Fq "Passive playback control probe" <<< "$STRINGS" || fail "missing passive playback-control probe marker"
grep -Fq "Passive Spotify playback state probe" <<< "$STRINGS" || fail "missing passive Spotify state probe marker"
grep -Fq "Studify probe mode disabled" <<< "$STRINGS" || fail "missing lightweight/probe-disabled marker"
grep -Fq "Spotify state bridge skipped; opt-in debug bridge disabled" <<< "$STRINGS" || fail "missing state-bridge opt-in safety marker"
grep -Fq "Passive press path probe" <<< "$STRINGS" || fail "missing press path probe marker"
grep -Fq "Deep Spotify row probe" <<< "$STRINGS" || fail "missing deep Spotify row probe marker"
grep -Fq "Deep Spotify row diff" <<< "$STRINGS" || fail "missing deep Spotify row diff marker"
! grep -Fq "Embedded row playing indicator" <<< "$STRINGS" || fail "embedded row indicator must not ship in passive probe build"
! grep -Fq "Embedded mini player mirror" <<< "$STRINGS" || fail "embedded mini-player mirror must not ship in passive probe build"
grep -Fq "STUDIFY AUDIO PLAYING" <<< "$STRINGS" || fail "missing audio playing marker"
grep -Fq "STUDIFY AUDIO MISSING" <<< "$STRINGS" || fail "missing audio missing marker"
grep -Fq "AVAudioPlayer" <<< "$STRINGS" || fail "missing AVAudioPlayer marker"
grep -Fq "UICollectionViewCell" <<< "$STRINGS" || fail "missing collection cell hook target"
grep -Fq "UITableViewCell" <<< "$STRINGS" || fail "missing table cell hook target"
! grep -Fq "Runtime probe" <<< "$STRINGS" || fail "runtime probe must not ship in the default overlay"
! grep -Fq "objc_copyClassList" <<< "$STRINGS" || fail "objc runtime class scan must not ship in the default overlay"
! grep -Fq "class_copyMethodList" <<< "$STRINGS" || fail "objc runtime method scan must not ship in the default overlay"

LINKS="$(otool -L "$DYLIB")"
grep -Fq "@loader_path/Orion.framework/Orion" <<< "$LINKS" || fail "missing direct Orion dependency"

PLAIN_LOADER_RPATH_COUNT="$(
  otool -l "$DYLIB" \
    | awk '/LC_RPATH/{inside=1; next} inside && /path /{print $2; inside=0}' \
    | { grep -Fx "@loader_path" || true; } \
    | wc -l \
    | tr -d ' '
)"

[ "$PLAIN_LOADER_RPATH_COUNT" = "0" ] || fail "plain @loader_path rpath should not be present"

echo "overlay-artifact-check: ok"
