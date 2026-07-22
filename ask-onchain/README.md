# 🔮 Ask Onchain

Ask a question in plain English. The agent picks a tool, pays for it, and answers.

This is the full agent loop in one script. `pay claude` reads your question and
decides which on-chain data source to use, the script fetches it through
[pay.sh](https://pay.sh) (paid per request in USDC, no API keys), then `pay claude`
answers using the data. Reason, act, respond.

The agent's tool belt is the rest of this library's data sources, and it chooses
on its own:

| Tool | What it pulls |
|---|---|
| `audit(address)` | a token contract's security risk |
| `price(symbol)` | current USD price |
| `holdings(address)` | a wallet's holdings and value |
| `gas()` | current gas price in gwei |
| `search(query)` | recent news or web info |

Deliver via stdout (default), Telegram, a webhook, or a websocket.

📎 **X thread:** _(link coming soon)_

---

## What it does

1. **Plan.** `pay claude` reads your question and returns which tool to use, and
   its arguments, as JSON.
2. **Act.** The script calls that tool's pay.sh endpoint and gets the data.
3. **Answer.** `pay claude` answers your question in plain English using the data.

It is a small but real agent loop: the model decides which paid tool to use, the
script pays for it, and the model answers. No hardcoded routing, the question
drives the tool choice.

## Try it instantly (no setup)

```bash
DRY_RUN=1 ./ask-onchain.sh
```

Runs a canned question end to end:

```
🔮 Ask Onchain
Q: Is the token at 0x1111…1111 safe to buy?
Used: audit(0x1111…1111)
A: No. The contract lets the owner mint new supply and blacklist holders, and
   ownership is not renounced... treat it as high risk and stay out.
```

No `pay`, no network. You can see the whole loop: the tool it chose, and the answer.

## How to run

```bash
QUESTION="what is the price of SOL?" ./ask-onchain.sh
# or pass it as an argument:
./ask-onchain.sh "how much is gas right now?"
./ask-onchain.sh "what does wallet 0xabc… hold?"
```

Different questions route to different tools. Non-stdout sinks emit a JSON payload
with the full trace (question, tool, args, data, answer), so an agent can chain it.

## End-to-end example

```bash
./example.sh          # demo mode (canned loop)
LIVE=1 ./example.sh   # real: needs a funded pay CLI + a valid .env
```

## Prerequisites

- **pay CLI**, installed and funded — <https://pay.sh>.
- **jq**, **curl** — JSON handling and HTTP.

## Environment variables

| Variable | Description |
|---|---|
| `QUESTION` | What to ask (or pass as the first argument) |
| `CHAIN` | _(optional)_ Network for address tools, default `ethereum` |
| `ALERT_SINK` | `stdout` (default), `telegram`, `webhook`, or `websocket` |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` | For the `telegram` sink |
| `WEBHOOK_URL` | For the `webhook` sink |
| `WS_URL` | For the `websocket` sink |
| `PAYSH_AUDIT_URL` / `PAYSH_MARKET_URL` / `PAYSH_WALLET_URL` / `PAYSH_RPC_URL` / `PAYSH_SEARCH_URL` | _(optional)_ Override any tool's endpoint |

> **Cost note:** one `pay claude` call to plan, one paid data call for the tool,
> and one `pay claude` call to answer. Three tiny paid requests per question.

> **Scope:** one tool per question, on purpose, to keep it a clean, cheap loop.
> Multi-tool planning (chain several calls) is the natural next step.
