#!/usr/bin/env bash
#
# example.sh — End-to-end sample: set env vars, call web-extractor.sh, receive the
# structured JSON.
#
# Runs in DRY_RUN (returns the canned result) so it works with no pay balance or
# credentials. Set LIVE=1 to extract from a real URL.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 1. Set the environment variables ----------------------------------------
if [ -f "$SCRIPT_DIR/.env" ]; then
  echo "Loading env from .env"
  set -a; . "$SCRIPT_DIR/.env"; set +a
else
  echo "No .env found — using inline demo values (override any via the environment)."
  export URL="${URL:-https://shop.example/widget}"
  export FIELDS="${FIELDS:-name,price,in_stock,rating}"
fi

if [ "${LIVE:-0}" = "1" ]; then export DRY_RUN=0; else export DRY_RUN=1; fi

# --- 2. Run it and receive the JSON ------------------------------------------
echo
echo "==> Extracting [${FIELDS}] from ${URL}"
echo

"$SCRIPT_DIR/web-extractor.sh" 2>/dev/null

echo
echo "==> Done. In live mode this pulls the fields straight from the page as typed JSON."
