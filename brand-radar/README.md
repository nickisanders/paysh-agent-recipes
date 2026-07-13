# 📣 Brand Radar

![Brand Radar demo](demo.gif)

Track what people are saying about you, and get pinged on every new mention.

Brand Radar searches social data (Reddit and more) through [pay.sh](https://pay.sh)
(paid per request in USDC, no API keys) for a keyword, remembers which posts it has
already seen, and alerts you on new mentions. With `SUMMARIZE=1` it runs the new
mentions through `pay claude` for a one-line sentiment read. Watch your brand, a
product, a competitor, or a token. Runs on a cron.

Deliver via Telegram, a webhook, a websocket, or stdout.

📎 **X thread:** _(link coming soon)_

---

## What it does

1. Searches `SOURCE` (default Reddit) for `QUERY` through pay.sh.
2. Compares the results to the post ids it saw last run.
3. Alerts on anything new, listing the top mentions with source and score.
4. With `SUMMARIZE=1`, adds a plain-English sentiment read of the new batch.

The first run saves a baseline and stays quiet, so you don't get paged for the
entire back catalogue. After that you only hear about genuinely new posts.

## Try it instantly (no setup)

```bash
DRY_RUN=1 ./brand-radar.sh
```

Treats the canned [`example-mentions.json`](./example-mentions.json) as new and
prints the alert. No `pay`, no network, no state written. Add the sentiment read:

```bash
DRY_RUN=1 SUMMARIZE=1 ./brand-radar.sh
```

Sample:

```
📣 3 new mention(s) of "pay.sh":
  - Has anyone tried pay.sh for agent payments? (r/AI_Agents, 42↑)
  - pay.sh vs traditional API keys, worth it? (r/solana, 18↑)
  - Shipped my first x402 agent this weekend with pay.sh (r/ethdev, 7↑)

Mostly positive. Builders are trying pay.sh for agent micropayments and finding
the keyless model smooth, with a couple of questions about the tradeoffs.
```

## Delivery

Set `ALERT_SINK` (default `telegram`). Non-telegram sinks emit a JSON payload:

```json
{"type":"brand_mentions","query":"pay.sh","count":3,"summary":"…",
 "mentions":[{"id":"…","title":"…","url":"…","source":"r/…","score":42}],"text":"📣 …"}
```

| `ALERT_SINK` | Needs | Delivery |
|---|---|---|
| `telegram` _(default)_ | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | Message to a chat |
| `webhook` | `WEBHOOK_URL` | `POST` the JSON payload to your URL |
| `websocket` | `WS_URL` + [`websocat`](https://github.com/vi/websocat) | Push the JSON payload to a WS endpoint |
| `stdout` | — | Print the JSON payload (pipe into your agent, `jq`, anything) |

## End-to-end example

```bash
./example.sh          # demo mode (uses the fixture)
LIVE=1 ./example.sh   # real: needs a funded pay CLI + a valid .env
```

## Prerequisites

- **pay CLI**, installed and funded — <https://pay.sh>.
- **jq**, **curl** — JSON handling and HTTP.

## Environment variables

| Variable | Description |
|---|---|
| `QUERY` | Keyword, brand, or token to track |
| `SOURCE` | Where to search (default `reddit`) |
| `SUMMARIZE` | `1` to add a pay claude sentiment read (default `0`) |
| `MAX_LIST` | How many new mentions to list per alert (default `5`) |
| `ALERT_SINK` | `telegram` (default), `webhook`, `websocket`, or `stdout` |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` | For the `telegram` sink |
| `WEBHOOK_URL` | For the `webhook` sink |
| `WS_URL` | For the `websocket` sink |
| `PAYSH_SOCIAL_URL` | _(optional)_ Override the pay.sh social endpoint |
| `STATE_DIR` | _(optional)_ Seen-id store, default `~/.brand-radar` |

## Set up the cron

Check every 15 minutes:

```cron
*/15 * * * * . $HOME/brand-radar.env && /path/to/brand-radar/brand-radar.sh >> $HOME/brand-radar.log 2>&1
```

> **Cost note:** one search request per run, plus one `pay claude` call per run
> with new mentions when `SUMMARIZE=1`. Tune the interval and your pay.sh balance.
