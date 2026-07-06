# ☕ Morning Brief

A daily cited digest on the topics you follow, delivered to your inbox.

For each topic you list, Morning Brief runs a web search through [pay.sh](https://pay.sh)
(Perplexity Sonar style, with citations), assembles a brief, and sends it. It
chains two pay.sh APIs in one script: web search to gather, and the agent email
inbox to deliver. Paid per request in USDC, no API keys. Runs on a daily cron.

Deliver via email (default), stdout, a webhook, or Telegram.

📎 **X thread:** _(link coming soon)_

---

## What it does

1. Splits `TOPICS` into individual searches (one paid search per topic).
2. Runs each through pay.sh's web-search endpoint and normalizes the cited answer.
3. Assembles a dated brief with a section and sources per topic.
4. Delivers it via your chosen sink. The email sink sends from a pay.sh agent
   inbox, so there's no SMTP server or mail account to set up.

This is the recipe that shows the multi-API story: two different paid pay.sh
services (search, then email) composed in one small script, each paid per call.

## Try it instantly (no setup)

```bash
DRY_RUN=1 ./morning-brief.sh
```

Builds a brief from the canned [`example-search.json`](./example-search.json) and
prints it. No `pay`, no network, nothing sent.

## Delivery

Set `ALERT_SINK` (default `email`). The `webhook` sink emits a JSON payload:

```json
{"type":"morning_brief","title":"Morning Brief","date":"Monday, July 6, 2026",
 "sections":[{"topic":"…","answer":"…","sources":[{"title":"…","url":"…"}]}],
 "text":"Morning Brief: …"}
```

| `ALERT_SINK` | Needs | Delivery |
|---|---|---|
| `email` _(default)_ | `EMAIL_TO` | Sent from a pay.sh agent inbox |
| `stdout` | — | Prints the brief (pipe it anywhere) |
| `webhook` | `WEBHOOK_URL` | `POST` the JSON payload to your URL |
| `telegram` | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | Message to a chat |

## End-to-end example

```bash
./example.sh          # demo mode (builds from the fixture, prints)
LIVE=1 ./example.sh   # real: needs a funded pay CLI + a valid .env
```

## Prerequisites

- **pay CLI**, installed and funded — <https://pay.sh>.
- **jq**, **curl** — JSON handling and HTTP.
- For the email sink: an `EMAIL_TO` address (delivery is from a pay.sh agent inbox,
  nothing to configure on your end).

## Environment variables

| Variable | Description |
|---|---|
| `TOPICS` | Topics/questions to research, comma or newline separated |
| `ALERT_SINK` | `email` (default), `stdout`, `webhook`, or `telegram` |
| `EMAIL_TO` | Recipient for the `email` sink |
| `WEBHOOK_URL` | For the `webhook` sink |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` | For the `telegram` sink |
| `BRIEF_TITLE` | _(optional)_ Heading and email subject, default `Morning Brief` |
| `PAYSH_SEARCH_URL` | _(optional)_ Override the pay.sh web-search endpoint |
| `PAYSH_EMAIL_URL` | _(optional)_ Override the pay.sh agent-email endpoint |

## Set up the cron

Every morning at 7am. Put your `export`s in an env file so cron has them:

```cron
0 7 * * * . $HOME/morning-brief.env && /path/to/morning-brief/morning-brief.sh >> $HOME/morning-brief.log 2>&1
```

> **Cost note:** one paid search per topic per run, plus one send. A 5-topic daily
> brief is ~6 paid requests a day. Tune your topic list and pay.sh balance.
