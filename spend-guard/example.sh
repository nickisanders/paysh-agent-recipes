#!/usr/bin/env bash
#
# example.sh — Show Spend Guard enforcing a daily cap and an allowlist.
#
# Runs in DRY_RUN (no pay, nothing spent). Each fresh temp ledger keeps the demo
# repeatable.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DRY_RUN=1 GUARD_CALL_USD=0.005

echo "==> 1) Daily cap of \$0.02, each call \$0.005. The 5th call gets blocked."
echo
D1="$(mktemp -d)"
for i in 1 2 3 4 5; do
  GUARD_STATE_DIR="$D1" GUARD_DAILY_CAP_USD=0.02 \
    "$SCRIPT_DIR/spend-guard.sh" pay curl -s https://audit.pay.sh/contract || true
done

echo
echo "==> 2) Allowlist: only audit.pay.sh is approved. A call anywhere else is blocked."
echo
D2="$(mktemp -d)"
GUARD_STATE_DIR="$D2" GUARD_ALLOW_HOSTS="audit.pay.sh" \
  "$SCRIPT_DIR/spend-guard.sh" pay curl -s https://audit.pay.sh/contract || true
GUARD_STATE_DIR="$D2" GUARD_ALLOW_HOSTS="audit.pay.sh" \
  "$SCRIPT_DIR/spend-guard.sh" pay curl -s https://sketchy.example.com/drain || true

echo
echo "==> Done. In live use, put 'spend-guard.sh' in front of your pay calls."
