# 🧲 Lead Enricher

![Lead Enricher demo](demo.gif)

Turn a plain list of leads into an enriched CSV.

Hand it a CSV of emails or domains and it looks up each row through
[pay.sh](https://pay.sh)'s enrichment gateway (paid per request in USDC, no API
keys), then writes the same rows back with extra columns: name, title, company,
industry, and headcount.

Unlike the other recipes this isn't a monitor. It's a batch transform: CSV in,
enriched CSV out. The output file is the deliverable, so there are no alert sinks.

📎 **X thread:** _(link coming soon)_

---

## What it does

1. Reads `INPUT_CSV` (a CSV with a header row).
2. For each row, looks up the value in `KEY_COLUMN` (an email or domain) through
   pay.sh's enrichment gateway. One paid request per row.
3. Appends five columns and writes the result to `OUTPUT_CSV` (or stdout).

Rows with no key value pass through with blank enrichment columns rather than
failing, so one bad row never sinks the batch.

## Try it instantly (no setup)

```bash
DRY_RUN=1 ./lead-enricher.sh
```

Enriches the bundled [`example-leads.csv`](./example-leads.csv) from a local
fixture and prints the result. No `pay`, no network. In:

```
name,email
Ada Lovelace,ada@analytical.io
```

Out:

```
name,email,enriched_name,enriched_title,enriched_company,enriched_industry,enriched_employees
Ada Lovelace,ada@analytical.io,"Ada Lovelace","Founder & CEO","Analytical Engines","Developer Tools","12"
```

## How to run

```bash
INPUT_CSV=./leads.csv OUTPUT_CSV=./enriched.csv ./lead-enricher.sh
# or pipe it:
INPUT_CSV=./leads.csv ./lead-enricher.sh > enriched.csv
```

Look up on the domain column instead of email:

```bash
INPUT_CSV=./accounts.csv KEY_COLUMN=domain ./lead-enricher.sh
```

## End-to-end example

[`example.sh`](./example.sh) prints the input, runs the enricher, and prints the
enriched output side by side:

```bash
./example.sh          # demo mode (enriches the fixture)
LIVE=1 ./example.sh   # real: needs a funded pay CLI + a valid .env
```

## Prerequisites

- **pay CLI**, installed and funded — <https://pay.sh>.
- **jq**, **curl** — JSON handling and HTTP.

## Environment variables

| Variable | Description |
|---|---|
| `INPUT_CSV` | Path to the input CSV (must have a header row) |
| `KEY_COLUMN` | Header to look up on, `email` or `domain` (default `email`) |
| `OUTPUT_CSV` | _(optional)_ Where to write the result (default: stdout) |
| `PAYSH_ENRICH_URL` | _(optional)_ Override the pay.sh enrichment endpoint |

> **Format note:** built for simple CSVs (no commas inside quoted fields). The key
> is read by column position, so quoted fields containing commas can shift it.
> Most exported lead lists are simple enough; clean odd ones first.

> **Cost note:** one enrichment request per row. A 1,000-row list is ~1,000 paid
> requests. Dedupe and trim your list before a big run.
