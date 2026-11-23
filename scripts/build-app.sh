#!/bin/bash
# Usage: scripts/build-app.sh [scheme]   (default scheme: Wait)
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel)"
SCHEME="${1:-Wait}"
if [ "$SCHEME" = "WaitWatch" ]; then DEST='platform=watchOS Simulator,name=Apple Watch Series 12 (42mm),OS=27.0'
else DEST='platform=iOS Simulator,name=iPhone 17,OS=27.0'; fi
xcodebuild -project "$ROOT/Wait/Wait.xcodeproj" -scheme "$SCHEME" -destination "$DEST" \
  -skipMacroValidation -skipPackagePluginValidation build 2>&1 \
  | tee /tmp/wait-build.log \
  | grep -E "error:|\*\* BUILD (SUCCEEDED|FAILED) \*\*"
exit "${PIPESTATUS[0]}"
