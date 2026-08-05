# 👁️ Vision Extractor

![Vision Extractor demo](demo.gif)

An image in, typed JSON out.

Vision Extractor sends an image to Gemini via a paid [pay.sh](https://pay.sh) call
(multimodal, fronted by pay.sh, no GCP account) and pulls out the fields you name
as clean JSON: a receipt's total, an invoice's line items, a screenshot's numbers,
a nutrition label's ingredients. Paid per image in USDC on Solana, no API keys.

The multimodal sibling of [Web Extractor](../web-extractor): name the fields, get
typed JSON back, ready for an agent to act on. Turns a photo into structured data
an agent can file, sum, or route.

Deliver via stdout (default), Telegram, a webhook, or a websocket.

📎 **X thread:** _(link coming soon)_

---

## What it does

1. Base64-encodes your `IMAGE` and sends it to Gemini via pay.sh.
2. Asks for the fields in `FIELDS` as a single JSON object.
3. Projects the response to exactly those keys (missing ones come back `null`).
4. Prints or delivers the JSON. The raw values ride along in the payload.

## Try it instantly (no setup)

```bash
DRY_RUN=1 ./vision-extractor.sh
```

Extracts from the canned [`example-vision.json`](./example-vision.json), a model
response for a coffee-shop receipt:

```
👁️ Vision Extract: example-vision.json
{
  "merchant": "Corner Cafe",
  "date": "2026-07-14",
  "total": 18.40,
  "currency": "USD",
  "items": ["Latte", "Croissant", "Sparkling water"]
}
```

No `pay`, no network, no image needed. The response also had `tax` and
`payment_method`; projection kept only the fields you asked for.

## How to run

```bash
IMAGE=./receipt.jpg FIELDS="merchant,date,total,currency,items" ./vision-extractor.sh
# or pass the image as an argument, and leave FIELDS empty to get everything:
./vision-extractor.sh ./invoice.png
```

Non-stdout sinks emit a JSON payload, so an agent can act on it:

```json
{"type":"vision_extract","source":"receipt.jpg",
 "data":{"merchant":"Corner Cafe","total":18.40, …},"text":"👁️ …"}
```

## End-to-end example

```bash
./example.sh                          # demo (offline fixture)
LIVE=1 IMAGE=./receipt.jpg ./example.sh   # real
```

## Prerequisites

- **pay CLI**, installed and funded — <https://pay.sh>.
- **jq**, **base64**, **curl** — JSON, image encoding, HTTP.

## Environment variables

| Variable | Description |
|---|---|
| `IMAGE` | Path to a local image file (or pass as the first argument) |
| `FIELDS` | Comma-separated fields to pull (empty = return everything read) |
| `ALERT_SINK` | `stdout` (default), `telegram`, `webhook`, or `websocket` |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` | For the `telegram` sink |
| `WEBHOOK_URL` | For the `webhook` sink |
| `WS_URL` | For the `websocket` sink |
| `PAYSH_VISION_URL` | _(optional)_ Override the pay.sh vision endpoint |

> **Handy for:** expense bots (photo of a receipt to a ledger row), invoice intake,
> reading a chart or dashboard screenshot into numbers, or any step where an agent
> needs to turn something it can only see into something it can compute on.
