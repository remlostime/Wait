#!/usr/bin/env bash
#
# Fails (exit 1) when a tracked file looks like it contains a hard-coded credential.
# Prints file:line only, never the matched value. Run from anywhere inside the repo.
#
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

PATTERNS=(
  'name: "apikey", value: "[A-Za-z0-9]{8,}"'
  'clientId: "[A-Za-z0-9]{16,}"'
  'clientSecret: "[A-Za-z0-9]{16,}"'
  'appSecret: "[A-Za-z0-9]{8,}"'
  'encryptionKey: "[A-Za-z0-9]{8,}"'
  'APM_COLLECTOR_TOKEN'
  'AIza[0-9A-Za-z_-]{35}'
  '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----'
  '_API_KEY *= *[A-Za-z0-9]{16,}'
)

status=0
for pattern in "${PATTERNS[@]}"; do
  matches=$(git grep -nIE -e "$pattern" -- . ':!docs' ':!scripts/check-secrets.sh' ':!**/Secrets.example.xcconfig' || true)
  if [[ -n "$matches" ]]; then
    echo "$matches" | cut -d: -f1-2
    status=1
  fi
done

if [[ "$status" -ne 0 ]]; then
  echo "check-secrets: possible credentials at the locations above" >&2
else
  echo "check-secrets: OK"
fi
exit "$status"
