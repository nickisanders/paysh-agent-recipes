#!/usr/bin/env bash
#
# approval-gate.sh — Human in the loop for an agent's big spends.
#
# Wrap an action that moves money. Below your limit the agent proceeds on its own.
# At or above it, the action pauses and asks a human to approve before it runs. A
# "no" (or a timeout) blocks it. Auto for the small stuff, a yes/no for anything
# that matters.
#
# Spend Guard sets hard caps the agent can't cross. Approval Gate is the softer
# layer: things it can do, but only with your say-so.
#
# Use it in front of a paid action, tagging its USD value:
#   AMOUNT_USD=200 approval-gate.sh pay curl -s -X POST https://.../transfer ...
#
# Try it with zero setup:  DRY_RUN=1 ./example.sh
#   Shows a small action auto-approve, and a big one approved then denied. No pay.
#
set -euo pipefail

# --- Policy (env) ------------------------------------------------------------
#   AMOUNT_USD           the USD value of this action (required)
#   APPROVE_OVER_USD     ask for approval at/above this (default: 25)
#   APPROVE_CHANNEL      terminal (default) | telegram
#   APPROVE_TIMEOUT      seconds to wait for a reply, then deny (default: 300)
#   TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID   for the telegram channel
#   DRY_RUN=1            simulate the decision with APPROVE_ANSWER, don't run
#   APPROVE_ANSWER       y or n, the simulated human answer in DRY_RUN

AMOUNT_USD="${AMOUNT_USD:-}"
APPROVE_OVER_USD="${APPROVE_OVER_USD:-25}"
APPROVE_CHANNEL="${APPROVE_CHANNEL:-terminal}"
APPROVE_TIMEOUT="${APPROVE_TIMEOUT:-300}"
DRY_RUN="${DRY_RUN:-0}"

log()  { printf '[approval-gate] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 2; }
usd()  { awk "BEGIN{printf \"\$%.2f\", $1}"; }

[ "$#" -gt 0 ] || die "Usage: AMOUNT_USD=<n> approval-gate.sh <command...>"
[ -n "$AMOUNT_USD" ] || die "Set AMOUNT_USD (the USD value of this action)."
command -v awk >/dev/null 2>&1 || die "'awk' is required."

# What is this action, for the human? Best-effort from the wrapped command.
target=""
for a in "$@"; do
  case "$a" in http://*|https://*) target="$(printf '%s' "$a" | sed -E 's#^https?://##; s#/.*$##')"; break;; esac
done
what="${target:-this action} for $(usd "$AMOUNT_USD")"

# --- Ask a human ------------------------------------------------------------
# Returns 0 for approve, 1 for deny.
ask_terminal() {
  local ans=""
  if { exec 3<>/dev/tty; } 2>/dev/null; then
    printf '[approval-gate] Approve %s? [y/N] ' "$what" >&3
    read -r ans <&3 || ans=""
    exec 3>&-
  else
    log "No terminal to ask on. Denying (use APPROVE_CHANNEL=telegram for headless agents)."
  fi
  case "$ans" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

ask_telegram() {
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] || { log "telegram channel needs TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID."; return 1; }
  command -v curl >/dev/null 2>&1 || { log "'curl' required for telegram."; return 1; }
  # The reply must come after this offset, so old messages don't count.
  local offset; offset="$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates?offset=-1" | jq -r '.result[-1].update_id // 0' 2>/dev/null || echo 0)"
  curl -sS -o /dev/null "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=Approve ${what}? Reply y to approve, n to deny." || true
  log "Waiting up to ${APPROVE_TIMEOUT}s for a reply..."
  local waited=0
  while [ "$waited" -lt "$APPROVE_TIMEOUT" ]; do
    local reply
    reply="$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates?offset=$((offset+1))&timeout=10" \
      | jq -r '[.result[].message.text] | last // empty' 2>/dev/null | tr 'A-Z' 'a-z' || true)"
    case "$reply" in y|yes) return 0 ;; n|no) return 1 ;; esac
    waited=$((waited + 10))
  done
  log "No reply in time."
  return 1
}

decide() {
  case "$APPROVE_CHANNEL" in
    terminal) ask_terminal ;;
    telegram) ask_telegram ;;
    *)        log "Unknown APPROVE_CHANNEL '$APPROVE_CHANNEL'."; return 1 ;;
  esac
}

# --- Gate --------------------------------------------------------------------
need_approval="$(awk "BEGIN{print ($AMOUNT_USD >= $APPROVE_OVER_USD) ? 1 : 0}")"

approved=0
if [ "$need_approval" = "0" ]; then
  log "$(usd "$AMOUNT_USD") is under the $(usd "$APPROVE_OVER_USD") limit. Auto-approved."
  approved=1
elif [ "$DRY_RUN" = "1" ]; then
  # Simulated human decision for the demo.
  [ "${APPROVE_ANSWER:-n}" = "y" ] && approved=1
  [ "$approved" = "1" ] && log "$(usd "$AMOUNT_USD") needs approval... approved." \
                        || log "$(usd "$AMOUNT_USD") needs approval... denied."
else
  log "$(usd "$AMOUNT_USD") needs approval (over the $(usd "$APPROVE_OVER_USD") limit)."
  if decide; then approved=1; log "Approved."; else log "Denied."; fi
fi

if [ "$approved" != "1" ]; then
  log "Blocked. The action did not run."
  exit 1
fi

# --- Run the approved action -------------------------------------------------
if [ "$DRY_RUN" = "1" ]; then
  log "Would run: $*  [dry run]"
  exit 0
fi
exec "$@"
