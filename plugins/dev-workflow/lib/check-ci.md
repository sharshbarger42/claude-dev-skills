# Check CI Status

Shared procedure for accurately checking CI/workflow status on a PR. Use this whenever you need to determine whether a PR's CI has passed, failed, or is still running.

## Why this exists

The Gitea commit status API (`/commits/{sha}/status`) returns status for a **specific SHA**. If a new commit is pushed to a PR branch after you fetched the PR metadata, you'll be checking a stale SHA and reporting incorrect results. This procedure ensures you always check the **current** HEAD.

## Procedure

### 1. Fetch fresh PR metadata

**Always re-fetch the PR immediately before checking CI.** Never reuse a previously-fetched `head.sha` — it may be stale.

```
mcp__gitea__pull_request_read
  method: get
  owner: {owner}
  repo: {repo}
  index: {pr_index}
```

Extract `head.sha` and `head.ref` (branch name) from the response. This is the **current** HEAD.

### 2. Check commit statuses

Query the Gitea commit status API for the fresh HEAD SHA:

```bash
curl -s "https://git.home.superwerewolves.ninja/api/v1/repos/{owner}/{repo}/commits/{head_sha}/status" \
  -H "Authorization: token {GITEA_TOKEN}"
```

Parse the response:
- `state` — aggregated status: `success`, `failure`, `pending`, `error`, or empty
- `statuses[]` — individual check results with `context`, `status`, `description`

### 3. Cross-reference with action runs

The commit status API may not reflect in-progress runs immediately. Always cross-reference with recent action runs:

```
mcp__gitea__actions_run_read
  method: list_runs
  owner: {owner}
  repo: {repo}
```

Filter results to runs matching the PR's `head_sha`. Check for:
- Runs with `status: "running"` or `status: "waiting"` — CI is still in progress
- Runs with `status: "completed"` and `conclusion: "failure"` — CI failed
- Runs with `status: "completed"` and `conclusion: "success"` — CI passed

### 4. Determine final CI state

Combine both sources to determine the authoritative CI state:

| Commit status | Action runs | Final state |
|--------------|-------------|-------------|
| `success` | All completed+success | **passed** |
| `success` | Any running/waiting | **running** (commit status is stale from a previous run) |
| `failure` | All completed | **failed** |
| `pending` | Any running/waiting | **running** |
| empty/none | No runs for SHA | **no-ci** (repo has no CI configured) |
| any | Any running for this SHA | **running** (takes priority) |

**Key rule:** If ANY action run for the current `head_sha` is still `running` or `waiting`, report CI as **running** — even if the commit status API says `success` (that's from a previous completed run, not the current one).

### 5. Return structured result

Return a structured result for the caller:

```
CI State: {passed | failed | running | no-ci}
Head SHA: {sha} (short: {sha[:8]})
Checks:
  - {context}: {status} — {description}
  - {context}: {status} — {description}
In-progress runs:
  - Run #{run_number}: {workflow_name} — {status} (started {started_at})
Failed runs:
  - Run #{run_number}: {workflow_name} — {conclusion} (job: {failing_job_name})
```

## Polling mode

When waiting for CI to complete (e.g., after a push or rebase):

1. Run the full procedure above
2. If state is `running`, wait 30 seconds and re-check
3. Poll for up to the caller's specified timeout (default: 10 minutes)
4. If still running after timeout, return `running` with a note that it timed out

## Token resolution

The Gitea API token is needed for the commit status endpoint. Resolve it in order:

1. `~/.config/code-review-agent/token` — available on all machines
2. Extract from running gitea-mcp process
3. `$GITEA_TOKEN` environment variable

## Common pitfalls

- **Stale SHA:** The #1 source of incorrect CI reports. Always re-fetch the PR first.
- **Skipped jobs:** `Build and Deploy` jobs are typically skipped on PRs (they only run on push to main). Don't count skipped jobs as failures.
- **Multiple workflows:** A repo may have multiple workflow files. Check ALL runs for the SHA, not just one.
- **Re-triggered runs:** A manual re-trigger creates a new run with a different `run_id` but the same `head_sha`. The latest run takes precedence.
