#!/usr/bin/env bash
#
# example.sh — End-to-end sample: set env vars, call depeg-watchdog.sh, receive
# the depeg alerts it detects.
#
# Runs in DRY_RUN (checks the canned prices) so it works with no pay balance or
# credentials. Set LIVE=1 to pull real prices and deliver.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 1. Set the environment variables ----------------------------------------
if [ -f "$SCRIPT_DIR/.env" ]; then
  echo "Loading env from .env"
  set -a; . "$SCRIPT_DIR/.env"; set +a
else
  echo "No .env found — using inline demo values (override any via the environment)."
  export ASSETS="${ASSETS:-USDC, USDT, DAI, FRAX}"
  export THRESHOLD_PCT="${THRESHOLD_PCT:-0.5}"
fi

if [ "${LIVE:-0}" = "1" ]; then export DRY_RUN=0; else export DRY_RUN=1; fi

# --- 2. Call it and receive the alerts ---------------------------------------
echo
echo "==> Watching ${ASSETS} for >${THRESHOLD_PCT}% drift from peg"
echo

alerts="$("$SCRIPT_DIR/depeg-watchdog.sh" 2>/dev/null | grep '^ALERT: ' || true)"

# --- 3. Do something with the data -------------------------------------------
if [ -z "$alerts" ]; then
  echo "==> Everything within band. No depegs."
  exit 0
fi

echo "==> Depeg(s) detected:"
echo
printf '%s\n' "$alerts" | while IFS= read -r line; do
  printf '  • %s\n' "${line#ALERT: }"
done

echo
echo "==> Done. In live mode this alerts on the peg break and again on recovery."
