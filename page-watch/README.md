# 📄 Page Watch

Watch any web page and get pinged the moment it changes.

Page Watch fetches a URL as clean markdown through [pay.sh](https://pay.sh)'s
web-scrape API (paid per request in USDC, no API keys), diffs it against the last
snapshot, and alerts you when the page changes. Point it at a competitor's pricing
page, a job board, a docs page, a changelog, or a terms-of-service page. Runs on a
cron. The first run just saves a baseline, so there are no false alerts, and an
unchanged page stays silent.

Deliver alerts via Telegram, a webhook, a websocket, or stdout. Every non-telegram
sink emits a JSON payload, so your agents can act on a change directly.

📎 **X thread:** _(link coming soon)_

---

## What it does

1. Fetches `WATCH_URL` as markdown via pay.sh (one paid request per check).
2. Compares it to the snapshot from the last run.
3. On a change, delivers an alert with a line count and a short diff excerpt, then
   advances the snapshot. First run saves a baseline and stays quiet.

Markdown (not raw HTML) is the unit of comparison on purpose: it ignores markup
churn, tracking params, and re-ordered attributes, so you alert on content changes,
not cosmetic ones. Use `IGNORE_PATTERN` to skip volatile lines (timestamps, nonces).

## Try it instantly (no setup)

```bash
DRY_RUN=1 ./page-watch.sh
```

Diffs the two canned fixtures ([`example-page-before.md`](./example-page-before.md)
and [`example-page-after.md`](./example-page-after.md), a pricing page that bumped a
price and added a plan) and prints the alert it would send. No `pay`, no network, no
state written.

## Alert transports

Set `ALERT_SINK` (default `telegram`). Non-telegram sinks emit a JSON payload:

```json
{"type":"page_change","url":"https://acme.example/pricing","changed":true,
 "added":7,"removed":2,"diff":"…unified diff…","text":"📄 Page changed: …"}
```

| `ALERT_SINK` | Needs | Delivery |
|---|---|---|
| `telegram` _(default)_ | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | Human message to a chat |
| `webhook` | `WEBHOOK_URL` | `POST` the JSON payload to your URL |
| `websocket` | `WS_URL` + [`websocat`](https://github.com/vi/websocat) | Push the JSON payload to a WS endpoint |
| `stdout` | — | Print the JSON payload (pipe into your agent, `jq`, anything) |

```bash
# Feed an agent directly:
ALERT_SINK=stdout ./page-watch.sh | your-agent --on-change
```

## End-to-end example

[`example.sh`](./example.sh) sets the env, calls the watcher, receives the detected
change, and processes it (here, prints a summary):

```bash
./example.sh          # demo mode (diffs the fixtures)
LIVE=1 ./example.sh   # real: needs a funded pay CLI + a valid .env
```

## Prerequisites

- **pay CLI**, installed and funded — <https://pay.sh>.
- **jq**, **diff**, **curl** — JSON, diffing, and HTTP (`diff`/`curl` ship on macOS and Linux).
- **Your chosen sink** — a Telegram bot ([@BotFather](https://t.me/BotFather),
  [@userinfobot](https://t.me/userinfobot) for your chat id), a webhook URL, or
  [`websocat`](https://github.com/vi/websocat). `stdout` needs nothing.

## Environment variables

| Variable | Description |
|---|---|
| `WATCH_URL` | The page to monitor |
| `ALERT_SINK` | `telegram` (default), `webhook`, `websocket`, or `stdout` |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` | For the `telegram` sink |
| `WEBHOOK_URL` | For the `webhook` sink |
| `WS_URL` | For the `websocket` sink |
| `IGNORE_PATTERN` | _(optional)_ Extended-regex of lines to ignore before diffing |
| `PAYSH_SCRAPE_URL` | _(optional)_ Override the pay.sh markdown-scrape endpoint |
| `STATE_DIR` | _(optional)_ Snapshot store, default `~/.page-watch` |

## How to run

```bash
export WATCH_URL="https://example.com/pricing"
export TELEGRAM_BOT_TOKEN="..."; export TELEGRAM_CHAT_ID="..."
./page-watch.sh
```

## Set up the cron

Check every 30 minutes. Put your `export`s in an env file so cron has them:

```cron
*/30 * * * * . $HOME/page-watch.env && /path/to/page-watch/page-watch.sh >> $HOME/page-watch.log 2>&1
```

Snapshots live in `~/.page-watch/`, one per URL, so you can watch several pages from
the same cron by pointing separate jobs at different `WATCH_URL`s.

> **Cost note:** one `pay` scrape request per check (a fraction of a cent). A `*/30`
> schedule is ~48 requests/day per page — tune the interval and your pay.sh balance.
