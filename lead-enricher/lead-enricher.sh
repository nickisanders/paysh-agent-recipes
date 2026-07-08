#!/usr/bin/env bash
#
# lead-enricher.sh — Turn a plain list of leads into an enriched CSV.
#
# Reads a CSV, looks up each row's key (an email or domain) through pay.sh's
# enrichment gateway (paid per request in USDC, no API keys), and writes the same
# rows back with extra columns: name, title, company, industry, headcount.
#
# Unlike the other recipes this isn't a monitor. It's a batch transform: CSV in,
# enriched CSV out. The output file is the deliverable, so there are no alert
# sinks.
#
# Try it with zero setup:  DRY_RUN=1 ./lead-enricher.sh
#   Enriches the canned example-leads.csv from a local fixture and prints the
#   result. No pay, no network.
#
set -euo pipefail

# --- Config ------------------------------------------------------------------
# Required (live mode):
#   INPUT_CSV           path to the input CSV (must have a header row)
#
# Optional:
#   KEY_COLUMN          header name to look up on (default: email)
#   OUTPUT_CSV          where to write the enriched CSV (default: stdout)
#   PAYSH_ENRICH_URL    pay.sh enrichment endpoint (has a sane default)
#   DRY_RUN=1           demo: enrich the fixture from EXAMPLE_ENRICH, print it
#   EXAMPLE_LEADS / EXAMPLE_ENRICH   fixtures used by DRY_RUN

KEY_COLUMN="${KEY_COLUMN:-email}"
PAYSH_ENRICH_URL="${PAYSH_ENRICH_URL:-https://enrich.pay.sh/lookup}"
DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_LEADS="${EXAMPLE_LEADS:-$SCRIPT_DIR/example-leads.csv}"
EXAMPLE_ENRICH="${EXAMPLE_ENRICH:-$SCRIPT_DIR/example-enrichment.json}"

# Columns this recipe appends to every row.
NEW_COLS="enriched_name,enriched_title,enriched_company,enriched_industry,enriched_employees"

# --- Helpers -----------------------------------------------------------------
log()  { printf '[lead-enricher] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed or not on PATH."; }
require_env() { [ -n "${!1:-}" ] || die "Missing required env var: $1"; }

# --- Preflight ---------------------------------------------------------------
require_cmd jq

if [ "$DRY_RUN" = "1" ]; then
  INPUT_CSV="${INPUT_CSV:-$EXAMPLE_LEADS}"
  [ -f "$INPUT_CSV" ]       || die "Input CSV not found: $INPUT_CSV"
  [ -f "$EXAMPLE_ENRICH" ]  || die "Fixture not found: $EXAMPLE_ENRICH"
  log "DRY RUN: enriching $INPUT_CSV from $EXAMPLE_ENRICH, printing to stdout."
else
  require_cmd curl
  require_env INPUT_CSV
  require_env PAYSH_ENRICH_URL
  [ -f "$INPUT_CSV" ] || die "Input CSV not found: $INPUT_CSV"
fi

# --- Enrichment lookup over pay.sh -------------------------------------------
# `pay` fronts the HTTP call and settles the x402 micropayment. Returns a JSON
# record; the field mapping below assumes flat keys. If your gateway nests them,
# adjust the jq in `enriched_fields`. One place to change.
enrich() {
  local key="$1"
  if [ "$DRY_RUN" = "1" ]; then
    jq -c --arg k "$key" '.[$k] // {}' "$EXAMPLE_ENRICH"
  else
    pay curl -s -G "$PAYSH_ENRICH_URL" --data-urlencode "query=${key}" 2>/dev/null || echo '{}'
  fi
}

# Pull the five columns we append, CSV-quoted. Empty record -> empty fields.
enriched_fields() {
  jq -r '[(.name // ""), (.title // ""), (.company // ""), (.industry // ""), (.employees // "")] | @csv' 2>/dev/null \
    || printf '"","","","",""'
}

# --- Find the key column index ----------------------------------------------
HEADER="$(head -1 "$INPUT_CSV")"
KEY_IDX="$(printf '%s' "$HEADER" | tr ',' '\n' | grep -n -x "$KEY_COLUMN" | head -1 | cut -d: -f1 || true)"
[ -n "$KEY_IDX" ] || die "KEY_COLUMN '$KEY_COLUMN' not found in header: $HEADER"

# --- Enrich, row by row ------------------------------------------------------
OUT="${OUTPUT_CSV:-/dev/stdout}"
rows=0
{
  printf '%s,%s\n' "$HEADER" "$NEW_COLS"
  tail -n +2 "$INPUT_CSV" | while IFS= read -r row; do
    [ -n "${row//[[:space:]]/}" ] || continue
    key="$(printf '%s' "$row" | cut -d, -f"$KEY_IDX" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    if [ -z "$key" ]; then
      log "Row has no '$KEY_COLUMN', leaving blank: $row"
      printf '%s,"","","","",""\n' "$row"
      continue
    fi
    log "Enriching: $key"
    fields="$(enrich "$key" | enriched_fields)"
    printf '%s,%s\n' "$row" "$fields"
  done
} > "$OUT"

# Report where it went (row count read from the input, minus header).
rows="$(( $(wc -l < "$INPUT_CSV") - 1 ))"
[ "$OUT" = "/dev/stdout" ] || log "Wrote $rows enriched row(s) to $OUT"
