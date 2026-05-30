#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

DEVICE_ID="${DEVICE_ID:-18A702BC-2DAA-5733-ACD8-079DEF96CC95}"
LIVECONTAINER_BUNDLE_ID="${LIVECONTAINER_BUNDLE_ID:-com.kdt.livecontainer.25P4CVCPW5}"
SPOTIFY_VIRTUAL_CONTAINER="${SPOTIFY_VIRTUAL_CONTAINER:-Documents/Data/Application/6F12DF95-8B98-4013-A346-198A838334A1}"
TWEAK_FOLDER="${TWEAK_FOLDER:-Documents/Tweaks/StudifySpotify}"
TWEAK_FOLDER_ALIASES="${TWEAK_FOLDER_ALIASES:-Documents/Tweaks/StudifyOverlay}"
DEFAULT_BASE_IPA="/Users/williamxu/Downloads/EeveeSpotify-6.6.2-9.1.28.ipa"
if [ ! -f "$DEFAULT_BASE_IPA" ]; then
  DEFAULT_BASE_IPA="Outputs/IPAS/EeveeSpotify-6.6.2-9.1.28-patched.ipa"
fi
BASE_IPA="${BASE_IPA:-$DEFAULT_BASE_IPA}"
DYLIB="${DYLIB:-Outputs/StudifyOverlay/LiveContainer/StudifyOverlay/StudifyOverlay.dylib}"
ORION_FRAMEWORK="${ORION_FRAMEWORK:-Outputs/StudifyOverlay/LiveContainer/StudifyOverlay/Orion.framework}"
TEST_MP3="${TEST_MP3:-/private/tmp/studify-test.mp3}"
SERVER_URL_FILE="${SERVER_URL_FILE:-/private/tmp/studify-server-url.txt}"
STUDIFY_SERVER_URL="${STUDIFY_SERVER_URL:-}"
COPY_SERVER_URL="${COPY_SERVER_URL:-0}"
PROBE_MODE="${PROBE_MODE:-1}"
PROBE_MODE_FILE="${PROBE_MODE_FILE:-/private/tmp/studify-probe-mode.txt}"
PROBE_UPLOAD_FILE="${PROBE_UPLOAD_FILE:-/private/tmp/studify-probe-upload.txt}"
STATE_BRIDGE="${STATE_BRIDGE:-0}"
STATE_BRIDGE_FILE="${STATE_BRIDGE_FILE:-/private/tmp/studify-state-bridge.txt}"
DEVICETCL_TIMEOUT="${DEVICETCL_TIMEOUT:-45}"
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
  TWEAK_FOLDER_ALIASES
  DYLIB
  ORION_FRAMEWORK
  TEST_MP3
  SERVER_URL_FILE
  STUDIFY_SERVER_URL
  COPY_SERVER_URL
  PROBE_MODE
  PROBE_UPLOAD_FILE
  STATE_BRIDGE
  STATE_BRIDGE_FILE
  DEVICETCL_TIMEOUT
  LOG_DEST
  PROBE_DEST

This builds/copies StudifyOverlay.dylib, optionally refreshes test.mp3,
enables StudifyLibrary/probe-mode.txt, clears stale overlay/probe logs,
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

  local status=$?
  if [ "$status" -eq 0 ]; then
    return 0
  fi

  if [ "${1:-}" = "xcrun" ] && [ "${2:-}" = "devicectl" ]; then
    for attempt in 2 3; do
      echo "warning: devicectl command failed with status $status; retrying attempt $attempt/3" >&2
      sleep 2
      if "$@"; then
        return 0
      fi
      status=$?
    done
  fi

  return "$status"
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

tweak_folders_to_update() {
  printf '%s\n' "$TWEAK_FOLDER"

  local alias
  for alias in $TWEAK_FOLDER_ALIASES; do
    [ -n "$alias" ] || continue
    [ "$alias" = "$TWEAK_FOLDER" ] && continue
    printf '%s\n' "$alias"
  done
}

copy_tweak_payload_to_folder() {
  local folder="$1"
  local label

  label="$(basename "$folder")"

  run xcrun devicectl device copy to \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$LIVECONTAINER_BUNDLE_ID" \
    --source "$DYLIB" \
    --destination "$folder/StudifyOverlay.dylib" \
    --json-output "/private/tmp/studify-copy-dylib-${label}-restart-test.json"

  run xcrun devicectl device copy to \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$LIVECONTAINER_BUNDLE_ID" \
    --source "$ORION_FRAMEWORK" \
    --destination "$folder/Orion.framework" \
    --json-output "/private/tmp/studify-copy-orion-${label}-restart-test.json"

  verify_remote_macho_file \
    "StudifyOverlay.dylib-${label}" \
    "$DYLIB" \
    "$folder/StudifyOverlay.dylib"

  verify_remote_macho_file \
    "Orion-${label}" \
    "$ORION_FRAMEWORK/Orion" \
    "$folder/Orion.framework/Orion"

  verify_remote_exact_file \
    "Orion-Info.plist-${label}" \
    "$ORION_FRAMEWORK/Info.plist" \
    "$folder/Orion.framework/Info.plist"

  if ! file_contains_string "/private/tmp/studify-verify-StudifyOverlay.dylib-${label}-$$" "Offline playable spoof groups skipped"; then
    echo "ERROR: phone dylib in $folder does not contain the stable offline-spoof safety marker" >&2
    exit 1
  fi
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
  local pids
  local pymobiledevice3_bin="/Users/williamxu/.local/bin/pymobiledevice3"

  if process_output="$(
    xcrun devicectl device info processes \
      --device "$DEVICE_ID" \
      --timeout "$DEVICETCL_TIMEOUT" \
      --json-output /private/tmp/studify-processes-restart-test.json
  )"; then
    pids="$(
      printf '%s\n' "$process_output" \
        | awk '/LiveContainer\.app\/LiveContainer|Spotify\.app\/Spotify/ { print $1 }' \
        | sort -u
    )"
  else
    echo "warning: CoreDevice process list failed; trying pymobiledevice3 process fallback"
    printf '%s\n' "$process_output" >&2

    if [ -x "$pymobiledevice3_bin" ]; then
      pids="$(
        {
          "$pymobiledevice3_bin" processes pgrep LiveContainer 2>/dev/null || true
          "$pymobiledevice3_bin" processes pgrep Spotify 2>/dev/null || true
        } \
          | awk '/LiveContainer|Spotify/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) print $i }' \
          | sort -u
      )"
    else
      pids=""
    fi
  fi

  if [ -n "$pids" ]; then
    while IFS= read -r pid; do
      [ -n "$pid" ] || continue
      run xcrun devicectl device process terminate \
        --device "$DEVICE_ID" \
        --pid "$pid" \
        --json-output "/private/tmp/studify-terminate-${pid}-restart-test.json"
    done <<< "$pids"
  else
    echo "LiveContainer/Spotify are not currently running; copy step will still run"
  fi
}

if [ "$NO_BUILD" = "0" ]; then
  run ./build-studify-overlay.sh "$BASE_IPA"
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

while IFS= read -r tweak_folder; do
  [ -n "$tweak_folder" ] || continue
  echo "copying tweak payload to $tweak_folder"
  copy_tweak_payload_to_folder "$tweak_folder"
done < <(tweak_folders_to_update)

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
  COPY_SERVER_URL=1
fi

if [ "$COPY_SERVER_URL" = "1" ] && [ -f "$SERVER_URL_FILE" ]; then
  run xcrun devicectl device copy to \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$LIVECONTAINER_BUNDLE_ID" \
    --source "$SERVER_URL_FILE" \
    --destination "$SPOTIFY_VIRTUAL_CONTAINER/Documents/StudifyLibrary/server-url.txt" \
    --json-output /private/tmp/studify-copy-server-url-restart-test.json
else
  echo "server URL copy skipped; probe mode writes local phone logs only"
fi

if [ "$PROBE_MODE" != "0" ]; then
  printf 'on\n' > "$PROBE_MODE_FILE"
  printf 'off\n' > "$PROBE_UPLOAD_FILE"
  run xcrun devicectl device copy to \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$LIVECONTAINER_BUNDLE_ID" \
    --source "$PROBE_MODE_FILE" \
    --destination "$SPOTIFY_VIRTUAL_CONTAINER/Documents/StudifyLibrary/probe-mode.txt" \
    --json-output /private/tmp/studify-copy-probe-mode-restart-test.json
  run xcrun devicectl device copy to \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$LIVECONTAINER_BUNDLE_ID" \
    --source "$PROBE_UPLOAD_FILE" \
    --destination "$SPOTIFY_VIRTUAL_CONTAINER/Documents/StudifyLibrary/probe-upload.txt" \
    --json-output /private/tmp/studify-copy-probe-upload-restart-test.json
else
  printf 'off\n' > "$PROBE_MODE_FILE"
  printf 'off\n' > "$PROBE_UPLOAD_FILE"
  run xcrun devicectl device copy to \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$LIVECONTAINER_BUNDLE_ID" \
    --source "$PROBE_MODE_FILE" \
    --destination "$SPOTIFY_VIRTUAL_CONTAINER/Documents/StudifyLibrary/probe-mode.txt" \
    --json-output /private/tmp/studify-copy-probe-mode-off-restart-test.json
  run xcrun devicectl device copy to \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$LIVECONTAINER_BUNDLE_ID" \
    --source "$PROBE_UPLOAD_FILE" \
    --destination "$SPOTIFY_VIRTUAL_CONTAINER/Documents/StudifyLibrary/probe-upload.txt" \
    --json-output /private/tmp/studify-copy-probe-upload-off-restart-test.json
  echo "probe mode disabled on phone; cleared stale probe-mode.txt state"
fi

if [ "$STATE_BRIDGE" != "0" ]; then
  printf 'on\n' > "$STATE_BRIDGE_FILE"
else
  printf 'off\n' > "$STATE_BRIDGE_FILE"
fi

run xcrun devicectl device copy to \
  --device "$DEVICE_ID" \
  --domain-type appDataContainer \
  --domain-identifier "$LIVECONTAINER_BUNDLE_ID" \
  --source "$STATE_BRIDGE_FILE" \
  --destination "$SPOTIFY_VIRTUAL_CONTAINER/Documents/StudifyLibrary/state-bridge.txt" \
  --json-output /private/tmp/studify-copy-state-bridge-restart-test.json

if [ "$STATE_BRIDGE" != "0" ]; then
  echo "state bridge enabled on phone for targeted debug run"
else
  echo "state bridge disabled on phone; cleared stale startup-crash path"
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
