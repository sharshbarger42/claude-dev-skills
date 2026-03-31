---
name: check-ci
description: Check CI status for a PR or all open PRs in a repo. Shows current workflow run state with accurate HEAD tracking.
allowed-tools: Bash, Read, mcp__gitea__pull_request_read, mcp__gitea__actions_run_read, mcp__gitea__list_pull_requests
---

# Check CI

Check CI/workflow status for one or all open PRs. Handles stale SHA detection and cross-references commit statuses with action runs.

**Input:** Optional PR or repo reference as the skill argument. Accepted formats:
- Specific PR: `food-automation#32` or `super-werewolves/food-automation#32`
- Repo only: `food-automation` — checks ALL open PRs
- Full URL: `https://git.home.superwerewolves.ninja/super-werewolves/food-automation/pulls/32`

If no argument is provided, infer from the current working directory.

## Step 1: Parse the argument

Extract `owner`, `repo`, and optional PR `index` from the argument.

### Repo resolution

!`cat $HOME/.config/development-skills/lib/resolve-repo.md`

### If no argument was provided

Infer the repo from the current working directory:

1. Run `git remote get-url origin` via Bash to get the remote URL
2. Parse `owner/repo` from the URL
3. If no match, ask which repo to use

## Step 2: Collect PRs

### If a specific PR index was provided

Build a list with just that one PR.

### If only a repo was provided

Call `mcp__gitea__list_pull_requests` with `state: "open"` to get all open, non-draft PRs.

If no open PRs, tell the user and stop.

## Step 3: Check CI for each PR

For each PR, run the shared check-ci procedure:

!`cat $HOME/.config/development-skills/lib/check-ci.md`

## Step 4: Report results

Present a summary table:

```
## CI Status — {owner}/{repo}

| PR | Title | HEAD | CI | Details |
|----|-------|------|----|---------|
| #{index} | {title} | {sha[:8]} | {status_emoji} {state} | {detail} |
| #{index} | {title} | {sha[:8]} | {status_emoji} {state} | {detail} |

Status emoji key:
- ✅ passed
- ❌ failed
- ⏳ running
- ➖ no-ci
```

For failed PRs, include the failing job name and a brief description of the error.

For running PRs, include which jobs are still in progress and how long they've been running.

### Verbose output

If any PR has failures, show additional detail:

```
### Failures

**#{index} {title}** — Run #{run_number}: {workflow_name}
  Job: {job_name} — {conclusion}
  Use `/check-ci {repo}#{index}` for full logs, or check: {run_html_url}
```
