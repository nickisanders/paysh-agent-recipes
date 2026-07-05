# ⚡ Realtime Whale Watcher

![Realtime Whale Watcher demo](demo.gif)

The low-latency sibling of [Whale Watcher](../whale-watcher). Instead of polling
on a cron, this is a **long-running process that follows the chain head** and
fires an alert the instant a whale-sized transfer to/from your wallet lands in a
new block. Deliver it via **Telegram, a webhook, a websocket, or stdout** —
you're not locked into any one channel.

It reads on-chain data through [pay.sh](https://pay.sh)'s pay-per-request
JSON-RPC (no API keys), so you still pay only for the calls you make. Works across
**EVM chains and Solana** — pick with one env var (`NETWORK`).

📎 **X thread:** <https://x.com/nickisanders/status/2073066021926121499>

---

## Why this exists

[Recipe #1](../whale-watcher) polls: dead simple, but your latency is bounded by
the cron interval and you only ever see settled history. Someone rightly asked:
for time-sensitive action, why poll instead of push?

This recipe is the answer. It trades a little setup (a long-running process +
a Telegram bot) for **~one-block latency** instead of ~one-cron-tick.

**The honest caveat:** pay.sh is per-request HTTP (x402), not a streaming
socket. So "realtime" here means *scan every block the moment it's produced* —
the lowest-latency model that fits a per-request payment rail. It catches
transactions at confirmation, not in the mempool. For pre-confirmation signal
you'd point `rpc()` at a mempool-exposing endpoint (`eth_subscribe`/pending), at
the cost of noise (pending txs can be dropped or replaced). That's a natural
recipe #3.

## What it does

1. Follows the chain head through pay.sh RPC (`eth_blockNumber` on EVM, `getSlot`
   on Solana).
2. Fetches each new block with full transactions and finds native transfers that
   touch `WATCH_WALLET`.
3. Keeps anything `>= THRESHOLD_NATIVE` and delivers it immediately via your
   chosen sink. Records the last-scanned block/slot so a restart resumes cleanly.

The two chains detect transfers differently, behind one interface:

- **EVM** — matches `tx.from`/`tx.to` and reads `tx.value` (hex wei).
- **Solana** — there's no `tx.value`, so it derives native SOL moves from each
  account's pre/post **balance deltas** (lamports). The wallet's own delta is the
  amount; the largest opposite-sign delta is the likely counterparty.

## Supported chains

Set `NETWORK` (default `ethereum`). Each preset sets the native symbol, decimals,
and a default pay.sh RPC route (override with `PAYSH_RPC_URL`).

| `NETWORK` | Chain | Native |
|---|---|---|
| `ethereum` | EVM | ETH |
| `base` | EVM | ETH |
| `arbitrum` | EVM | ETH |
| `optimism` | EVM | ETH |
| `polygon` | EVM | POL |
| `bnb` | EVM | BNB |
| `avalanche` | EVM | AVAX |
| `solana` | Solana | SOL |

```bash
NETWORK=solana ./realtime-whale.sh          # watch a Solana wallet for SOL whales
NETWORK=base   ./realtime-whale.sh          # watch a Base wallet for ETH whales
```

> Scope: this watches **native-asset** transfers (ETH, SOL, etc.). Token whales
> (ERC-20 on EVM, SPL like USDC on Solana) live in logs/instructions rather than
> the native value, so they're a follow-on. USD thresholds need a price call, kept
> out of the hot loop on purpose to stay fast and dependency-light. On Solana, the
> counterparty is a best-effort guess (largest opposite balance delta).

## Alert transports

Set `ALERT_SINK` to route alerts wherever you want — you're not forced into
Telegram. Every non-telegram sink emits a machine-readable JSON payload, so your
**agents** can consume alerts directly:

```json
{"type":"whale_alert","network":"ethereum","wallet":"0xd8dA…6045","direction":"in",
 "value":"420.000000","symbol":"ETH","counterparty":"0x28C6…1d60","tx":"0x8f2e…5e8f",
 "text":"🐋 Whale alert [ethereum]: …"}
```

| `ALERT_SINK` | Needs | Delivery |
|---|---|---|
| `telegram` _(default)_ | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | Human message to a chat |
| `webhook` | `WEBHOOK_URL` | `POST` the JSON payload to your URL |
| `websocket` | `WS_URL` + [`websocat`](https://github.com/vi/websocat) | Push the JSON payload to a WS endpoint |
| `stdout` | — | Print the JSON payload (pipe into your agent, `jq`, anything) |

```bash
# Feed an agent directly, no third-party service:
ALERT_SINK=stdout ./realtime-whale.sh | your-agent --consume

# Or fan out to your own infra:
ALERT_SINK=webhook WEBHOOK_URL=https://you.example.com/whale ./realtime-whale.sh
```

## Try it instantly (no setup)

```bash
DRY_RUN=1 ./realtime-whale.sh
```

Scans a canned block once and prints the alerts it would deliver. No `pay`, no
bot, no loop. Tune the threshold, or switch chains:

```bash
DRY_RUN=1 THRESHOLD_NATIVE=200 ./realtime-whale.sh                 # only the 420 ETH transfer
DRY_RUN=1 THRESHOLD_NATIVE=500 ./realtime-whale.sh                 # nothing qualifies, silent
DRY_RUN=1 NETWORK=solana ./realtime-whale.sh                       # Solana demo (SOL whales)
DRY_RUN=1 NETWORK=solana THRESHOLD_NATIVE=3000 ./realtime-whale.sh # only the 5000 SOL transfer
```

Each network scans its own fixture ([`example-block.json`](./example-block.json)
for EVM, [`example-block-solana.json`](./example-block-solana.json) for Solana).

## End-to-end example

[`example.sh`](./example.sh) sets the env, calls the watcher, receives the
flagged transfers, and processes them (here, prints a summary):

```bash
./example.sh                        # demo mode
THRESHOLD_NATIVE=200 ./example.sh   # raise the bar
LIVE=1 ./example.sh                 # real: needs a funded pay CLI + Telegram bot
```

## Prerequisites

- **pay CLI**, installed and funded — <https://pay.sh>.
- **jq**, **bc**, **curl** — `bc` does the wei bignum math that overflows shell ints.
- **Your chosen sink** — a Telegram bot ([@BotFather](https://t.me/BotFather) for the
  token, [@userinfobot](https://t.me/userinfobot) for your chat id), a webhook URL,
  or [`websocat`](https://github.com/vi/websocat) for the websocket sink. `stdout`
  needs nothing.

## Environment variables

| Variable | Description |
|---|---|
| `NETWORK` | Chain to watch: `ethereum` (default), `base`, `arbitrum`, `optimism`, `polygon`, `bnb`, `avalanche`, `solana` |
| `WATCH_WALLET` | Wallet to monitor (EVM `0x` address, or Solana base58 when `NETWORK=solana`) |
| `THRESHOLD_NATIVE` | Min transfer size in the native unit (e.g. `100` = 100 ETH/SOL) |
| `ALERT_SINK` | `telegram` (default), `webhook`, `websocket`, or `stdout` — see [Alert transports](#alert-transports) |
| `TELEGRAM_BOT_TOKEN` | Bot token from @BotFather (telegram sink) |
| `TELEGRAM_CHAT_ID` | Chat/channel id to push alerts to (telegram sink) |
| `WEBHOOK_URL` | URL to `POST` the JSON payload to (webhook sink) |
| `WS_URL` | Websocket URL to push the JSON payload to (websocket sink) |
| `PAYSH_RPC_URL` | _(optional)_ Override the network's default pay.sh RPC route |
| `NATIVE_SYMBOL` | _(optional)_ Override the preset's display symbol |
| `DECIMALS` | _(optional)_ Override native decimals (18 EVM, 9 Solana) |
| `POLL_SECONDS` | _(optional)_ Head poll interval, default `3` |
| `STATE_DIR` | _(optional)_ Last-scanned block store, default `~/.whale-watcher` |

## How to run

It's a daemon, not a cron job — start it once and leave it running:

```bash
cp .env.example .env   # fill in your values
set -a; . ./.env; set +a
./realtime-whale.sh
```

To keep it alive across reboots, run it under a process manager (systemd,
`pm2`, `supervisord`, or a `tmux`/`nohup` session):

```bash
# quick and dirty
nohup ./realtime-whale.sh >> ~/realtime-whale.log 2>&1 &
```

```ini
# systemd unit (/etc/systemd/system/realtime-whale.service)
[Service]
EnvironmentFile=/home/you/realtime-whale-watcher/.env
ExecStart=/home/you/realtime-whale-watcher/realtime-whale.sh
Restart=always
```

> **Cost note:** this makes one `eth_blockNumber` call per poll plus one
> `eth_getBlockByNumber` per new block. At a ~12s block time and `POLL_SECONDS=3`
> that's roughly a handful of paid requests per minute — tune `POLL_SECONDS` and
> your pay.sh balance to taste.
