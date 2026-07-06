# 🔻 Depeg Watchdog

Watch stablecoins and get alerted the moment one drifts off its peg.

For each asset you list, Depeg Watchdog pulls the current price from
[pay.sh](https://pay.sh) market data (paid per request in USDC, no API keys) and
alerts when the price is more than `THRESHOLD_PCT` away from the peg. It tracks
each coin's pegged/depegged state, so you get one alert when a coin breaks its peg
and one when it recovers, not a page on every single run. Designed for a cron.

Deliver via Telegram, a webhook, a websocket, or stdout.

📎 **X thread:** _(link coming soon)_

---

## What it does

1. For each symbol in `ASSETS`, fetches the USD price via pay.sh market data.
2. Computes the drift from `PEG` (default `1.00`) as a percentage.
3. If the drift exceeds `THRESHOLD_PCT`, the coin is "depegged".
4. Alerts only on a state change: once when it breaks peg, once when it recovers.

The state tracking is what makes it cron-friendly. A naive threshold check would
re-alert every run for as long as a coin stays off peg; this fires once per event.

## Try it instantly (no setup)

```bash
DRY_RUN=1 ./depeg-watchdog.sh
```

Checks the canned [`example-prices.json`](./example-prices.json) against a 0.5%
band and prints the alerts it would send (DAI and FRAX are off peg in the fixture;
USDC and USDT are within band). No `pay`, no network, no state written. Tune it:

```bash
DRY_RUN=1 THRESHOLD_PCT=2 ./depeg-watchdog.sh   # only FRAX (2.48% off) qualifies
DRY_RUN=1 THRESHOLD_PCT=3 ./depeg-watchdog.sh   # nothing qualifies, all quiet
```

## Delivery

Set `ALERT_SINK` (default `telegram`). Non-telegram sinks emit a JSON payload:

```json
{"type":"depeg_alert","asset":"DAI","price":"0.9931","peg":"1.00",
 "deviation_pct":"0.69","direction":"below","text":"⚠️ Depeg alert: DAI …"}
```

| `ALERT_SINK` | Needs | Delivery |
|---|---|---|
| `telegram` _(default)_ | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | Message to a chat |
| `webhook` | `WEBHOOK_URL` | `POST` the JSON payload to your URL |
| `websocket` | `WS_URL` + [`websocat`](https://github.com/vi/websocat) | Push the JSON payload to a WS endpoint |
| `stdout` | — | Print the JSON payload (pipe into your agent, `jq`, anything) |

## End-to-end example

```bash
./example.sh          # demo mode (checks the fixture)
LIVE=1 ./example.sh   # real: needs a funded pay CLI + a valid .env
```

## Prerequisites

- **pay CLI**, installed and funded — <https://pay.sh>.
- **jq**, **bc**, **curl** — JSON, the percentage math, and HTTP.
- **Your chosen sink** — a Telegram bot, a webhook URL, or `websocat`. `stdout`
  needs nothing.

## Environment variables

| Variable | Description |
|---|---|
| `ASSETS` | Stablecoin symbols to watch, comma or space separated |
| `THRESHOLD_PCT` | % drift from peg that triggers an alert (default `0.5`) |
| `ALERT_SINK` | `telegram` (default), `webhook`, `websocket`, or `stdout` |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` | For the `telegram` sink |
| `WEBHOOK_URL` | For the `webhook` sink |
| `WS_URL` | For the `websocket` sink |
| `PEG` | _(optional)_ Peg value to measure against, default `1.00` |
| `PAYSH_MARKET_URL` | _(optional)_ Override the pay.sh market-data endpoint |
| `STATE_DIR` | _(optional)_ Peg-state store, default `~/.depeg-watchdog` |

## Set up the cron

Check every 5 minutes:

```cron
*/5 * * * * . $HOME/depeg-watchdog.env && /path/to/depeg-watchdog/depeg-watchdog.sh >> $HOME/depeg-watchdog.log 2>&1
```

> **Cost note:** one price request per asset per run. Watching 3 coins every 5
> minutes is ~864 requests/day. Tune the interval, asset list, and pay.sh balance.
