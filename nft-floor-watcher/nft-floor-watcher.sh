#!/usr/bin/env bash
#
# nft-floor-watcher.sh — Alert when an NFT collection's floor crosses your line.
#
# Checks a Solana NFT collection's floor price via a paid pay.sh call and alerts
# when it drops below your buy line or rises above your sell line. Paid per
# request in USDC on Solana, no API keys.
#
# Only fires on a crossing, not on every check, so a collection sitting under your
# buy line does not spam you. It remembers the last floor it saw per collection.
#
# Deliver via stdout (default), Telegram, a webhook, or a websocket.
#
# Try it with zero setup:  DRY_RUN=1 ./nft-floor-watcher.sh
#   Evaluates the canned example-floor.json against a 13 SOL buy line. No pay, no network.
#
set -euo pipefail

# --- Config ------------------------------------------------------------------
# Required (live mode):
#   COLLECTION            collection slug/symbol to watch (or pass as the first argument)
#   FLOOR_BELOW_SOL       and/or FLOOR_ABOVE_SOL   at least one threshold
#
# Optional:
#   ALERT_SINK            stdout (default) | telegram | webhook | websocket
#   PAYSH_NFT_URL         the pay.sh floor endpoint (sane default)
#   STATE_DIR             where the last-seen floor is remembered (default ~/.nft-floor-watcher)
#   DRY_RUN=1             demo: read EXAMPLE_FLOOR, print instead of deliver
#   EXAMPLE_FLOOR         canned snapshot for DRY_RUN

COLLECTION="${COLLECTION:-${1:-}}"
FLOOR_BELOW_SOL="${FLOOR_BELOW_SOL:-}"
FLOOR_ABOVE_SOL="${FLOOR_ABOVE_SOL:-}"
ALERT_SINK="${ALERT_SINK:-stdout}"
PAYSH_NFT_URL="${PAYSH_NFT_URL:-https://market.pay.sh/nft/floor}"
DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${STATE_DIR:-$HOME/.nft-floor-watcher}"
EXAMPLE_FLOOR="${EXAMPLE_FLOOR:-$SCRIPT_DIR/example-floor.json}"

# --- Helpers -----------------------------------------------------------------
log()  { printf '[nft-floor-watcher] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed or not on PATH."; }
require_env() { [ -n "${!1:-}" ] || die "Missing required env var: $1"; }
# Float compare: `fcmp A '<=' B` succeeds (exit 0) when the relation holds.
fcmp() { awk -v a="$1" -v b="$3" "BEGIN{ exit !(a $2 b) }"; }

# --- Preflight ---------------------------------------------------------------
require_cmd jq
require_cmd awk

if [ "$DRY_RUN" = "1" ]; then
  [ -f "$EXAMPLE_FLOOR" ] || die "Fixture not found: $EXAMPLE_FLOOR"
  COLLECTION="${COLLECTION:-$(jq -r '.slug // .collection // "collection"' "$EXAMPLE_FLOOR")}"
  # A default buy line so the demo actually fires against the fixture floor.
  [ -n "$FLOOR_BELOW_SOL$FLOOR_ABOVE_SOL" ] || FLOOR_BELOW_SOL="13"
  log "DRY RUN: evaluating example-floor.json, printing instead of delivering."
else
  require_cmd curl
  [ -n "$COLLECTION" ] || die "Set COLLECTION (or pass the collection slug as the first argument)."
  [ -n "$FLOOR_BELOW_SOL$FLOOR_ABOVE_SOL" ] || die "Set FLOOR_BELOW_SOL and/or FLOOR_ABOVE_SOL."
  require_env PAYSH_NFT_URL
  case "$ALERT_SINK" in
    stdout)    : ;;
    telegram)  require_env TELEGRAM_BOT_TOKEN; require_env TELEGRAM_CHAT_ID ;;
    webhook)   require_env WEBHOOK_URL ;;
    websocket) require_env WS_URL; require_cmd websocat ;;
    *)         die "Unknown ALERT_SINK '$ALERT_SINK' (use: stdout|telegram|webhook|websocket)" ;;
  esac
fi

# --- The paid source ---------------------------------------------------------
# `pay` fronts the HTTP call and settles the x402 micropayment. In DRY_RUN it
# reads the fixture. Adjust the field mapping if your endpoint's shape differs.
fetch_floor() {
  if [ "$DRY_RUN" = "1" ]; then
    cat "$EXAMPLE_FLOOR"
  else
    pay curl -s -G "$PAYSH_NFT_URL" --data-urlencode "collection=$COLLECTION" 2>/dev/null \
      | jq -c '.' 2>/dev/null || echo '{}'
  fi
}

# --- Delivery (pluggable sink) -----------------------------------------------
deliver() {
  local text="$1" payload="$2"
  case "$ALERT_SINK" in
    stdout)    printf '%s\n' "$text" ;;
    telegram)
      local code
      code="$(curl -sS -o /dev/null -w '%{http_code}' \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" --data-urlencode "text=${text}" || echo "000")"
      [ "$code" = "200" ] && log "Pushed to Telegram." || log "Telegram HTTP $code." ;;
    webhook)
      local code
      code="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$WEBHOOK_URL" \
        -H 'content-type: application/json' --data "$payload" || echo "000")"
      case "$code" in 2*) log "Posted to webhook ($code).";; *) log "Webhook HTTP $code.";; esac ;;
    websocket)
      printf '%s\n' "$payload" | websocat -n1 "$WS_URL" >/dev/null 2>&1 \
        && log "Pushed to websocket." || log "Websocket push failed ($WS_URL)." ;;
  esac
}

# --- Fetch + parse -----------------------------------------------------------
log "Checking floor for ${COLLECTION} ..."
snapshot="$(fetch_floor)"

name="$(printf '%s'  "$snapshot" | jq -r '.collection // empty')"
[ -n "$name" ] || name="$COLLECTION"
floor="$(printf '%s' "$snapshot" | jq -r '.floor_sol // .floor // empty')"
[ -n "$floor" ] || die "No floor price in the response for '${COLLECTION}'."
prev_floor="$(printf '%s' "$snapshot" | jq -r '.prev_floor_sol // empty')"
listed="$(printf '%s'    "$snapshot" | jq -r '.listed // empty')"

# --- Crossing logic ----------------------------------------------------------
# Persisted last-seen floor lets us fire only on a crossing, not every check.
# In DRY_RUN (and on first-ever sight) there is no state, so a breach fires once.
mkdir -p "$STATE_DIR" 2>/dev/null || true
state_file="$STATE_DIR/$(printf '%s' "$COLLECTION" | tr -c 'A-Za-z0-9._-' '_').floor"
last=""
[ "$DRY_RUN" = "1" ] || { [ -f "$state_file" ] && last="$(cat "$state_file" 2>/dev/null)"; }

alert=""      # below | above | (empty = no alert)
line=""
if [ -n "$FLOOR_BELOW_SOL" ] && fcmp "$floor" '<=' "$FLOOR_BELOW_SOL"; then
  # Fire only if we weren't already under the line last time.
  if [ -z "$last" ] || fcmp "$last" '>' "$FLOOR_BELOW_SOL"; then alert="below"; line="$FLOOR_BELOW_SOL"; fi
fi
if [ -z "$alert" ] && [ -n "$FLOOR_ABOVE_SOL" ] && fcmp "$floor" '>=' "$FLOOR_ABOVE_SOL"; then
  if [ -z "$last" ] || fcmp "$last" '<' "$FLOOR_ABOVE_SOL"; then alert="above"; line="$FLOOR_ABOVE_SOL"; fi
fi

# Remember this floor for next time (live only).
[ "$DRY_RUN" = "1" ] || printf '%s\n' "$floor" > "$state_file" 2>/dev/null || true

# --- Assemble ----------------------------------------------------------------
# Optional "(was X, -Y%)" delta when we know a previous floor.
delta=""
if [ -n "$prev_floor" ] && fcmp "$prev_floor" '>' "0"; then
  pct="$(awk -v f="$floor" -v p="$prev_floor" 'BEGIN{ printf "%+.0f", (f-p)/p*100 }')"
  delta=" (was ${prev_floor}, ${pct}%)"
fi

facts="Floor ${floor} SOL${delta}"
[ -n "$listed" ] && facts="${facts}  •  ${listed} listed"

body="🖼️ NFT Floor Watcher: ${name}
${facts}"
case "$alert" in
  below) body="${body}
⤵️ Dropped below your ${line} SOL buy line." ;;
  above) body="${body}
⤴️ Rose above your ${line} SOL sell line." ;;
  *)     body="${body}
✅ Within range, no alert." ;;
esac

payload="$(jq -nc \
  --arg collection "$COLLECTION" --arg name "$name" \
  --argjson floor "$floor" \
  --arg alert "${alert:-none}" --arg text "$body" \
  --argjson listed "${listed:-null}" --argjson prev "${prev_floor:-null}" \
  '{type:"nft_floor",collection:$collection,name:$name,floor_sol:$floor,
    prev_floor_sol:$prev,listed:$listed,alert:$alert,text:$text}')"

if [ "$DRY_RUN" = "1" ]; then
  printf '%s\n' "$body"
  log "Done (dry run)."
  exit 0
fi

# Only ship on an actual crossing; a plain in-range check stays quiet.
if [ -n "$alert" ]; then
  deliver "$body" "$payload"
  log "Done (alert: $alert)."
else
  [ "$ALERT_SINK" = "stdout" ] && printf '%s\n' "$body"
  log "Done (no crossing)."
fi
