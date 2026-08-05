#!/usr/bin/env bash
#
# example.sh — Vision Extractor end to end.
#
#   ./example.sh          demo: extracts from the fixture (no network, no image)
#   LIVE=1 ./example.sh   real: needs a funded pay CLI + IMAGE=path/to/image
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [ "${LIVE:-0}" = "1" ]; then
  : "${IMAGE:?set IMAGE=path/to/image (e.g. a receipt photo) for a live run}"
  echo "LIVE: reading ${IMAGE} via pay.sh (Gemini) ..."
  exec ./vision-extractor.sh
else
  echo "DEMO: pulling merchant/date/total/currency/items from a receipt. Nothing spent, no network."
  echo
  DRY_RUN=1 ./vision-extractor.sh
fi
