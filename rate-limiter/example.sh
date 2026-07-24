#!/usr/bin/env bash
#
# example.sh — Show the rate limiter allow a burst up to the cap, then trip.
#
# Runs in DRY_RUN (no pay, nothing spent). A fresh temp bucket keeps it repeatable.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DRY_RUN=1 RATE_MAX=3 RATE_WINDOW_SEC=60 RATE_STATE_DIR="$(mktemp -d)"

echo "==> Limit: 3 calls per 60s. A buggy loop fires 6 in a row."
echo
for i in 1 2 3 4 5 6; do
  "$SCRIPT_DIR/rate-limiter.sh" pay curl -s https://audit.pay.sh/contract || true
done

echo
echo "==> Done. The first 3 ran, the rest were blocked. Put 'rate-limiter.sh' in front of your pay calls."
