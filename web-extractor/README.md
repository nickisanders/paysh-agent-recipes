# 📑 Web Extractor

Turn any web page into structured JSON for the fields you name.

Give it a URL and a list of fields; it asks [pay.sh](https://pay.sh)'s
structured-extract endpoint (paid per request in USDC, no API keys) to pull just
those fields and returns clean, typed JSON. No parsing HTML, no scraping the whole
page. You name the fields, you get the values.

Not a monitor. It is a transform: URL in, JSON out. The JSON is the deliverable,
so there are no alert sinks. Print it, save it, or pipe it into an agent.

📎 **X thread:** _(link coming soon)_

---

## What it does

1. Takes a `URL` and a comma-separated `FIELDS` list.
2. Asks pay.sh to extract exactly those fields from the page.
3. Writes clean JSON to `OUTPUT` (or stdout).

Where Page Watch tells you *that* a page changed, Web Extractor gives you the
*data on* a page, as typed values an agent or a dataset can use directly.

## Try it instantly (no setup)

```bash
DRY_RUN=1 ./web-extractor.sh
```

Returns the canned [`example-extract.json`](./example-extract.json):

```json
{
  "name": "Acme Wireless Widget",
  "price": "$79.00",
  "in_stock": true,
  "rating": "4.6"
}
```

No `pay`, no network. Note `in_stock` comes back as a real boolean, not a string.

## How to run

```bash
URL=https://shop.example/widget FIELDS=name,price,in_stock ./web-extractor.sh
# or pass the URL as an argument:
FIELDS=name,price ./web-extractor.sh https://shop.example/widget
# save it:
URL=... FIELDS=... OUTPUT=./out.json ./web-extractor.sh
```

Pipe it straight into an agent or jq:

```bash
URL=... FIELDS=price,in_stock ./web-extractor.sh | jq '.in_stock'
```

## End-to-end example

```bash
./example.sh          # demo mode (returns the fixture)
LIVE=1 ./example.sh   # real: needs a funded pay CLI + a valid .env
```

## Prerequisites

- **pay CLI**, installed and funded — <https://pay.sh>.
- **jq**, **curl** — JSON handling and HTTP.

## Environment variables

| Variable | Description |
|---|---|
| `URL` | Page to extract from (or pass as the first argument) |
| `FIELDS` | Comma-separated fields to pull (e.g. `name,price,in_stock`) |
| `OUTPUT` | _(optional)_ Where to write the JSON (default: stdout) |
| `PAYSH_EXTRACT_URL` | _(optional)_ Override the pay.sh structured-extract endpoint |

> **Tip:** name fields the way they appear on the page (`price`, `sku`, `author`,
> `published_at`). The cleaner your field names, the better the extraction.
