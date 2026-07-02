#!/usr/bin/env bash
#
# realtime-whale.sh — Low-latency wallet watcher. Pushes a Telegram alert the
# instant a whale-sized transfer to/from your wallet lands in a new block.
#
# Recipe #1 (../whale-watcher) polls on a cron: simple, but you're bounded by the
# cron interval and only see settled history. This one is a long-running process
# that tight-loops the chain head through pay.sh's JSON-RPC (paid per request,
# no API keys), scans each NEW block for your wallet, and pushes to Telegram
# immediately. Latency is ~one block instead of ~one cron tick.
#
# pay.sh is per-request HTTP (x402), not a streaming socket — so "realtime" here
# means "scan every block as it's produced," which is the honest low-latency
# model that fits the payment rail. For pre-confirmation (mempool) signal you'd
# need a mempool-exposing endpoint; see the README.
#
# Try it with zero setup:  DRY_RUN=1 ./realtime-whale.sh
#   Scans the canned example-block.json once and prints the Telegram message it
#   would push. No pay, no Telegram, no long-running loop.
#
set -euo pipefail

# --- Config ------------------------------------------------------------------
# Required (live mode):
#   PAYSH_RPC_URL       pay.sh JSON-RPC endpoint for the target chain
#   WATCH_WALLET        wallet address to watch (native transfers to/from)
#   THRESHOLD_NATIVE    min transfer size in the chain's native unit (e.g. ETH)
#   TELEGRAM_BOT_TOKEN  from @BotFather
#   TELEGRAM_CHAT_ID    your chat/channel id (talk to @userinfobot to get yours)
#
# Optional:
#   NATIVE_SYMBOL       display symbol for the native asset (default: ETH)
#   POLL_SECONDS        head poll interval, seconds (default: 3)
#   STATE_DIR           where the last-scanned block is stored (default: ~/.whale-watcher)
#   DRY_RUN=1           demo: scan EXAMPLE_BLOCK once, print instead of push
#   EXAMPLE_BLOCK       canned block for DRY_RUN (default: ./example-block.json)

NATIVE_SYMBOL="${NATIVE_SYMBOL:-ETH}"
POLL_SECONDS="${POLL_SECONDS:-3}"
STATE_DIR="${STATE_DIR:-$HOME/.whale-watcher}"
DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_BLOCK="${EXAMPLE_BLOCK:-$SCRIPT_DIR/example-block.json}"

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
  printf 'scale=6; %s / 10^18\n' "$wei" | bc
}

# 0x-hex -> decimal integer (block numbers; safe for typical heights)
hex_to_int() { printf '%d' "$1"; }

# --- Preflight ---------------------------------------------------------------
require_cmd jq
require_cmd bc

if [ "$DRY_RUN" = "1" ]; then
  WATCH_WALLET="${WATCH_WALLET:-0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045}"
  THRESHOLD_NATIVE="${THRESHOLD_NATIVE:-100}"
  log "DRY RUN — scanning $EXAMPLE_BLOCK once, printing instead of pushing to Telegram."
else
  require_cmd curl
  for v in PAYSH_RPC_URL WATCH_WALLET THRESHOLD_NATIVE TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID; do
    require_env "$v"
  done
fi

case "$THRESHOLD_NATIVE" in ''|*[!0-9.]*) die "THRESHOLD_NATIVE must be a number, got: '$THRESHOLD_NATIVE'";; esac

# Lowercase the wallet once for case-insensitive address matching.
WALLET_LC="$(printf '%s' "$WATCH_WALLET" | tr 'A-Z' 'a-z')"

# --- Paid JSON-RPC over pay.sh ----------------------------------------------
# `pay` fronts the HTTP call and settles the x402 micropayment. If your pay CLI
# uses a different wrapper form, this one function is the only thing to change.
rpc() {
  local method="$1" params="$2"
  pay curl -s -X POST "$PAYSH_RPC_URL" \
    -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"${method}\",\"params\":${params}}"
}

# --- Telegram push -----------------------------------------------------------
push_telegram() {
  local text="$1"
  curl -sS -o /dev/null -w '%{http_code}' \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${text}" \
    --data-urlencode "disable_web_page_preview=true" || echo "000"
}

# --- Scan one block ----------------------------------------------------------
# Given a full block JSON (result.transactions[]), emit an alert for every
# native transfer to/from the wallet at/above the threshold.
scan_block() {
  local block_json="$1"

  # Keep only txs that touch our wallet and carry a value; jq lowercases
  # addresses so matching is case-insensitive.
  local hits
  hits="$(printf '%s' "$block_json" | jq -c --arg w "$WALLET_LC" '
    .result.transactions[]?
    | select((.value // "0x0") != "0x0")
    | select((((.from // "") | ascii_downcase) == $w)
          or (((.to   // "") | ascii_downcase) == $w))
  ' 2>/dev/null || true)"

  [ -n "${hits//[[:space:]]/}" ] || return 0

  while IFS= read -r tx; do
    [ -n "$tx" ] || continue
    local value_hex from to hash native over dir other
    value_hex="$(printf '%s' "$tx" | jq -r '.value')"
    from="$(printf '%s' "$tx"      | jq -r '.from // "?"')"
    to="$(printf '%s' "$tx"        | jq -r '.to // "?"')"
    hash="$(printf '%s' "$tx"      | jq -r '.hash // "?"')"

    native="$(hex_to_native "$value_hex")"
    over="$(printf '%s >= %s\n' "$native" "$THRESHOLD_NATIVE" | bc)"
    [ "$over" = "1" ] || continue

    if [ "$(printf '%s' "$from" | tr 'A-Z' 'a-z')" = "$WALLET_LC" ]; then
      dir="out"; other="$to"
    else
      dir="in";  other="$from"
    fi

    local body
    body="🐋 Whale alert: ${WATCH_WALLET:0:6}…${WATCH_WALLET: -4} ${dir} ${native} ${NATIVE_SYMBOL} (counterparty ${other:0:6}…). tx ${hash:0:10}…"

    if [ "$DRY_RUN" = "1" ]; then
      log "Whale detected (${native} ${NATIVE_SYMBOL}) — would push to Telegram:"
      printf 'TELEGRAM: %s\n' "$body"
      continue
    fi

    log "Whale detected (${native} ${NATIVE_SYMBOL}). Pushing to Telegram ..."
    local code; code="$(push_telegram "$body")"
    if [ "$code" = "200" ]; then log "Pushed tx $hash."; else log "Telegram HTTP $code for tx $hash."; fi
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
LAST_FILE="$STATE_DIR/${WATCH_WALLET}.lastblock"
last=0
[ -f "$LAST_FILE" ] && last="$(cat "$LAST_FILE" 2>/dev/null || echo 0)"

log "Watching ${WATCH_WALLET} for transfers >= ${THRESHOLD_NATIVE} ${NATIVE_SYMBOL} (poll ${POLL_SECONDS}s)."
while true; do
  head_hex="$(rpc eth_blockNumber '[]' | jq -r '.result // empty' 2>/dev/null || true)"
  if [ -z "$head_hex" ]; then
    log "No head from RPC — retrying."; sleep "$POLL_SECONDS"; continue
  fi
  head="$(hex_to_int "$head_hex")"

  # First run: start from the current head, don't replay history.
  [ "$last" -eq 0 ] && last="$((head - 1))"

  while [ "$last" -lt "$head" ]; do
    n="$((last + 1))"
    n_hex="$(printf '0x%x' "$n")"
    block="$(rpc eth_getBlockByNumber "[\"${n_hex}\", true]" 2>/dev/null || true)"
    if printf '%s' "$block" | jq -e '.result.transactions' >/dev/null 2>&1; then
      scan_block "$block"
      last="$n"
      printf '%s\n' "$last" > "$LAST_FILE"
    else
      # Block not ready yet or a transient RPC hiccup — back off and retry.
      break
    fi
  done

  sleep "$POLL_SECONDS"
done
