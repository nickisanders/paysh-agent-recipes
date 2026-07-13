#!/usr/bin/env bash
#
# web-extractor.sh — Turn any web page into structured JSON for the fields you name.
#
# Give it a URL and a list of fields; it asks pay.sh's structured-extract endpoint
# (paid per request in USDC, no API keys) to pull just those fields and returns
# clean, typed JSON. No parsing HTML, no scraping the whole page: you name the
# fields, you get the values.
#
# Not a monitor. It's a transform: URL in, JSON out. The JSON is the deliverable,
# so there are no alert sinks. Print it, save it, or pipe it into an agent.
#
# Try it with zero setup:  DRY_RUN=1 ./web-extractor.sh
#   Returns the canned example-extract.json. No pay, no network.
#
set -euo pipefail

# --- Config ------------------------------------------------------------------
# Required (live mode):
#   URL                 the page to extract from (or pass as the first argument)
#   FIELDS              comma-separated fields to pull (e.g. name,price,in_stock)
#
# Optional:
#   OUTPUT              where to write the JSON (default: stdout)
#   PAYSH_EXTRACT_URL   pay.sh structured-extract endpoint (has a sane default)
#   DRY_RUN=1           demo: return EXAMPLE_EXTRACT instead of calling pay
#   EXAMPLE_EXTRACT     canned result for DRY_RUN

URL="${URL:-${1:-}}"
FIELDS="${FIELDS:-}"
PAYSH_EXTRACT_URL="${PAYSH_EXTRACT_URL:-https://extract.pay.sh/fields}"
DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_EXTRACT="${EXAMPLE_EXTRACT:-$SCRIPT_DIR/example-extract.json}"

# --- Helpers -----------------------------------------------------------------
log()  { printf '[web-extractor] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed or not on PATH."; }
require_env() { [ -n "${!1:-}" ] || die "Missing required env var: $1"; }

# --- Preflight ---------------------------------------------------------------
require_cmd jq

if [ "$DRY_RUN" = "1" ]; then
  URL="${URL:-https://shop.example/widget}"
  FIELDS="${FIELDS:-name,price,in_stock,rating}"
  [ -f "$EXAMPLE_EXTRACT" ] || die "Fixture not found: $EXAMPLE_EXTRACT"
  log "DRY RUN: returning $EXAMPLE_EXTRACT for fields [$FIELDS], no pay call."
else
  require_cmd curl
  [ -n "$URL" ] || die "Set URL (or pass it as the first argument)."
  require_env FIELDS
  require_env PAYSH_EXTRACT_URL
fi

# Fields as a JSON array of trimmed, non-empty strings. awk trims and drops
# blanks and always exits 0, so an all-blank FIELDS reaches the check below.
FIELDS_JSON="$(printf '%s' "$FIELDS" | tr ',' '\n' \
  | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); if (length) print }' | jq -R . | jq -s .)"
[ "$(printf '%s' "$FIELDS_JSON" | jq 'length')" -gt 0 ] || die "FIELDS has no usable field names."

# --- Structured extract over pay.sh ------------------------------------------
# `pay` fronts the HTTP call and settles the x402 micropayment. Sends the URL and
# the field list; expects a JSON object of {field: value} back. Adjust the request
# shape here if your pay.sh route differs.
extract() {
  if [ "$DRY_RUN" = "1" ]; then
    cat "$EXAMPLE_EXTRACT"
    return 0
  fi
  local body
  body="$(jq -nc --arg url "$URL" --argjson fields "$FIELDS_JSON" '{url:$url, fields:$fields}')"
  pay curl -s -X POST "$PAYSH_EXTRACT_URL" \
    -H 'content-type: application/json' --data "$body" 2>/dev/null || echo '{}'
}

# --- Run ---------------------------------------------------------------------
log "Extracting [$FIELDS] from $URL ..."
result="$(extract)"

if ! printf '%s' "$result" | jq -e . >/dev/null 2>&1; then
  die "Extract endpoint returned no usable JSON."
fi

# Pretty JSON to the chosen destination.
OUT="${OUTPUT:-/dev/stdout}"
printf '%s\n' "$result" | jq . > "$OUT"
[ "$OUT" = "/dev/stdout" ] || log "Wrote extracted JSON to $OUT"
