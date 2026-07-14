# ⛽ Gas Ticker

Get pinged when gas is cheap enough to transact.

Gas Ticker reads the current gas price from [pay.sh](https://pay.sh)'s JSON-RPC
(paid per request in USDC, no API keys) and alerts you when it drops below your
target, then again when it climbs back. It tracks a cheap/normal state, so you get
one alert per swing, not a page on every run. Designed for a cron.

Deliver via Telegram, a webhook, a websocket, or stdout.

📎 **X thread:** _(link coming soon)_

---

## What it does

1. Calls `eth_gasPrice` through pay.sh and converts wei to gwei.
2. Compares it to your `GWEI_THRESHOLD`.
3. Alerts when gas crosses below the target ("cheap"), and again when it crosses
   back above ("normal"). Nothing in between.

The state tracking is what makes it cron-friendly: a plain threshold check would
re-alert every run for as long as gas stays low. This fires once per crossing.

## Try it instantly (no setup)

```bash
DRY_RUN=1 ./gas-ticker.sh
```

Reads the canned [`example-gas.json`](./example-gas.json) (12 gwei) against a
20 gwei target and prints the alert. No `pay`, no network, no state written. Tune
the target:

```bash
DRY_RUN=1 GWEI_THRESHOLD=10 ./gas-ticker.sh   # 12 gwei is above 10, stays quiet
```

## Delivery

Set `ALERT_SINK` (default `telegram`). Non-telegram sinks emit a JSON payload:

```json
{"type":"gas_cheap","chain":"ethereum","gwei":"12.00","threshold":"20",
 "status":"cheap","text":"⛽ Gas is cheap: 12.00 gwei …"}
```

| `ALERT_SINK` | Needs | Delivery |
|---|---|---|
| `telegram` _(default)_ | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | Message to a chat |
| `webhook` | `WEBHOOK_URL` | `POST` the JSON payload to your URL |
| `websocket` | `WS_URL` + [`websocat`](https://github.com/vi/websocat) | Push the JSON payload to a WS endpoint |
| `stdout` | — | Print the JSON payload (pipe into your agent, `jq`, anything) |

## End-to-end example

```bash
./example.sh          # demo mode (reads the fixture)
LIVE=1 ./example.sh   # real: needs a funded pay CLI + a valid .env
```

## Prerequisites

- **pay CLI**, installed and funded — <https://pay.sh>.
- **jq**, **awk**, **curl** — JSON, the gwei math, and HTTP.
- **Your chosen sink** — a Telegram bot, a webhook URL, or `websocat`. `stdout`
  needs nothing.

## Environment variables

| Variable | Description |
|---|---|
| `GWEI_THRESHOLD` | Alert when gas drops below this many gwei |
| `CHAIN` | _(optional)_ Display label for the network, default `ethereum` |
| `ALERT_SINK` | `telegram` (default), `webhook`, `websocket`, or `stdout` |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` | For the `telegram` sink |
| `WEBHOOK_URL` | For the `webhook` sink |
| `WS_URL` | For the `websocket` sink |
| `PAYSH_RPC_URL` | _(optional)_ Override the pay.sh RPC endpoint (e.g. another chain) |
| `STATE_DIR` | _(optional)_ State store, default `~/.gas-ticker` |

## Set up the cron

Check every 2 minutes:

```cron
*/2 * * * * . $HOME/gas-ticker.env && /path/to/gas-ticker/gas-ticker.sh >> $HOME/gas-ticker.log 2>&1
```

> **Cost note:** one `eth_gasPrice` request per run. Every 2 minutes is ~720
> requests/day. Tune the interval and your pay.sh balance.
