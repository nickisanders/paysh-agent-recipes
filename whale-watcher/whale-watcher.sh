#!/usr/bin/env bash
#
# whale-watcher.sh — Watch a wallet, SMS you when a whale-sized transaction lands.
#
# Queries Heurist Mesh for recent onchain activity of $WATCH_WALLET via `pay claude`
# (paid per-request over pay.sh — no API keys), and fires a Twilio SMS when a
# transaction at or above $THRESHOLD_USD is detected. Designed to run on a cron.
#
# It keeps a small state file of already-alerted transaction hashes so the same
# whale never pages you twice, and stays silent when nothing qualifies.
#
# Try it with zero setup:  DRY_RUN=1 ./whale-watcher.sh
#   Feeds the script the canned example-response.json instead of calling pay,
#   and prints the SMS it *would* send instead of texting. No pay/Twilio needed.
#
set -euo pipefail

# --- Config ------------------------------------------------------------------
# Required env vars (see README):
#   TWILIO_ACCOUNT_SID  TWILIO_AUTH_TOKEN  TWILIO_FROM  ALERT_TO
#   WATCH_WALLET  THRESHOLD_USD
#
# Optional:
#   STATE_DIR         where seen-tx hashes are stored (default: ~/.whale-watcher)
#   DRY_RUN=1         demo mode: use EXAMPLE_RESPONSE, no pay call, print SMS only
#   EXAMPLE_RESPONSE  canned JSON for DRY_RUN (default: ./example-response.json)

STATE_DIR="${STATE_DIR:-$HOME/.whale-watcher}"
DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_RESPONSE="${EXAMPLE_RESPONSE:-$SCRIPT_DIR/example-response.json}"

# --- Helpers -----------------------------------------------------------------
log()  { printf '[whale-watcher] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed or not on PATH."
}

require_env() {
  local name="$1"
  [ -n "${!name:-}" ] || die "Missing required env var: $name"
}

# --- Preflight ---------------------------------------------------------------
require_cmd jq

if [ "$DRY_RUN" = "1" ]; then
  # Demo mode: no pay/Twilio needed. Fill sensible defaults so it runs bare.
  WATCH_WALLET="${WATCH_WALLET:-0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045}"
  THRESHOLD_USD="${THRESHOLD_USD:-1000000}"
  ALERT_TO="${ALERT_TO:-+1XXXXXXXXXX}"
  log "DRY RUN — reading $EXAMPLE_RESPONSE, no pay call, printing SMS instead of sending."
else
  require_cmd pay
  require_cmd curl
  for v in TWILIO_ACCOUNT_SID TWILIO_AUTH_TOKEN TWILIO_FROM ALERT_TO WATCH_WALLET THRESHOLD_USD; do
    require_env "$v"
  done
fi

# Validate THRESHOLD_USD is numeric.
case "$THRESHOLD_USD" in
  ''|*[!0-9.]*) die "THRESHOLD_USD must be a number, got: '$THRESHOLD_USD'" ;;
esac

# Persist seen hashes in live mode; in dry-run use /dev/null so demos repeat.
if [ "$DRY_RUN" = "1" ]; then
  SEEN_FILE="/dev/null"
else
  mkdir -p "$STATE_DIR"
  SEEN_FILE="$STATE_DIR/${WATCH_WALLET}.seen"
  touch "$SEEN_FILE"
fi

# --- Query Heurist Mesh via pay claude ---------------------------------------
# We ask for STRICT JSON so the response is machine-parseable. Keep the schema
# tight — Claude fills usd_value from the onchain data Heurist Mesh returns.
read -r -d '' PROMPT <<EOF || true
Use the Heurist Mesh tools to look up the most recent onchain transactions for
wallet address ${WATCH_WALLET}. For each transaction include its hash, the USD
value at time of transfer, the token symbol, the direction ("in" or "out"), the
counterparty address, and an ISO 8601 timestamp.

Respond with ONLY a JSON object and nothing else — no markdown, no code fences,
no commentary. Use exactly this shape:

{"transactions":[{"hash":"...","usd_value":0,"token":"...","direction":"in|out","counterparty":"...","timestamp":"..."}]}

If you cannot find any transactions, respond with {"transactions":[]}.
EOF

if [ "$DRY_RUN" = "1" ]; then
  [ -f "$EXAMPLE_RESPONSE" ] || die "Example response not found: $EXAMPLE_RESPONSE"
  RAW="$(cat "$EXAMPLE_RESPONSE")"
else
  log "Querying Heurist Mesh for ${WATCH_WALLET} ..."
  RAW="$(pay claude -p "$PROMPT" 2>/dev/null || true)"
fi

if [ -z "${RAW//[[:space:]]/}" ]; then
  log "Empty response from pay claude — nothing to do."
  exit 0
fi

# Extract the JSON object even if the model wrapped it in prose or code fences.
# Drop ``` fence lines, then trim everything before the first '{' and after the
# last '}'. Parameter expansion keeps internal newlines intact, so multi-line
# (pretty-printed) JSON survives — jq parses the rest.
JSON="$(printf '%s' "$RAW" | tr -d '\r' | grep -v '^[[:space:]]*```')"
JSON="${JSON#"${JSON%%\{*}"}"   # strip any prose before the first '{'
JSON="${JSON%"${JSON##*\}}"}"   # strip any prose after the last '}'

# Validate it parses; if not, fail safe with no alert.
if ! printf '%s' "$JSON" | jq -e '.transactions' >/dev/null 2>&1; then
  log "Could not parse a transactions array from the response — no alert sent."
  exit 0
fi

# --- Find qualifying transactions --------------------------------------------
# Pull hash + usd_value + token + direction for anything at/above the threshold,
# highest value first. jq guards against null/missing usd_value.
QUALIFYING="$(printf '%s' "$JSON" | jq -c \
  --argjson thr "$THRESHOLD_USD" '
    [ .transactions[]
      | select((.usd_value // 0) >= $thr) ]
    | sort_by(-(.usd_value // 0))
    | .[]
  ' 2>/dev/null || true)"

if [ -z "${QUALIFYING//[[:space:]]/}" ]; then
  log "No transaction >= \$$THRESHOLD_USD found. Staying quiet."
  exit 0
fi

# --- Alert on each new whale (dedup via state file) --------------------------
alerts_sent=0
while IFS= read -r tx; do
  [ -n "$tx" ] || continue

  hash="$(printf '%s' "$tx" | jq -r '.hash // empty')"
  [ -n "$hash" ] || continue

  # Skip if we've already paged about this exact transaction.
  if grep -qxF "$hash" "$SEEN_FILE"; then
    continue
  fi

  usd="$(printf '%s' "$tx"       | jq -r '(.usd_value // 0)')"
  token="$(printf '%s' "$tx"     | jq -r '.token // "?"')"
  direction="$(printf '%s' "$tx" | jq -r '.direction // "?"')"
  other="$(printf '%s' "$tx"     | jq -r '.counterparty // "?"')"

  # Round USD to whole dollars for a clean text.
  usd_fmt="$(printf '%.0f' "$usd" 2>/dev/null || printf '%s' "$usd")"

  body="🐋 Whale alert: ${WATCH_WALLET:0:6}…${WATCH_WALLET: -4} ${direction} \$${usd_fmt} in ${token} (counterparty ${other:0:6}…). tx ${hash:0:10}…"

  if [ "$DRY_RUN" = "1" ]; then
    log "Whale detected (\$$usd_fmt $token) — would send SMS:"
    printf 'SMS -> %s: %s\n' "$ALERT_TO" "$body"
    alerts_sent=$((alerts_sent + 1))
    continue
  fi

  log "Whale detected (\$$usd_fmt $token). Sending SMS ..."
  http_code="$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
    "https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json" \
    --data-urlencode "To=${ALERT_TO}" \
    --data-urlencode "From=${TWILIO_FROM}" \
    --data-urlencode "Body=${body}" \
    -u "${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}" || echo "000")"

  if [ "$http_code" = "201" ]; then
    printf '%s\n' "$hash" >> "$SEEN_FILE"
    alerts_sent=$((alerts_sent + 1))
    log "SMS sent for tx $hash."
  else
    log "Twilio returned HTTP $http_code for tx $hash — will retry next run."
  fi
done <<< "$QUALIFYING"

log "Done. $alerts_sent alert(s) sent."
