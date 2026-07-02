# paysh-agent-recipes

Short, copy-pasteable AI agent workflows built on [**pay.sh**](https://pay.sh) —
the platform for per-request API micropayments in USDC, with **no API keys and no
accounts**. Each recipe pays for exactly the calls it makes, right when it makes
them.

Every recipe lives in its own folder with a working script and a README that
links to the matching X thread. Clone one, set a few env vars, and run.

## Recipes

| Recipe | What it does | Stack |
|---|---|---|
| [🐋 Whale Watcher](./whale-watcher) | Watches a wallet and SMS-alerts you when a transaction crosses a USD threshold | `pay claude` · Heurist Mesh · Twilio · cron |

_More recipes coming — PRs welcome._

## How these work

Every recipe uses the [`pay`](https://pay.sh) CLI to make paid API/AI calls over
pay.sh. You fund a wallet with USDC once; each request settles a tiny micropayment
via the x402 protocol. No sign-up, no billing account, no API keys to rotate.

## Getting started

1. Pick a recipe folder and open its `README.md`.
2. Most recipes ship a **`DRY_RUN=1`** demo mode with a canned response — run it
   first to see the workflow end-to-end with no `pay` balance or credentials.
3. Install and fund the `pay` CLI — see <https://pay.sh>.
4. Set the listed environment variables and run the script for real.

## License

MIT
