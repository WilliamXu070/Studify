#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

DEFAULT_BASE_IPA="/Users/williamxu/Downloads/EeveeSpotify-6.6.2-9.1.28.ipa"
if [ ! -f "$DEFAULT_BASE_IPA" ]; then
  DEFAULT_BASE_IPA="Outputs/IPAS/EeveeSpotify-6.6.2-9.1.28.ipa"
fi

BASE_IPA="${1:-${BASE_IPA:-$DEFAULT_BASE_IPA}}"
OUTPUT_IPA="${OUTPUT_IPA:-Outputs/IPAS/StudifyFull-9.1.28-25P4CVCPW5.ipa}"
BUNDLE_ID="${BUNDLE_ID:-com.spotify.client.25P4CVCPW5}"
OVERLAY_DEB="${OVERLAY_DEB:-Outputs/StudifyOverlay/StudifyOverlayLatest.deb}"
IVINJECT="${IVINJECT:-/private/tmp/studify-bin/ivinject-arm64}"

export HOME="${STUDIFY_BUILD_HOME:-/private/tmp/studify-home}"
mkdir -p "$HOME/.ivinject" "$(dirname "$OUTPUT_IPA")"

[ -f "$BASE_IPA" ] || {
  echo "missing base IPA: $BASE_IPA" >&2
  exit 1
}

[ -f "$OVERLAY_DEB" ] || {
  echo "missing overlay deb: $OVERLAY_DEB" >&2
  echo "run ./build-studify-overlay.sh first" >&2
  exit 1
}

[ -x "$IVINJECT" ] || {
  echo "missing ivinject: $IVINJECT" >&2
  exit 1
}

echo "======================================"
echo "Building Studify full IPA"
echo "======================================"
echo "Base IPA:    $BASE_IPA"
echo "Overlay deb: $OVERLAY_DEB"
echo "Bundle ID:   $BUNDLE_ID"
echo "Output IPA:  $OUTPUT_IPA"
echo "======================================"

"$IVINJECT" \
  "$BASE_IPA" \
  "$OUTPUT_IPA" \
  --overwrite \
  -i "$OVERLAY_DEB" \
  -s - \
  -d \
  -b "$BUNDLE_ID" \
  --level Optimal

TMP_DIR="/private/tmp/studify-full-ipa-check-$$"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
unzip -q "$OUTPUT_IPA" Payload/Spotify.app/Info.plist Payload/Spotify.app/Frameworks/StudifyOverlay.dylib -d "$TMP_DIR"

ACTUAL_BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$TMP_DIR/Payload/Spotify.app/Info.plist")"
if [ "$ACTUAL_BUNDLE_ID" != "$BUNDLE_ID" ]; then
  echo "ERROR: output bundle id mismatch: $ACTUAL_BUNDLE_ID" >&2
  exit 1
fi

if ! LC_ALL=C grep -aFq "Native playback bridge seeded offline user intent" "$TMP_DIR/Payload/Spotify.app/Frameworks/StudifyOverlay.dylib"; then
  echo "ERROR: output IPA overlay is missing recovered offline seed marker" >&2
  exit 1
fi

rm -rf "$TMP_DIR"

echo ""
echo "======================================"
echo "Studify full IPA complete"
echo "======================================"
ls -lh "$OUTPUT_IPA"
