#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

VERSION="6.6.2"
OUTPUT_DIR="Outputs/Tweaks"

export THEOS="${THEOS:-/Users/williamxu/theos}"
export THEOS_PACKAGE_SCHEME="${THEOS_PACKAGE_SCHEME:-rootless}"
export HOME="${STUDIFY_BUILD_HOME:-/private/tmp/studify-home}"
export PATH="/private/tmp/studify-bin:$THEOS/bin:$PATH"

if [ "$THEOS_PACKAGE_SCHEME" = "rootless" ]; then
  ARCH="arm64"
else
  ARCH="arm"
fi

mkdir -p "$HOME" "$OUTPUT_DIR"

echo "======================================"
echo "Building Studify tweak package"
echo "======================================"
echo "Theos:          $THEOS"
echo "Package scheme: $THEOS_PACKAGE_SCHEME"
echo "Output:         $OUTPUT_DIR/StudifyLatest.deb"
echo "======================================"

make package

DEB_FILE="$(ls -1t "packages/com.eevee.spotify_${VERSION}"*_iphoneos-"${ARCH}"*.deb 2>/dev/null | head -1)"
if [ -z "$DEB_FILE" ]; then
  echo "ERROR: No matching .deb found in packages/ for version $VERSION arch $ARCH"
  exit 1
fi

cp "$DEB_FILE" "$OUTPUT_DIR/StudifyLatest.deb"
cp "$DEB_FILE" "$OUTPUT_DIR/$(basename "$DEB_FILE")"

echo ""
echo "======================================"
echo "Build complete"
echo "======================================"
echo "Latest deb: $OUTPUT_DIR/StudifyLatest.deb"
echo "Source deb: $DEB_FILE"
ls -lh "$OUTPUT_DIR/StudifyLatest.deb" "$DEB_FILE"
