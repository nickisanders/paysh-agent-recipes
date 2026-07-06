#!/usr/bin/env bash
#
# morning-brief.sh — A daily cited digest on the topics you follow.
#
# For each topic, it runs a web search through pay.sh (Perplexity Sonar style,
# with citations), assembles a brief, and delivers it. Chains two pay.sh APIs in
# one script: web search to gather, and the agent email inbox to send. Paid per
# request in USDC, no API keys. Designed to run on a daily cron.
#
# Deliver via email (default), stdout, a webhook, or Telegram (ALERT_SINK).
#
# Try it with zero setup:  DRY_RUN=1 ./morning-brief.sh
#   Assembles a brief from the canned example-search.json and prints it. No pay,
#   no network, nothing sent.
#
set -euo pipefail

# --- Config ------------------------------------------------------------------
# Required (live mode):
#   TOPICS              topics/questions to research, comma or newline separated
#
# Delivery — pick one with ALERT_SINK (default: email):
#   email      -> needs EMAIL_TO (sent from a pay.sh agent inbox)
#   stdout     -> prints the brief (pipe it anywhere)
#   webhook    -> needs WEBHOOK_URL   (POSTs the JSON payload)
#   telegram   -> needs TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID
#
# Optional:
#   BRIEF_TITLE         heading + email subject (default: "Morning Brief")
#   PAYSH_SEARCH_URL    pay.sh web-search endpoint (has a sane default)
#   PAYSH_EMAIL_URL     pay.sh agent-email send endpoint (has a sane default)
#   DRY_RUN=1           demo: build from EXAMPLE_SEARCH, print instead of send
#   EXAMPLE_SEARCH      canned search results for DRY_RUN

ALERT_SINK="${ALERT_SINK:-email}"
BRIEF_TITLE="${BRIEF_TITLE:-Morning Brief}"
PAYSH_SEARCH_URL="${PAYSH_SEARCH_URL:-https://search.pay.sh/answer}"
PAYSH_EMAIL_URL="${PAYSH_EMAIL_URL:-https://email.pay.sh/send}"
DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_SEARCH="${EXAMPLE_SEARCH:-$SCRIPT_DIR/example-search.json}"

# --- Helpers -----------------------------------------------------------------
log()  { printf '[morning-brief] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed or not on PATH."; }
require_env() { [ -n "${!1:-}" ] || die "Missing required env var: $1"; }

# --- Preflight ---------------------------------------------------------------
require_cmd jq

if [ "$DRY_RUN" = "1" ]; then
  TOPICS="${TOPICS:-AI agent payments, Solana ecosystem}"
  [ -f "$EXAMPLE_SEARCH" ] || die "Fixture not found: $EXAMPLE_SEARCH"
  log "DRY RUN: building brief from $EXAMPLE_SEARCH, printing instead of delivering."
else
  require_cmd curl
  require_env TOPICS
  require_env PAYSH_SEARCH_URL
  case "$ALERT_SINK" in
    email)     require_env EMAIL_TO; require_env PAYSH_EMAIL_URL ;;
    stdout)    : ;;
    webhook)   require_env WEBHOOK_URL ;;
    telegram)  require_env TELEGRAM_BOT_TOKEN; require_env TELEGRAM_CHAT_ID ;;
    *)         die "Unknown ALERT_SINK '$ALERT_SINK' (use: email|stdout|webhook|telegram)" ;;
  esac
fi

# Human date for the heading/subject. %e is space-padded and portable; collapse
# the resulting double space.
DATE_STR="$(date '+%A, %B %e, %Y' | sed 's/  */ /g')"

# --- Web search over pay.sh --------------------------------------------------
# `pay` fronts the HTTP call and settles the x402 micropayment. Returns a cited
# answer; we normalize the likely response shapes into our own schema. If your
# pay.sh route differs, this is the one function to adjust.
search_topic() {
  local topic="$1" raw
  raw="$(pay curl -s -G "$PAYSH_SEARCH_URL" --data-urlencode "q=${topic}" 2>/dev/null || true)"
  printf '%s' "$raw" | jq -c --arg t "$topic" '
    {
      topic: $t,
      answer: (.answer // .text // .summary // ""),
      sources: (((.citations // .sources // []) | map({title:(.title // .url // ""), url:(.url // "")})))
    }' 2>/dev/null \
    || jq -nc --arg t "$topic" '{topic:$t, answer:"", sources:[]}'
}

# --- Gather sections (one normalized JSON object per topic) -------------------
build_sections() {
  if [ "$DRY_RUN" = "1" ]; then
    jq -c '.[]' "$EXAMPLE_SEARCH"
    return 0
  fi
  printf '%s\n' "$TOPICS" | tr ',' '\n' | while IFS= read -r topic; do
    topic="$(printf '%s' "$topic" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -n "$topic" ] || continue
    log "Searching: $topic"
    search_topic "$topic"
  done
}

# --- Assemble the brief (plain text) -----------------------------------------
assemble_digest() {
  local sections="$1"
  printf '%s: %s\n\n' "$BRIEF_TITLE" "$DATE_STR"
  while IFS= read -r sec; do
    [ -n "$sec" ] || continue
    local topic answer srcs
    topic="$(printf '%s' "$sec"  | jq -r '.topic')"
    answer="$(printf '%s' "$sec" | jq -r '.answer')"
    [ -n "${answer//[[:space:]]/}" ] || answer="(no results)"
    printf '## %s\n%s\n' "$topic" "$answer"
    srcs="$(printf '%s' "$sec" | jq -r '.sources[]? | "  - \(.title) (\(.url))"')"
    [ -z "${srcs//[[:space:]]/}" ] || printf 'Sources:\n%s\n' "$srcs"
    printf '\n'
  done <<< "$sections"
}

# --- Delivery (pluggable sink) -----------------------------------------------
deliver() {
  local subject="$1" text="$2" payload="$3"
  case "$ALERT_SINK" in
    email)
      local code
      code="$(pay curl -sS -o /dev/null -w '%{http_code}' -X POST "$PAYSH_EMAIL_URL" \
        -H 'content-type: application/json' \
        --data "$(jq -nc --arg to "$EMAIL_TO" --arg subject "$subject" --arg text "$text" \
                  '{to:$to,subject:$subject,text:$text}')" || echo "000")"
      case "$code" in 2*) log "Emailed to $EMAIL_TO ($code).";; *) log "Email HTTP $code.";; esac
      ;;
    webhook)
      local code
      code="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$WEBHOOK_URL" \
        -H 'content-type: application/json' --data "$payload" || echo "000")"
      case "$code" in 2*) log "Posted to webhook ($code).";; *) log "Webhook HTTP $code.";; esac
      ;;
    telegram)
      local code
      code="$(curl -sS -o /dev/null -w '%{http_code}' \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${text}" || echo "000")"
      [ "$code" = "200" ] && log "Pushed to Telegram." || log "Telegram HTTP $code."
      ;;
    stdout)
      printf '%s\n' "$text"
      ;;
  esac
}

# --- Run ---------------------------------------------------------------------
sections="$(build_sections)"
[ -n "${sections//[[:space:]]/}" ] || die "No search results to brief on."

digest="$(assemble_digest "$sections")"
subject="${BRIEF_TITLE}: ${DATE_STR}"
payload="$(jq -nc \
  --arg title "$BRIEF_TITLE" --arg date "$DATE_STR" --arg text "$digest" \
  --argjson sections "$(printf '%s' "$sections" | jq -s '.')" \
  '{type:"morning_brief",title:$title,date:$date,sections:$sections,text:$text}')"

if [ "$DRY_RUN" = "1" ]; then
  log "Would deliver via '${ALERT_SINK}'. Brief:"
  printf '%s\n' "$digest"
  log "Done (dry run)."
  exit 0
fi

deliver "$subject" "$digest" "$payload"
log "Done."
