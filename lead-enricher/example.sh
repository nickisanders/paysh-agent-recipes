#!/usr/bin/env bash
#
# example.sh — End-to-end sample: show the input, run lead-enricher.sh, show the
# enriched output.
#
# Runs in DRY_RUN (enriches the fixture from a local file) so it works with no pay
# balance or credentials. Set LIVE=1 to enrich INPUT_CSV for real.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 1. Set the environment variables ----------------------------------------
if [ -f "$SCRIPT_DIR/.env" ]; then
  echo "Loading env from .env"
  set -a; . "$SCRIPT_DIR/.env"; set +a
else
  echo "No .env found — using the bundled example-leads.csv."
  export INPUT_CSV="${INPUT_CSV:-$SCRIPT_DIR/example-leads.csv}"
fi

if [ "${LIVE:-0}" = "1" ]; then export DRY_RUN=0; else export DRY_RUN=1; fi

# --- 2. Show the input, run, show the output ---------------------------------
echo
echo "==> Input (${INPUT_CSV}):"
column -t -s, "$INPUT_CSV" 2>/dev/null || cat "$INPUT_CSV"

echo
echo "==> Enriched:"
"$SCRIPT_DIR/lead-enricher.sh" 2>/dev/null | column -t -s,

echo
echo "==> Done. In live mode each row is looked up through pay.sh's enrichment gateway."
