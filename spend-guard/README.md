# 🛡️ Spend Guard

A spending cap for agents that pay their own way.

Autonomous agents paying per request is the whole point of this library. The
obvious worry is an agent that spends money you didn't intend. Spend Guard is the
answer: wrap any `pay` call and it checks the call against your policy before a
cent moves, a per-call cap, a daily cap, and an endpoint allowlist. It keeps a
ledger of every approved spend and blocks anything that breaks a rule.

The hard floor underneath all of it is still the oldest trick there is: fund the
agent's wallet with only what you're willing to lose. Spend Guard adds the
finer-grained policy on top.

📎 **X thread:** _(link coming soon)_

---

## What it does

Put it in front of a `pay` call:

```bash
spend-guard.sh pay curl -s -G https://audit.pay.sh/contract ...
```

Before running the call it checks:

1. **Allowlist** — is the target host approved? (`GUARD_ALLOW_HOSTS`)
2. **Per-call cap** — is this call within the single-call limit? (`GUARD_CALL_MAX_USD`)
3. **Daily cap** — would today's total exceed the day's budget? (`GUARD_DAILY_CAP_USD`)

If all pass, it runs the call and records the spend to a daily ledger. If any
fail, it blocks: the call never runs, and nothing is spent. Failed calls are not
charged, matching x402's pay-for-a-response model.

## Try it instantly (no setup)

```bash
DRY_RUN=1 ./example.sh
```

Shows the daily cap block the call that would go over, and the allowlist block a
call to an unapproved host:

```
[spend-guard] spent $0.0050 on audit.pay.sh. Today: $0.0200 / $0.0200.
[spend-guard] BLOCKED: daily cap reached: today $0.0200 + $0.0050 would exceed $0.0200.
[spend-guard] Not running the call. Nothing spent.
...
[spend-guard] BLOCKED: host 'sketchy.example.com' is not in the allowlist (audit.pay.sh).
```

No `pay`, nothing spent.

## Wrap your recipes with it

Any recipe in this library calls `pay`. Route those calls through the guard by
setting a `PAY` variable and using it in place of `pay`:

```bash
export PAY="/path/to/spend-guard.sh pay"
# then in the recipe:  $PAY curl -s -G "$SOME_URL" ...
```

Or just prefix a one-off:

```bash
GUARD_DAILY_CAP_USD=0.50 GUARD_ALLOW_HOSTS="audit.pay.sh" \
  spend-guard.sh pay curl -s -G https://audit.pay.sh/contract ...
```

## Environment variables

| Variable | Description |
|---|---|
| `GUARD_DAILY_CAP_USD` | Max total spend per day (default `1.00`) |
| `GUARD_CALL_MAX_USD` | Max spend on a single call (default `0.10`) |
| `GUARD_CALL_USD` | Assumed cost of a call, for accounting (default `0.005`) |
| `GUARD_ALLOW_HOSTS` | Space/comma list of allowed hosts (empty = allow all) |
| `GUARD_STATE_DIR` | Where the ledger lives (default `~/.spend-guard`) |

> **Honest limitation:** the true per-call price lives in the x402 handshake that
> the `pay` CLI settles internally, so the guard accounts using `GUARD_CALL_USD`
> rather than reading each quote. Set it to your route's price (or an upper
> bound). If a future `pay` exposes the quote, the guard can read the real number.

> **Cost note:** the guard itself costs nothing. It runs local checks around your
> paid calls.
