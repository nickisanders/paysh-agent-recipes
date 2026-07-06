#!/usr/bin/env bash
#
# example.sh — End-to-end sample: set env vars, call page-watch.sh, receive the
# change it detects and act on it.
#
# Runs in DRY_RUN (diffs the two fixtures) so it works with no pay balance or
# credentials. Set LIVE=1 to scrape the real WATCH_URL and deliver for real.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 1. Set the environment variables ----------------------------------------
if [ -f "$SCRIPT_DIR/.env" ]; then
  echo "Loading env from .env"
  set -a; . "$SCRIPT_DIR/.env"; set +a
else
  echo "No .env found — using inline demo values (override any via the environment)."
  export WATCH_URL="${WATCH_URL:-https://acme.example/pricing}"
fi

if [ "${LIVE:-0}" = "1" ]; then export DRY_RUN=0; else export DRY_RUN=1; fi

# --- 2. Call the watcher, receive its data -----------------------------------
echo
echo "==> Running page-watch.sh (watching ${WATCH_URL})"
echo

alerts="$("$SCRIPT_DIR/page-watch.sh" 2>/dev/null | grep '^ALERT: ' || true)"

# --- 3. Do something with the data -------------------------------------------
if [ -z "$alerts" ]; then
  echo "==> No change detected. Nothing to do."
  exit 0
fi

echo "==> Change detected:"
echo
printf '%s\n' "$alerts" | while IFS= read -r line; do
  printf '  • %s\n' "${line#ALERT: }"
done

echo
echo "==> Done. In live mode this delivers to your chosen sink the moment the page changes."
