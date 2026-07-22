#!/usr/bin/env bash
#
# example.sh — End-to-end sample: set env vars, call ask-onchain.sh, watch the
# agent plan, fetch, and answer.
#
# Runs in DRY_RUN (canned plan/fetch/answer) so it works with no pay balance or
# credentials. Set LIVE=1 to ask a real QUESTION.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 1. Set the environment variables ----------------------------------------
if [ -f "$SCRIPT_DIR/.env" ]; then
  echo "Loading env from .env"
  set -a; . "$SCRIPT_DIR/.env"; set +a
else
  echo "No .env found — asking the bundled demo question."
fi

if [ "${LIVE:-0}" = "1" ]; then export DRY_RUN=0; else export DRY_RUN=1; fi

# --- 2. Run it and watch the loop --------------------------------------------
echo
echo "==> Asking on-chain"
echo

"$SCRIPT_DIR/ask-onchain.sh" 2>/dev/null

echo
echo "==> Done. In live mode the agent picks a tool, pays for it, and answers."
