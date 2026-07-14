#!/usr/bin/env bash
#
# gas-ticker.sh — Get pinged when gas is cheap enough to transact.
#
# Reads the current gas price from pay.sh's JSON-RPC (paid per request in USDC,
# no API keys) and alerts you when it drops below your target, then again when it
# climbs back. Tracks a cheap/normal state so you get one alert per swing, not a
# page every run. Designed for a cron.
#
# Deliver via Telegram, a webhook, a websocket, or stdout (ALERT_SINK).
#
# Try it with zero setup:  DRY_RUN=1 ./gas-ticker.sh
#   Reads the canned example-gas.json (12 gwei) and prints the alert. No pay,
#   no network, no state written.
#
set -euo pipefail

# --- Config ------------------------------------------------------------------
# Required (live mode):
#   GWEI_THRESHOLD      alert when gas drops below this many gwei
#
# Delivery — pick one with ALERT_SINK (default: telegram):
#   telegram   -> needs TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID
#   webhook    -> needs WEBHOOK_URL   (POSTs the JSON payload)
#   websocket  -> needs WS_URL        (pushes the JSON payload via websocat)
#   stdout     -> prints the JSON payload (pipe it into your agent / anything)
#
# Optional:
#   CHAIN               display label for the network (default: ethereum)
#   PAYSH_RPC_URL       pay.sh JSON-RPC endpoint (has a sane default)
#   STATE_DIR           where gas state is stored (default: ~/.gas-ticker)
#   DRY_RUN=1           demo: read EXAMPLE_GAS, print instead of deliver
#   EXAMPLE_GAS         canned eth_gasPrice response for DRY_RUN

ALERT_SINK="${ALERT_SINK:-telegram}"
CHAIN="${CHAIN:-ethereum}"
PAYSH_RPC_URL="${PAYSH_RPC_URL:-https://rpc.pay.sh/eth}"
STATE_DIR="${STATE_DIR:-$HOME/.gas-ticker}"
DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_GAS="${EXAMPLE_GAS:-$SCRIPT_DIR/example-gas.json}"

# --- Helpers -----------------------------------------------------------------
log()  { printf '[gas-ticker] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed or not on PATH."; }
require_env() { [ -n "${!1:-}" ] || die "Missing required env var: $1"; }

# --- Preflight ---------------------------------------------------------------
require_cmd jq
require_cmd awk

if [ "$DRY_RUN" = "1" ]; then
  GWEI_THRESHOLD="${GWEI_THRESHOLD:-20}"
  [ -f "$EXAMPLE_GAS" ] || die "Fixture not found: $EXAMPLE_GAS"
  log "DRY RUN: reading $EXAMPLE_GAS against a ${GWEI_THRESHOLD} gwei target, printing instead of delivering."
else
  require_cmd curl
  require_env GWEI_THRESHOLD
  require_env PAYSH_RPC_URL
  case "$ALERT_SINK" in
    telegram)  require_env TELEGRAM_BOT_TOKEN; require_env TELEGRAM_CHAT_ID ;;
    webhook)   require_env WEBHOOK_URL ;;
    websocket) require_env WS_URL; require_cmd websocat ;;
    stdout)    : ;;
    *)         die "Unknown ALERT_SINK '$ALERT_SINK' (use: telegram|webhook|websocket|stdout)" ;;
  esac
fi

case "$GWEI_THRESHOLD" in ''|*[!0-9.]*) die "GWEI_THRESHOLD must be a number, got: '$GWEI_THRESHOLD'";; esac

# --- Read gas price over pay.sh ----------------------------------------------
# `pay` fronts the HTTP call and settles the x402 micropayment. eth_gasPrice
# returns wei as hex; we convert to gwei. If your route differs, change here.
fetch_gas_gwei() {
  local hex
  if [ "$DRY_RUN" = "1" ]; then
    hex="$(jq -r '.result // empty' "$EXAMPLE_GAS")"
  else
    hex="$(pay curl -s -X POST "$PAYSH_RPC_URL" \
      -H 'content-type: application/json' \
      -d '{"jsonrpc":"2.0","id":1,"method":"eth_gasPrice","params":[]}' 2>/dev/null \
      | jq -r '.result // empty' 2>/dev/null || true)"
  fi
  [ -n "$hex" ] || return 1
  # hex wei -> decimal wei (fits 64-bit for realistic gas) -> gwei, 2dp.
  local wei; wei="$(printf '%d' "$hex" 2>/dev/null)" || return 1
  awk "BEGIN{printf \"%.2f\", $wei/1000000000}"
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
  local status="$1" gwei="$2"
  local body
  if [ "$status" = "cheap" ]; then
    body="⛽ Gas is cheap: ${gwei} gwei on ${CHAIN} (below your ${GWEI_THRESHOLD} target). Good time to transact."
  else
    body="⛽ Gas back up: ${gwei} gwei on ${CHAIN} (above ${GWEI_THRESHOLD})."
  fi
  local payload
  payload="$(jq -nc \
    --arg type "$([ "$status" = cheap ] && echo gas_cheap || echo gas_normal)" \
    --arg chain "$CHAIN" --arg gwei "$gwei" --arg threshold "$GWEI_THRESHOLD" \
    --arg status "$status" --arg text "$body" \
    '{type:$type,chain:$chain,gwei:$gwei,threshold:$threshold,status:$status,text:$text}')"

  if [ "$DRY_RUN" = "1" ]; then
    printf 'ALERT: %s\n' "$body"
    printf 'PAYLOAD: %s\n' "$payload"
    return 0
  fi
  log "$body"
  deliver "$body" "$payload"
}

# --- Run ---------------------------------------------------------------------
gwei="$(fetch_gas_gwei || true)"
[ -n "${gwei:-}" ] || die "Could not read a gas price from the RPC."

# Is gas below the target right now?
below="$(awk "BEGIN{print ($gwei < $GWEI_THRESHOLD) ? 1 : 0}")"
now="normal"; [ "$below" = "1" ] && now="cheap"

# DRY_RUN: no state, just report the current read.
if [ "$DRY_RUN" = "1" ]; then
  if [ "$now" = "cheap" ]; then
    emit cheap "$gwei"
  else
    log "Gas is ${gwei} gwei on ${CHAIN}, not below ${GWEI_THRESHOLD}. Staying quiet."
  fi
  log "Done (dry run)."
  exit 0
fi

# Live: alert only when the cheap/normal state changes.
mkdir -p "$STATE_DIR"
SF="$STATE_DIR/${CHAIN}.status"
prev="normal"; [ -f "$SF" ] && prev="$(cat "$SF" 2>/dev/null || echo normal)"

if [ "$now" != "$prev" ]; then
  emit "$now" "$gwei"
  printf '%s\n' "$now" > "$SF"
else
  log "Gas is ${gwei} gwei on ${CHAIN} (${now}), no change."
  printf '%s\n' "$now" > "$SF"
fi
