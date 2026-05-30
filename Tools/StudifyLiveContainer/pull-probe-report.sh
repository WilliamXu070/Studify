#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

DEVICE_ID="${DEVICE_ID:-18A702BC-2DAA-5733-ACD8-079DEF96CC95}"
LIVECONTAINER_BUNDLE_ID="${LIVECONTAINER_BUNDLE_ID:-com.kdt.livecontainer.25P4CVCPW5}"
LOG_DEST="${LOG_DEST:-/private/tmp/studify_overlay_debug_latest.log}"
PROBE_DEST="${PROBE_DEST:-/private/tmp/studify_probe_events_latest.jsonl}"

pull_file() {
  local label="$1"
  local source_path="$2"
  local destination_path="$3"
  local json_path="$4"

  echo "+ pull $label"
  if xcrun devicectl device copy from \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$LIVECONTAINER_BUNDLE_ID" \
    --source "$source_path" \
    --destination "$destination_path" \
    --json-output "$json_path"; then
    echo "pulled $label: $destination_path"
  else
    echo "warning: could not pull $label from $source_path" >&2
  fi
}

pull_file \
  "overlay log" \
  "tmp/studify_overlay_debug.log" \
  "$LOG_DEST" \
  "/private/tmp/studify-pull-overlay-report.json"

pull_file \
  "probe events" \
  "tmp/studify_probe_events.jsonl" \
  "$PROBE_DEST" \
  "/private/tmp/studify-pull-probe-report.json"

echo ""
node Tools/StudifyLiveContainer/summarize-probe-events.js "$PROBE_DEST" "$LOG_DEST"
