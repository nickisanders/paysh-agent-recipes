#!/usr/bin/env bash
#
# example.sh — End-to-end sample: set env vars, call whale-watcher.sh, receive
# the alert data back and act on it.
#
# This is the integration pattern you'd embed in your own tooling: run the
# watcher, capture the transactions it flags, and do something with them
# (here we just parse and print a summary).
#
# Runs in DRY_RUN by default so it works with no pay balance or Twilio creds.
# To run it for real, set LIVE=1 and make sure your .env has valid credentials.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 1. Set the environment variables ----------------------------------------
# Prefer a local .env if present; otherwise fall back to inline demo values.
if [ -f "$SCRIPT_DIR/.env" ]; then
  echo "Loading env from .env"
  set -a; . "$SCRIPT_DIR/.env"; set +a
else
  echo "No .env found — using inline demo values (override any via the environment)."
  export WATCH_WALLET="${WATCH_WALLET:-0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045}"
  export THRESHOLD_USD="${THRESHOLD_USD:-1000000}"
  export ALERT_TO="${ALERT_TO:-+14155550123}"
fi

# Toggle real vs. demo. LIVE=1 calls pay + Twilio for real; default is DRY_RUN.
if [ "${LIVE:-0}" = "1" ]; then
  export DRY_RUN=0
else
  export DRY_RUN=1
fi

# --- 2. Call the script, receive its data ------------------------------------
# whale-watcher.sh prints one `SMS -> <to>: <body>` line per flagged whale on
# stdout (and diagnostics on stderr). We capture stdout as the "received data".
echo
echo "==> Running whale-watcher.sh (watching ${WATCH_WALLET}, threshold \$${THRESHOLD_USD})"
echo

alerts="$("$SCRIPT_DIR/whale-watcher.sh" | grep '^SMS -> ' || true)"

# --- 3. Do something with the data -------------------------------------------
if [ -z "$alerts" ]; then
  echo "==> No whales over the threshold. Nothing to process."
  exit 0
fi

count="$(printf '%s\n' "$alerts" | wc -l | tr -d ' ')"
echo "==> Received $count alert(s):"
echo

# Each line looks like:  SMS -> +1...: 🐋 Whale alert: ...
# Strip the `SMS -> <to>: ` prefix to get just the message body.
printf '%s\n' "$alerts" | while IFS= read -r line; do
  body="${line#SMS -> *: }"
  printf '  • %s\n' "$body"
done

echo
echo "==> Done. Plug this loop into Slack, a webhook, a DB — wherever you route alerts."
