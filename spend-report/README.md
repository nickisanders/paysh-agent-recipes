# 🧾 Spend Report

![Spend Report demo](demo.gif)

See exactly what your agents spent.

The other guardrails control agent spending: [Spend Guard](../spend-guard) caps how
*much*, [Approval Gate](../approval-gate) adds a *human*, [Rate Limiter](../rate-limiter)
caps how *often*. Spend Report is the visibility half. It reads the ledgers Spend
Guard writes and rolls them up into a plain report: total spent, by endpoint, by
day. Paid per request in USDC means every call is a line item, so the accounting
is exact, not estimated.

Deliver via stdout (default), Telegram, a webhook, or a websocket, e.g. a daily
spend digest pushed to a channel.

📎 **X thread:** _(link coming soon)_

---

## What it does

1. Reads every `<date>.ledger` file in your Spend Guard state dir.
2. Sums the amounts and groups them two ways: by endpoint and by day.
3. Prints a report, or ships the same numbers as JSON to a sink.

Each ledger line is one paid call (`amount host time`), so there is no sampling
or estimating: the total is the sum of what actually settled.

## Try it instantly (no setup)

```bash
DRY_RUN=1 ./spend-report.sh
```

Rolls up the canned [`example-ledgers/`](./example-ledgers):

```
🧾 Spend Report
$0.16 across 20 calls over 3 day(s)
Avg $0.05/day

By endpoint:
  • search.pay.sh    $0.08  (4 calls)
  • audit.pay.sh     $0.04  (9 calls)
  • market.pay.sh    $0.03  (5 calls)
  • wallet.pay.sh    $0.01  (2 calls)

By day:
  • 2026-07-22  $0.04  (6 calls)
  • 2026-07-23  $0.07  (7 calls)
  • 2026-07-24  $0.05  (7 calls)
```

No `pay`, nothing spent.

## How to run

Point it at your real Spend Guard state dir (the two recipes share the default):

```bash
GUARD_STATE_DIR=~/.spend-guard ./spend-report.sh
```

Non-stdout sinks emit a JSON payload, so an agent or dashboard can chart it:

```json
{"type":"spend_report","total_usd":0.16,"total_calls":20,"days":3,
 "by_endpoint":[{"host":"search.pay.sh","usd":0.08,"calls":4}, …],
 "by_day":[{"day":"2026-07-22","usd":0.04,"calls":6}, …],"text":"🧾 …"}
```

## End-to-end example

```bash
./example.sh          # demo mode (rolls up the fixture ledgers)
LIVE=1 ./example.sh   # real: reads your actual Spend Guard state dir
```

## Prerequisites

- **jq**, **awk** — JSON handling and aggregation.
- A state dir written by [Spend Guard](../spend-guard). No ledgers yet just means
  nothing has been spent.

## Environment variables

| Variable | Description |
|---|---|
| `GUARD_STATE_DIR` | Where Spend Guard writes its ledgers (default `~/.spend-guard`) |
| `ALERT_SINK` | `stdout` (default), `telegram`, `webhook`, or `websocket` |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` | For the `telegram` sink |
| `WEBHOOK_URL` | For the `webhook` sink |
| `WS_URL` | For the `websocket` sink |

> **The full set:** control *plus* visibility. Cap how much (Spend Guard), add a
> human (Approval Gate), cap how often (Rate Limiter), then see where it all went
> (Spend Report). Cron this daily and the report lands in your channel each morning.
