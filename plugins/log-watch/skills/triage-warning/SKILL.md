---
name: triage-warning
description: Triage a single warning-level log event. Fetches surrounding context, classifies the warning (benign / actionable / recurring), and decides whether to surface or drop it.
allowed-tools: Bash, Read, Grep, Glob, mcp__gitea__issue_write
---

# Triage Warning

Handle one warning event passed from `watch-logs`. Warnings are noisy by default — the goal here is to **suppress the benign ones** and only surface the signal.

**Input** (from skill arg): `--pod=<pod> --namespace=<ns> --ts=<iso8601> --hash=<hash>`

## Step 0: Parse arguments

Extract `pod`, `namespace`, `ts`, `hash`.

## Step 1: Fetch context

LogQL conventions and endpoint live in `lib/loki-query.md`:

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/loki-query.md`

Query Loki for a ±2-minute window around `ts`, filtered to the same pod:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/loki-poll.sh \
  '{namespace="'"${NAMESPACE}"'",pod="'"${POD}"'"}' 4 200
```

(Using 4-minute window = ±2 minutes around the event.)

Keep the warning line plus the 5 lines before and 5 lines after.

## Step 2: Map pod to source repo

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/namespace-repo-map.md`

## Step 3: Classify

Produce one of three verdicts:

- **`benign`** — known noise pattern: deprecation warnings for dependencies, retry-succeeded loops, expected shutdown messages, health-check timeouts under load.
- **`actionable`** — points at a likely bug: null/undefined access, unexpected state transition, retries-exhausted-but-didn't-fail-loudly, slow-query warnings above threshold.
- **`recurring`** — hash has been seen ≥ 5 times in the last hour (check `~/.cache/log-watch/seen-events.json` `count` field). Elevated beyond warning — warrants an issue even if individually benign.

Base the verdict on:

- The warning text itself
- The ±2-min pod context
- A quick grep in the source repo for the warning string or the emitting function name

## Step 4: Act

### If `benign`

Write nothing to Discord. Append a single line to `~/.cache/log-watch/triage-log.ndjson`:

```json
{"ts":"<ts>","hash":"<hash>","severity":"warning","verdict":"benign","pod":"<pod>"}
```

Exit.

### If `actionable`

Post a Discord embed (amber, 15844367) with:

- Title: `Warning (actionable): <pod>`
- First 200 chars of the warning line
- Suspected cause (1-2 sentences)
- Suggested next step (1 sentence)

Do **not** open a Gitea issue for a first-sighting warning — wait for recurrence.

### If `recurring`

Post a Discord embed (amber) AND open a Gitea issue in the owning repo via `mcp__gitea__issue_write`:

- Title: `Recurring warning: <first 60 chars of normalized line>`
- Body: warning line, pod, namespace, count from dedup state, first-seen/last-seen timestamps, ±2-min context
- Labels: `bug`, `status: backlog`

Record the issue number in the triage log entry so future ticks don't double-file.

## Step 5: Report

Print a one-line summary:

```
triage-warning → <verdict> (<pod>)
```
