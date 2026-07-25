#!/usr/bin/env bash
#
# spend-report.sh — See exactly what your agents spent.
#
# The guardrails control agent spending: Spend Guard caps how much, Approval Gate
# adds a human, Rate Limiter caps how often. This is the visibility half: it reads
# the ledgers Spend Guard writes and rolls them up into a plain report, total, by
# endpoint, by day, so you can actually see where the USDC went.
#
# Deliver via stdout (default), Telegram, a webhook, or a websocket, e.g. a daily
# spend digest pushed to a channel.
#
# Try it with zero setup:  DRY_RUN=1 ./spend-report.sh
#   Reads the canned example-ledgers/ instead of your real state dir. No network.
#
set -euo pipefail

# --- Config ------------------------------------------------------------------
# Optional:
#   GUARD_STATE_DIR   where Spend Guard writes its <date>.ledger files
#                     (default ~/.spend-guard, matching the Spend Guard recipe)
#   ALERT_SINK        stdout (default) | telegram | webhook | websocket
#   DRY_RUN=1         demo: read EXAMPLE_LEDGER_DIR instead of the real state dir
#   EXAMPLE_LEDGER_DIR  canned ledgers for DRY_RUN

ALERT_SINK="${ALERT_SINK:-stdout}"
DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD_STATE_DIR="${GUARD_STATE_DIR:-$HOME/.spend-guard}"
EXAMPLE_LEDGER_DIR="${EXAMPLE_LEDGER_DIR:-$SCRIPT_DIR/example-ledgers}"

# --- Helpers -----------------------------------------------------------------
log()  { printf '[spend-report] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed or not on PATH."; }
require_env() { [ -n "${!1:-}" ] || die "Missing required env var: $1"; }

# --- Preflight ---------------------------------------------------------------
require_cmd awk
require_cmd jq

if [ "$DRY_RUN" = "1" ]; then
  STATE_DIR="$EXAMPLE_LEDGER_DIR"
  log "DRY RUN: rolling up $(basename "$STATE_DIR")/, printing instead of delivering."
else
  STATE_DIR="$GUARD_STATE_DIR"
  case "$ALERT_SINK" in
    stdout)    : ;;
    telegram)  require_cmd curl; require_env TELEGRAM_BOT_TOKEN; require_env TELEGRAM_CHAT_ID ;;
    webhook)   require_cmd curl; require_env WEBHOOK_URL ;;
    websocket) require_env WS_URL; require_cmd websocat ;;
    *)         die "Unknown ALERT_SINK '$ALERT_SINK' (use: stdout|telegram|webhook|websocket)" ;;
  esac
fi

# --- Gather the ledgers ------------------------------------------------------
# Spend Guard writes one file per day, "<date>.ledger", each line: "amount host time".
# We glob them, newest last. A missing / empty dir just means nothing spent yet.
shopt -s nullglob
ledgers=("$STATE_DIR"/*.ledger)
shopt -u nullglob

if [ "${#ledgers[@]}" -eq 0 ]; then
  body="🧾 Spend Report
No ledgers found in ${STATE_DIR}. Nothing spent yet."
  if [ "$DRY_RUN" = "1" ] || [ "$ALERT_SINK" = "stdout" ]; then printf '%s\n' "$body"; fi
  log "No ledgers found."
  exit 0
fi

days="${#ledgers[@]}"

# --- Roll up -----------------------------------------------------------------
# Totals across every ledger.
read -r total_usd total_calls < <(
  awk '{ t += $1; c++ } END { printf "%.4f %d\n", t, (c+0) }' "${ledgers[@]}"
)

# Per-endpoint spend + calls, richest first. Emits "host<TAB>usd<TAB>calls".
by_endpoint="$(
  awk '{ ht[$2] += $1; hc[$2]++ }
       END { for (h in ht) printf "%s\t%.4f\t%d\n", h, ht[h], hc[h] }' "${ledgers[@]}" \
    | sort -t$'\t' -k2 -rn
)"

# Per-day spend, oldest first (the filename is the date, minus ".ledger").
by_day="$(
  for f in "${ledgers[@]}"; do
    d="$(basename "$f" .ledger)"
    awk -v d="$d" '{ t += $1; c++ } END { printf "%s\t%.4f\t%d\n", d, t, (c+0) }' "$f"
  done
)"

avg_per_day="$(awk -v t="$total_usd" -v d="$days" 'BEGIN { printf "%.4f", (d>0 ? t/d : 0) }')"

# --- Assemble the report -----------------------------------------------------
fmt_usd() { awk -v v="$1" 'BEGIN { printf "$%.2f", v }'; }

body="🧾 Spend Report
$(fmt_usd "$total_usd") across ${total_calls} calls over ${days} day(s)
Avg $(fmt_usd "$avg_per_day")/day"

body="${body}

By endpoint:"
while IFS=$'\t' read -r host usd calls; do
  [ -n "$host" ] || continue
  body="${body}
  • $(printf '%-16s' "$host") $(fmt_usd "$usd")  (${calls} calls)"
done <<< "$by_endpoint"

body="${body}

By day:"
while IFS=$'\t' read -r day usd calls; do
  [ -n "$day" ] || continue
  body="${body}
  • ${day}  $(fmt_usd "$usd")  (${calls} calls)"
done <<< "$by_day"

# --- JSON payload for non-stdout sinks ---------------------------------------
endpoints_json="$(
  printf '%s\n' "$by_endpoint" \
    | awk -F'\t' 'NF>=3 { printf "%s%s", (NR>1?"\n":""), $0 }' \
    | jq -R -s 'split("\n") | map(select(length>0) | split("\t"))
                | map({host:.[0], usd:(.[1]|tonumber), calls:(.[2]|tonumber)})'
)"
days_json="$(
  printf '%s\n' "$by_day" \
    | jq -R -s 'split("\n") | map(select(length>0) | split("\t"))
                | map({day:.[0], usd:(.[1]|tonumber), calls:(.[2]|tonumber)})'
)"
payload="$(jq -nc \
  --argjson total_usd "$total_usd" --argjson total_calls "$total_calls" \
  --argjson days "$days" --arg text "$body" \
  --argjson by_endpoint "$endpoints_json" --argjson by_day "$days_json" \
  '{type:"spend_report",total_usd:$total_usd,total_calls:$total_calls,days:$days,
    by_endpoint:$by_endpoint,by_day:$by_day,text:$text}')"

# --- Deliver (pluggable sink) ------------------------------------------------
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

if [ "$DRY_RUN" = "1" ]; then
  printf '%s\n' "$body"
  log "Done (dry run)."
  exit 0
fi

deliver "$body" "$payload"
log "Done."
