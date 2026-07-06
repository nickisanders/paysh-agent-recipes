#!/usr/bin/env bash
#
# page-watch.sh — Watch any web page and alert when it changes.
#
# Fetches WATCH_URL as clean markdown through pay.sh's web-scrape API (paid per
# request in USDC, no API keys), diffs it against the last snapshot, and alerts
# you when the page changes. Designed to run on a cron. First run just saves a
# baseline, so there are no false alerts; unchanged pages stay silent.
#
# Deliver alerts via Telegram, a webhook, a websocket, or stdout (ALERT_SINK).
# Non-telegram sinks emit a machine-readable JSON payload for agents.
#
# Try it with zero setup:  DRY_RUN=1 ./page-watch.sh
#   Diffs the two canned fixtures and prints the alert it would send. No pay,
#   no network, no state written.
#
set -euo pipefail

# --- Config ------------------------------------------------------------------
# Required (live mode):
#   WATCH_URL           the page to monitor
#
# Alert transport — pick one with ALERT_SINK (default: telegram):
#   telegram   -> needs TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID
#   webhook    -> needs WEBHOOK_URL   (POSTs the JSON payload)
#   websocket  -> needs WS_URL        (pushes the JSON payload via websocat)
#   stdout     -> prints the JSON payload (pipe it into your agent / anything)
#
# Optional:
#   SUMMARIZE=1         summarize the change in plain English via `pay claude`
#                       (one extra paid call, only when a change is detected)
#   PAYSH_SCRAPE_URL    pay.sh markdown-scrape endpoint (has a sane default)
#   IGNORE_PATTERN      extended-regex of lines to ignore (timestamps, nonces…)
#   STATE_DIR           where page snapshots are stored (default: ~/.page-watch)
#   DRY_RUN=1           demo: diff the fixtures, print instead of deliver
#   EXAMPLE_BEFORE / EXAMPLE_AFTER   fixtures used by DRY_RUN

ALERT_SINK="${ALERT_SINK:-telegram}"
SUMMARIZE="${SUMMARIZE:-0}"
PAYSH_SCRAPE_URL="${PAYSH_SCRAPE_URL:-https://scrape.pay.sh/markdown}"
STATE_DIR="${STATE_DIR:-$HOME/.page-watch}"
DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_BEFORE="${EXAMPLE_BEFORE:-$SCRIPT_DIR/example-page-before.md}"
EXAMPLE_AFTER="${EXAMPLE_AFTER:-$SCRIPT_DIR/example-page-after.md}"

# --- Helpers -----------------------------------------------------------------
log()  { printf '[page-watch] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed or not on PATH."; }
require_env() { [ -n "${!1:-}" ] || die "Missing required env var: $1"; }

# Optionally strip volatile lines so rotating timestamps/nonces don't false-alarm.
filtered() {
  if [ -n "${IGNORE_PATTERN:-}" ]; then
    printf '%s' "$1" | grep -vE "$IGNORE_PATTERN" || true
  else
    printf '%s' "$1"
  fi
}

# --- Preflight ---------------------------------------------------------------
require_cmd jq
require_cmd diff

if [ "$DRY_RUN" = "1" ]; then
  WATCH_URL="${WATCH_URL:-https://acme.example/pricing}"
  [ -f "$EXAMPLE_BEFORE" ] || die "Fixture not found: $EXAMPLE_BEFORE"
  [ -f "$EXAMPLE_AFTER" ]  || die "Fixture not found: $EXAMPLE_AFTER"
  log "DRY RUN — diffing fixtures for $WATCH_URL, printing instead of delivering."
else
  require_cmd curl
  require_env WATCH_URL
  require_env PAYSH_SCRAPE_URL
  case "$ALERT_SINK" in
    telegram)  require_env TELEGRAM_BOT_TOKEN; require_env TELEGRAM_CHAT_ID ;;
    webhook)   require_env WEBHOOK_URL ;;
    websocket) require_env WS_URL; require_cmd websocat ;;
    stdout)    : ;;
    *)         die "Unknown ALERT_SINK '$ALERT_SINK' (use: telegram|webhook|websocket|stdout)" ;;
  esac
fi

# --- Fetch the page as markdown via pay.sh -----------------------------------
# `pay` fronts the HTTP call and settles the x402 micropayment. Assumes the
# endpoint returns markdown as plain text; if yours returns JSON like
# {"markdown":"..."}, pipe this through `jq -r .markdown`. One line to change.
fetch_markdown() {
  pay curl -s -G "$PAYSH_SCRAPE_URL" --data-urlencode "url=$1"
}

# --- Alert delivery (pluggable sink) -----------------------------------------
# Deliver one alert. `text` is the human string (Telegram); `payload` is the
# machine-readable JSON (webhook/websocket/stdout). Never aborts on failure.
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

# --- Summarize a diff in plain English (optional, paid) ----------------------
# Turns the raw diff into a human sentence via `pay claude`. In DRY_RUN it
# returns a canned example so the demo shows the feature without paying.
summarize_diff() {
  local url="$1" d="$2"
  if [ "$DRY_RUN" = "1" ]; then
    printf 'Starter now includes 20 projects (was 10), the Pro plan rose from $49 to $59/mo, and a new Team plan launched at $99/mo.'
    return 0
  fi
  local prompt
  prompt="You monitor a web page for changes. Below is a unified diff of the page (as markdown) at ${url}. In one or two plain sentences, say what changed for a human reader. No preamble, no markdown, just the summary.

${d}"
  pay claude -p "$prompt" 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g; s/ *$//' || true
}

# --- Compare two versions and alert on change --------------------------------
# Emits an alert if the (filtered) markdown differs. Returns the diff details.
compare_and_alert() {
  local url="$1" old_raw="$2" new_raw="$3"
  local oldf newf
  oldf="$(filtered "$old_raw")"
  newf="$(filtered "$new_raw")"

  if [ "$oldf" = "$newf" ]; then
    log "No change at $url."
    return 1
  fi

  # diff exits 1 when files differ — that's expected, so guard set -e.
  local d added removed excerpt
  d="$(diff <(printf '%s\n' "$oldf") <(printf '%s\n' "$newf") || true)"
  added="$(printf '%s\n' "$d"   | grep -cE '^> ' || true)"
  removed="$(printf '%s\n' "$d" | grep -cE '^< ' || true)"
  # A compact one-line summary of the first few changed lines for the message.
  excerpt="$(printf '%s\n' "$d" | grep -E '^[<>] ' | head -4 \
    | sed -e 's/^< /− /' -e 's/^> /+ /' \
    | awk 'NR>1{printf " · "} {printf "%s", $0} END{if (NR) print ""}')"

  # Optional plain-English summary of the change via pay claude.
  local summary=""
  if [ "$SUMMARIZE" = "1" ]; then
    summary="$(summarize_diff "$url" "$d")"
  fi

  # Prefer the AI summary in the human message; fall back to the raw excerpt.
  local headline="$excerpt"
  [ -n "${summary//[[:space:]]/}" ] && headline="$summary"

  local body payload
  body="📄 Page changed: ${url} (+${added}/-${removed} lines). ${headline}"
  payload="$(jq -nc \
    --arg url "$url" --arg text "$body" --arg summary "$summary" \
    --argjson added "$added" --argjson removed "$removed" \
    --arg diff "$(printf '%s' "$d" | head -c 1200)" \
    '{type:"page_change",url:$url,changed:true,added:$added,removed:$removed,summary:$summary,diff:$diff,text:$text}')"

  if [ "$DRY_RUN" = "1" ]; then
    log "Change detected (+${added}/-${removed}) — would deliver via '${ALERT_SINK}':"
    printf 'ALERT: %s\n' "$body"
    printf 'PAYLOAD: %s\n' "$payload"
    return 0
  fi

  log "Change detected (+${added}/-${removed}). Delivering via '${ALERT_SINK}' ..."
  deliver "$body" "$payload"
  return 0
}

# --- DRY_RUN: diff the fixtures ----------------------------------------------
if [ "$DRY_RUN" = "1" ]; then
  compare_and_alert "$WATCH_URL" "$(cat "$EXAMPLE_BEFORE")" "$(cat "$EXAMPLE_AFTER")" || true
  log "Done (dry run)."
  exit 0
fi

# --- Live: fetch, compare to the last snapshot, alert ------------------------
mkdir -p "$STATE_DIR"
SNAP_FILE="$STATE_DIR/$(printf '%s' "$WATCH_URL" | cksum | cut -d' ' -f1).md"

log "Checking $WATCH_URL ..."
new_raw="$(fetch_markdown "$WATCH_URL" || true)"
if [ -z "${new_raw//[[:space:]]/}" ]; then
  die "Empty response from scrape endpoint — leaving the last snapshot untouched."
fi

if [ ! -f "$SNAP_FILE" ]; then
  printf '%s' "$new_raw" > "$SNAP_FILE"
  log "Baseline saved for $WATCH_URL. No alert on first run."
  exit 0
fi

if compare_and_alert "$WATCH_URL" "$(cat "$SNAP_FILE")" "$new_raw"; then
  printf '%s' "$new_raw" > "$SNAP_FILE"   # advance the baseline after alerting
else
  # No meaningful change; refresh the snapshot so ignored churn doesn't pile up.
  printf '%s' "$new_raw" > "$SNAP_FILE"
fi
