---
name: watch-prs
description: Poll open PRs for state changes and either notify (default) or auto-route to fix-pr/qa-pr/merge-prs. Designed to be run on an interval via /loop.
allowed-tools: Bash, Read, Write, Skill, mcp__gitea__list_pull_requests, mcp__gitea__pull_request_read, mcp__gitea__actions_run_read
---

# Watch PRs

Continuously watch open PRs and react when their state changes — a new review, new comment, CI transition, label change, or merge. Runs one polling tick per invocation; cadence is driven externally by `/loop`.

**Input:** optional flags, parsed from the skill argument string:

- `--scope=<repo>` — a repo shorthand, `owner/repo`, or `all` (default: `all`)
- `--mode=notify|auto` — default `notify`. In `auto`, state transitions route to handler skills (see routing matrix below). Notify-only sends a Discord summary and stops.
- `--max-actions=<N>` — maximum auto-actions per tick (default `3`; only applies in `--mode=auto`)
- Example: `watch-prs --scope=food-automation --mode=auto --max-actions=5`

## Step 0: Parse arguments and resolve scope

Parse the argument string. Apply defaults: `scope=all`, `mode=notify`, `max-actions=3`.

### Repo resolution

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/resolve-repo.md`

If `scope=all`, use every repo in the shorthand table. Otherwise resolve the single repo.

## Step 1: Load prior-tick state

State lives at `~/.cache/dev-workflow/watch-prs-state.json`. Create the parent directory if missing. If the file doesn't exist *or* cannot be parsed as JSON (e.g., truncated from a prior crash), log a warning and treat it as `{}` — same as a first-tick cold start.

Schema (keyed by `{owner}/{repo}#{index}`):

```json
{
  "super-werewolves/food-automation#42": {
    "head_sha": "abc123",
    "labels": ["pr: needs-review"],
    "review_count": 0,
    "comment_count": 3,
    "ci_status": "passed",
    "mergeable": true,
    "merged": false,
    "latest_review_verdict": null,
    "latest_review_author_is_bot": false,
    "last_seen": "2026-04-19T12:00:00Z"
  }
}
```

## Step 2: Fetch current PR state

For each repo in scope:

1. Call `mcp__gitea__list_pull_requests` with `state: "open"` (and `state: "closed"` on a second pass so we can detect merges that happened since last tick — filter to `merged_at` since the prior tick's `last_seen` timestamp, falling back to the last 24h on a cold start. Keying off `last_seen` means merges during extended poller downtime aren't misclassified as `closed-unmerged`).
2. For each PR, collect: `head.sha`, `labels` (names only), review count, comment count, `mergeable`, `merged` flag. When `review_count` increased, fetch the latest review via `mcp__gitea__pull_request_read` method `get_reviews` and record its `state` as `latest_review_verdict` and whether its author is a bot as `latest_review_author_is_bot`.
3. For CI status on open PRs, reuse the shared check-ci procedure:

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/check-ci.md`

Keep the full details in memory; we only diff the fields listed above.

## Step 3: Diff against prior state

For each PR in the current snapshot, compare against the prior-tick state to produce **events**. Emit at most one event per PR per tick — if multiple fields changed, pick the highest-priority one (in the order listed):

| Event | Trigger |
|-------|---------|
| `merged` | `merged` flipped from `false`/absent to `true` |
| `ci-failed` | `ci_status` transitioned to `failed` (from any non-`failed` value) |
| `merge-conflict` | `mergeable` transitioned to `false` |
| `label-changed` | The `pr:` status label (see `lib/pr-status-labels.md`) changed |
| `new-review` | `review_count` increased |
| `new-comment` | `comment_count` increased |
| `head-sha-changed` | `head_sha` changed since last tick (force-push or rebase) |
| `new-pr` | PR is present in the current snapshot but absent from prior state |

PRs present in prior state but missing from the current snapshot (and not detected as `merged`) were closed without merge — emit `closed-unmerged` and include them in notify output, but never auto-route them.

### First-tick behavior

On a cold start (empty prior state), do NOT flood notifications for every open PR. Instead:

- Record the current snapshot
- Emit a single `first-tick` summary event listing PR counts by status
- Skip auto-routing on this tick

## Step 4: Route events

### Notify mode (default)

For each event, append a line to the Discord summary. Send one combined embed per tick using the template pattern from `lib/discord-notify.md` (title: "PR Watch Tick — {timestamp}"). If there are zero events, send nothing.

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/discord-notify.md`

### Auto mode

Route by event type:

| Event | Action |
|-------|--------|
| `label-changed` → `pr: comments-pending` | Invoke `/dev-workflow:fix-pr {owner}/{repo}#{index}` via the Skill tool |
| `label-changed` → `pr: awaiting-dev-verification` | Invoke `/dev-workflow:qa-pr {owner}/{repo}#{index}` |
| `label-changed` → `pr: ready-to-merge` | Invoke `/dev-workflow:merge-prs --scope={owner}/{repo}` |
| `new-review` with `latest_review_verdict` = `REQUEST_CHANGES` and `latest_review_author_is_bot` = `false` | Invoke `/dev-workflow:fix-pr {owner}/{repo}#{index}` (verdict and author come from the state tracked in Step 2) |
| `ci-failed` | **Notify only** — never auto-touch a failing PR |
| `merge-conflict` | **Notify only** — needs human to resolve |
| `merged`, `closed-unmerged`, `new-pr`, `new-comment` | Notify only |

**Hard safety rules for auto mode:**

1. Check the PR's `status:` label before routing. If it has `status: in-progress`, skip — another agent is working on it.
2. Route at most `--max-actions` auto-actions per tick across all repos (default `3`). If more qualify, log the overflow as a notify event and stop.
3. Before invoking a handler skill, record the planned action to `~/.cache/dev-workflow/watch-prs-actions.log` (append-only, one line per action with timestamp + PR ref). This is the audit trail if something goes sideways. The log is safe to rotate or truncate at any time; consider size-based rotation (e.g., on next tick if >1MB, move to `.log.1` and start fresh).
4. Before routing any auto-action whose gate depends on CI (e.g., `pr: ready-to-merge`), verify the recorded `ci_status` corresponds to the current `head_sha`. If CI has not yet run against a new head after a force-push (`head-sha-changed` fired this tick or `ci_status` is `unknown`/`pending`), notify only and defer routing to a later tick.

## Step 5: Persist state

Overwrite `~/.cache/dev-workflow/watch-prs-state.json` with the current snapshot. Include `last_seen` set to the tick's start time. Write to a temp file in the same directory and atomically `mv` over the target to avoid producing corrupt state if the process is killed mid-write.

Pruning: drop entries for PRs that were merged or closed more than 7 days ago to keep the file bounded.

## Step 6: Report

Print a short summary to stdout so the user sees it in the terminal:

```
Watch PRs tick — 2026-04-19T12:05:00Z
Scope: 3 repos, 12 open PRs tracked
Events: 2 new-review, 1 ci-failed, 0 merged
Mode: notify (Discord sent)
```

If in auto mode, also list the actions taken:

```
Auto-actions taken (2):
  - food-automation#42 → fix-pr (label → comments-pending)
  - MAC#15 → merge-prs (label → ready-to-merge)
```

## Notes on polling cadence

This skill does not sleep or loop on its own. Pair it with `/loop`:

```
/loop 5m /dev-workflow:watch-prs --mode=notify
```

The 5-minute cadence balances freshness against Gitea API load. For `--mode=auto`, prefer 10m+ so you have time to interrupt if something looks wrong.
