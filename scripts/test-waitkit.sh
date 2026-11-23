#!/bin/bash
# Usage: scripts/test-waitkit.sh [TestTarget[/Suite[/test()]] ...]   (no args = all package tests)
# ${ARGS[@]+...} keeps `set -u` happy on macOS bash 3.2 when there are no arguments.
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT/Wait/Packages/WaitKit" || exit 1
ARGS=()
for t in "$@"; do ARGS+=("-only-testing:$t"); done
xcodebuild test -scheme WaitKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -skipMacroValidation -skipPackagePluginValidation ${ARGS[@]+"${ARGS[@]}"} 2>&1 \
  | tee /tmp/wk-test.log \
  | grep -E "error:|✘|recorded an issue|Test run with|\*\* TEST (SUCCEEDED|FAILED) \*\*"
exit "${PIPESTATUS[0]}"
