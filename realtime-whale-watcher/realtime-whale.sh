#!/usr/bin/env bash
#
# realtime-whale.sh — Low-latency, multi-chain wallet watcher. Delivers an alert
# the instant a whale-sized transfer to/from your wallet lands in a new block.
#
# Recipe #1 (../whale-watcher) polls on a cron: simple, but you're bounded by the
# cron interval and only see settled history. This one is a long-running process
# that tight-loops the chain head through pay.sh's JSON-RPC (paid per request,
# no API keys), scans each NEW block for your wallet, and delivers immediately.
# Latency is ~one block instead of ~one cron tick.
#
# pay.sh is per-request HTTP (x402), not a streaming socket, so "realtime" here
# means "scan every block as it's produced," which is the honest low-latency
# model that fits the payment rail. For pre-confirmation (mempool) signal you'd
# need a mempool-exposing endpoint; see the README.
#
# Chains: pick with NETWORK (default: ethereum). EVM chains scan tx from/to/value;
# Solana detects native SOL moves via pre/post balance deltas.
#
# Try it with zero setup:
#   DRY_RUN=1 ./realtime-whale.sh                 # EVM (ethereum) demo
#   DRY_RUN=1 NETWORK=solana ./realtime-whale.sh  # Solana demo
#
set -euo pipefail

# --- Config ------------------------------------------------------------------
# Required (live mode):
#   WATCH_WALLET        wallet address to watch (native transfers to/from)
#   THRESHOLD_NATIVE    min transfer size in the chain's native unit (ETH, SOL, ...)
#
# Chain selection:
#   NETWORK             ethereum | base | arbitrum | optimism | polygon | bnb |
#                       avalanche | solana   (default: ethereum)
#   PAYSH_RPC_URL       override the pay.sh JSON-RPC endpoint for that network
#   NATIVE_SYMBOL       override the display symbol (default: per-network)
#   DECIMALS            override native decimals (default: 18 EVM, 9 Solana)
#
# Alert transport — pick one with ALERT_SINK (default: telegram):
#   telegram   -> needs TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID
#   webhook    -> needs WEBHOOK_URL   (POSTs the JSON payload)
#   websocket  -> needs WS_URL        (pushes the JSON payload via websocat)
#   stdout     -> prints the JSON payload (pipe it into your agent / anything)
# Non-telegram sinks emit a machine-readable JSON payload, so agents can consume
# alerts directly instead of parsing a human string.
#
# Optional:
#   POLL_SECONDS        head poll interval, seconds (default: 3)
#   STATE_DIR           where the last-scanned block is stored (default: ~/.whale-watcher)
#   DRY_RUN=1           demo: scan EXAMPLE_BLOCK once, print instead of deliver
#   EXAMPLE_BLOCK       canned block for DRY_RUN (default: per-network fixture)

NETWORK="${NETWORK:-ethereum}"
ALERT_SINK="${ALERT_SINK:-telegram}"
POLL_SECONDS="${POLL_SECONDS:-3}"
STATE_DIR="${STATE_DIR:-$HOME/.whale-watcher}"
DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Helpers -----------------------------------------------------------------
log()  { printf '[realtime-whale] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed or not on PATH."; }
require_env() { [ -n "${!1:-}" ] || die "Missing required env var: $1"; }

# hex (0x...) wei -> decimal native units, 6dp. bc handles the bignum that
# overflows 64-bit shell integers; ibase=16 needs uppercase hex.
hex_to_native() {
  local h="${1#0x}"
  [ -n "$h" ] || { echo 0; return; }
  h="$(printf '%s' "$h" | tr 'a-f' 'A-F')"
  local wei; wei="$(printf 'ibase=16; %s\n' "$h" | bc)"
  printf 'scale=6; %s / 10^%s\n' "$wei" "$DECIMALS" | bc
}

# --- Resolve the network preset ----------------------------------------------
# Sets CHAIN (evm|solana) plus default symbol, decimals, and RPC route. The
# pay.sh RPC routes are the documented per-network pattern; override with
# PAYSH_RPC_URL if yours differs.
case "$(printf '%s' "$NETWORK" | tr 'A-Z' 'a-z')" in
  ethereum|eth|mainnet) CHAIN=evm;    def_sym=ETH;  def_dec=18; def_rpc="https://rpc.pay.sh/eth" ;;
  base)                 CHAIN=evm;    def_sym=ETH;  def_dec=18; def_rpc="https://rpc.pay.sh/base" ;;
  arbitrum|arb)         CHAIN=evm;    def_sym=ETH;  def_dec=18; def_rpc="https://rpc.pay.sh/arbitrum" ;;
  optimism|op)          CHAIN=evm;    def_sym=ETH;  def_dec=18; def_rpc="https://rpc.pay.sh/optimism" ;;
  polygon|matic|pol)    CHAIN=evm;    def_sym=POL;  def_dec=18; def_rpc="https://rpc.pay.sh/polygon" ;;
  bnb|bsc)              CHAIN=evm;    def_sym=BNB;  def_dec=18; def_rpc="https://rpc.pay.sh/bsc" ;;
  avalanche|avax)       CHAIN=evm;    def_sym=AVAX; def_dec=18; def_rpc="https://rpc.pay.sh/avalanche" ;;
  solana|sol)           CHAIN=solana; def_sym=SOL;  def_dec=9;  def_rpc="https://rpc.pay.sh/solana" ;;
  *) die "Unknown NETWORK '$NETWORK' (try: ethereum, base, arbitrum, optimism, polygon, bnb, avalanche, solana)" ;;
esac
NATIVE_SYMBOL="${NATIVE_SYMBOL:-$def_sym}"
DECIMALS="${DECIMALS:-$def_dec}"
PAYSH_RPC_URL="${PAYSH_RPC_URL:-$def_rpc}"

# --- Preflight ---------------------------------------------------------------
require_cmd jq
require_cmd bc

if [ "$DRY_RUN" = "1" ]; then
  if [ "$CHAIN" = "solana" ]; then
    WATCH_WALLET="${WATCH_WALLET:-7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU}"
    EXAMPLE_BLOCK="${EXAMPLE_BLOCK:-$SCRIPT_DIR/example-block-solana.json}"
  else
    WATCH_WALLET="${WATCH_WALLET:-0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045}"
    EXAMPLE_BLOCK="${EXAMPLE_BLOCK:-$SCRIPT_DIR/example-block.json}"
  fi
  THRESHOLD_NATIVE="${THRESHOLD_NATIVE:-100}"
  log "DRY RUN — scanning $EXAMPLE_BLOCK once (network: $NETWORK), printing instead of delivering."
else
  require_cmd curl
  for v in PAYSH_RPC_URL WATCH_WALLET THRESHOLD_NATIVE; do
    require_env "$v"
  done
  # Validate only the env the chosen sink actually needs.
  case "$ALERT_SINK" in
    telegram)  require_env TELEGRAM_BOT_TOKEN; require_env TELEGRAM_CHAT_ID ;;
    webhook)   require_env WEBHOOK_URL ;;
    websocket) require_env WS_URL; require_cmd websocat ;;
    stdout)    : ;;
    *)         die "Unknown ALERT_SINK '$ALERT_SINK' (use: telegram|webhook|websocket|stdout)" ;;
  esac
fi

case "$THRESHOLD_NATIVE" in ''|*[!0-9.]*) die "THRESHOLD_NATIVE must be a number, got: '$THRESHOLD_NATIVE'";; esac

# --- Paid JSON-RPC over pay.sh ----------------------------------------------
# `pay` fronts the HTTP call and settles the x402 micropayment. If your pay CLI
# uses a different wrapper form, this one function is the only thing to change.
rpc() {
  local method="$1" params="$2"
  pay curl -s -X POST "$PAYSH_RPC_URL" \
    -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"${method}\",\"params\":${params}}"
}

# --- Alert delivery (pluggable sink) -----------------------------------------
# Deliver one alert. `text` is the human string (Telegram); `payload` is the
# machine-readable JSON (webhook/websocket/stdout). Logs the outcome; never
# aborts the watcher on a delivery failure.
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

# --- Chain adapters ----------------------------------------------------------
# Each chain implements: head (latest height), get_block, and extract_hits.
# extract_hits emits one normalized JSON object per qualifying transfer:
#   {dir:"in|out", value:"<native, string>", counterparty:"<addr>", tx:"<id>"}

chain_head() {
  case "$CHAIN" in
    evm)
      local h; h="$(rpc eth_blockNumber '[]' | jq -r '.result // empty' 2>/dev/null || true)"
      [ -n "$h" ] && printf '%d\n' "$h"           # hex -> decimal
      ;;
    solana)
      rpc getSlot '[{"commitment":"confirmed"}]' | jq -r '.result // empty' 2>/dev/null || true
      ;;
  esac
}

chain_get_block() {
  local n="$1"
  case "$CHAIN" in
    evm)
      local n_hex; n_hex="$(printf '0x%x' "$n")"
      rpc eth_getBlockByNumber "[\"${n_hex}\", true]"
      ;;
    solana)
      rpc getBlock "[${n}, {\"commitment\":\"confirmed\",\"encoding\":\"json\",\"maxSupportedTransactionVersion\":0,\"transactionDetails\":\"full\",\"rewards\":false}]"
      ;;
  esac
}

# EVM: match tx.from/tx.to, value is hex wei. bc converts the bignum.
extract_hits_evm() {
  local wallet_lc; wallet_lc="$(printf '%s' "$WATCH_WALLET" | tr 'A-Z' 'a-z')"
  local candidates
  candidates="$(printf '%s' "$1" | jq -c --arg w "$wallet_lc" '
    .result.transactions[]?
    | select((.value // "0x0") != "0x0")
    | select((((.from // "") | ascii_downcase) == $w)
          or (((.to   // "") | ascii_downcase) == $w))
  ' 2>/dev/null || true)"
  [ -n "${candidates//[[:space:]]/}" ] || return 0

  local tx value_hex from to hash native over dir other
  while IFS= read -r tx; do
    [ -n "$tx" ] || continue
    value_hex="$(printf '%s' "$tx" | jq -r '.value')"
    from="$(printf '%s' "$tx"      | jq -r '.from // "?"')"
    to="$(printf '%s' "$tx"        | jq -r '.to // "?"')"
    hash="$(printf '%s' "$tx"      | jq -r '.hash // "?"')"

    native="$(hex_to_native "$value_hex")"
    over="$(printf '%s >= %s\n' "$native" "$THRESHOLD_NATIVE" | bc)"
    [ "$over" = "1" ] || continue

    if [ "$(printf '%s' "$from" | tr 'A-Z' 'a-z')" = "$wallet_lc" ]; then
      dir="out"; other="$to"
    else
      dir="in";  other="$from"
    fi
    jq -nc --arg dir "$dir" --arg value "$native" --arg cp "$other" --arg tx "$hash" \
      '{dir:$dir,value:$value,counterparty:$cp,tx:$tx}'
  done <<< "$candidates"
}

# Solana: no tx.value field — derive native SOL moves from the per-account
# pre/post balance deltas (lamports). The wallet's own delta is the transfer
# amount; the biggest opposite-sign delta is the likely counterparty. Balances
# fit in a JS double for realistic whale sizes, so jq does the whole thing.
extract_hits_solana() {
  printf '%s' "$1" | jq -c \
    --arg w "$WATCH_WALLET" --argjson thr "$THRESHOLD_NATIVE" --argjson dec "$DECIMALS" '
    def base: pow(10; $dec);
    .result.transactions[]?
    | select(.meta.err == null)
    | . as $t
    | $t.transaction.message.accountKeys as $keys
    | ($keys | index($w)) as $i
    | select($i != null)
    | ($t.meta.postBalances[$i] - $t.meta.preBalances[$i]) as $delta
    | select(($delta | fabs) >= ($thr * base))
    | ([ range(0; ($keys | length))
         | {j: ., d: ($t.meta.postBalances[.] - $t.meta.preBalances[.]) } ]
       | map(select(.j != $i))) as $others
    | (if ($others | length) == 0 then null
       elif $delta > 0 then ($others | min_by(.d))
       else ($others | max_by(.d)) end) as $cp
    | {
        dir: (if $delta > 0 then "in" else "out" end),
        value: ((($delta | fabs) / base) | . * 1000000 | round / 1000000 | tostring),
        counterparty: (if $cp == null then "?" else ($keys[$cp.j] // "?") end),
        tx: ($t.transaction.signatures[0] // "?")
      }
  ' 2>/dev/null || true
}

extract_hits() {
  case "$CHAIN" in
    evm)    extract_hits_evm "$1" ;;
    solana) extract_hits_solana "$1" ;;
  esac
}

# --- Emit one normalized hit -------------------------------------------------
emit_hit() {
  local dir="$1" value="$2" other="$3" id="$4"
  local value_fmt; value_fmt="$(printf '%.6f' "$value" 2>/dev/null || printf '%s' "$value")"

  local body payload
  body="🐋 Whale alert [${NETWORK}]: ${WATCH_WALLET:0:6}…${WATCH_WALLET: -4} ${dir} ${value_fmt} ${NATIVE_SYMBOL} (counterparty ${other:0:6}…). tx ${id:0:10}…"
  payload="$(jq -nc \
    --arg network "$NETWORK" --arg wallet "$WATCH_WALLET" --arg dir "$dir" \
    --arg value "$value_fmt" --arg symbol "$NATIVE_SYMBOL" --arg counterparty "$other" \
    --arg tx "$id" --arg text "$body" \
    '{type:"whale_alert",network:$network,wallet:$wallet,direction:$dir,value:$value,symbol:$symbol,counterparty:$counterparty,tx:$tx,text:$text}')"

  if [ "$DRY_RUN" = "1" ]; then
    log "Whale detected (${value_fmt} ${NATIVE_SYMBOL}) — would deliver via '${ALERT_SINK}':"
    printf 'ALERT: %s\n' "$body"
    printf 'PAYLOAD: %s\n' "$payload"
    return 0
  fi

  log "Whale detected (${value_fmt} ${NATIVE_SYMBOL}). Delivering via '${ALERT_SINK}' ..."
  deliver "$body" "$payload"
}

# --- Scan one block ----------------------------------------------------------
scan_block() {
  local hits; hits="$(extract_hits "$1")"
  [ -n "${hits//[[:space:]]/}" ] || return 0

  local hit dir value cp tx
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    dir="$(printf '%s' "$hit"   | jq -r '.dir')"
    value="$(printf '%s' "$hit" | jq -r '.value')"
    cp="$(printf '%s' "$hit"    | jq -r '.counterparty')"
    tx="$(printf '%s' "$hit"    | jq -r '.tx')"
    emit_hit "$dir" "$value" "$cp" "$tx"
  done <<< "$hits"
}

# --- DRY_RUN: one-shot against the fixture -----------------------------------
if [ "$DRY_RUN" = "1" ]; then
  [ -f "$EXAMPLE_BLOCK" ] || die "Example block not found: $EXAMPLE_BLOCK"
  scan_block "$(cat "$EXAMPLE_BLOCK")"
  log "Done (dry run)."
  exit 0
fi

# --- Live: follow the chain head --------------------------------------------
mkdir -p "$STATE_DIR"
LAST_FILE="$STATE_DIR/${NETWORK}-${WATCH_WALLET}.lastblock"
last=0
[ -f "$LAST_FILE" ] && last="$(cat "$LAST_FILE" 2>/dev/null || echo 0)"

log "Watching ${WATCH_WALLET} on ${NETWORK} for transfers >= ${THRESHOLD_NATIVE} ${NATIVE_SYMBOL} (poll ${POLL_SECONDS}s)."
while true; do
  head="$(chain_head)"
  if [ -z "$head" ]; then
    log "No head from RPC — retrying."; sleep "$POLL_SECONDS"; continue
  fi

  # First run: start from the current head, don't replay history.
  [ "$last" -eq 0 ] && last="$((head - 1))"

  while [ "$last" -lt "$head" ]; do
    n="$((last + 1))"
    block="$(chain_get_block "$n" 2>/dev/null || true)"
    if printf '%s' "$block" | jq -e '.result.transactions' >/dev/null 2>&1; then
      scan_block "$block"
      last="$n"; printf '%s\n' "$last" > "$LAST_FILE"
    elif printf '%s' "$block" | jq -e '.error' >/dev/null 2>&1; then
      # Solana skips slots routinely (-32007/-32009): advance past them instead
      # of stalling. Any other error: back off and retry the same height.
      ecode="$(printf '%s' "$block" | jq -r '.error.code // 0')"
      if [ "$CHAIN" = "solana" ] && { [ "$ecode" = "-32007" ] || [ "$ecode" = "-32009" ]; }; then
        last="$n"; printf '%s\n' "$last" > "$LAST_FILE"
      else
        break
      fi
    else
      # Block not produced yet, or a transient hiccup — retry next tick.
      break
    fi
  done

  sleep "$POLL_SECONDS"
done
