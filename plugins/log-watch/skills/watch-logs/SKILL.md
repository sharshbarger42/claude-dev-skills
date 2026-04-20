---
name: watch-logs
description: Poll a log source (Loki, journald, or file) for warnings, errors, and debug events. Dedups across ticks and routes new events to severity-specific handler skills.
allowed-tools: Bash, Read, Write, Skill
---

# Watch Logs

Run one polling tick against a log source. Detect new warning/error/debug events, dedup against prior ticks, and route each new event to the appropriate handler skill (or just notify).

Designed to be driven by `/loop`:

```
/loop 2m /log-watch:watch-logs --source=loki --mode=notify
```

**Input flags** (parsed from the skill argument string):

- `--source=loki|journald|file` — default `loki`. In v1 only `loki` is implemented; the other two are stubs that emit a "not yet supported" notice and exit. See issues #145 and #146 for the research tickets.
- `--since=<minutes>` — window to query. Default `15`.
- `--mode=notify|auto` — default `notify`. In `auto`, new events dispatch to the handler skills listed below.
- `--filter=<LogQL>` — override the default namespace selector for Loki.
- `--namespaces=<a,b,c>` — restrict Loki queries to these namespaces. Default: all shipped namespaces (see `lib/loki-query.md`).

## Step 0: Parse arguments

Apply defaults: `source=loki`, `since=15`, `mode=notify`.

If `source` is not `loki`, print the following and exit successfully:

```
Source "<source>" is not yet supported in log-watch v1.
Research tickets:
  - journald: super-werewolves/development-skills#145
  - file:     super-werewolves/development-skills#146
```

## Step 1: Load dedup state

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/log-event-dedup.md`

Load `~/.cache/log-watch/seen-events.json` (or `{}` if missing).

## Step 2: Fetch log lines from Loki

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/loki-query.md`

Build three queries — one per severity — unless `--filter` overrides. Use the namespace selector derived from `--namespaces` (or the default multi-namespace regex).

Run each via the helper:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/loki-poll.sh "<query>" "${SINCE}" 500
```

Parse streams → `(timestamp_ns, line, pod, namespace, severity)` tuples.

**Severity assignment:**

- Matches `(?i)error|exception|traceback|panic|fatal` → `error`
- Matches `(?i)warn|warning` (and no error match) → `warning`
- Matches `(?i)debug` → `debug`

Lines that don't match any severity keyword are dropped.

## Step 3: Dedup and emit events

For each tuple, compute the dedup hash per `lib/log-event-dedup.md` and check state:

- **New event** → append to the events list with full context (line, pod, namespace, severity, timestamp)
- **Duplicate** → update `last_seen_ns` and `count` in state; skip

Stop collecting once the events list hits **20** per severity per tick — avoids runaway dispatch when a service is spewing.

## Step 4: Route events

### Notify mode (default)

Group events by severity. Send one Discord embed per severity that has ≥ 1 event. Include: pod name, namespace, timestamp, first 200 chars of the line. Colour code:

- `error` → red (15158332)
- `warning` → amber (15844367)
- `debug` → grey (8421504)

If zero events across all severities, send nothing.

### Auto mode

For each new event, dispatch via the `Skill` tool to the matching handler:

| Severity | Handler |
|----------|---------|
| `warning` | `log-watch:triage-warning` |
| `error` | `log-watch:investigate-error` |
| `debug` | `log-watch:debug-trace` |

Pass the event context as the skill argument — a single line of:

```
--pod=<pod> --namespace=<ns> --ts=<iso8601> --hash=<hash>
```

**Safety caps:**

1. Max **5** auto-dispatches per tick (across all severities combined). If more qualify, notify-summarize the overflow.
2. Before dispatching, check the event's `last_dispatched_ns` in `seen-events.json`. If it's within the last 6 hours of the event timestamp, skip — handler already ran for this hash, don't thrash.
3. When a dispatch fires, set `last_dispatched_ns` to the current time on that hash's entry before invoking the handler. This co-locates cooldown state with dedup state so pruning (24h) bounds both automatically — no separate append-only log to rotate.

## Step 5: Persist state and report

Write updated dedup state. Prune entries older than 24 hours per the dedup lib.

Print a one-line summary to stdout:

```
watch-logs tick — 2026-04-19T12:05:00Z
source=loki since=15m
new: 2 errors, 5 warnings, 0 debug
mode=notify → Discord sent (2 embeds)
```

In auto mode, list dispatches:

```
auto-dispatched (2/5):
  error   dragon-den/dragon-den-7c8f → investigate-error
  warning food-automation/food-automation-9d2a → triage-warning
```

## Notes

- Loki is the only implemented source in v1. Journald and file sources are blocked on issues #145 and #146.
- Dedup window and normalisation rules live in `lib/log-event-dedup.md` — tune there rather than in this skill.
- Keep the Loki query `limit` modest (500 default). High-traffic apps can saturate a single query; rely on dedup to collapse bursts into a single event.
