#!/usr/bin/env bash
#
# example.sh — End-to-end sample: set env vars, call morning-brief.sh, receive
# the assembled brief.
#
# Runs in DRY_RUN (builds from the canned search fixture) so it works with no pay
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
  export TOPICS="${TOPICS:-AI agent payments, Solana ecosystem}"
  export ALERT_SINK="${ALERT_SINK:-stdout}"
fi

if [ "${LIVE:-0}" = "1" ]; then export DRY_RUN=0; else export DRY_RUN=1; fi

# --- 2. Call it and receive the brief ----------------------------------------
echo
echo "==> Building brief on: ${TOPICS}"
echo

"$SCRIPT_DIR/morning-brief.sh" 2>/dev/null

echo
echo "==> Done. In live mode this searches each topic and delivers via your sink."
