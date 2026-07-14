#!/usr/bin/env bash
#
# example.sh — End-to-end sample: set env vars, call gas-ticker.sh, receive the
# gas alert.
#
# Runs in DRY_RUN (reads the canned gas price) so it works with no pay balance or
# credentials. Set LIVE=1 to read real gas and deliver.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 1. Set the environment variables ----------------------------------------
if [ -f "$SCRIPT_DIR/.env" ]; then
  echo "Loading env from .env"
  set -a; . "$SCRIPT_DIR/.env"; set +a
else
  echo "No .env found — using inline demo values (override any via the environment)."
  export GWEI_THRESHOLD="${GWEI_THRESHOLD:-20}"
  export CHAIN="${CHAIN:-ethereum}"
fi

if [ "${LIVE:-0}" = "1" ]; then export DRY_RUN=0; else export DRY_RUN=1; fi

# --- 2. Run it and receive the alert -----------------------------------------
echo
echo "==> Watching ${CHAIN} gas for a drop below ${GWEI_THRESHOLD} gwei"
echo

alerts="$("$SCRIPT_DIR/gas-ticker.sh" 2>/dev/null | grep '^ALERT: ' || true)"

# --- 3. Do something with the data -------------------------------------------
if [ -z "$alerts" ]; then
  echo "==> Gas is not below your target right now. Nothing to send."
  exit 0
fi

echo "==> Alert:"
echo
printf '%s\n' "$alerts" | while IFS= read -r line; do
  printf '  • %s\n' "${line#ALERT: }"
done

echo
echo "==> Done. In live mode this alerts once when gas gets cheap and once when it climbs back."
