#!/usr/bin/env bash
#
# example.sh — End-to-end sample: set env vars, call company-dossier.sh, receive
# the brief.
#
# Runs in DRY_RUN (builds from the canned sources) so it works with no pay balance
# or credentials. Set LIVE=1 to research a real DOMAIN.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 1. Set the environment variables ----------------------------------------
if [ -f "$SCRIPT_DIR/.env" ]; then
  echo "Loading env from .env"
  set -a; . "$SCRIPT_DIR/.env"; set +a
else
  echo "No .env found — building a dossier from the bundled fixture."
fi

if [ "${LIVE:-0}" = "1" ]; then export DRY_RUN=0; else export DRY_RUN=1; fi

# --- 2. Run it and receive the brief -----------------------------------------
echo
echo "==> Building company dossier"
echo

"$SCRIPT_DIR/company-dossier.sh" 2>/dev/null

echo
echo "==> Done. In live mode this pays for enrichment + news and synthesizes a brief."
