#!/usr/bin/env bash
#
# example.sh — Show Approval Gate auto-approving a small action and gating a big
# one (approved, then denied).
#
# Runs in DRY_RUN (the human answer is simulated with APPROVE_ANSWER). No pay.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DRY_RUN=1 APPROVE_OVER_USD=25

echo "==> 1) A small \$5 action, under the \$25 limit. Runs on its own."
echo
AMOUNT_USD=5 "$SCRIPT_DIR/approval-gate.sh" pay curl -s https://market.pay.sh/price || true

echo
echo "==> 2) A \$200 action needs approval. Here the human says yes."
echo
AMOUNT_USD=200 APPROVE_ANSWER=y "$SCRIPT_DIR/approval-gate.sh" pay curl -s -X POST https://market.pay.sh/transfer || true

echo
echo "==> 3) Same \$200 action, but the human says no."
echo
AMOUNT_USD=200 APPROVE_ANSWER=n "$SCRIPT_DIR/approval-gate.sh" pay curl -s -X POST https://market.pay.sh/transfer || true

echo
echo "==> Done. In live use, put 'approval-gate.sh' in front of a paid action and tag its AMOUNT_USD."
