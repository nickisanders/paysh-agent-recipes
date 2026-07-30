#!/usr/bin/env bash
#
# example.sh — NFT Floor Watcher end to end.
#
#   ./example.sh          demo: evaluates the fixture against a 13 SOL buy line (no network)
#   LIVE=1 ./example.sh   real: needs a funded pay CLI + COLLECTION + a threshold
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [ "${LIVE:-0}" = "1" ]; then
  : "${COLLECTION:?set COLLECTION=<slug> for a live run}"
  echo "LIVE: checking ${COLLECTION} floor via pay.sh ..."
  exec ./nft-floor-watcher.sh
else
  echo "DEMO: floor 12.4 SOL vs a 13 SOL buy line. Nothing spent, no network."
  echo
  DRY_RUN=1 FLOOR_BELOW_SOL=13 ./nft-floor-watcher.sh
fi
