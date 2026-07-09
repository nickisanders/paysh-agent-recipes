#!/usr/bin/env bash
#
# example.sh — End-to-end sample: set env vars, call brand-radar.sh, receive the
# new-mention alert.
#
# Runs in DRY_RUN (treats the canned mentions as new) so it works with no pay
# balance or credentials. Set LIVE=1 to search for real and deliver.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 1. Set the environment variables ----------------------------------------
if [ -f "$SCRIPT_DIR/.env" ]; then
  echo "Loading env from .env"
  set -a; . "$SCRIPT_DIR/.env"; set +a
else
  echo "No .env found — using inline demo values (override any via the environment)."
  export QUERY="${QUERY:-pay.sh}"
  export ALERT_SINK="${ALERT_SINK:-stdout}"
fi

if [ "${LIVE:-0}" = "1" ]; then export DRY_RUN=0; else export DRY_RUN=1; fi

# --- 2. Run it and receive the alert -----------------------------------------
echo
echo "==> Scanning for mentions of \"${QUERY}\""
echo

"$SCRIPT_DIR/brand-radar.sh" 2>/dev/null

echo
echo "==> Done. In live mode this alerts only on mentions it hasn't seen before."
