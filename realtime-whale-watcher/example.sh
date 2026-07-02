#!/usr/bin/env bash
#
# example.sh — End-to-end sample: set env vars, call realtime-whale.sh, receive
# the alerts it would push and act on them.
#
# Runs in DRY_RUN (scans example-block.json once) so it works with no pay balance
# and no Telegram bot. Set LIVE=1 to follow the real chain head and push for real.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 1. Set the environment variables ----------------------------------------
if [ -f "$SCRIPT_DIR/.env" ]; then
  echo "Loading env from .env"
  set -a; . "$SCRIPT_DIR/.env"; set +a
else
  echo "No .env found — using inline demo values (override any via the environment)."
  export WATCH_WALLET="${WATCH_WALLET:-0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045}"
  export THRESHOLD_NATIVE="${THRESHOLD_NATIVE:-100}"
  export NATIVE_SYMBOL="${NATIVE_SYMBOL:-ETH}"
fi

if [ "${LIVE:-0}" = "1" ]; then export DRY_RUN=0; else export DRY_RUN=1; fi

# --- 2. Call the watcher, receive its data -----------------------------------
# In DRY_RUN the watcher scans one block and prints `TELEGRAM: <body>` per hit.
echo
echo "==> Running realtime-whale.sh (watching ${WATCH_WALLET}, threshold ${THRESHOLD_NATIVE} ${NATIVE_SYMBOL:-ETH})"
echo

alerts="$("$SCRIPT_DIR/realtime-whale.sh" | grep '^TELEGRAM: ' || true)"

# --- 3. Do something with the data -------------------------------------------
if [ -z "$alerts" ]; then
  echo "==> No whales over the threshold in that block. Nothing to push."
  exit 0
fi

count="$(printf '%s\n' "$alerts" | wc -l | tr -d ' ')"
echo "==> Received $count alert(s):"
echo
printf '%s\n' "$alerts" | while IFS= read -r line; do
  printf '  • %s\n' "${line#TELEGRAM: }"
done

echo
echo "==> Done. In live mode these push to Telegram the moment the block lands."
