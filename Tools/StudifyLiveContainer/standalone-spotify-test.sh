#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

DEVICE_ID="${DEVICE_ID:-18A702BC-2DAA-5733-ACD8-079DEF96CC95}"
SPOTIFY_BUNDLE_ID="${SPOTIFY_BUNDLE_ID:-com.spotify.client.25P4CVCPW5}"
FULL_IPA="${FULL_IPA:-Outputs/IPAS/StudifyFull-9.1.28-25P4CVCPW5.ipa}"
PROBE_MODE="${PROBE_MODE:-0}"
PROBE_MODE_FILE="${PROBE_MODE_FILE:-/private/tmp/studify-standalone-probe-mode.txt}"
PROBE_UPLOAD_FILE="${PROBE_UPLOAD_FILE:-/private/tmp/studify-standalone-probe-upload.txt}"
STATE_BRIDGE="${STATE_BRIDGE:-0}"
STATE_BRIDGE_FILE="${STATE_BRIDGE_FILE:-/private/tmp/studify-standalone-state-bridge.txt}"
TEST_MP3="${TEST_MP3:-/private/tmp/studify-test.mp3}"
EMPTY_LOG="${EMPTY_LOG:-/private/tmp/studify-standalone-empty-log.txt}"
EMPTY_PROBE_LOG="${EMPTY_PROBE_LOG:-/private/tmp/studify-standalone-empty-probe.jsonl}"
LOG_DEST="${LOG_DEST:-/private/tmp/studify_standalone_overlay_debug_latest.log}"
PROBE_DEST="${PROBE_DEST:-/private/tmp/studify_standalone_probe_events_latest.jsonl}"
DEVICETCL_TIMEOUT="${DEVICETCL_TIMEOUT:-45}"
INSTALL=0
BUILD_IPA=0
LAUNCH=1
PULL_ONLY=0

usage() {
  cat <<'USAGE'
Usage: Tools/StudifyLiveContainer/standalone-spotify-test.sh [--build-ipa] [--install] [--no-launch] [--pull-only]

Environment overrides:
  DEVICE_ID
  SPOTIFY_BUNDLE_ID
  FULL_IPA
  PROBE_MODE
  STATE_BRIDGE
  TEST_MP3
  LOG_DEST
  PROBE_DEST

This helper targets the directly installed Spotify bundle, not Spotify inside
LiveContainer. It writes Documents/StudifyLibrary config files into the
standalone app data container, clears/pulls overlay logs, and optionally installs
the full injected IPA built by build-studify-full-ipa.sh. Use --pull-only after
a manual row tap so the evidence logs are not cleared before they are copied.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --build-ipa)
      BUILD_IPA=1
      ;;
    --install)
      INSTALL=1
      ;;
    --no-launch)
      LAUNCH=0
      ;;
    --pull-only)
      PULL_ONLY=1
      LAUNCH=0
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

terminate_spotify_if_running() {
  local process_output
  local pids
  local pymobiledevice3_bin="/Users/williamxu/.local/bin/pymobiledevice3"

  if process_output="$(
    xcrun devicectl device info processes \
      --device "$DEVICE_ID" \
      --timeout "$DEVICETCL_TIMEOUT" \
      --json-output /private/tmp/studify-standalone-processes.json
  )"; then
    pids="$(
      printf '%s\n' "$process_output" \
        | awk '/Spotify\.app\/Spotify/ { print $1 }' \
        | sort -u
    )"
  else
    echo "warning: CoreDevice process list failed; trying pymobiledevice3 process fallback"
    printf '%s\n' "$process_output" >&2

    if [ -x "$pymobiledevice3_bin" ]; then
      pids="$(
        "$pymobiledevice3_bin" processes pgrep Spotify 2>/dev/null \
          | awk '/Spotify/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) print $i }' \
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
        --json-output "/private/tmp/studify-standalone-terminate-${pid}.json"
    done <<< "$pids"
  else
    echo "standalone Spotify is not currently running"
  fi
}

copy_to_app_container() {
  local label="$1"
  local source_file="$2"
  local destination_path="$3"

  run xcrun devicectl device copy to \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$SPOTIFY_BUNDLE_ID" \
    --source "$source_file" \
    --destination "$destination_path" \
    --json-output "/private/tmp/studify-standalone-copy-${label}.json"
}

pull_from_app_container() {
  local label="$1"
  local source_path="$2"
  local destination_path="$3"

  echo "+ pull $label"
  if xcrun devicectl device copy from \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$SPOTIFY_BUNDLE_ID" \
    --source "$source_path" \
    --destination "$destination_path" \
    --json-output "/private/tmp/studify-standalone-pull-${label}.json"; then
    echo "pulled $label: $destination_path"
  else
    echo "warning: could not pull $label from standalone $source_path" >&2
  fi
}

install_full_ipa() {
  local extract_dir="/private/tmp/studify-standalone-install-app"

  [ -f "$FULL_IPA" ] || {
    echo "missing full IPA: $FULL_IPA" >&2
    echo "run ./build-studify-full-ipa.sh first, or pass --build-ipa" >&2
    exit 1
  }

  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  unzip -q "$FULL_IPA" -d "$extract_dir"

  if ! run xcrun devicectl device install app \
    --device "$DEVICE_ID" \
    "$extract_dir/Payload/Spotify.app" \
    --timeout 90 \
    --json-output /private/tmp/studify-standalone-install.json \
    --log-output /private/tmp/studify-standalone-install.log; then
    echo "" >&2
    echo "standalone IPA install failed." >&2
    echo "If the error mentions a process-scoped coordinated install, iOS is still holding a stale install coordinator for $SPOTIFY_BUNDLE_ID." >&2
    echo "Do not use this as runtime evidence; install the IPA with SideStore/AltStore or clear the stale coordinator on the device, then rerun this helper." >&2
    exit 1
  fi
}

if [ "$PULL_ONLY" = "0" ]; then
  if [ "$BUILD_IPA" = "1" ]; then
    run ./build-studify-full-ipa.sh
  fi

  terminate_spotify_if_running

  if [ "$INSTALL" = "1" ]; then
    install_full_ipa
  fi

  if [ "$PROBE_MODE" != "0" ]; then
    printf 'on\n' > "$PROBE_MODE_FILE"
  else
    printf 'off\n' > "$PROBE_MODE_FILE"
  fi
  printf 'off\n' > "$PROBE_UPLOAD_FILE"

  if [ "$STATE_BRIDGE" != "0" ]; then
    printf 'on\n' > "$STATE_BRIDGE_FILE"
  else
    printf 'off\n' > "$STATE_BRIDGE_FILE"
  fi

  copy_to_app_container "probe-mode" "$PROBE_MODE_FILE" "Documents/StudifyLibrary/probe-mode.txt"
  copy_to_app_container "probe-upload" "$PROBE_UPLOAD_FILE" "Documents/StudifyLibrary/probe-upload.txt"
  copy_to_app_container "state-bridge" "$STATE_BRIDGE_FILE" "Documents/StudifyLibrary/state-bridge.txt"

  if [ -f "$TEST_MP3" ]; then
    copy_to_app_container "test-mp3" "$TEST_MP3" "Documents/StudifyLibrary/audio/test.mp3"
  else
    echo "warning: test MP3 not found at $TEST_MP3; seeded silent playback fallback will still report playing=true"
  fi

  printf '' > "$EMPTY_LOG"
  copy_to_app_container "clear-overlay-log" "$EMPTY_LOG" "tmp/studify_overlay_debug.log"

  printf '' > "$EMPTY_PROBE_LOG"
  copy_to_app_container "clear-probe-log" "$EMPTY_PROBE_LOG" "tmp/studify_probe_events.jsonl"

  if [ "$LAUNCH" = "1" ]; then
    run xcrun devicectl device process launch \
      --device "$DEVICE_ID" \
      "$SPOTIFY_BUNDLE_ID" \
      --activate \
      --json-output /private/tmp/studify-standalone-launch.json

    sleep 2
  fi
fi

pull_from_app_container "overlay-log" "tmp/studify_overlay_debug.log" "$LOG_DEST"
pull_from_app_container "probe-events" "tmp/studify_probe_events.jsonl" "$PROBE_DEST"

echo ""
node Tools/StudifyLiveContainer/summarize-probe-events.js "$PROBE_DEST" "$LOG_DEST"

echo ""
echo "Next on iPhone for standalone Spotify:"
echo "1. Put Spotify offline."
echo "2. Open a playlist."
echo "3. Tap a song row."
echo "4. Re-run this helper with --pull-only so the row-tap logs are copied without being cleared."
