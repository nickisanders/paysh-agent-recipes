# 🔎 Semantic Search

![Semantic Search demo](demo.gif)

Search a pile of text by meaning, not keywords.

Semantic Search embeds your query and each document with a paid [pay.sh](https://pay.sh)
call (Vertex AI text embeddings, fronted by pay.sh, no GCP account), then ranks the
documents by cosine similarity and returns the closest matches. Paid per embedding
in USDC on Solana, no API keys.

This is the building block behind agent memory, FAQ bots, and RAG. Give an agent a
pile of text and it can find the relevant bits for any question, even when the
words don't overlap. In the demo, "how do I get my money back?" matches "Refunds
are issued to the original payment method" despite sharing no keywords.

Deliver via stdout (default), Telegram, a webhook, or a websocket.

📎 **X thread:** _(link coming soon)_

---

## What it does

1. Embeds your `QUERY` via pay.sh.
2. Embeds each line of your `CORPUS` file via pay.sh.
3. Ranks documents by cosine similarity to the query.
4. Returns the top `TOP_K` matches with scores.

## Try it instantly (no setup)

```bash
DRY_RUN=1 ./semantic-search.sh
```

Ranks the canned [`example-corpus.json`](./example-corpus.json), whose embeddings
are precomputed so it runs offline:

```
🔎 Semantic Search: "how do I get my money back?"
Top matches:
  1. (0.99) Refunds are issued to the original payment method within 5 to 10 business days.
  2. (0.58) You can update your billing details from the account settings page.
  3. (0.35) Orders over $50 ship free and arrive in 3 to 5 business days.
```

No `pay`, nothing spent. The refund doc wins on meaning alone, no shared keywords.

## How to run

Put your documents in a text file, one per line, then query it:

```bash
QUERY="can I return this?" CORPUS=./docs.txt ./semantic-search.sh
# or pass the query as an argument:
CORPUS=./docs.txt ./semantic-search.sh "can I return this?"
```

Non-stdout sinks emit a JSON payload, so an agent can act on the matches:

```json
{"type":"semantic_search","query":"can I return this?",
 "matches":[{"score":0.94,"text":"Refunds are issued …"}, …],"text":"🔎 …"}
```

## End-to-end example

```bash
./example.sh                                        # demo (offline fixture)
LIVE=1 QUERY="can I return this?" CORPUS=./docs.txt ./example.sh   # real
```

## Prerequisites

- **pay CLI**, installed and funded — <https://pay.sh>.
- **jq**, **awk**, **curl** — JSON, cosine math, HTTP.

## Environment variables

| Variable | Description |
|---|---|
| `QUERY` | The search query (or pass as the first argument) |
| `CORPUS` | Path to a text file, one document per line |
| `TOP_K` | How many matches to return (default `3`) |
| `ALERT_SINK` | `stdout` (default), `telegram`, `webhook`, or `websocket` |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` | For the `telegram` sink |
| `WEBHOOK_URL` | For the `webhook` sink |
| `WS_URL` | For the `websocket` sink |
| `PAYSH_EMBED_URL` | _(optional)_ Override the pay.sh embeddings endpoint |

> **Caching tip:** this embeds the whole corpus on every run, which is fine for a
> small file but wasteful for a big one. In production, embed your documents once,
> store the vectors, and only embed the query each time. You pay per embedding, so
> caching the corpus is the difference between paying once and paying every search.
