#!/usr/bin/env bash
#
# depeg-watchdog.sh — Watch stablecoins and alert when one drifts off its peg.
#
# For each asset, it pulls the current price from pay.sh market data (paid per
# request in USDC, no API keys) and alerts when the price is more than
# THRESHOLD_PCT away from PEG. Designed to run on a cron. It tracks each asset's
# pegged/depegged state, so you get one alert when a coin breaks its peg and one
# when it recovers, not a page every single run.
#
# Deliver via Telegram, a webhook, a websocket, or stdout (ALERT_SINK).
#
# Try it with zero setup:  DRY_RUN=1 ./depeg-watchdog.sh
#   Checks the canned example-prices.json and prints the alerts it would send.
#   No pay, no network, no state written.
#
set -euo pipefail

# --- Config ------------------------------------------------------------------
# Required (live mode):
#   ASSETS              stablecoin symbols, comma/space separated (e.g. USDC,DAI)
#
# Delivery — pick one with ALERT_SINK (default: telegram):
#   telegram   -> needs TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID
#   webhook    -> needs WEBHOOK_URL   (POSTs the JSON payload)
#   websocket  -> needs WS_URL        (pushes the JSON payload via websocat)
#   stdout     -> prints the JSON payload (pipe it into your agent / anything)
#
# Optional:
#   PEG                 peg value to measure against (default: 1.00)
#   THRESHOLD_PCT       % drift from peg that triggers an alert (default: 0.5)
#   PAYSH_MARKET_URL    pay.sh market-data endpoint (has a sane default)
#   STATE_DIR           where peg state is stored (default: ~/.depeg-watchdog)
#   DRY_RUN=1           demo: check EXAMPLE_PRICES, print instead of deliver
#   EXAMPLE_PRICES      canned prices for DRY_RUN

ALERT_SINK="${ALERT_SINK:-telegram}"
PEG="${PEG:-1.00}"
THRESHOLD_PCT="${THRESHOLD_PCT:-0.5}"
PAYSH_MARKET_URL="${PAYSH_MARKET_URL:-https://market.pay.sh/price}"
STATE_DIR="${STATE_DIR:-$HOME/.depeg-watchdog}"
DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_PRICES="${EXAMPLE_PRICES:-$SCRIPT_DIR/example-prices.json}"

# --- Helpers -----------------------------------------------------------------
log()  { printf '[depeg-watchdog] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed or not on PATH."; }
require_env() { [ -n "${!1:-}" ] || die "Missing required env var: $1"; }

# --- Preflight ---------------------------------------------------------------
require_cmd jq
require_cmd bc

if [ "$DRY_RUN" = "1" ]; then
  ASSETS="${ASSETS:-USDC, USDT, DAI, FRAX}"
  [ -f "$EXAMPLE_PRICES" ] || die "Fixture not found: $EXAMPLE_PRICES"
  log "DRY RUN: checking $EXAMPLE_PRICES against a ${THRESHOLD_PCT}% band, printing instead of delivering."
else
  require_cmd curl
  require_env ASSETS
  require_env PAYSH_MARKET_URL
  case "$ALERT_SINK" in
    telegram)  require_env TELEGRAM_BOT_TOKEN; require_env TELEGRAM_CHAT_ID ;;
    webhook)   require_env WEBHOOK_URL ;;
    websocket) require_env WS_URL; require_cmd websocat ;;
    stdout)    : ;;
    *)         die "Unknown ALERT_SINK '$ALERT_SINK' (use: telegram|webhook|websocket|stdout)" ;;
  esac
fi

case "$THRESHOLD_PCT" in ''|*[!0-9.]*) die "THRESHOLD_PCT must be a number, got: '$THRESHOLD_PCT'";; esac

# --- Price lookup over pay.sh ------------------------------------------------
# `pay` fronts the HTTP call and settles the x402 micropayment. Returns the USD
# price; we read the likely fields. Adjust this one function if your route differs.
fetch_price() {
  local asset="$1" raw
  raw="$(pay curl -s -G "$PAYSH_MARKET_URL" --data-urlencode "symbol=${asset}" 2>/dev/null || true)"
  printf '%s' "$raw" | jq -r '.price // .usd // .current_price // empty' 2>/dev/null || true
}

# --- Delivery (pluggable sink) -----------------------------------------------
deliver() {
  local text="$1" payload="$2"
  case "$ALERT_SINK" in
    telegram)
      local code
      code="$(curl -sS -o /dev/null -w '%{http_code}' \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${text}" \
        --data-urlencode "disable_web_page_preview=true" || echo "000")"
      [ "$code" = "200" ] && log "Pushed to Telegram." || log "Telegram HTTP $code."
      ;;
    webhook)
      local code
      code="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$WEBHOOK_URL" \
        -H 'content-type: application/json' --data "$payload" || echo "000")"
      case "$code" in 2*) log "Posted to webhook ($code).";; *) log "Webhook HTTP $code.";; esac
      ;;
    websocket)
      if printf '%s\n' "$payload" | websocat -n1 "$WS_URL" >/dev/null 2>&1; then
        log "Pushed to websocket."
      else
        log "Websocket push failed ($WS_URL)."
      fi
      ;;
    stdout)
      printf '%s\n' "$payload"
      ;;
  esac
}

# --- Emit one alert ----------------------------------------------------------
emit() {
  local status="$1" asset="$2" price="$3" dev="$4" dir="$5"
  local dev_fmt; dev_fmt="$(printf '%.2f' "$dev")"
  local body
  if [ "$status" = "depegged" ]; then
    body="⚠️ Depeg alert: ${asset} at \$${price}, ${dev_fmt}% ${dir} \$${PEG} peg."
  else
    body="✅ Repeg: ${asset} back at \$${price}, within ${THRESHOLD_PCT}% of \$${PEG}."
  fi
  local payload
  payload="$(jq -nc \
    --arg type "$([ "$status" = depegged ] && echo depeg_alert || echo repeg)" \
    --arg asset "$asset" --arg price "$price" --arg peg "$PEG" \
    --arg deviation_pct "$dev_fmt" --arg direction "$dir" --arg text "$body" \
    '{type:$type,asset:$asset,price:$price,peg:$peg,deviation_pct:$deviation_pct,direction:$direction,text:$text}')"

  if [ "$DRY_RUN" = "1" ]; then
    printf 'ALERT: %s\n' "$body"
    printf 'PAYLOAD: %s\n' "$payload"
    return 0
  fi
  log "$body"
  deliver "$body" "$payload"
}

# --- Check one asset ---------------------------------------------------------
check_asset() {
  local asset="$1" price
  if [ "$DRY_RUN" = "1" ]; then
    price="$(jq -r --arg a "$asset" '.[$a] // empty' "$EXAMPLE_PRICES")"
  else
    price="$(fetch_price "$asset")"
  fi
  if [ -z "${price//[[:space:]]/}" ]; then
    log "No price for $asset, skipping."
    return 0
  fi

  # Signed deviation from peg, in percent. abs value for the threshold test.
  local dev abs over dir
  dev="$(printf 'scale=6; (%s - %s) / %s * 100\n' "$price" "$PEG" "$PEG" | bc)"
  abs="${dev#-}"
  over="$(printf '%s >= %s\n' "$abs" "$THRESHOLD_PCT" | bc)"
  case "$dev" in -*) dir="below" ;; *) dir="above" ;; esac

  local now="pegged"; [ "$over" = "1" ] && now="depegged"

  # DRY_RUN: no state, just report anything currently off peg.
  if [ "$DRY_RUN" = "1" ]; then
    if [ "$now" = "depegged" ]; then
      emit depegged "$asset" "$price" "$abs" "$dir"
    else
      log "$asset at \$$price is within band ($(printf '%.2f' "$abs")%)."
    fi
    return 0
  fi

  # Live: alert only when the pegged/depegged state changes.
  local sf="$STATE_DIR/${asset}.status" prev="pegged"
  [ -f "$sf" ] && prev="$(cat "$sf" 2>/dev/null || echo pegged)"
  if [ "$now" != "$prev" ]; then
    if [ "$now" = "depegged" ]; then emit depegged "$asset" "$price" "$abs" "$dir"
    else                             emit repegged  "$asset" "$price" "$abs" "$dir"; fi
    printf '%s\n' "$now" > "$sf"
  else
    log "$asset at \$$price ($now), no change."
    printf '%s\n' "$now" > "$sf"
  fi
}

# --- Run ---------------------------------------------------------------------
[ "$DRY_RUN" = "1" ] || mkdir -p "$STATE_DIR"

printf '%s\n' "$ASSETS" | tr ',' '\n' | while IFS= read -r asset; do
  asset="$(printf '%s' "$asset" | tr -d '[:space:]')"
  [ -n "$asset" ] || continue
  check_asset "$asset"
done
