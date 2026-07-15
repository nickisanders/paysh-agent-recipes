#!/usr/bin/env bash
#
# example.sh — End-to-end sample: set env vars, call portfolio-pulse.sh, receive
# the snapshot.
#
# Runs in DRY_RUN (builds from the canned holdings) so it works with no pay
# balance or credentials. Set LIVE=1 to snapshot a real WALLET.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 1. Set the environment variables ----------------------------------------
if [ -f "$SCRIPT_DIR/.env" ]; then
  echo "Loading env from .env"
  set -a; . "$SCRIPT_DIR/.env"; set +a
else
  echo "No .env found — snapshotting the bundled fixture wallet."
fi

if [ "${LIVE:-0}" = "1" ]; then export DRY_RUN=0; else export DRY_RUN=1; fi

# --- 2. Run it and receive the snapshot --------------------------------------
echo
echo "==> Building portfolio snapshot"
echo

"$SCRIPT_DIR/portfolio-pulse.sh" 2>/dev/null

echo
echo "==> Done. In live mode this pulls real holdings and can push to any sink daily."
