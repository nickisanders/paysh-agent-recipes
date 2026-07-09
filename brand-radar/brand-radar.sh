#!/usr/bin/env bash
#
# brand-radar.sh — Track mentions of a keyword and get pinged on new ones.
#
# Searches social data (Reddit and more) through pay.sh (paid per request in
# USDC, no API keys) for QUERY, remembers which posts it has already seen, and
# alerts you on new mentions. With SUMMARIZE=1 it runs the new mentions through
# `pay claude` for a one-line sentiment read. Designed to run on a cron. The
# first run saves a baseline, so you aren't paged for the whole backlog.
#
# Deliver via Telegram, a webhook, a websocket, or stdout (ALERT_SINK).
#
# Try it with zero setup:  DRY_RUN=1 ./brand-radar.sh
#   Treats the canned example-mentions.json as new and prints the alert. No pay,
#   no network, no state written.
#
set -euo pipefail

# --- Config ------------------------------------------------------------------
# Required (live mode):
#   QUERY               keyword/brand/token to track
#
# Optional:
#   SOURCE              where to search (default: reddit)
#   SUMMARIZE           1 to add a pay claude sentiment read (default: 0)
#   MAX_LIST            how many new mentions to list in the alert (default: 5)
#   ALERT_SINK          telegram (default) | webhook | websocket | stdout
#   PAYSH_SOCIAL_URL    pay.sh social-search endpoint (has a sane default)
#   STATE_DIR           where seen post ids are stored (default: ~/.brand-radar)
#   DRY_RUN=1           demo: treat EXAMPLE_MENTIONS as new, print instead of send
#   EXAMPLE_MENTIONS    canned mentions for DRY_RUN

SOURCE="${SOURCE:-reddit}"
SUMMARIZE="${SUMMARIZE:-0}"
MAX_LIST="${MAX_LIST:-5}"
ALERT_SINK="${ALERT_SINK:-telegram}"
PAYSH_SOCIAL_URL="${PAYSH_SOCIAL_URL:-https://social.pay.sh/search}"
STATE_DIR="${STATE_DIR:-$HOME/.brand-radar}"
DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_MENTIONS="${EXAMPLE_MENTIONS:-$SCRIPT_DIR/example-mentions.json}"

# --- Helpers -----------------------------------------------------------------
log()  { printf '[brand-radar] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed or not on PATH."; }
require_env() { [ -n "${!1:-}" ] || die "Missing required env var: $1"; }

# --- Preflight ---------------------------------------------------------------
require_cmd jq

if [ "$DRY_RUN" = "1" ]; then
  QUERY="${QUERY:-pay.sh}"
  [ -f "$EXAMPLE_MENTIONS" ] || die "Fixture not found: $EXAMPLE_MENTIONS"
  log "DRY RUN: treating $EXAMPLE_MENTIONS as new mentions of '$QUERY', printing instead of sending."
else
  require_cmd curl
  require_env QUERY
  require_env PAYSH_SOCIAL_URL
  case "$ALERT_SINK" in
    telegram)  require_env TELEGRAM_BOT_TOKEN; require_env TELEGRAM_CHAT_ID ;;
    webhook)   require_env WEBHOOK_URL ;;
    websocket) require_env WS_URL; require_cmd websocat ;;
    stdout)    : ;;
    *)         die "Unknown ALERT_SINK '$ALERT_SINK' (use: telegram|webhook|websocket|stdout)" ;;
  esac
fi

# --- Social search over pay.sh -----------------------------------------------
# `pay` fronts the HTTP call and settles the x402 micropayment. Normalizes the
# likely response shapes into a flat list. Adjust the mapping if yours differs.
fetch_mentions() {
  local raw
  if [ "$DRY_RUN" = "1" ]; then
    raw="$(cat "$EXAMPLE_MENTIONS")"
  else
    raw="$(pay curl -s -G "$PAYSH_SOCIAL_URL" \
      --data-urlencode "q=${QUERY}" --data-urlencode "source=${SOURCE}" 2>/dev/null || echo '[]')"
  fi
  printf '%s' "$raw" | jq -c '
    (if type == "array" then . else (.results // .posts // .data // []) end)
    | map({
        id:      (.id // .name // .url // ""),
        title:   (.title // ""),
        url:     (.url // .permalink // ""),
        author:  (.author // ""),
        source:  (.source // .subreddit // ""),
        score:   (.score // .ups // 0),
        snippet: (.snippet // .selftext // "")
      })
  ' 2>/dev/null || echo '[]'
}

# --- Sentiment read via pay claude (optional) --------------------------------
summarize_mentions() {
  local mentions="$1"
  if [ "$DRY_RUN" = "1" ]; then
    printf "Mostly positive. Builders are trying pay.sh for agent micropayments and finding the keyless model smooth, with a couple of questions about the trust and security tradeoffs."
    return 0
  fi
  pay claude -p "Here are new social mentions of \"${QUERY}\" (JSON). In one or two plain sentences, summarize the overall sentiment and the main themes. No preamble, no markdown. Mentions: ${mentions}" \
    2>/dev/null | tr '\n' ' ' | sed 's/  */ /g; s/ *$//' || true
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
    stdout)
      printf '%s\n' "$payload"
      ;;
  esac
}

# --- Alert on a set of new mentions ------------------------------------------
alert_new() {
  local new="$1" count
  count="$(printf '%s' "$new" | jq 'length')"

  local list summary body payload
  list="$(printf '%s' "$new" | jq -r --argjson n "$MAX_LIST" '.[:$n][] | "  - \(.title) (\(.source), \(.score)↑)"')"

  summary=""
  if [ "$SUMMARIZE" = "1" ]; then
    summary="$(summarize_mentions "$new")"
  fi

  body="📣 ${count} new mention(s) of \"${QUERY}\":
${list}"
  [ "$count" -gt "$MAX_LIST" ] && body="${body}
  … and $((count - MAX_LIST)) more"
  [ -n "${summary//[[:space:]]/}" ] && body="${body}

${summary}"

  payload="$(jq -nc \
    --arg query "$QUERY" --argjson count "$count" --arg summary "$summary" \
    --arg text "$body" --argjson mentions "$new" \
    '{type:"brand_mentions",query:$query,count:$count,summary:$summary,mentions:$mentions,text:$text}')"

  if [ "$DRY_RUN" = "1" ]; then
    printf '%s\n' "$body"
    log "Done (dry run)."
    return 0
  fi
  deliver "$body" "$payload"
}

# --- Run ---------------------------------------------------------------------
mentions="$(fetch_mentions)"

if [ "$DRY_RUN" = "1" ]; then
  [ "$(printf '%s' "$mentions" | jq 'length')" -gt 0 ] || { log "No mentions in fixture."; exit 0; }
  alert_new "$mentions"
  exit 0
fi

mkdir -p "$STATE_DIR"
slug="$(printf '%s' "${QUERY}-${SOURCE}" | tr -c 'A-Za-z0-9' '_')"
SEEN_FILE="$STATE_DIR/${slug}.seen"

# Ids present right now.
ids_now="$(printf '%s' "$mentions" | jq -r '.[].id' | grep -v '^$' || true)"

if [ ! -f "$SEEN_FILE" ]; then
  printf '%s\n' "$ids_now" > "$SEEN_FILE"
  log "Baseline saved for '$QUERY' ($(printf '%s\n' "$ids_now" | grep -c . || true) mentions). No alert on first run."
  exit 0
fi

# New = mentions whose id is not in the seen file.
seen_json="$( (jq -R . "$SEEN_FILE" 2>/dev/null | jq -s .) || echo '[]')"
new="$(printf '%s' "$mentions" | jq -c --argjson seen "$seen_json" '[ .[] | select((.id as $i | $seen | index($i)) | not) ]')"
new_count="$(printf '%s' "$new" | jq 'length')"

if [ "$new_count" -eq 0 ]; then
  log "No new mentions of '$QUERY'."
  exit 0
fi

log "$new_count new mention(s) of '$QUERY'. Alerting via '$ALERT_SINK' ..."
alert_new "$new"
printf '%s\n' "$ids_now" > "$SEEN_FILE"   # advance the baseline
