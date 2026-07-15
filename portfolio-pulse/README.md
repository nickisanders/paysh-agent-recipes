# 💼 Portfolio Pulse

A daily snapshot of a wallet's holdings and value.

Portfolio Pulse pulls a wallet's token holdings and USD values from
[pay.sh](https://pay.sh) (paid per request in USDC, no API keys) and prints a
clean snapshot: total value, 24h change, top holdings with their share, and the
biggest mover. Not an alert, a digest. Run it on a daily cron and wake up to where
your bags stand.

Deliver via stdout (default), Telegram, a webhook, or a websocket.

📎 **X thread:** _(link coming soon)_

---

## What it does

1. Fetches `WALLET`'s holdings and values via pay.sh.
2. Ranks them by value and computes each one's share of the total.
3. Prints the total, the 24h change, the top holdings, and the biggest mover.

Where Whale Watcher tracks a wallet's transactions, Portfolio Pulse tracks its
composition: what you hold and what it's worth, summarized on a schedule.

## Try it instantly (no setup)

```bash
DRY_RUN=1 ./portfolio-pulse.sh
```

Builds the snapshot from the canned
[`example-portfolio.json`](./example-portfolio.json):

```
💼 Portfolio Pulse: 0xd8dA…6045 on ethereum
$124,530 (+3.2% 24h)

Top holdings:
  • ETH   $82,100  (66%)
  • USDC  $30,000  (24%)
  • LINK  $12,430  (10%)
Biggest mover: LINK +8.1%
```

No `pay`, no network. Show fewer lines with `TOP=3`.

## How to run

```bash
WALLET=0xYOURWALLET ./portfolio-pulse.sh
# or pass it as an argument:
./portfolio-pulse.sh 0xYOURWALLET
```

Non-stdout sinks emit a JSON payload with the full holdings, for agents:

```json
{"type":"portfolio_pulse","wallet":"0x…","chain":"ethereum","total_usd":124530,
 "change_24h_pct":3.2,"holdings":[{"symbol":"ETH","value_usd":82100,…}],"text":"💼 …"}
```

## End-to-end example

```bash
./example.sh          # demo mode (builds from the fixture)
LIVE=1 ./example.sh   # real: needs a funded pay CLI + a valid .env
```

## Prerequisites

- **pay CLI**, installed and funded — <https://pay.sh>.
- **jq**, **awk**, **curl** — JSON, the formatting math, and HTTP.

## Environment variables

| Variable | Description |
|---|---|
| `WALLET` | Wallet address to snapshot (or pass as the first argument) |
| `CHAIN` | _(optional)_ Network, default `ethereum` |
| `TOP` | _(optional)_ How many holdings to list, default `5` |
| `ALERT_SINK` | `stdout` (default), `telegram`, `webhook`, or `websocket` |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` | For the `telegram` sink |
| `WEBHOOK_URL` | For the `webhook` sink |
| `WS_URL` | For the `websocket` sink |
| `PAYSH_WALLET_URL` | _(optional)_ Override the pay.sh wallet-holdings endpoint |

## Set up the cron

Every morning at 8am:

```cron
0 8 * * * . $HOME/portfolio-pulse.env && /path/to/portfolio-pulse/portfolio-pulse.sh >> $HOME/portfolio-pulse.log 2>&1
```

> **Not financial advice:** a snapshot of holdings and values, nothing more.

> **Cost note:** one wallet request per run. A daily snapshot is ~30 paid
> requests a month. Tune the schedule and your pay.sh balance.
