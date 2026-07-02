# 🐋 Whale Watcher

Monitor any wallet and get an **SMS the moment a whale-sized transaction lands**.

The script asks [Heurist Mesh](https://mesh.heurist.ai/) for the wallet's recent
on-chain activity through [`pay claude`](https://pay.sh) — paid per request over
pay.sh with USDC, **no API keys or accounts** — and fires a
[Twilio](https://www.twilio.com/) text when a transfer at or above your USD
threshold shows up. Runs on a cron, dedupes so the same transaction never pages
you twice, and stays silent when nothing qualifies.

📎 **X thread:** <https://x.com/nickisanders/status/2072759755798626603>

---

## Try it instantly (no setup)

Want to see it work before installing `pay` or configuring Twilio? Run the demo:

```bash
DRY_RUN=1 ./whale-watcher.sh
```

This feeds the script the canned [`example-response.json`](./example-response.json)
instead of calling `pay`, and **prints the SMS it would send** instead of texting.
No `pay`, no Twilio, no cost. Tweak the threshold to see the filter work:

```bash
DRY_RUN=1 THRESHOLD_USD=100 ./whale-watcher.sh      # catches all 3 sample txs
DRY_RUN=1 THRESHOLD_USD=5000000 ./whale-watcher.sh  # catches none — stays quiet
```

## End-to-end example

[`example.sh`](./example.sh) is the full integration pattern: it sets the env
vars, calls `whale-watcher.sh`, **receives the flagged transactions back**, and
processes them (here, printing a summary — swap in Slack, a webhook, or a DB).

```bash
./example.sh                     # demo mode, inline defaults
THRESHOLD_USD=100 ./example.sh   # lower the bar to see all sample txs
LIVE=1 ./example.sh              # real: needs a funded pay CLI + valid .env
```

It reads a local `.env` if present (copy [`.env.example`](./.env.example) to
`.env`), otherwise falls back to demo values. Sample output:

```
==> Running whale-watcher.sh (watching 0xd8dA…6045, threshold $1000000)

==> Received 2 alert(s):

  • 🐋 Whale alert: 0xd8dA…6045 out $3240000 in WETH (counterparty 0x28C6…). tx 0x8f2e5b1a…
  • 🐋 Whale alert: 0xd8dA…6045 in $1512000 in USDC (counterparty 0x21a3…). tx 0x1a2b3c4d…

==> Done. Plug this loop into Slack, a webhook, a DB — wherever you route alerts.
```

## What it does

1. Queries Heurist Mesh via `pay claude` for recent transactions of `WATCH_WALLET`.
2. Parses the JSON response with `jq` and keeps transfers `>= THRESHOLD_USD`.
3. Sends a Twilio SMS for each new whale (tracked in a state file, so no repeats).
4. Exits quietly with no alert when the response has nothing over the threshold —
   no false alarms.

## Prerequisites

- **pay CLI** — install and fund it once. See the pay.sh setup guide:
  <https://pay.sh> (this is what powers `pay claude`; no API keys needed, you just
  fund a wallet with USDC and pay per request).
- **jq** — JSON parsing. `brew install jq` (macOS) or `apt-get install jq` (Linux).
- **curl** — ships with macOS and most Linux distros.
- **A Twilio account** with an SMS-capable phone number.

## Environment variables

| Variable | Description |
|---|---|
| `TWILIO_ACCOUNT_SID` | Your Twilio Account SID |
| `TWILIO_AUTH_TOKEN` | Your Twilio Auth Token |
| `TWILIO_FROM` | Twilio phone number to send from, E.164 (e.g. `+14155550100`) |
| `ALERT_TO` | Number to text the alert to, E.164 (e.g. `+14155550123`) |
| `WATCH_WALLET` | Wallet address to monitor |
| `THRESHOLD_USD` | Minimum transaction size (USD) that triggers an alert, e.g. `50000` |
| `STATE_DIR` | _(optional)_ Where seen-tx hashes are stored. Default: `~/.whale-watcher` |

## How to run

```bash
export TWILIO_ACCOUNT_SID="ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
export TWILIO_AUTH_TOKEN="your_auth_token"
export TWILIO_FROM="+14155550100"
export ALERT_TO="+14155550123"
export WATCH_WALLET="0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
export THRESHOLD_USD="50000"

./whale-watcher.sh
```

The first run may print `No transaction >= $50000 found. Staying quiet.` — that's
the expected quiet path.

## What you'll see

Given a Heurist Mesh response like [`example-response.json`](./example-response.json):

```json
{
  "transactions": [
    { "hash": "0x8f2e…5e8f", "usd_value": 3240000.0, "token": "WETH",
      "direction": "out", "counterparty": "0x28C6…1d60", "timestamp": "2026-07-02T14:32:10Z" },
    { "hash": "0xdead…aabb", "usd_value": 118.42, "token": "USDC",
      "direction": "out", "counterparty": "0x5a52…Efcb", "timestamp": "2026-07-02T12:58:01Z" }
  ]
}
```

...with `THRESHOLD_USD=1000000`, the $3.24M transfer fires a text and the $118 one
is ignored:

```
🐋 Whale alert: 0xd8dA…6045 out $3240000 in WETH (counterparty 0x28C6…). tx 0x8f2e5b1a…
```

Each transaction is texted only once — its hash is recorded in the state file, so
the next cron run won't re-alert on the same whale.

## Set up the cron

Check every 5 minutes. Put your `export`s in a small env file so cron has them:

```bash
# ~/whale-watcher.env
export TWILIO_ACCOUNT_SID="AC..."
export TWILIO_AUTH_TOKEN="..."
export TWILIO_FROM="+14155550100"
export ALERT_TO="+14155550123"
export WATCH_WALLET="0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
export THRESHOLD_USD="50000"
```

Then add the job with `crontab -e`:

```cron
*/5 * * * * . $HOME/whale-watcher.env && /path/to/whale-watcher/whale-watcher.sh >> $HOME/whale-watcher.log 2>&1
```

Logs go to `~/whale-watcher.log`; alerted transaction hashes are remembered in
`~/.whale-watcher/` so a whale is only texted once.

> **Cost note:** each run makes one `pay claude` request (a few fractions of a
> cent in USDC). A `*/5` schedule is ~288 requests/day — tune the interval and
> your pay.sh balance to taste.
