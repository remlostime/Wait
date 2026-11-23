#!/bin/bash
# Fails if the iOS client references a market-data provider host or key.
# Since plan 04 the app talks only to the Wait backend (overview §6.3 item 1).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
pattern='api\.twelvedata\.com|alphavantage\.co|finnhub\.io|api\.tiingo\.com|alpaca\.markets|api\.massive\.com|api\.polygon\.io|TWELVE_DATA_API_KEY|TwelveDataAPIKey|twelveData\('
if git grep -niIE "$pattern" -- Wait; then
  echo "check-client-has-no-provider-keys: provider hosts or keys found in the iOS client (matches above)" >&2
  exit 1
fi
echo "check-client-has-no-provider-keys: ok"
