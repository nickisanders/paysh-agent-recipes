#!/usr/bin/env bash
#
# spend-guard.sh — A spending cap for agents that pay their own way.
#
# Wrap any `pay` call with this. It checks the call against your policy before a
# cent moves: a per-call cap, a daily cap, and an endpoint allowlist. It keeps a
# ledger of every approved spend, and it blocks (does not run the call) if the
# call would break a rule. The hard floor underneath all of this is still the
# oldest trick there is: fund the agent's wallet with only what you're willing to
# lose.
#
# Use it in front of pay:
#   spend-guard.sh pay curl -s -G https://audit.pay.sh/contract ...
# Or point a recipe at it:  PAY="spend-guard.sh pay"  then call "$PAY curl ..."
#
# Try it with zero setup:  DRY_RUN=1 ./example.sh
#   Simulates a run of calls and shows the daily cap block one. No pay, no spend.
#
set -euo pipefail

# --- Policy (env) ------------------------------------------------------------
#   GUARD_DAILY_CAP_USD   max total spend per day       (default: 1.00)
#   GUARD_CALL_MAX_USD    max spend on a single call    (default: 0.10)
#   GUARD_CALL_USD        assumed cost of this call     (default: 0.005)
#   GUARD_ALLOW_HOSTS     space/comma list of allowed hosts (default: all)
#   GUARD_STATE_DIR       where the ledger lives         (default: ~/.spend-guard)
#   DRY_RUN=1             don't run the call; simulate + record (for demos)

GUARD_DAILY_CAP_USD="${GUARD_DAILY_CAP_USD:-1.00}"
GUARD_CALL_MAX_USD="${GUARD_CALL_MAX_USD:-0.10}"
GUARD_CALL_USD="${GUARD_CALL_USD:-0.005}"
GUARD_ALLOW_HOSTS="${GUARD_ALLOW_HOSTS:-}"
GUARD_STATE_DIR="${GUARD_STATE_DIR:-$HOME/.spend-guard}"
DRY_RUN="${DRY_RUN:-0}"

log()  { printf '[spend-guard] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 2; }
usd()  { awk "BEGIN{printf \"\$%.4f\", $1}"; }

[ "$#" -gt 0 ] || die "Usage: spend-guard.sh <command...>  (e.g. spend-guard.sh pay curl ...)"
command -v awk >/dev/null 2>&1 || die "'awk' is required."

# --- Find the target host in the wrapped command -----------------------------
host=""
for a in "$@"; do
  case "$a" in
    http://*|https://*)
      host="$(printf '%s' "$a" | sed -E 's#^https?://##; s#/.*$##; s#:.*$##')"
      break ;;
  esac
done

# --- Ledger: today's spend so far --------------------------------------------
mkdir -p "$GUARD_STATE_DIR"
day="$(date +%F)"
LEDGER="$GUARD_STATE_DIR/${day}.ledger"
touch "$LEDGER"
today="$(awk '{s+=$1} END{printf "%.6f", s+0}' "$LEDGER")"

# --- Policy checks (block before spending) -----------------------------------
block() { log "BLOCKED: $1"; log "Not running the call. Nothing spent."; exit 1; }

# 1. Allowlist.
if [ -n "$GUARD_ALLOW_HOSTS" ] && [ -n "$host" ]; then
  ok=0
  for h in $(printf '%s' "$GUARD_ALLOW_HOSTS" | tr ',' ' '); do
    [ "$host" = "$h" ] && ok=1 && break
  done
  [ "$ok" = "1" ] || block "host '$host' is not in the allowlist ($GUARD_ALLOW_HOSTS)."
fi

# 2. Per-call cap.
if [ "$(awk "BEGIN{print ($GUARD_CALL_USD > $GUARD_CALL_MAX_USD) ? 1 : 0}")" = "1" ]; then
  block "this call ($(usd "$GUARD_CALL_USD")) exceeds the per-call cap ($(usd "$GUARD_CALL_MAX_USD"))."
fi

# 3. Daily cap.
projected="$(awk "BEGIN{printf \"%.6f\", $today + $GUARD_CALL_USD}")"
if [ "$(awk "BEGIN{print ($projected > $GUARD_DAILY_CAP_USD) ? 1 : 0}")" = "1" ]; then
  block "daily cap reached: today $(usd "$today") + $(usd "$GUARD_CALL_USD") would exceed $(usd "$GUARD_DAILY_CAP_USD")."
fi

# --- Approved: run the call, then record the spend ---------------------------
rc=0
if [ "$DRY_RUN" != "1" ]; then
  "$@"
  rc=$?
fi

# Record only on success. With x402 you pay for a response you got, so a failed
# call generally shouldn't be charged.
if [ "$rc" -eq 0 ]; then
  printf '%s %s %s\n' "$GUARD_CALL_USD" "${host:-local}" "$(date +%H:%M:%S)" >> "$LEDGER"
  new_today="$(awk '{s+=$1} END{printf "%.4f", s+0}' "$LEDGER")"
  verb="spent"; [ "$DRY_RUN" = "1" ] && verb="would spend"
  log "$verb $(usd "$GUARD_CALL_USD") on ${host:-local}. Today: \$${new_today} / $(usd "$GUARD_DAILY_CAP_USD")."
else
  log "call failed (exit $rc), not charged."
fi

exit "$rc"
