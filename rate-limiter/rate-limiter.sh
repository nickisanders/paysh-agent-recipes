#!/usr/bin/env bash
#
# rate-limiter.sh — A circuit breaker for an agent's paid calls.
#
# Wrap any `pay` call. It allows up to N calls per time window, then trips: extra
# calls are blocked, not run. A buggy loop or a runaway agent can burn a lot of
# fractions-of-a-cent in a hurry. This caps how often, the way Spend Guard caps
# how much and Approval Gate adds a human.
#
# Use it in front of pay:
#   rate-limiter.sh pay curl -s -G https://audit.pay.sh/contract ...
#
# Try it with zero setup:  DRY_RUN=1 ./example.sh
#   Fires a burst of calls and shows the breaker trip. No pay, nothing spent.
#
set -euo pipefail

# --- Policy (env) ------------------------------------------------------------
#   RATE_MAX          max calls allowed per window      (default: 30)
#   RATE_WINDOW_SEC   the window, in seconds            (default: 60)
#   RATE_STATE_DIR    where the call log lives          (default: ~/.rate-limiter)
#   RATE_KEY          bucket name, to limit groups separately (default: default)
#   DRY_RUN=1         don't run the call; just decide + record (for demos)

RATE_MAX="${RATE_MAX:-30}"
RATE_WINDOW_SEC="${RATE_WINDOW_SEC:-60}"
RATE_STATE_DIR="${RATE_STATE_DIR:-$HOME/.rate-limiter}"
RATE_KEY="${RATE_KEY:-default}"
DRY_RUN="${DRY_RUN:-0}"

log()  { printf '[rate-limiter] %s\n' "$*" >&2; }
die()  { log "ERROR: $*"; exit 2; }

[ "$#" -gt 0 ] || die "Usage: rate-limiter.sh <command...>  (e.g. rate-limiter.sh pay curl ...)"
command -v awk >/dev/null 2>&1 || die "'awk' is required."

# --- Count recent calls in the window ----------------------------------------
mkdir -p "$RATE_STATE_DIR"
LEDGER="$RATE_STATE_DIR/${RATE_KEY}.calls"
touch "$LEDGER"
now="$(date +%s)"
cutoff="$((now - RATE_WINDOW_SEC))"

# Prune to the window and count what remains.
tmp="$(mktemp)"
awk -v c="$cutoff" '$1 >= c' "$LEDGER" > "$tmp" 2>/dev/null || true
mv "$tmp" "$LEDGER"
count="$(awk 'END{print NR+0}' "$LEDGER")"

# --- Trip if the window is full ----------------------------------------------
if [ "$count" -ge "$RATE_MAX" ]; then
  log "TRIPPED: ${count}/${RATE_MAX} calls in the last ${RATE_WINDOW_SEC}s. Blocked, not run."
  exit 1
fi

# --- Allowed: record and run -------------------------------------------------
printf '%s\n' "$now" >> "$LEDGER"
log "call $((count + 1))/${RATE_MAX} in the last ${RATE_WINDOW_SEC}s. Allowed."

if [ "$DRY_RUN" = "1" ]; then
  log "Would run: $*  [dry run]"
  exit 0
fi
exec "$@"
