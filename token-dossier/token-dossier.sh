#!/usr/bin/env bash
#
# token-dossier.sh — One token address in, a full due-diligence brief out.
#
# Orchestrates several paid pay.sh calls for one address and synthesizes them
# into a single verdict: contract risk (audit), price and 24h move (market data),
# recent large flows (on-chain), and social sentiment. Then `pay claude` writes a
# one-paragraph "should you be careful with this" brief. Paid per request in
# USDC, no API keys.
#
# This is the orchestration recipe: one question, many paid sources, one answer.
# A failure in any single source degrades gracefully instead of aborting.
#
# Deliver via stdout (default), Telegram, a webhook, or a websocket.
#
# Try it with zero setup:  DRY_RUN=1 ./token-dossier.sh
#   Builds a dossier from the canned example-dossier.json. No pay, no network.
#
set -euo pipefail

# --- Config ------------------------------------------------------------------
# Required (live mode):
#   ADDRESS             token contract address (or pass as the first argument)
#
# Optional:
#   CHAIN               network the token is on (default: ethereum)
#   SYMBOL              ticker for display (otherwise taken from market data)
#   ALERT_SINK          stdout (default) | telegram | webhook | websocket
#   PAYSH_AUDIT_URL / PAYSH_MARKET_URL / PAYSH_ONCHAIN_URL / PAYSH_SOCIAL_URL
#                       the four pay.sh endpoints (each has a sane default)
#   DRY_RUN=1           demo: build from EXAMPLE_DOSSIER, print instead of deliver
#   EXAMPLE_DOSSIER     canned sources for DRY_RUN

ADDRESS="${ADDRESS:-${1:-}}"
CHAIN="${CHAIN:-ethereum}"
ALERT_SINK="${ALERT_SINK:-stdout}"
PAYSH_AUDIT_URL="${PAYSH_AUDIT_URL:-https://audit.pay.sh/contract}"
PAYSH_MARKET_URL="${PAYSH_MARKET_URL:-https://market.pay.sh/price}"
PAYSH_ONCHAIN_URL="${PAYSH_ONCHAIN_URL:-https://onchain.pay.sh/token}"
PAYSH_SOCIAL_URL="${PAYSH_SOCIAL_URL:-https://social.pay.sh/search}"
DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_DOSSIER="${EXAMPLE_DOSSIER:-$SCRIPT_DIR/example-dossier.json}"

# --- Helpers -----------------------------------------------------------------
log()  { printf '[token-dossier] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed or not on PATH."; }
require_env() { [ -n "${!1:-}" ] || die "Missing required env var: $1"; }

# --- Preflight ---------------------------------------------------------------
require_cmd jq

if [ "$DRY_RUN" = "1" ]; then
  [ -f "$EXAMPLE_DOSSIER" ] || die "Fixture not found: $EXAMPLE_DOSSIER"
  ADDRESS="${ADDRESS:-0x1111111111111111111111111111111111111111}"
  log "DRY RUN: building dossier from $EXAMPLE_DOSSIER, printing instead of delivering."
else
  require_cmd curl
  [ -n "$ADDRESS" ] || die "Set ADDRESS (or pass the token address as the first argument)."
  for v in PAYSH_AUDIT_URL PAYSH_MARKET_URL PAYSH_ONCHAIN_URL PAYSH_SOCIAL_URL; do require_env "$v"; done
  case "$ALERT_SINK" in
    stdout)    : ;;
    telegram)  require_env TELEGRAM_BOT_TOKEN; require_env TELEGRAM_CHAT_ID ;;
    webhook)   require_env WEBHOOK_URL ;;
    websocket) require_env WS_URL; require_cmd websocat ;;
    *)         die "Unknown ALERT_SINK '$ALERT_SINK' (use: stdout|telegram|webhook|websocket)" ;;
  esac
fi

# --- The four paid sources ---------------------------------------------------
# `pay` fronts each HTTP call and settles the x402 micropayment. In DRY_RUN each
# reads its slice of the fixture. Any source that fails returns {} so one bad
# feed degrades the dossier instead of killing it.
fetch_source() {
  local key="$1"; shift
  if [ "$DRY_RUN" = "1" ]; then
    jq -c --arg k "$key" '.[$k] // {}' "$EXAMPLE_DOSSIER"
    return 0
  fi
  local out; out="$("$@" 2>/dev/null || echo '{}')"
  printf '%s' "$out" | jq -e . >/dev/null 2>&1 && printf '%s' "$out" || echo '{}'
}

audit_call()   { pay curl -s -G "$PAYSH_AUDIT_URL"   --data-urlencode "address=$ADDRESS" --data-urlencode "chain=$CHAIN"; }
market_call()  { pay curl -s -G "$PAYSH_MARKET_URL"  --data-urlencode "symbol=${SYMBOL:-$ADDRESS}"; }
onchain_call() { pay curl -s -G "$PAYSH_ONCHAIN_URL" --data-urlencode "address=$ADDRESS" --data-urlencode "chain=$CHAIN"; }
social_call()  { pay curl -s -G "$PAYSH_SOCIAL_URL"  --data-urlencode "q=${SYMBOL:-$ADDRESS}"; }

# --- pay claude synthesis ----------------------------------------------------
synthesize() {
  local combined="$1"
  if [ "$DRY_RUN" = "1" ]; then
    printf "This token carries serious contract risk: the owner can still mint supply and blacklist holders, and ownership is not renounced. Price is down 8%% on the day with several large outflows, and the top holder controls 41%% of supply. Social chatter is mixed. Treat it as high risk and size accordingly, if at all."
    return 0
  fi
  pay claude -p "You are a token due-diligence assistant. Given these findings from four sources (JSON: contract audit, market, on-chain flows, social), write one plain-English paragraph on what someone should watch out for before buying. No preamble, no markdown. Findings: ${combined}" \
    2>/dev/null | tr '\n' ' ' | sed 's/  */ /g; s/ *$//' || true
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

# --- Gather ------------------------------------------------------------------
log "Building dossier for ${ADDRESS} on ${CHAIN} ..."
audit="$(fetch_source audit audit_call)"
market="$(fetch_source market market_call)"
onchain="$(fetch_source onchain onchain_call)"
social="$(fetch_source social social_call)"

# Symbol for display: env override, else market data, else short address.
SYMBOL="${SYMBOL:-$(printf '%s' "$market" | jq -r '.symbol // empty')}"
label="${SYMBOL:-${ADDRESS:0:6}…${ADDRESS: -4}}"

# --- Pull display fields -----------------------------------------------------
audit_risk="$(printf '%s' "$audit"  | jq -r '(.risk // .risk_level // "unknown") | ascii_upcase')"
audit_flags="$(printf '%s' "$audit" | jq -r '(.flags // []) | join(", ") // ""')"
price="$(printf '%s' "$market"      | jq -r '.price // .usd // "?"')"
change="$(printf '%s' "$market"     | jq -r '.change_24h // .change // "?"')"
flows="$(printf '%s' "$onchain"     | jq -r '.note // (if .large_transfers_24h then "\(.large_transfers_24h) large transfers in 24h" else "no data" end)')"
sentiment="$(printf '%s' "$social"  | jq -r '.sentiment // "?"')"
mentions="$(printf '%s' "$social"   | jq -r '.mentions // 0')"

# Composite verdict, anchored on contract risk.
case "$audit_risk" in
  HIGH)   verdict="AVOID" ;;
  MEDIUM) verdict="CAUTION" ;;
  LOW)    verdict="LOOKS OK" ;;
  *)      verdict="UNKNOWN" ;;
esac

combined="$(jq -nc \
  --argjson audit "$audit" --argjson market "$market" \
  --argjson onchain "$onchain" --argjson social "$social" \
  '{audit:$audit,market:$market,onchain:$onchain,social:$social}')"
synthesis="$(synthesize "$combined")"

# --- Assemble the dossier ----------------------------------------------------
body="🗂️ Token Dossier: ${label} on ${CHAIN}
Verdict: ${verdict}"
[ -n "${synthesis//[[:space:]]/}" ] && body="${body}

${synthesis}"
body="${body}

• Contract: ${audit_risk}${audit_flags:+ ($audit_flags)}
• Price: \$${price} (${change}% 24h)
• Flows: ${flows}
• Sentiment: ${sentiment} (${mentions} mentions)"

payload="$(jq -nc \
  --arg address "$ADDRESS" --arg chain "$CHAIN" --arg symbol "$label" \
  --arg verdict "$verdict" --arg synthesis "$synthesis" --arg text "$body" \
  --argjson sources "$combined" \
  '{type:"token_dossier",address:$address,chain:$chain,symbol:$symbol,verdict:$verdict,synthesis:$synthesis,sources:$sources,text:$text}')"

if [ "$DRY_RUN" = "1" ]; then
  printf '%s\n' "$body"
  log "Done (dry run). Non-stdout sinks would receive the JSON payload with all four sources."
  exit 0
fi

deliver "$body" "$payload"
log "Done."
