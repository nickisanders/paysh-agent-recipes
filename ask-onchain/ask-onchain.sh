#!/usr/bin/env bash
#
# ask-onchain.sh — Ask a question in plain English. The agent picks a tool, pays
# for it, and answers.
#
# This is the full agent loop in one script: `pay claude` reads your question and
# decides which onchain data source to use, the script fetches it through pay.sh
# (paid per request in USDC, no API keys), then `pay claude` answers using the
# data. Reason, act, respond.
#
# The agent's tool belt is the rest of this library's data sources: a token audit,
# a price feed, wallet holdings, gas, and web search. It chooses on its own.
#
# Try it with zero setup:  DRY_RUN=1 ./ask-onchain.sh
#   Runs a canned question end to end (plan, fetch, answer). No pay, no network.
#
set -euo pipefail

# --- Config ------------------------------------------------------------------
# Required (live mode):
#   QUESTION            what to ask (or pass it as the first argument)
#
# Optional:
#   CHAIN               network for address-based tools (default: ethereum)
#   ALERT_SINK          stdout (default) | telegram | webhook | websocket
#   PAYSH_AUDIT_URL / PAYSH_MARKET_URL / PAYSH_WALLET_URL / PAYSH_RPC_URL /
#   PAYSH_SEARCH_URL    the pay.sh endpoints for each tool (sane defaults)
#   DRY_RUN=1           demo: canned plan/data/answer, print instead of deliver
#   EXAMPLE_DATA        canned tool outputs for DRY_RUN

QUESTION="${QUESTION:-${1:-}}"
CHAIN="${CHAIN:-ethereum}"
ALERT_SINK="${ALERT_SINK:-stdout}"
PAYSH_AUDIT_URL="${PAYSH_AUDIT_URL:-https://audit.pay.sh/contract}"
PAYSH_MARKET_URL="${PAYSH_MARKET_URL:-https://market.pay.sh/price}"
PAYSH_WALLET_URL="${PAYSH_WALLET_URL:-https://wallet.pay.sh/holdings}"
PAYSH_RPC_URL="${PAYSH_RPC_URL:-https://rpc.pay.sh/eth}"
PAYSH_SEARCH_URL="${PAYSH_SEARCH_URL:-https://search.pay.sh/answer}"
DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_DATA="${EXAMPLE_DATA:-$SCRIPT_DIR/example-data.json}"

# The tools the agent can choose from, described for the planner.
TOOLS='audit(address): security risk of a token contract;
price(symbol): current USD price of a token;
holdings(address): a wallet'"'"'s token holdings and total value;
gas(): current gas price in gwei;
search(query): recent news or web info'

# --- Helpers -----------------------------------------------------------------
log()  { printf '[ask-onchain] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed or not on PATH."; }
require_env() { [ -n "${!1:-}" ] || die "Missing required env var: $1"; }

# --- Preflight ---------------------------------------------------------------
require_cmd jq

if [ "$DRY_RUN" = "1" ]; then
  QUESTION="${QUESTION:-Is the token at 0x1111111111111111111111111111111111111111 safe to buy?}"
  [ -f "$EXAMPLE_DATA" ] || die "Fixture not found: $EXAMPLE_DATA"
  log "DRY RUN: running a canned plan/fetch/answer, printing instead of delivering."
else
  require_cmd curl
  [ -n "$QUESTION" ] || die "Set QUESTION (or pass it as the first argument)."
  case "$ALERT_SINK" in
    stdout)    : ;;
    telegram)  require_env TELEGRAM_BOT_TOKEN; require_env TELEGRAM_CHAT_ID ;;
    webhook)   require_env WEBHOOK_URL ;;
    websocket) require_env WS_URL; require_cmd websocat ;;
    *)         die "Unknown ALERT_SINK '$ALERT_SINK' (use: stdout|telegram|webhook|websocket)" ;;
  esac
fi

# --- Step 1: plan (which tool?) ----------------------------------------------
# pay claude reads the question and picks one tool + its args. In DRY_RUN it
# returns a canned plan so the demo runs without paying.
plan() {
  if [ "$DRY_RUN" = "1" ]; then
    # A tiny keyword router stands in for the model, so the demo routes different
    # questions to different tools without paying. Live mode uses pay claude.
    local q; q="$(printf '%s' "$QUESTION" | tr 'A-Z' 'a-z')"
    case "$q" in
      *price*|*worth*|*trading*|*cost*)      jq -nc '{tool:"price",args:{symbol:"SOL"}}' ;;
      *gas*)                                  jq -nc '{tool:"gas",args:{}}' ;;
      *hold*|*portfolio*|*balance*|*own*)     jq -nc '{tool:"holdings",args:{address:"0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"}}' ;;
      *safe*|*rug*|*risk*|*audit*|*scam*)     jq -nc '{tool:"audit",args:{address:"0x1111111111111111111111111111111111111111"}}' ;;
      *)                                      jq -nc --arg q "$QUESTION" '{tool:"search",args:{query:$q}}' ;;
    esac
    return 0
  fi
  local prompt="You are an onchain assistant with these tools:
${TOOLS}
Pick the single best tool for the user's question and its arguments. Respond with
ONLY JSON: {\"tool\":\"<name>\",\"args\":{...}}. No prose. Question: ${QUESTION}"
  pay claude -p "$prompt" 2>/dev/null \
    | grep -o '{.*}' | head -1 || true
}

# --- Step 2: execute (fetch via pay.sh) --------------------------------------
execute() {
  local tool="$1" args="$2"
  if [ "$DRY_RUN" = "1" ]; then
    jq -c --arg t "$tool" '.[$t] // {}' "$EXAMPLE_DATA"
    return 0
  fi
  local a
  case "$tool" in
    audit)    a="$(printf '%s' "$args" | jq -r '.address // empty')"
              pay curl -s -G "$PAYSH_AUDIT_URL"  --data-urlencode "address=$a" --data-urlencode "chain=$CHAIN" ;;
    price)    a="$(printf '%s' "$args" | jq -r '.symbol // empty')"
              pay curl -s -G "$PAYSH_MARKET_URL" --data-urlencode "symbol=$a" ;;
    holdings) a="$(printf '%s' "$args" | jq -r '.address // empty')"
              pay curl -s -G "$PAYSH_WALLET_URL" --data-urlencode "address=$a" --data-urlencode "chain=$CHAIN" ;;
    gas)      pay curl -s -X POST "$PAYSH_RPC_URL" -H 'content-type: application/json' \
                -d '{"jsonrpc":"2.0","id":1,"method":"eth_gasPrice","params":[]}' ;;
    search)   a="$(printf '%s' "$args" | jq -r '.query // empty')"
              pay curl -s -G "$PAYSH_SEARCH_URL" --data-urlencode "q=$a" ;;
    *)        echo '{}" }' ;;
  esac 2>/dev/null || echo '{}'
}

# --- Step 3: answer (natural language) ---------------------------------------
answer() {
  local data="$1"
  if [ "$DRY_RUN" = "1" ]; then
    # Canned answers keyed off which fixture came back, so the demo reads right.
    if   printf '%s' "$data" | jq -e '.risk' >/dev/null 2>&1; then
      printf "No. The owner can mint new supply and blacklist holders, and ownership is not renounced. Any one is a red flag; together the deployer can dilute or freeze you at will. High risk, stay out."
    elif printf '%s' "$data" | jq -e '.price' >/dev/null 2>&1; then
      printf "SOL is trading around \$182.40, up about 2.3%% over the last 24 hours."
    elif printf '%s' "$data" | jq -e '.gwei' >/dev/null 2>&1; then
      printf "Gas is about 12 gwei right now, which is cheap. A good window to get a transaction in."
    elif printf '%s' "$data" | jq -e '.total_usd' >/dev/null 2>&1; then
      printf "The wallet holds roughly \$124,530, mostly ETH (~\$82k) and USDC (~\$30k)."
    else
      printf "The protocol shipped a v2 upgrade last week with lower fees and native stablecoin support."
    fi
    return 0
  fi
  pay claude -p "Answer the user's question in two or three plain sentences using this data. No preamble. Question: ${QUESTION}. Data: ${data}" \
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

# --- Run the loop ------------------------------------------------------------
log "Thinking ..."
p="$(plan)"
printf '%s' "$p" | jq -e '.tool' >/dev/null 2>&1 || die "Could not plan a tool for that question."
tool="$(printf '%s' "$p"  | jq -r '.tool')"
args="$(printf '%s' "$p"  | jq -c '.args // {}')"

log "Using tool: ${tool}"
data="$(execute "$tool" "$args")"
printf '%s' "$data" | jq -e . >/dev/null 2>&1 || data='{}'

ans="$(answer "$data")"

# Compact one-line view of the args for display (e.g. 0x1111…1111).
arg_view="$(printf '%s' "$args" | jq -r 'to_entries | map(.value) | join(", ")')"
[ ${#arg_view} -le 16 ] || arg_view="${arg_view:0:6}…${arg_view: -4}"

body="🔮 Ask Onchain
Q: ${QUESTION}
Used: ${tool}(${arg_view})
A: ${ans}"

payload="$(jq -nc \
  --arg question "$QUESTION" --arg tool "$tool" --argjson args "$args" \
  --arg answer "$ans" --arg text "$body" --argjson data "$data" \
  '{type:"ask_onchain",question:$question,tool:$tool,args:$args,data:$data,answer:$answer,text:$text}')"

if [ "$DRY_RUN" = "1" ]; then
  printf '%s\n' "$body"
  log "Done (dry run)."
  exit 0
fi

deliver "$body" "$payload"
log "Done."
