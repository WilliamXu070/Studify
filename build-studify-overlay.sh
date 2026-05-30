#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$ROOT_DIR/Overlay/StudifyOverlay"
OUTPUT_DIR="$ROOT_DIR/Outputs/StudifyOverlay"
LIVE_DIR="$OUTPUT_DIR/LiveContainer/StudifyOverlay"
OUTPUT_ZIP="$OUTPUT_DIR/StudifyOverlay-LiveContainer.zip"
BASE_IPA="${1:-Outputs/IPAS/EeveeSpotify-6.6.2-9.1.28-patched.ipa}"
TMP_DIR="/private/tmp/studify-overlay-frameworks"

export THEOS="${THEOS:-/Users/williamxu/theos}"
export THEOS_PACKAGE_SCHEME="${THEOS_PACKAGE_SCHEME:-rootless}"
export HOME="${STUDIFY_BUILD_HOME:-/private/tmp/studify-home}"
export PATH="/private/tmp/studify-bin:$THEOS/bin:$PATH"
export COPYFILE_DISABLE=1

mkdir -p "$HOME" "$OUTPUT_DIR"

echo "======================================"
echo "Building Studify overlay tweak"
echo "======================================"
echo "Project:  $PROJECT_DIR"
echo "Base IPA: $BASE_IPA"
echo "Output:   $OUTPUT_DIR"
echo "======================================"

make -C "$PROJECT_DIR" package

DEB_FILE="$(ls -1t "$PROJECT_DIR"/packages/com.studify.overlay_*_iphoneos-arm64.deb 2>/dev/null | head -1)"
if [ -z "$DEB_FILE" ]; then
  echo "ERROR: no overlay .deb found"
  exit 1
fi

rm -rf "$LIVE_DIR" "$TMP_DIR"
mkdir -p "$LIVE_DIR" "$TMP_DIR"

cp "$DEB_FILE" "$OUTPUT_DIR/StudifyOverlayLatest.deb"
cp "$PROJECT_DIR/.theos/_/var/jb/Library/MobileSubstrate/DynamicLibraries/StudifyOverlay.dylib" "$LIVE_DIR/StudifyOverlay.dylib"

if [ -f "$BASE_IPA" ]; then
  if unzip -l "$BASE_IPA" "Payload/Spotify.app/Frameworks/Orion.framework/*" >/dev/null 2>&1; then
    unzip -q "$BASE_IPA" "Payload/Spotify.app/Frameworks/Orion.framework/*" -d "$TMP_DIR"
    ditto --noextattr --norsrc "$TMP_DIR/Payload/Spotify.app/Frameworks/Orion.framework" "$LIVE_DIR/Orion.framework"
  else
    echo "warning: base IPA does not contain Orion.framework; LiveContainer may need Orion from another source"
  fi
else
  echo "warning: base IPA missing: $BASE_IPA"
fi

install_name_tool \
  -change "@rpath/Orion.framework/Orion" \
  "@loader_path/Orion.framework/Orion" \
  "$LIVE_DIR/StudifyOverlay.dylib"

xattr -cr "$LIVE_DIR"
if [ -d "$LIVE_DIR/Orion.framework" ]; then
  xattr -cr "$LIVE_DIR/Orion.framework"
  codesign --force --sign - --timestamp=none "$LIVE_DIR/Orion.framework"
fi
codesign --force --sign - --timestamp=none "$LIVE_DIR/StudifyOverlay.dylib"

rm -f "$OUTPUT_ZIP"
(
  cd "$OUTPUT_DIR/LiveContainer"
  zip -qry -X "$OUTPUT_ZIP" "StudifyOverlay"
)

echo ""
echo "======================================"
echo "Studify overlay build complete"
echo "======================================"
echo "Latest deb: $OUTPUT_DIR/StudifyOverlayLatest.deb"
echo "LiveContainer folder: $LIVE_DIR"
echo "LiveContainer zip: $OUTPUT_ZIP"
find "$LIVE_DIR" -maxdepth 2 \( -name '*.dylib' -o -name '*.framework' \) -print
ls -lh "$OUTPUT_DIR/StudifyOverlayLatest.deb" "$OUTPUT_ZIP"
