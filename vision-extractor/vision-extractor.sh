#!/usr/bin/env bash
#
# vision-extractor.sh — An image in, typed JSON out.
#
# Sends an image to Gemini via a paid pay.sh call (multimodal, fronted by pay.sh,
# no GCP account) and pulls out the fields you name as clean JSON: a receipt's
# total, an invoice's line items, a screenshot's numbers, a label's ingredients.
# Paid per image in USDC on Solana, no API keys.
#
# The multimodal sibling of Web Extractor: name the fields, get typed JSON back,
# ready for an agent to act on.
#
# Deliver via stdout (default), Telegram, a webhook, or a websocket.
#
# Try it with zero setup:  DRY_RUN=1 ./vision-extractor.sh
#   Extracts from the canned example-vision.json. No pay, no network, no image needed.
#
set -euo pipefail

# --- Config ------------------------------------------------------------------
# Required (live mode):
#   IMAGE               path to a local image file (or pass as the first argument)
#
# Optional:
#   FIELDS              comma-separated fields to pull (empty = return everything)
#   ALERT_SINK          stdout (default) | telegram | webhook | websocket
#   PAYSH_VISION_URL    the pay.sh vision endpoint (sane default)
#   DRY_RUN=1           demo: read EXAMPLE_VISION, print instead of deliver
#   EXAMPLE_VISION      canned model response for DRY_RUN

IMAGE="${IMAGE:-${1:-}}"
FIELDS="${FIELDS:-}"
ALERT_SINK="${ALERT_SINK:-stdout}"
PAYSH_VISION_URL="${PAYSH_VISION_URL:-https://gemini.pay.sh/vision}"
DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_VISION="${EXAMPLE_VISION:-$SCRIPT_DIR/example-vision.json}"

# --- Helpers -----------------------------------------------------------------
log()  { printf '[vision-extractor] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed or not on PATH."; }
require_env() { [ -n "${!1:-}" ] || die "Missing required env var: $1"; }

# --- Preflight ---------------------------------------------------------------
require_cmd jq

if [ "$DRY_RUN" = "1" ]; then
  [ -f "$EXAMPLE_VISION" ] || die "Fixture not found: $EXAMPLE_VISION"
  # A sensible default field set so the demo shows projection at work.
  FIELDS="${FIELDS:-merchant,date,total,currency,items}"
  SOURCE_LABEL="example-vision.json"
  log "DRY RUN: extracting from example-vision.json. Printing instead of delivering."
else
  require_cmd curl
  require_cmd base64
  [ -n "$IMAGE" ]   || die "Set IMAGE to a local image file (or pass it as the first argument)."
  [ -f "$IMAGE" ]   || die "Image not found: $IMAGE"
  require_env PAYSH_VISION_URL
  SOURCE_LABEL="$(basename "$IMAGE")"
  case "$ALERT_SINK" in
    stdout)    : ;;
    telegram)  require_env TELEGRAM_BOT_TOKEN; require_env TELEGRAM_CHAT_ID ;;
    webhook)   require_env WEBHOOK_URL ;;
    websocket) require_env WS_URL; require_cmd websocat ;;
    *)         die "Unknown ALERT_SINK '$ALERT_SINK' (use: stdout|telegram|webhook|websocket)" ;;
  esac
fi

# --- The paid call -----------------------------------------------------------
# `pay` fronts the HTTP call and settles the x402 micropayment. We hand Gemini the
# base64 image plus an instruction to return JSON for the requested fields. In
# DRY_RUN we read the fixture. Adjust the field mapping if your route differs.
fetch_extraction() {
  if [ "$DRY_RUN" = "1" ]; then
    jq -c '.result // .data // .' "$EXAMPLE_VISION"
  else
    local b64 want prompt
    b64="$(base64 < "$IMAGE" | tr -d '\n')"
    if [ -n "$FIELDS" ]; then
      want="with exactly these keys: ${FIELDS}"
    else
      want="with all the fields you can read from it"
    fi
    prompt="Extract the contents of this image as a single JSON object ${want}. Return only JSON, no prose, no code fences."
    pay curl -s -X POST "$PAYSH_VISION_URL" -H 'content-type: application/json' \
      --data "$(jq -nc --arg img "$b64" --arg p "$prompt" '{image:$img,prompt:$p}')" 2>/dev/null \
      | jq -c '(.result // .data // .)' 2>/dev/null || echo '{}'
  fi
}

# --- Project to requested fields ---------------------------------------------
# With FIELDS set, keep only those keys (missing -> null). Empty FIELDS = as-is.
project() {
  local raw="$1"
  if [ -z "$FIELDS" ]; then
    printf '%s' "$raw" | jq '.'
    return
  fi
  printf '%s' "$raw" | jq --arg fields "$FIELDS" '
    . as $o
    | ($fields | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)))
    | reduce .[] as $k ({}; . + {($k): ($o[$k] // null)})'
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

# --- Run ---------------------------------------------------------------------
log "Reading ${SOURCE_LABEL} ..."
raw="$(fetch_extraction)"
[ -n "${raw//[[:space:]]/}" ] && [ "$raw" != "{}" ] || die "No data extracted from ${SOURCE_LABEL}."

data="$(project "$raw")"

body="👁️ Vision Extract: ${SOURCE_LABEL}
$(printf '%s' "$data" | jq '.')"

payload="$(jq -nc --arg source "$SOURCE_LABEL" --arg text "$body" \
  --argjson data "$data" \
  '{type:"vision_extract",source:$source,data:$data,text:$text}')"

if [ "$DRY_RUN" = "1" ]; then
  printf '%s\n' "$body"
  log "Done (dry run)."
  exit 0
fi

deliver "$body" "$payload"
log "Done."
