#!/usr/bin/env bash
#
# contract-auditor.sh — Audit a smart contract and get a plain-English risk brief.
#
# Pulls a security analysis for a contract address from a pay.sh audit endpoint
# (paid per request in USDC, no API keys), then runs the findings through
# `pay claude` to explain the risk in plain English. Address in, brief out.
#
# Deliver via stdout (default), Telegram, a webhook, or a websocket.
#
# Try it with zero setup:  DRY_RUN=1 ./contract-auditor.sh
#   Audits the canned example-audit.json and prints the brief. No pay, no network.
#
set -euo pipefail

# --- Config ------------------------------------------------------------------
# Required (live mode):
#   ADDRESS             contract address to audit (or pass as the first argument)
#
# Optional:
#   CHAIN               network the contract is on (default: ethereum)
#   SUMMARIZE           1 to add a pay claude plain-English brief (default: 1)
#   ALERT_SINK          stdout (default) | telegram | webhook | websocket
#   PAYSH_AUDIT_URL     pay.sh contract-audit endpoint (has a sane default)
#   DRY_RUN=1           demo: audit EXAMPLE_AUDIT, print instead of deliver
#   EXAMPLE_AUDIT       canned findings for DRY_RUN

ADDRESS="${ADDRESS:-${1:-}}"
CHAIN="${CHAIN:-ethereum}"
SUMMARIZE="${SUMMARIZE:-1}"
ALERT_SINK="${ALERT_SINK:-stdout}"
PAYSH_AUDIT_URL="${PAYSH_AUDIT_URL:-https://audit.pay.sh/contract}"
DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_AUDIT="${EXAMPLE_AUDIT:-$SCRIPT_DIR/example-audit.json}"

# --- Helpers -----------------------------------------------------------------
log()  { printf '[contract-auditor] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed or not on PATH."; }
require_env() { [ -n "${!1:-}" ] || die "Missing required env var: $1"; }

# --- Preflight ---------------------------------------------------------------
require_cmd jq

if [ "$DRY_RUN" = "1" ]; then
  [ -f "$EXAMPLE_AUDIT" ] || die "Fixture not found: $EXAMPLE_AUDIT"
  ADDRESS="${ADDRESS:-$(jq -r '.address' "$EXAMPLE_AUDIT")}"
  log "DRY RUN: auditing $EXAMPLE_AUDIT, printing instead of delivering."
else
  require_cmd curl
  [ -n "$ADDRESS" ] || die "Set ADDRESS (or pass the contract address as the first argument)."
  require_env PAYSH_AUDIT_URL
  case "$ALERT_SINK" in
    stdout)    : ;;
    telegram)  require_env TELEGRAM_BOT_TOKEN; require_env TELEGRAM_CHAT_ID ;;
    webhook)   require_env WEBHOOK_URL ;;
    websocket) require_env WS_URL; require_cmd websocat ;;
    *)         die "Unknown ALERT_SINK '$ALERT_SINK' (use: stdout|telegram|webhook|websocket)" ;;
  esac
fi

# --- Audit lookup over pay.sh ------------------------------------------------
# `pay` fronts the HTTP call and settles the x402 micropayment. Returns the raw
# findings JSON; adjust the field names below if your audit route differs.
fetch_audit() {
  local addr="$1" chain="$2"
  if [ "$DRY_RUN" = "1" ]; then
    cat "$EXAMPLE_AUDIT"
  else
    pay curl -s -G "$PAYSH_AUDIT_URL" \
      --data-urlencode "address=${addr}" --data-urlencode "chain=${chain}" 2>/dev/null || echo '{}'
  fi
}

# --- Plain-English brief via pay claude --------------------------------------
summarize_audit() {
  local findings="$1"
  if [ "$DRY_RUN" = "1" ]; then
    printf "The owner can still mint new supply and freeze (blacklist) individual holders, and ownership has not been renounced. That lets the deployer dilute or trap holders at any time, so treat this contract as high risk and avoid holding size."
    return 0
  fi
  pay claude -p "You are a smart-contract security assistant. Given these findings (JSON), explain in two or three plain sentences what someone should be worried about before interacting with this contract. No preamble, no markdown. Findings: ${findings}" \
    2>/dev/null | tr '\n' ' ' | sed 's/  */ /g; s/ *$//' || true
}

# --- Delivery (pluggable sink) -----------------------------------------------
deliver() {
  local text="$1" payload="$2"
  case "$ALERT_SINK" in
    stdout)
      printf '%s\n' "$text"
      ;;
    telegram)
      local code
      code="$(curl -sS -o /dev/null -w '%{http_code}' \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${text}" || echo "000")"
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
  esac
}

# --- Run ---------------------------------------------------------------------
log "Auditing ${ADDRESS} on ${CHAIN} ..."
findings="$(fetch_audit "$ADDRESS" "$CHAIN")"
if ! printf '%s' "$findings" | jq -e . >/dev/null 2>&1; then
  die "Audit endpoint returned no usable JSON."
fi

risk="$(printf '%s' "$findings"  | jq -r '(.risk // .risk_level // "unknown") | ascii_upcase')"
flags="$(printf '%s' "$findings" | jq -r '(.flags // []) | join(", ")')"

summary=""
if [ "$SUMMARIZE" = "1" ]; then
  summary="$(summarize_audit "$findings")"
fi

short="${ADDRESS:0:6}…${ADDRESS: -4}"
body="🔍 Contract audit: ${short} on ${CHAIN}
Risk: ${risk}"
[ -n "${summary//[[:space:]]/}" ] && body="${body}
${summary}"
[ -n "${flags//[[:space:]]/}" ]   && body="${body}
Flags: ${flags}"

payload="$(jq -nc \
  --arg address "$ADDRESS" --arg chain "$CHAIN" --arg risk "$risk" \
  --arg summary "$summary" --arg text "$body" \
  --argjson findings "$findings" \
  '{type:"contract_audit",address:$address,chain:$chain,risk:$risk,summary:$summary,findings:$findings,text:$text}')"

if [ "$DRY_RUN" = "1" ]; then
  printf '%s\n' "$body"
  log "Done (dry run). Non-stdout sinks would receive this JSON payload:"
  printf '%s\n' "$payload" | jq -c '{type,address,chain,risk,summary}' >&2
  exit 0
fi

deliver "$body" "$payload"
log "Done."
