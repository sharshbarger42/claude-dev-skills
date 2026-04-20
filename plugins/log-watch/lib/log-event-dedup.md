# Log Event Dedup

Prevents `watch-logs` from re-reporting the same event on every polling tick.

## State file

```
~/.cache/log-watch/seen-events.json
```

Schema:

```json
{
  "<hash>": {
    "first_seen_ns": 1713574800000000000,
    "last_seen_ns": 1713575400000000000,
    "count": 3,
    "pod": "dragon-den-7c8f",
    "severity": "error",
    "last_dispatched_ns": 1713575000000000000
  }
}
```

`last_dispatched_ns` is set by `watch-logs` auto mode when a handler skill runs for this hash. Used to enforce a 6-hour per-hash cooldown without needing a separate append-only action log. `null` / absent means the handler has never run for this hash.

Create `~/.cache/log-watch/` if missing. Treat a missing file as `{}`.

## Hash computation

For each raw log line, compute:

```
hash = sha1( normalize(line) + "|" + pod_name )[:16]
```

`normalize(line)`:

1. Strip the leading timestamp (first whitespace-separated token if it parses as a timestamp).
2. Replace sequences of digits ≥ 4 chars with `<N>` (request IDs, timestamps, pids).
3. Replace UUIDs with `<UUID>`.
4. Collapse runs of whitespace.

This makes "request 123 failed" and "request 456 failed" collapse to the same hash — both are the same event.

**Intentional collision on step 2.** The `digits ≥ 4` rule also collapses IPv4 octets, port numbers (`8080`, `3000`), and PIDs into `<N>`. This is deliberate: dedup is tuned for event-kind matching, not per-peer reporting. Two "connection refused" lines that differ only by destination port become one event. If you need per-port or per-host granularity later, tighten the regex to require a word boundary before the digits, or add pod/IP extraction ahead of normalisation.

## Dedup window

A hash is considered a **new event** if either:

- It's not in the state file, OR
- Its `last_seen_ns` is more than **30 minutes** older than the current log line's timestamp (so recurrence after a long quiet period re-triggers)

Otherwise it's a duplicate — increment `count` and update `last_seen_ns`, but do not emit an event.

## Pruning

At the end of each tick, drop hashes whose `last_seen_ns` is older than 24 hours. Keeps the state file bounded.
