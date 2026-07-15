#!/usr/bin/env bash
#
# portfolio-pulse.sh — A daily snapshot of a wallet's holdings and value.
#
# Pulls a wallet's token holdings and USD values from pay.sh (paid per request in
# USDC, no API keys) and prints a clean snapshot: total value, 24h change, top
# holdings, and the biggest mover. Not an alert, a digest. Designed for a daily
# cron so you wake up to where your bags stand.
#
# Deliver via stdout (default), Telegram, a webhook, or a websocket.
#
# Try it with zero setup:  DRY_RUN=1 ./portfolio-pulse.sh
#   Builds the snapshot from the canned example-portfolio.json. No pay, no network.
#
set -euo pipefail

# --- Config ------------------------------------------------------------------
# Required (live mode):
#   WALLET              wallet address to snapshot (or pass as the first argument)
#
# Optional:
#   CHAIN               network the wallet is on (default: ethereum)
#   TOP                 how many holdings to list (default: 5)
#   ALERT_SINK          stdout (default) | telegram | webhook | websocket
#   PAYSH_WALLET_URL    pay.sh wallet-holdings endpoint (has a sane default)
#   DRY_RUN=1           demo: build from EXAMPLE_PORTFOLIO, print instead of deliver
#   EXAMPLE_PORTFOLIO   canned holdings for DRY_RUN

WALLET="${WALLET:-${1:-}}"
CHAIN="${CHAIN:-ethereum}"
TOP="${TOP:-5}"
ALERT_SINK="${ALERT_SINK:-stdout}"
PAYSH_WALLET_URL="${PAYSH_WALLET_URL:-https://wallet.pay.sh/holdings}"
DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_PORTFOLIO="${EXAMPLE_PORTFOLIO:-$SCRIPT_DIR/example-portfolio.json}"

# --- Helpers -----------------------------------------------------------------
log()  { printf '[portfolio-pulse] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed or not on PATH."; }
require_env() { [ -n "${!1:-}" ] || die "Missing required env var: $1"; }

# Format a number as USD with thousands separators, no decimals. Commas are
# inserted manually so it works regardless of awk locale support.
usd() {
  awk -v n="$1" 'BEGIN{
    neg=(n<0); if(neg) n=-n;
    s=sprintf("%d", int(n+0.5)); out=""; len=length(s);
    for(i=1;i<=len;i++){ out=out substr(s,i,1); r=len-i; if(r>0 && r%3==0) out=out ","; }
    printf "%s$%s", (neg?"-":""), out;
  }'
}
# Signed percent, one decimal (e.g. +3.2%, -1.0%).
pct() { awk "BEGIN{printf \"%+.1f%%\", $1}"; }

# --- Preflight ---------------------------------------------------------------
require_cmd jq
require_cmd awk

if [ "$DRY_RUN" = "1" ]; then
  [ -f "$EXAMPLE_PORTFOLIO" ] || die "Fixture not found: $EXAMPLE_PORTFOLIO"
  WALLET="${WALLET:-$(jq -r '.address' "$EXAMPLE_PORTFOLIO")}"
  log "DRY RUN: building snapshot from $EXAMPLE_PORTFOLIO, printing instead of delivering."
else
  require_cmd curl
  [ -n "$WALLET" ] || die "Set WALLET (or pass the address as the first argument)."
  require_env PAYSH_WALLET_URL
  case "$ALERT_SINK" in
    stdout)    : ;;
    telegram)  require_env TELEGRAM_BOT_TOKEN; require_env TELEGRAM_CHAT_ID ;;
    webhook)   require_env WEBHOOK_URL ;;
    websocket) require_env WS_URL; require_cmd websocat ;;
    *)         die "Unknown ALERT_SINK '$ALERT_SINK' (use: stdout|telegram|webhook|websocket)" ;;
  esac
fi

# --- Fetch holdings over pay.sh ----------------------------------------------
# `pay` fronts the HTTP call and settles the x402 micropayment. Expects a JSON
# object with total_usd, change_24h_pct, and a holdings[] of {symbol, value_usd,
# change_24h_pct}. Adjust the mapping here if your route differs.
fetch_portfolio() {
  if [ "$DRY_RUN" = "1" ]; then
    cat "$EXAMPLE_PORTFOLIO"
  else
    pay curl -s -G "$PAYSH_WALLET_URL" \
      --data-urlencode "address=$WALLET" --data-urlencode "chain=$CHAIN" 2>/dev/null || echo '{}'
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

# --- Run ---------------------------------------------------------------------
log "Building portfolio snapshot for ${WALLET} on ${CHAIN} ..."
data="$(fetch_portfolio)"
if ! printf '%s' "$data" | jq -e '.holdings' >/dev/null 2>&1; then
  die "Wallet endpoint returned no holdings."
fi

total="$(printf '%s' "$data"  | jq -r '.total_usd // 0')"
change="$(printf '%s' "$data" | jq -r '.change_24h_pct // 0')"
short="${WALLET:0:6}…${WALLET: -4}"

# Top holdings by value, with each one's share of the total.
holdings_lines="$(printf '%s' "$data" | jq -r --argjson top "$TOP" --argjson total "$total" '
  .holdings
  | sort_by(-.value_usd)
  | .[:$top][]
  | "\(.symbol)\t\(.value_usd)\t\((if $total>0 then (.value_usd/$total*100) else 0 end))"')"

list=""
while IFS=$'\t' read -r sym val share; do
  [ -n "$sym" ] || continue
  list="${list}  • ${sym}  $(usd "$val")  ($(awk "BEGIN{printf \"%.0f%%\", $share}"))
"
done <<< "$holdings_lines"

# Biggest 24h mover among holdings.
mover="$(printf '%s' "$data" | jq -r '
  (.holdings | max_by(.change_24h_pct)) as $m
  | "\($m.symbol)\t\($m.change_24h_pct)"')"
mover_sym="$(printf '%s' "$mover" | cut -f1)"
mover_pct="$(printf '%s' "$mover" | cut -f2)"

body="💼 Portfolio Pulse: ${short} on ${CHAIN}
$(usd "$total") ($(pct "$change") 24h)

Top holdings:
${list}Biggest mover: ${mover_sym} $(pct "$mover_pct")"

payload="$(jq -nc \
  --arg wallet "$WALLET" --arg chain "$CHAIN" --arg text "$body" \
  --argjson total "$total" --argjson change "$change" \
  --argjson holdings "$(printf '%s' "$data" | jq '.holdings')" \
  '{type:"portfolio_pulse",wallet:$wallet,chain:$chain,total_usd:$total,change_24h_pct:$change,holdings:$holdings,text:$text}')"

if [ "$DRY_RUN" = "1" ]; then
  printf '%s\n' "$body"
  log "Done (dry run)."
  exit 0
fi

deliver "$body" "$payload"
log "Done."
