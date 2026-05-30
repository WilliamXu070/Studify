#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

PATCHED_IPA="${1:-Outputs/IPAS/EeveeSpotify-6.6.2-9.1.28-patched.ipa}"
OUTPUT_DIR="Outputs/LiveContainerTweaks/StudifySpotify"
OUTPUT_ZIP="Outputs/LiveContainerTweaks/StudifySpotify-LiveContainer.zip"
TMP_DIR="/private/tmp/studify-livecontainer-frameworks"

export THEOS="${THEOS:-/Users/williamxu/theos}"

echo "======================================"
echo "Exporting LiveContainer tweak files"
echo "======================================"
echo "Patched IPA source: $PATCHED_IPA"
echo "Output folder:      $OUTPUT_DIR"
echo "======================================"

./build-tweak-local.sh

if [ ! -f "$PATCHED_IPA" ]; then
  echo "ERROR: Patched IPA not found: $PATCHED_IPA"
  echo "Build it once with build-ipa-local.sh so this script can extract Orion.framework."
  exit 1
fi

rm -rf "$OUTPUT_DIR" "$TMP_DIR"
mkdir -p "$OUTPUT_DIR" "$TMP_DIR"

cp ".theos/_/var/jb/Library/MobileSubstrate/DynamicLibraries/EeveeSpotify.dylib" "$OUTPUT_DIR/EeveeSpotify.dylib"
cp -R ".theos/_/var/jb/Library/Application Support/EeveeSpotify.bundle" "$OUTPUT_DIR/EeveeSpotify.bundle"
cp -R "$THEOS/lib/iphone/rootless/SwiftProtobuf.framework" "$OUTPUT_DIR/SwiftProtobuf.framework"

unzip -q "$PATCHED_IPA" \
  "Payload/Spotify.app/Frameworks/Orion.framework/*" \
  -d "$TMP_DIR"
cp -R "$TMP_DIR/Payload/Spotify.app/Frameworks/Orion.framework" "$OUTPUT_DIR/Orion.framework"

install_name_tool \
  -change "/private/tmp/studify-swiftprotobuf-framework/SwiftProtobuf.framework/SwiftProtobuf" \
  "@rpath/SwiftProtobuf.framework/SwiftProtobuf" \
  "$OUTPUT_DIR/EeveeSpotify.dylib"

if ! otool -l "$OUTPUT_DIR/EeveeSpotify.dylib" | grep -q "path @loader_path "; then
  install_name_tool -add_rpath "@loader_path" "$OUTPUT_DIR/EeveeSpotify.dylib"
fi

xattr -cr "$OUTPUT_DIR"
codesign --force --sign - --timestamp=none "$OUTPUT_DIR/SwiftProtobuf.framework"
codesign --force --sign - --timestamp=none "$OUTPUT_DIR/Orion.framework"
codesign --force --sign - --timestamp=none "$OUTPUT_DIR/EeveeSpotify.dylib"

rm -f "$OUTPUT_ZIP"
(
  cd "$(dirname "$OUTPUT_DIR")"
  zip -qry "$(basename "$OUTPUT_ZIP")" "$(basename "$OUTPUT_DIR")"
)

echo ""
echo "======================================"
echo "LiveContainer export complete"
echo "======================================"
find "$OUTPUT_DIR" -maxdepth 2 \( -name '*.dylib' -o -name '*.framework' -o -name '*.bundle' \) -print
echo ""
echo "Zip for transfer: $OUTPUT_ZIP"
ls -lh "$OUTPUT_ZIP"
