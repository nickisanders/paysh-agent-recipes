# ✋ Approval Gate

![Approval Gate demo](demo.gif)

Human in the loop for an agent's big spends.

Wrap an action that moves money and tag its USD value. Below your limit the agent
proceeds on its own. At or above it, the action pauses and asks a human to approve
before it runs. A "no" (or a timeout) blocks it. Auto for the small stuff, a
yes/no for anything that matters.

[Spend Guard](../spend-guard) sets hard caps the agent can't cross. Approval Gate
is the softer layer next to it: things the agent may do, but only with your
say-so. (And the hardware version of this is a Tangem tap, coming separately.)

📎 **X thread:** _(link coming soon)_

---

## What it does

Put it in front of a paid action, tagging the value:

```bash
AMOUNT_USD=200 approval-gate.sh pay curl -s -X POST https://.../transfer ...
```

- Under `APPROVE_OVER_USD`: auto-approved, the action runs.
- At or above it: asks a human. On yes, it runs. On no or timeout, it blocks and
  nothing happens.

Ask on the **terminal** (a `y/N` prompt) for interactive use, or via **Telegram**
(a message you reply to) for a headless agent. If it can't reach a human, it fails
safe and denies.

## Try it instantly (no setup)

```bash
DRY_RUN=1 ./example.sh
```

Shows a small action auto-approve, and a big one approved then denied (the human
answer is simulated with `APPROVE_ANSWER`):

```
[approval-gate] $5.00 is under the $25.00 limit. Auto-approved.
[approval-gate] $200.00 needs approval... approved.
[approval-gate] $200.00 needs approval... denied.
[approval-gate] Blocked. The action did not run.
```

No `pay`, nothing spent.

## Channels

| `APPROVE_CHANNEL` | How it asks |
|---|---|
| `terminal` _(default)_ | a `y/N` prompt on the terminal |
| `telegram` | sends a message, waits for you to reply `y` or `n` (needs `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID`) |

## Environment variables

| Variable | Description |
|---|---|
| `AMOUNT_USD` | The USD value of the action (required) |
| `APPROVE_OVER_USD` | Ask for approval at or above this (default `25`) |
| `APPROVE_CHANNEL` | `terminal` (default) or `telegram` |
| `APPROVE_TIMEOUT` | Telegram: seconds to wait for a reply, then deny (default `300`) |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` | For the `telegram` channel |

> **Fail-safe:** if no human can be reached (no terminal, no reply in time), the
> action is denied, not approved. Silence is a no.
