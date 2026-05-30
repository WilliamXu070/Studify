#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

DEVICE_ID="${DEVICE_ID:-18A702BC-2DAA-5733-ACD8-079DEF96CC95}"
LIVECONTAINER_BUNDLE_ID="${LIVECONTAINER_BUNDLE_ID:-com.kdt.livecontainer.25P4CVCPW5}"
SPOTIFY_VIRTUAL_CONTAINER="${SPOTIFY_VIRTUAL_CONTAINER:-Documents/Data/Application/6F12DF95-8B98-4013-A346-198A838334A1}"
TWEAK_FOLDER="${TWEAK_FOLDER:-Documents/Tweaks/StudifySpotify}"
DYLIB="${DYLIB:-Outputs/StudifyOverlay/LiveContainer/StudifyOverlay/StudifyOverlay.dylib}"
ORION_FRAMEWORK="${ORION_FRAMEWORK:-Outputs/StudifyOverlay/LiveContainer/StudifyOverlay/Orion.framework}"
TEST_MP3="${TEST_MP3:-/private/tmp/studify-test.mp3}"
SERVER_URL_FILE="${SERVER_URL_FILE:-/private/tmp/studify-server-url.txt}"
STUDIFY_SERVER_URL="${STUDIFY_SERVER_URL:-}"
LOG_DEST="${LOG_DEST:-/private/tmp/studify_overlay_debug_latest.log}"
EMPTY_LOG="${EMPTY_LOG:-/private/tmp/studify-overlay-empty-log.txt}"
PROBE_DEST="${PROBE_DEST:-/private/tmp/studify_probe_events_latest.jsonl}"
EMPTY_PROBE_LOG="${EMPTY_PROBE_LOG:-/private/tmp/studify-probe-empty-log.jsonl}"
NO_BUILD=0

usage() {
  cat <<'USAGE'
Usage: Tools/StudifyLiveContainer/restart-test.sh [--no-build]

Environment overrides:
  DEVICE_ID
  LIVECONTAINER_BUNDLE_ID
  SPOTIFY_VIRTUAL_CONTAINER
  TWEAK_FOLDER
  DYLIB
  ORION_FRAMEWORK
  TEST_MP3
  SERVER_URL_FILE
  STUDIFY_SERVER_URL
  LOG_DEST
  PROBE_DEST

This builds/copies StudifyOverlay.dylib, optionally refreshes test.mp3 and
StudifyLibrary/server-url.txt, clears stale overlay/probe logs,
terminates LiveContainer if running, relaunches it, and pulls the overlay log.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-build)
      NO_BUILD=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

run() {
  echo "+ $*"
  "$@"
}

hash_file() {
  shasum -a 256 "$1" | awk '{ print $1 }'
}

code_signature_offset() {
  otool -l "$1" | awk '
    /LC_CODE_SIGNATURE/ { in_sig = 1; next }
    in_sig && /dataoff/ { print $2; exit }
  '
}

macho_payload_hash() {
  local file="$1"
  local dataoff

  dataoff="$(code_signature_offset "$file")"
  if [ -z "$dataoff" ]; then
    hash_file "$file"
    return
  fi

  dd if="$file" bs=1 count="$dataoff" 2>/dev/null | shasum -a 256 | awk '{ print $1 }'
}

verify_remote_exact_file() {
  local label="$1"
  local local_file="$2"
  local remote_path="$3"
  local tmp_file="/private/tmp/studify-verify-${label}-$$"
  local json_file="/private/tmp/studify-verify-${label}-$$.json"
  local expected_hash
  local actual_hash

  run xcrun devicectl device copy from \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$LIVECONTAINER_BUNDLE_ID" \
    --source "$remote_path" \
    --destination "$tmp_file" \
    --json-output "$json_file"

  expected_hash="$(hash_file "$local_file")"
  actual_hash="$(hash_file "$tmp_file")"

  if [ "$expected_hash" != "$actual_hash" ]; then
    echo "ERROR: phone copy mismatch for $label" >&2
    echo "  local: $expected_hash  $local_file" >&2
    echo "  phone: $actual_hash  $remote_path" >&2
    exit 1
  fi

  echo "verified phone copy: $label $actual_hash"
}

verify_remote_macho_file() {
  local label="$1"
  local local_file="$2"
  local remote_path="$3"
  local tmp_file="/private/tmp/studify-verify-${label}-$$"
  local json_file="/private/tmp/studify-verify-${label}-$$.json"
  local expected_hash
  local actual_hash

  run xcrun devicectl device copy from \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$LIVECONTAINER_BUNDLE_ID" \
    --source "$remote_path" \
    --destination "$tmp_file" \
    --json-output "$json_file"

  expected_hash="$(macho_payload_hash "$local_file")"
  actual_hash="$(macho_payload_hash "$tmp_file")"

  if [ "$expected_hash" != "$actual_hash" ]; then
    echo "ERROR: phone Mach-O payload mismatch for $label" >&2
    echo "  local: $expected_hash  $local_file" >&2
    echo "  phone: $actual_hash  $remote_path" >&2
    exit 1
  fi

  echo "verified phone Mach-O payload: $label $actual_hash"
}

file_contains_string() {
  local file="$1"
  local marker="$2"
  local tmp_file="/private/tmp/studify-strings-$$.txt"

  strings "$file" > "$tmp_file"
  grep -Fq "$marker" "$tmp_file"
}

terminate_livecontainer_if_running() {
  local process_output
  local live_pid

  process_output="$(
    xcrun devicectl device info processes \
      --device "$DEVICE_ID" \
      --json-output /private/tmp/studify-processes-restart-test.json
  )"

  live_pid="$(
    printf '%s\n' "$process_output" \
      | awk '/LiveContainer\.app\/LiveContainer/ { print $1 }' \
      | tail -1
  )"

  if [ -n "$live_pid" ]; then
    run xcrun devicectl device process terminate \
      --device "$DEVICE_ID" \
      --pid "$live_pid" \
      --json-output /private/tmp/studify-terminate-livecontainer-restart-test.json
  else
    echo "LiveContainer is not currently running; copy step will still run"
  fi
}

if [ "$NO_BUILD" = "0" ]; then
  run ./build-studify-overlay.sh
  run Tests/StudifyDiagnostics/overlay-artifact-check.sh
else
  run Tests/StudifyDiagnostics/overlay-artifact-check.sh
fi

[ -f "$DYLIB" ] || {
  echo "missing dylib: $DYLIB" >&2
  exit 1
}

[ -d "$ORION_FRAMEWORK" ] || {
  echo "missing Orion framework: $ORION_FRAMEWORK" >&2
  exit 1
}

if ! file_contains_string "$DYLIB" "Offline playable spoof groups skipped"; then
  echo "ERROR: local dylib does not contain the stable offline-spoof safety marker" >&2
  echo "Refusing to deploy because a previous unsafe build may still be selected." >&2
  exit 1
fi

echo "preflight local hashes:"
echo "  StudifyOverlay.dylib payload $(macho_payload_hash "$DYLIB")"
echo "  Orion.framework/Orion payload $(macho_payload_hash "$ORION_FRAMEWORK/Orion")"
echo "  Orion.framework/Info.plist $(hash_file "$ORION_FRAMEWORK/Info.plist")"

terminate_livecontainer_if_running

run xcrun devicectl device copy to \
  --device "$DEVICE_ID" \
  --domain-type appDataContainer \
  --domain-identifier "$LIVECONTAINER_BUNDLE_ID" \
  --source "$DYLIB" \
  --destination "$TWEAK_FOLDER/StudifyOverlay.dylib" \
  --json-output /private/tmp/studify-copy-dylib-restart-test.json

run xcrun devicectl device copy to \
  --device "$DEVICE_ID" \
  --domain-type appDataContainer \
  --domain-identifier "$LIVECONTAINER_BUNDLE_ID" \
  --source "$ORION_FRAMEWORK" \
  --destination "$TWEAK_FOLDER/Orion.framework" \
  --json-output /private/tmp/studify-copy-orion-restart-test.json

verify_remote_macho_file \
  "StudifyOverlay.dylib" \
  "$DYLIB" \
  "$TWEAK_FOLDER/StudifyOverlay.dylib"

verify_remote_macho_file \
  "Orion" \
  "$ORION_FRAMEWORK/Orion" \
  "$TWEAK_FOLDER/Orion.framework/Orion"

verify_remote_exact_file \
  "Orion-Info.plist" \
  "$ORION_FRAMEWORK/Info.plist" \
  "$TWEAK_FOLDER/Orion.framework/Info.plist"

if ! file_contains_string "/private/tmp/studify-verify-StudifyOverlay.dylib-$$" "Offline playable spoof groups skipped"; then
  echo "ERROR: phone dylib does not contain the stable offline-spoof safety marker" >&2
  exit 1
fi

if [ -f "$TEST_MP3" ]; then
  run xcrun devicectl device copy to \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$LIVECONTAINER_BUNDLE_ID" \
    --source "$TEST_MP3" \
    --destination "$SPOTIFY_VIRTUAL_CONTAINER/Documents/StudifyLibrary/audio/test.mp3" \
    --json-output /private/tmp/studify-copy-test-mp3-restart-test.json

  run xcrun devicectl device copy to \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$LIVECONTAINER_BUNDLE_ID" \
    --source "$TEST_MP3" \
    --destination "$SPOTIFY_VIRTUAL_CONTAINER/Documents/test.mp3" \
    --json-output /private/tmp/studify-copy-test-mp3-fallback-restart-test.json
else
  echo "warning: test MP3 not found at $TEST_MP3; skipping audio copy"
fi

if [ -n "$STUDIFY_SERVER_URL" ]; then
  printf '%s\n' "$STUDIFY_SERVER_URL" > "$SERVER_URL_FILE"
fi

if [ -f "$SERVER_URL_FILE" ]; then
  run xcrun devicectl device copy to \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$LIVECONTAINER_BUNDLE_ID" \
    --source "$SERVER_URL_FILE" \
    --destination "$SPOTIFY_VIRTUAL_CONTAINER/Documents/StudifyLibrary/server-url.txt" \
    --json-output /private/tmp/studify-copy-server-url-restart-test.json
else
  echo "warning: server URL file not found at $SERVER_URL_FILE; leaving existing phone config unchanged"
fi

printf '' > "$EMPTY_LOG"
run xcrun devicectl device copy to \
  --device "$DEVICE_ID" \
  --domain-type appDataContainer \
  --domain-identifier "$LIVECONTAINER_BUNDLE_ID" \
  --source "$EMPTY_LOG" \
  --destination tmp/studify_overlay_debug.log \
  --json-output /private/tmp/studify-clear-overlay-log-restart-test.json

printf '' > "$EMPTY_PROBE_LOG"
run xcrun devicectl device copy to \
  --device "$DEVICE_ID" \
  --domain-type appDataContainer \
  --domain-identifier "$LIVECONTAINER_BUNDLE_ID" \
  --source "$EMPTY_PROBE_LOG" \
  --destination tmp/studify_probe_events.jsonl \
  --json-output /private/tmp/studify-clear-probe-log-restart-test.json

run xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  "$LIVECONTAINER_BUNDLE_ID" \
  --activate \
  --json-output /private/tmp/studify-launch-livecontainer-restart-test.json

sleep 2

if xcrun devicectl device copy from \
  --device "$DEVICE_ID" \
  --domain-type appDataContainer \
  --domain-identifier "$LIVECONTAINER_BUNDLE_ID" \
  --source tmp/studify_overlay_debug.log \
  --destination "$LOG_DEST" \
  --json-output /private/tmp/studify-pull-log-restart-test.json; then
  echo ""
  echo "latest Studify log: $LOG_DEST"
  tail -n 80 "$LOG_DEST"
else
  echo "warning: overlay log was not pulled; open Spotify inside LiveContainer, interact once, then pull it manually"
fi

if xcrun devicectl device copy from \
  --device "$DEVICE_ID" \
  --domain-type appDataContainer \
  --domain-identifier "$LIVECONTAINER_BUNDLE_ID" \
  --source tmp/studify_probe_events.jsonl \
  --destination "$PROBE_DEST" \
  --json-output /private/tmp/studify-pull-probe-restart-test.json; then
  echo ""
  echo "latest Studify probe events: $PROBE_DEST"
  node Tools/StudifyLiveContainer/summarize-probe-events.js "$PROBE_DEST" "$LOG_DEST"
else
  echo "warning: probe events were not pulled; interact once, then run Tools/StudifyLiveContainer/pull-probe-report.sh"
fi

echo ""
echo "Next on iPhone:"
echo "1. If Spotify did not open automatically, open it inside LiveContainer."
echo "2. Go to a real playlist."
echo "3. Tap a song row."
echo "4. Run Tools/StudifyLiveContainer/pull-probe-report.sh immediately after the prompt/playback result."
