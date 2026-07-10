# paysh-agent-recipes

A library of short, copy-pasteable AI agent workflows that pay their own way —
built on [pay.sh](https://pay.sh), the per-request USDC micropayment layer from
the Solana Foundation and Google Cloud. No API keys, no accounts, no
subscriptions: each recipe pays for exactly the calls it makes, right when it
makes them.

Every recipe is a single script in its own folder, with a `DRY_RUN` demo, an
example driver, and a README linking its X thread. Clone it, set a few env vars,
run.

![Realtime Whale Watcher demo](realtime-whale-watcher/demo.gif)

## Recipes

### ⛓️ Onchain & crypto

| Recipe | What it does | Stack | Thread |
|---|---|---|---|
| [🐋 Whale Watcher](./whale-watcher) | Watches a wallet and SMS-alerts you when a transaction crosses a USD threshold | `pay claude` · Heurist Mesh · Twilio · cron | [X](https://x.com/nickisanders/status/2072759755798626603) |
| [⚡ Realtime Whale Watcher](./realtime-whale-watcher) | Low-latency sibling: follows the chain head (EVM + Solana) and pushes within ~one block of a whale-sized transfer, via Telegram / webhook / websocket / stdout | pay.sh JSON-RPC · block scan · pluggable chains + sinks | [X](https://x.com/nickisanders/status/2073066021926121499) |
| [🔻 Depeg Watchdog](./depeg-watchdog) | Watches stablecoins and alerts when one drifts off its peg, once on the break and once on recovery | pay.sh market data · state machine · cron | _soon_ |
| [🔍 Contract Auditor](./contract-auditor) | Audits a smart contract address and returns a plain-English risk brief (via pay claude), with the raw findings for agents | pay.sh audit + pay claude · on-demand | _soon_ |
| [🗂️ Token Dossier](./token-dossier) | One address in, a full due-diligence brief out: orchestrates audit + market + on-chain + social into one synthesized verdict | pay.sh (4 sources) + pay claude · orchestration | _soon_ |

### 🌐 Web & data

| Recipe | What it does | Stack | Thread |
|---|---|---|---|
| [📄 Page Watch](./page-watch) | Watches any web page and alerts you when it changes (pricing pages, job boards, docs, ToS), via Telegram / webhook / websocket / stdout | pay.sh scrape → markdown · diff · cron | _soon_ |
| [☕ Morning Brief](./morning-brief) | Daily cited digest on the topics you follow, emailed to you; chains two pay.sh APIs (web search + agent email) | pay.sh search + email · cron | _soon_ |
| [🧲 Lead Enricher](./lead-enricher) | Batch transform: takes a CSV of emails/domains and writes back an enriched CSV (name, title, company, industry, headcount) | pay.sh enrichment gateway · CSV in/out | _soon_ |
| [📣 Brand Radar](./brand-radar) | Tracks mentions of a keyword/brand/token across Reddit and more, alerts on new ones with an optional pay claude sentiment read | pay.sh social data + pay claude · cron | _soon_ |

_More recipes coming — PRs welcome._

## How these work

Every recipe uses the [`pay`](https://pay.sh) CLI to make paid API/AI calls over
pay.sh. You fund a wallet with USDC once; each request settles a tiny micropayment
via the x402 protocol. No sign-up, no billing account, no API keys to rotate.

## Getting started

1. Pick a recipe folder and open its `README.md`.
2. Most recipes ship a `DRY_RUN=1` demo mode with a canned response — run it
   first to see the workflow end-to-end with no `pay` balance or credentials.
3. Install and fund the `pay` CLI — see <https://pay.sh>.
4. Set the listed environment variables and run the script for real.

## License

MIT
