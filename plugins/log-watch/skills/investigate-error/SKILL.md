---
name: investigate-error
description: Investigate a single error-level log event. Fetches context, locates the emitting code, diagnoses the root cause, and proposes a fix or files a bug issue.
allowed-tools: Bash, Read, Grep, Glob, mcp__gitea__issue_write, mcp__gitea__issue_read
---

# Investigate Error

Handle one error event from `watch-logs`. Errors are high-signal — the goal is to **get from "an error happened" to "here is the file, line, and likely cause"** in a single tick.

**Input** (from skill arg): `--pod=<pod> --namespace=<ns> --ts=<iso8601> --hash=<hash>`

## Step 0: Parse arguments

Extract `pod`, `namespace`, `ts`, `hash`.

## Step 1: Fetch error context

Query Loki for a ±5-minute window around `ts`, filtered to the same pod. Pull up to 500 lines — errors often include stack traces that span many lines.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/loki-poll.sh \
  '{namespace="'"${NAMESPACE}"'",pod="'"${POD}"'"}' 10 500
```

Extract:

- The error line itself
- Any associated stack trace (consecutive lines starting with whitespace, `at `, `File "...`, or containing `line \d+`)
- The 20 lines preceding the error (often the operation that triggered it)

## Step 2: Cross-pod correlation

Query the same 10-minute window across all pods in the namespace to find related errors — upstream/downstream services often fail together.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/loki-poll.sh \
  '{namespace="'"${NAMESPACE}"'"} |~ "(?i)(error|exception|traceback|panic|fatal)"' 10 200
```

Note any other pods that errored in the same window.

## Step 3: Locate the code

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/namespace-repo-map.md`

In the repo:

1. Grep for a distinctive substring of the error message (quote-strip, ID-normalise first)
2. Grep for function names from the stack trace
3. Read the matching file around the emitting line

If the error is from a dependency (stack trace points into `node_modules/`, `site-packages/`, etc.), find where our code calls into that path.

## Step 4: Diagnose

Produce a root-cause hypothesis with:

- **File + line** — where the error originates in our code
- **Probable cause** — 2-3 sentences: what condition triggered the error
- **Confidence** — `high` (clear one-to-one match), `medium` (plausible but not certain), `low` (best guess, needs human)
- **Suggested fix** — 1-2 sentences, or "needs investigation" if unclear

## Step 5: Act

### Check for an existing issue first

Before filing, search the owning repo for open issues matching the normalised error via `mcp__gitea__issue_read` method `list_issues` with `state=open` and search terms from the error.

If an issue already exists with this error signature, **do not file a duplicate** — just post a Discord comment pointing to it.

### If new and confidence ≥ medium

File a Gitea issue in the owning repo via `mcp__gitea__issue_write`:

- Title: `Error in <pod>: <first 60 chars of normalized line>`
- Body (markdown):
  - Error line + stack trace (code-fenced)
  - Timestamp, pod, namespace, hash
  - Diagnosis from Step 4 (file, line, cause, confidence)
  - Correlated errors in other pods, if any
  - Suggested fix
- Labels: `bug`, `status: backlog`

Post a Discord embed (red, 15158332) with the issue link.

### If confidence = low

Post a Discord embed (red) with the error summary and diagnosis, but do **not** file an issue — human should look first.

## Step 6: Report

One-line summary:

```
investigate-error → <verdict> (<pod>) issue=#<n>
```

where `verdict` is `filed-issue`, `updated-existing`, or `notified-only`.
