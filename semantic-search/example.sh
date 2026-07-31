#!/usr/bin/env bash
#
# example.sh — Semantic Search end to end.
#
#   ./example.sh          demo: ranks the fixture corpus (precomputed vectors, no network)
#   LIVE=1 ./example.sh   real: needs a funded pay CLI + QUERY + CORPUS file
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [ "${LIVE:-0}" = "1" ]; then
  : "${QUERY:?set QUERY=\"...\" for a live run}"
  : "${CORPUS:?set CORPUS=path/to/docs.txt (one document per line)}"
  echo "LIVE: embedding query + corpus via pay.sh ..."
  exec ./semantic-search.sh
else
  echo "DEMO: query \"how do I get my money back?\" over a 4-doc corpus. Nothing spent, no network."
  echo
  DRY_RUN=1 ./semantic-search.sh
fi
