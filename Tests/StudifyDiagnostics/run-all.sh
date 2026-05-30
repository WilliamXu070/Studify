#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

RUN_BUILD=0
if [ "${1:-}" = "--build" ]; then
  RUN_BUILD=1
fi

echo "== Studify diagnostics =="
echo "root: $ROOT_DIR"

if [ "$RUN_BUILD" = "1" ]; then
  echo ""
  echo "== Build IPA and LiveContainer export =="
  export THEOS="${THEOS:-/Users/williamxu/theos}"
  export THEOS_PACKAGE_SCHEME="${THEOS_PACKAGE_SCHEME:-rootless}"
  export STUDIFY_BUILD_HOME="${STUDIFY_BUILD_HOME:-/private/tmp/studify-home}"
  export HOME="$STUDIFY_BUILD_HOME"
  export PATH="/private/tmp/studify-bin:$THEOS/bin:$PATH"
  mkdir -p "$HOME" "$HOME/.ivinject"

  ./build-tweak-local.sh
  ./build-ipa-local.sh
  ./export-livecontainer-tweak.sh
fi

echo ""
echo "== Source regression checks =="
node Tests/StudifyDiagnostics/source-regression-test.js
node Tests/StudifyDiagnostics/probe-source-test.js
node Tests/StudifyDiagnostics/probe-report-test.js

echo ""
echo "== Server smoke test =="
node Tests/StudifyDiagnostics/server-smoke-test.js

echo ""
echo "== Artifact checks =="
Tests/StudifyDiagnostics/artifact-check.sh

echo ""
echo "Studify diagnostics: all checks passed"
