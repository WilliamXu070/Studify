#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if [ "$#" -eq 0 ]; then
  set -- \
    "Decrryted IPA/com.spotify.client-9.1.28-Decrypted.ipa" \
    "/Users/williamxu/Downloads/EeveeSpotify-6.6.2-9.1.28.ipa" \
    "/Users/williamxu/Downloads/test.ipa" \
    "Outputs/IPAS/EeveeSpotify-6.6.2-9.1.28.ipa" \
    "Outputs/IPAS/EeveeSpotify-6.6.2-9.1.28-patched.ipa"
fi

echo "== IPA inventory =="

for ipa in "$@"; do
  echo ""
  echo "IPA: $ipa"

  if [ ! -f "$ipa" ]; then
    echo "  status: missing"
    continue
  fi

  ls -lh "$ipa" | awk '{print "  size: " $5}'

  list="$(unzip -l "$ipa")"
  markers="$(grep -E "Payload/Spotify.app/(Frameworks/EeveeSpotify.dylib$|EeveeSpotify.bundle/Info.plist$|Frameworks/Orion.framework/Orion$|Frameworks/SwiftProtobuf.framework/SwiftProtobuf$|Frameworks/CydiaSubstrate.framework/CydiaSubstrate$)" <<< "$list" || true)"

  if [ -n "$markers" ]; then
    echo "  status: contaminated / already tweaked"
    sed 's/^/  found: /' <<< "$markers"
  else
    echo "  status: clean candidate"
  fi
done
