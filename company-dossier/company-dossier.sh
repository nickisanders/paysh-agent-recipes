#!/usr/bin/env bash
#
# company-dossier.sh — One domain in, a one-page company brief out.
#
# Orchestrates two paid pay.sh calls for a company: firmographic enrichment (what
# they do, size, location) and a recent-news search, then `pay claude` writes a
# plain-English brief. Paid per request in USDC, no API keys.
#
# The web/data sibling of Token Dossier: one question, a couple of paid sources,
# one answer. A failure in any source degrades gracefully instead of aborting.
#
# Deliver via stdout (default), Telegram, a webhook, or a websocket.
#
# Try it with zero setup:  DRY_RUN=1 ./company-dossier.sh
#   Builds a brief from the canned example-company.json. No pay, no network.
#
set -euo pipefail

# --- Config ------------------------------------------------------------------
# Required (live mode):
#   DOMAIN              company domain to research (or pass as the first argument)
#
# Optional:
#   ALERT_SINK          stdout (default) | telegram | webhook | websocket
#   PAYSH_ENRICH_URL / PAYSH_SEARCH_URL   the two pay.sh endpoints (sane defaults)
#   DRY_RUN=1           demo: build from EXAMPLE_COMPANY, print instead of deliver
#   EXAMPLE_COMPANY     canned sources for DRY_RUN

DOMAIN="${DOMAIN:-${1:-}}"
ALERT_SINK="${ALERT_SINK:-stdout}"
PAYSH_ENRICH_URL="${PAYSH_ENRICH_URL:-https://enrich.pay.sh/lookup}"
PAYSH_SEARCH_URL="${PAYSH_SEARCH_URL:-https://search.pay.sh/answer}"
DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_COMPANY="${EXAMPLE_COMPANY:-$SCRIPT_DIR/example-company.json}"

# --- Helpers -----------------------------------------------------------------
log()  { printf '[company-dossier] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed or not on PATH."; }
require_env() { [ -n "${!1:-}" ] || die "Missing required env var: $1"; }
# Host from a URL, for compact news attribution.
host() { printf '%s' "$1" | sed -E 's#^https?://##; s#^www\.##; s#/.*$##'; }

# --- Preflight ---------------------------------------------------------------
require_cmd jq

if [ "$DRY_RUN" = "1" ]; then
  [ -f "$EXAMPLE_COMPANY" ] || die "Fixture not found: $EXAMPLE_COMPANY"
  DOMAIN="${DOMAIN:-$(jq -r '.enrichment.domain // "example.com"' "$EXAMPLE_COMPANY")}"
  log "DRY RUN: building brief from $EXAMPLE_COMPANY, printing instead of delivering."
else
  require_cmd curl
  [ -n "$DOMAIN" ] || die "Set DOMAIN (or pass the company domain as the first argument)."
  require_env PAYSH_ENRICH_URL
  require_env PAYSH_SEARCH_URL
  case "$ALERT_SINK" in
    stdout)    : ;;
    telegram)  require_env TELEGRAM_BOT_TOKEN; require_env TELEGRAM_CHAT_ID ;;
    webhook)   require_env WEBHOOK_URL ;;
    websocket) require_env WS_URL; require_cmd websocat ;;
    *)         die "Unknown ALERT_SINK '$ALERT_SINK' (use: stdout|telegram|webhook|websocket)" ;;
  esac
fi

# --- The paid sources --------------------------------------------------------
# `pay` fronts each HTTP call and settles the x402 micropayment. In DRY_RUN each
# reads its slice of the fixture. A source that fails returns {} / [] so the brief
# still assembles. Adjust the field mapping if your routes differ.
fetch_enrichment() {
  if [ "$DRY_RUN" = "1" ]; then
    jq -c '.enrichment // {}' "$EXAMPLE_COMPANY"
  else
    pay curl -s -G "$PAYSH_ENRICH_URL" --data-urlencode "query=$DOMAIN" 2>/dev/null \
      | jq -c '.' 2>/dev/null || echo '{}'
  fi
}

fetch_news() {
  if [ "$DRY_RUN" = "1" ]; then
    jq -c '.news // []' "$EXAMPLE_COMPANY"
  else
    pay curl -s -G "$PAYSH_SEARCH_URL" --data-urlencode "q=${1} recent news" 2>/dev/null \
      | jq -c '(.results // .citations // .news // []) | map({title:(.title // ""), url:(.url // "")})' 2>/dev/null \
      || echo '[]'
  fi
}

# --- pay claude synthesis ----------------------------------------------------
synthesize() {
  local combined="$1"
  if [ "$DRY_RUN" = "1" ]; then
    printf "Stripe is the default payments layer for internet businesses and is leaning hard into stablecoins, just expanding USDC-style payments to 100+ countries. With a rising private valuation and deep merchant reach, they are positioning as core infrastructure for agent and onchain commerce, not just cards."
    return 0
  fi
  pay claude -p "You are a business research assistant. Given these findings (JSON: firmographics + recent news) for a company, write one plain-English paragraph a salesperson or partner could use: what they do, what's notable right now, and a one-line take. No preamble, no markdown. Findings: ${combined}" \
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
log "Building dossier for ${DOMAIN} ..."
enrichment="$(fetch_enrichment)"

name="$(printf '%s' "$enrichment"     | jq -r '.name // empty')"
[ -n "$name" ] || name="$DOMAIN"
industry="$(printf '%s' "$enrichment" | jq -r '.industry // "?"')"
employees="$(printf '%s' "$enrichment"| jq -r '.employees // empty')"
location="$(printf '%s' "$enrichment" | jq -r '.location // empty')"

news="$(fetch_news "$name")"

# One-line facts row from whatever enrichment returned.
facts="$industry"
[ -n "$employees" ] && facts="${facts} · ~${employees} employees"
[ -n "$location" ]  && facts="${facts} · ${location}"

combined="$(jq -nc --argjson enrichment "$enrichment" --argjson news "$news" \
  '{enrichment:$enrichment,news:$news}')"
synthesis="$(synthesize "$combined")"

# --- Assemble the brief ------------------------------------------------------
body="🏢 Company Dossier: ${name} (${DOMAIN})
${facts}"
[ -n "${synthesis//[[:space:]]/}" ] && body="${body}

${synthesis}"

news_lines="$(printf '%s' "$news" | jq -r '.[]? | "\(.title)\t\(.url)"')"
if [ -n "${news_lines//[[:space:]]/}" ]; then
  body="${body}

Recent:"
  while IFS=$'\t' read -r title url; do
    [ -n "$title" ] || continue
    body="${body}
  • ${title} ($(host "$url"))"
  done <<< "$news_lines"
fi

payload="$(jq -nc \
  --arg domain "$DOMAIN" --arg name "$name" --arg synthesis "$synthesis" --arg text "$body" \
  --argjson enrichment "$enrichment" --argjson news "$news" \
  '{type:"company_dossier",domain:$domain,name:$name,synthesis:$synthesis,enrichment:$enrichment,news:$news,text:$text}')"

if [ "$DRY_RUN" = "1" ]; then
  printf '%s\n' "$body"
  log "Done (dry run)."
  exit 0
fi

deliver "$body" "$payload"
log "Done."
