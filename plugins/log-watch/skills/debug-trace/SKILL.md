---
name: debug-trace
description: Deep-dive on a debug-level log event. Correlates traces across services, extracts timing/state, and produces a structured investigation note. Opt-in — debug is high-volume.
allowed-tools: Bash, Read, Grep, Glob
---

# Debug Trace

Handle one debug event passed from `watch-logs`. Unlike warnings/errors, debug traces are **investigative** rather than remedial — the user invokes this (or auto-mode dispatches it) when they want a structured view of what a service was doing around a point in time.

Expect this skill to be invoked sparingly. Debug is noisy; `watch-logs` only surfaces debug events when explicitly filtered for.

**Input** (from skill arg): `--pod=<pod> --namespace=<ns> --ts=<iso8601> --hash=<hash>`

## Step 0: Parse arguments

Extract `pod`, `namespace`, `ts`, `hash`.

## Step 1: Fetch broad context

Debug traces are most useful with wide windows. Pull ±10 minutes of all logs (every severity) for the pod:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/loki-poll.sh \
  '{namespace="'"${NAMESPACE}"'",pod="'"${POD}"'"}' 20 1000
```

Organise into a timeline. For each entry record: timestamp, severity, line.

## Step 2: Extract trace identifiers

Scan all lines for common correlation IDs:

- Request ID (`request_id=`, `req_id=`, `rid=`, `X-Request-ID` header values)
- Trace ID (`trace_id=`, `traceparent` W3C format)
- User/tenant ID (`user_id=`, `tenant=`)
- Job/task ID (`job_id=`, `task_id=`)

Pick the most specific ID that appears in the debug event. This is the **trace key**.

## Step 3: Cross-service correlation

If a trace key was found, query Loki across all namespaces for that key:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/loki-poll.sh \
  '{namespace=~".+"} |= "<trace_key>"' 30 500
```

Merge results with the pod timeline, sorted by timestamp. This produces a cross-service trace — often reveals that a "slow frontend" was actually waiting on a downstream service.

## Step 4: Structure the trace

Produce a compact markdown timeline:

```markdown
## Trace for <trace_key>
### Timeline (UTC)
| Time | Service | Severity | Line |
|------|---------|----------|------|
| 12:03:04.123 | dragon-den/dragon-den-7c8f | DEBUG | entered handler /items |
| 12:03:04.145 | MAC/mac-orch-abc | INFO  | task dispatched id=<task_id> |
| 12:03:09.980 | MAC/mac-orch-abc | WARN  | task timeout after 5s |
| 12:03:10.001 | dragon-den/dragon-den-7c8f | ERROR | upstream timeout |

### Gap analysis
- 5.8s between task dispatch and timeout
- No intermediate progress signals
```

Highlight:

- Gaps > 1s between log entries
- Severity transitions (INFO → WARN → ERROR progression)
- Services that appear in the trace but emit no debug lines (possible instrumentation gap)

## Step 5: Link to code

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/namespace-repo-map.md`

For each notable step in the timeline, find the emitting line in source using the mapping above. Annotate the timeline with `file:line` references.

## Step 6: Report

**Always post to Discord** in notify mode — debug traces are opt-in, so the user wants to see what came back. Use a blue embed (3447003) with:

- Title: `Debug trace: <trace_key or pod+ts>`
- Summary (1-2 sentences)
- Timeline (first 20 rows; truncate with "… N more rows")
- File/line references

In `auto` mode: the same Discord post, plus save the full timeline to:

```
~/.cache/log-watch/traces/<hash>.md
```

Do **not** file Gitea issues from this skill — debug traces are exploratory, not remedial. If the trace reveals a bug, invoke `investigate-error` explicitly.

## Notes

- This skill does the most work per invocation. Keep `watch-logs --source=loki` debug dispatch rare — usually only when the user explicitly filters for a trace key.
- The cross-service query in Step 3 is the expensive one; skip it if no trace key is found.
