#!/usr/bin/env bash
#
# example.sh — End-to-end sample: set env vars, call contract-auditor.sh, receive
# the risk brief.
#
# Runs in DRY_RUN (audits the canned fixture) so it works with no pay balance or
# credentials. Set LIVE=1 to audit a real ADDRESS.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 1. Set the environment variables ----------------------------------------
if [ -f "$SCRIPT_DIR/.env" ]; then
  echo "Loading env from .env"
  set -a; . "$SCRIPT_DIR/.env"; set +a
else
  echo "No .env found — auditing the bundled fixture contract."
fi

if [ "${LIVE:-0}" = "1" ]; then export DRY_RUN=0; else export DRY_RUN=1; fi

# --- 2. Run it and receive the brief -----------------------------------------
echo
echo "==> Auditing contract"
echo

"$SCRIPT_DIR/contract-auditor.sh" 2>/dev/null

echo
echo "==> Done. In live mode this audits a real address and can push to any sink."
