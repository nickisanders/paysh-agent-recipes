#!/usr/bin/env bash
#
# example.sh — Spend Report end to end.
#
#   ./example.sh          demo: rolls up the canned example-ledgers/ (no network)
#   LIVE=1 ./example.sh   real: reads your actual Spend Guard state dir
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [ "${LIVE:-0}" = "1" ]; then
  echo "LIVE: reading ${GUARD_STATE_DIR:-$HOME/.spend-guard} ..."
  exec ./spend-report.sh
else
  echo "DEMO: rolling up the canned ledgers. Nothing spent, no network."
  echo
  DRY_RUN=1 ./spend-report.sh
fi
