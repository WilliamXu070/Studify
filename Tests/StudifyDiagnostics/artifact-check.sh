#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

PATCHED_IPA="Outputs/IPAS/EeveeSpotify-6.6.2-9.1.28-patched.ipa"
CLEAN_IPA="Decrryted IPA/com.spotify.client-9.1.28-Decrypted.ipa"
LIVE_DIR="Outputs/LiveContainerTweaks/StudifySpotify"
BUILT_DYLIB=".theos/obj/debug/arm64/EeveeSpotify.dylib"

fail() {
  echo "artifact-check: FAIL: $*" >&2
  exit 1
}

need_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

need_dir() {
  [ -d "$1" ] || fail "missing directory: $1"
}

contains() {
  local haystack="$1"
  local needle="$2"
  grep -Fq "$needle" <<< "$haystack" || fail "missing marker: $needle"
}

not_contains() {
  local haystack="$1"
  local needle="$2"
  local context="${3:-artifact}"
  if grep -Fq "$needle" <<< "$haystack"; then
    fail "$context is contaminated: found $needle"
  fi
}

need_file "$BUILT_DYLIB"
BUILT_STRINGS="$(strings "$BUILT_DYLIB")"
contains "$BUILT_STRINGS" "STUDIFY HOOK FIRED"
contains "$BUILT_STRINGS" "STUDIFY POST STARTED"
contains "$BUILT_STRINGS" "STUDIFY UICONTROL HOOK ACTIVE"
contains "$BUILT_STRINGS" "sendAction:to:forEvent:"

if [ -f "$PATCHED_IPA" ]; then
  IPA_STRINGS="$(unzip -p "$PATCHED_IPA" Payload/Spotify.app/Frameworks/EeveeSpotify.dylib | strings)"
  contains "$IPA_STRINGS" "STUDIFY HOOK FIRED"
  contains "$IPA_STRINGS" "STUDIFY POST STARTED"
  contains "$IPA_STRINGS" "STUDIFY UICONTROL HOOK ACTIVE"
  contains "$IPA_STRINGS" "sendAction:to:forEvent:"

  IPA_LIST="$(unzip -l "$PATCHED_IPA")"
  contains "$IPA_LIST" "Payload/Spotify.app/Frameworks/EeveeSpotify.dylib"
  contains "$IPA_LIST" "Payload/Spotify.app/Frameworks/Orion.framework/Orion"
  contains "$IPA_LIST" "Payload/Spotify.app/Frameworks/SwiftProtobuf.framework/SwiftProtobuf"
fi

if [ -f "$CLEAN_IPA" ]; then
  CLEAN_LIST="$(unzip -l "$CLEAN_IPA")"
  if [ "${STUDIFY_ALLOW_CONTAMINATED_INPUT:-0}" = "1" ]; then
    if grep -Fq "EeveeSpotify.dylib" <<< "$CLEAN_LIST"; then
      echo "artifact-check: warning: input IPA $CLEAN_IPA is already injected; continuing because STUDIFY_ALLOW_CONTAMINATED_INPUT=1"
    fi
  else
    not_contains "$CLEAN_LIST" "EeveeSpotify.dylib" "input IPA $CLEAN_IPA"
    not_contains "$CLEAN_LIST" "EeveeSpotify.bundle" "input IPA $CLEAN_IPA"
  fi
fi

if [ -d "$LIVE_DIR" ]; then
  need_file "$LIVE_DIR/EeveeSpotify.dylib"
  need_dir "$LIVE_DIR/Orion.framework"
  need_dir "$LIVE_DIR/SwiftProtobuf.framework"
  need_dir "$LIVE_DIR/EeveeSpotify.bundle"

  LIVE_LINKS="$(otool -L "$LIVE_DIR/EeveeSpotify.dylib")"
  contains "$LIVE_LINKS" "@rpath/SwiftProtobuf.framework/SwiftProtobuf"
  contains "$LIVE_LINKS" "@rpath/Orion.framework/Orion"
  not_contains "$LIVE_LINKS" "/private/tmp/studify-swiftprotobuf-framework" "LiveContainer dylib dependency list"

  LIVE_RPATHS="$(otool -l "$LIVE_DIR/EeveeSpotify.dylib")"
  contains "$LIVE_RPATHS" "path @loader_path"
fi

echo "artifact-check: ok"
