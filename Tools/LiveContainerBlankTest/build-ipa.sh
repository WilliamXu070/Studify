#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="StudifyBlankTest"
BUILD_DIR="$ROOT_DIR/Build/LiveContainerBlankTest"
PAYLOAD_DIR="$BUILD_DIR/Payload"
APP_DIR="$PAYLOAD_DIR/$APP_NAME.app"
OUTPUT_DIR="$ROOT_DIR/Outputs/IPAS"
OUTPUT_IPA="$OUTPUT_DIR/StudifyBlankLiveContainerTest.ipa"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos --find clang)"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR" "$OUTPUT_DIR"

cp "$ROOT_DIR/Tools/LiveContainerBlankTest/Info.plist" "$APP_DIR/Info.plist"

"$CLANG" \
  -fobjc-arc \
  -arch arm64 \
  -miphoneos-version-min=15.0 \
  -isysroot "$SDK_PATH" \
  "$ROOT_DIR/Tools/LiveContainerBlankTest/main.m" \
  -o "$APP_DIR/$APP_NAME" \
  -framework UIKit \
  -framework Foundation

xattr -cr "$APP_DIR"
codesign --force --sign - --timestamp=none "$APP_DIR/$APP_NAME"
codesign --force --sign - --timestamp=none "$APP_DIR"

rm -f "$OUTPUT_IPA"
(
  cd "$BUILD_DIR"
  zip -qry "$OUTPUT_IPA" Payload
)

echo "Built $OUTPUT_IPA"
ls -lh "$OUTPUT_IPA"
