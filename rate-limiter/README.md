# 🚦 Rate Limiter

![Rate Limiter demo](demo.gif)

A circuit breaker for an agent's paid calls.

Wrap any `pay` call. It allows up to N calls per time window, then trips: extra
calls are blocked, not run. A buggy loop or a runaway agent can burn a lot of
fractions-of-a-cent in a hurry. This caps how *often*, the way
[Spend Guard](../spend-guard) caps how *much* and
[Approval Gate](../approval-gate) adds a human.

The window slides, so it recovers on its own: once old calls age out, the agent
is free to go again.

📎 **X thread:** _(link coming soon)_

---

## What it does

Put it in front of a `pay` call:

```bash
rate-limiter.sh pay curl -s -G https://audit.pay.sh/contract ...
```

It counts how many calls happened in the last `RATE_WINDOW_SEC` seconds. Under
`RATE_MAX`, the call runs and is recorded. At the limit, it trips and blocks,
until enough calls age out of the window.

## Try it instantly (no setup)

```bash
DRY_RUN=1 ./example.sh
```

Fires 6 calls with a limit of 3 per 60s. The first 3 run, the rest are blocked:

```
[rate-limiter] call 1/3 in the last 60s. Allowed.
[rate-limiter] call 2/3 in the last 60s. Allowed.
[rate-limiter] call 3/3 in the last 60s. Allowed.
[rate-limiter] TRIPPED: 3/3 calls in the last 60s. Blocked, not run.
[rate-limiter] TRIPPED: 3/3 calls in the last 60s. Blocked, not run.
[rate-limiter] TRIPPED: 3/3 calls in the last 60s. Blocked, not run.
```

No `pay`, nothing spent.

## Separate buckets

Limit different jobs independently with `RATE_KEY`:

```bash
RATE_KEY=whale-watcher RATE_MAX=10 rate-limiter.sh pay curl ...
RATE_KEY=research      RATE_MAX=60 rate-limiter.sh pay curl ...
```

## Environment variables

| Variable | Description |
|---|---|
| `RATE_MAX` | Max calls allowed per window (default `30`) |
| `RATE_WINDOW_SEC` | The window, in seconds (default `60`) |
| `RATE_KEY` | Bucket name, to limit groups separately (default `default`) |
| `RATE_STATE_DIR` | Where the call log lives (default `~/.rate-limiter`) |

> **Fail-fast, not queue:** a tripped call is blocked and returns non-zero, it is
> not queued and retried. Your agent decides what to do with the block (back off,
> stop, alert). Pair it with Spend Guard and Approval Gate for the full set.
