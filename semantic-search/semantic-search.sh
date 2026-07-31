#!/usr/bin/env bash
#
# semantic-search.sh — Search a corpus by meaning, not keywords.
#
# Embeds your query and each document via a paid pay.sh call (Vertex AI text
# embeddings, fronted by pay.sh, no GCP account), then ranks the documents by
# cosine similarity and returns the closest matches. Paid per embedding in USDC
# on Solana, no API keys.
#
# The building block behind agent memory, FAQ bots, and RAG: give an agent a pile
# of text and it can find the relevant bits for any question, even when the words
# don't overlap.
#
# Deliver via stdout (default), Telegram, a webhook, or a websocket.
#
# Try it with zero setup:  DRY_RUN=1 ./semantic-search.sh
#   Ranks the canned example-corpus.json (embeddings precomputed). No pay, no network.
#
set -euo pipefail

# --- Config ------------------------------------------------------------------
# Required (live mode):
#   QUERY               the search query (or pass as the first argument)
#   CORPUS              path to a text file, one document per line
#
# Optional:
#   TOP_K               how many matches to return (default 3)
#   ALERT_SINK          stdout (default) | telegram | webhook | websocket
#   PAYSH_EMBED_URL     the pay.sh embeddings endpoint (sane default)
#   DRY_RUN=1           demo: read EXAMPLE_CORPUS (precomputed vectors), print
#   EXAMPLE_CORPUS      canned corpus for DRY_RUN

QUERY="${QUERY:-${1:-}}"
CORPUS="${CORPUS:-}"
TOP_K="${TOP_K:-3}"
ALERT_SINK="${ALERT_SINK:-stdout}"
PAYSH_EMBED_URL="${PAYSH_EMBED_URL:-https://vertex.pay.sh/embeddings}"
DRY_RUN="${DRY_RUN:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_CORPUS="${EXAMPLE_CORPUS:-$SCRIPT_DIR/example-corpus.json}"

# --- Helpers -----------------------------------------------------------------
log()  { printf '[semantic-search] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed or not on PATH."; }
require_env() { [ -n "${!1:-}" ] || die "Missing required env var: $1"; }

# --- Preflight ---------------------------------------------------------------
require_cmd jq
require_cmd awk

if [ "$DRY_RUN" = "1" ]; then
  [ -f "$EXAMPLE_CORPUS" ] || die "Fixture not found: $EXAMPLE_CORPUS"
  QUERY="${QUERY:-$(jq -r '.query // "your query"' "$EXAMPLE_CORPUS")}"
  log "DRY RUN: ranking example-corpus.json (embeddings precomputed). Printing instead of delivering."
else
  require_cmd curl
  [ -n "$QUERY" ]  || die "Set QUERY (or pass the query as the first argument)."
  [ -n "$CORPUS" ] || die "Set CORPUS to a text file (one document per line)."
  [ -f "$CORPUS" ] || die "Corpus file not found: $CORPUS"
  require_env PAYSH_EMBED_URL
  case "$ALERT_SINK" in
    stdout)    : ;;
    telegram)  require_env TELEGRAM_BOT_TOKEN; require_env TELEGRAM_CHAT_ID ;;
    webhook)   require_env WEBHOOK_URL ;;
    websocket) require_env WS_URL; require_cmd websocat ;;
    *)         die "Unknown ALERT_SINK '$ALERT_SINK' (use: stdout|telegram|webhook|websocket)" ;;
  esac
fi

# --- Embedding (the paid call) -----------------------------------------------
# `pay` fronts each HTTP call and settles the x402 micropayment. Returns the
# embedding vector as a JSON array. Adjust the field mapping if your route differs.
embed() {
  pay curl -s -G "$PAYSH_EMBED_URL" --data-urlencode "input=$1" 2>/dev/null \
    | jq -c '(.embedding // .data[0].embedding // .vector // [])' 2>/dev/null || echo '[]'
}

# --- Build the corpus (text + vector), one TSV line per doc ------------------
# "<comma-joined embedding>\t<text>", plus the query vector as a comma list.
if [ "$DRY_RUN" = "1" ]; then
  query_vec="$(jq -r '.query_embedding | @csv' "$EXAMPLE_CORPUS")"
  corpus_tsv="$(jq -r '.docs[] | [(.embedding | @csv), .text] | @tsv' "$EXAMPLE_CORPUS")"
else
  log "Embedding query and corpus via pay.sh ..."
  query_vec="$(embed "$QUERY" | jq -r '@csv')"
  [ -n "$query_vec" ] && [ "$query_vec" != '""' ] || die "Empty query embedding from pay.sh."
  corpus_tsv=""
  while IFS= read -r doc; do
    [ -n "${doc//[[:space:]]/}" ] || continue
    vec="$(embed "$doc" | jq -r '@csv')"
    [ -n "$vec" ] && [ "$vec" != '""' ] || { log "Skipping (no embedding): ${doc:0:40}..."; continue; }
    corpus_tsv="${corpus_tsv}${vec}"$'\t'"${doc}"$'\n'
  done < "$CORPUS"
  [ -n "$corpus_tsv" ] || die "Nothing embedded from the corpus."
fi

# --- Rank by cosine similarity -----------------------------------------------
ranked="$(
  printf '%s\n' "$corpus_tsv" | awk -F'\t' -v q="$query_vec" '
    BEGIN { n = split(q, qv, ","); qn = 0; for (i = 1; i <= n; i++) qn += qv[i]*qv[i]; qn = sqrt(qn) }
    NF >= 2 {
      m = split($1, dv, ","); dot = 0; dn = 0;
      for (i = 1; i <= m; i++) { dot += qv[i]*dv[i]; dn += dv[i]*dv[i] }
      dn = sqrt(dn);
      score = (qn > 0 && dn > 0) ? dot/(qn*dn) : 0;
      printf "%.4f\t%s\n", score, $2;
    }
  ' | sort -t$'\t' -k1 -rn | head -n "$TOP_K"
)"

# --- Assemble ----------------------------------------------------------------
body="🔎 Semantic Search: \"${QUERY}\"
Top matches:"
i=0
while IFS=$'\t' read -r score text; do
  [ -n "$text" ] || continue
  i=$((i+1))
  body="${body}
  ${i}. ($(printf '%.2f' "$score")) ${text}"
done <<< "$ranked"

matches_json="$(
  printf '%s\n' "$ranked" | jq -R -s '
    split("\n") | map(select(length > 0) | split("\t"))
    | map({score: (.[0] | tonumber), text: .[1]})'
)"
payload="$(jq -nc --arg query "$QUERY" --arg text "$body" --argjson matches "$matches_json" \
  '{type:"semantic_search",query:$query,matches:$matches,text:$text}')"

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
