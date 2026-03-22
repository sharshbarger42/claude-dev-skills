---
name: update-prs
description: Rebase open PRs onto latest main and verify CI passes. Use when PRs are stale or have merge conflicts.
argument-hint: "[repo] or [repo#N]"
---

# Update PRs Skill

Rebase open PR branches onto the latest base branch (usually main) and verify CI passes afterward. Handles one PR or all open PRs in a repo.

**Input:** Optional repo or PR reference as the skill argument. Accepted formats:
- Repo only: `food-automation` or `super-werewolves/food-automation` — updates ALL open PRs
- Specific PR: `food-automation#32` or `super-werewolves/food-automation#32` — updates one PR
- Full URL: `https://git.home.superwerewolves.ninja/super-werewolves/food-automation/pulls/32`

If no argument is provided, infer from the current working directory.

## Step 1: Parse the argument

Extract `owner`, `repo`, and optional PR `index` from the argument.

### Repo resolution

!`cat $HOME/.claude/development-skills/lib/resolve-repo.md`

### If no argument was provided

Infer the repo from the current working directory:

1. Run `git remote get-url origin` via Bash to get the remote URL
2. Match the URL against the shorthand table
3. If a match is found, use `AskUserQuestion` to confirm:
   - Option 1: **Yes, use {repo}** — proceed with the inferred repo (all open PRs)
   - Option 2: **Different repo** — user types the shorthand name
4. If no match is found, ask which repo to use

## Step 2: Collect PRs to update

### If a specific PR index was provided

Fetch the single PR using `mcp__gitea__get_pull_request_by_index`. Verify it is:
- Open (not merged or closed)
- Not a draft

If the PR is merged or closed, tell the user and stop.

Build a working list with one entry.

### If only a repo was provided

Call `mcp__gitea__list_repo_pull_requests` with `state: "open"`.

If there are no open PRs, tell the user and stop.

Build a working list from all open, non-draft PRs. For each, record:
- `index`, `title`, `head.ref` (branch name), `head.sha` (current commit), `base.ref` (target branch), `mergeable`

Show the user what will be updated:

```
Found {N} open PRs in {owner}/{repo}:

| PR | Title | Branch | Mergeable |
|----|-------|--------|-----------|
| #{index} | {title} | {head_branch} | {Yes/No/Conflicts} |

Rebasing all onto latest {base_branch}.
```

## Step 3: Resolve Gitea API token

The Gitea API token is needed for the update endpoint. Extract it from the running gitea-mcp process:

```bash
ps aux | grep 'gitea-mcp.*-token' | grep -v grep | head -1 | grep -oP '(?<=-token )\S+'
```

If no token is found, stop and tell the user:
> Could not find Gitea API token. Ensure the gitea-mcp server is running.

Store the token for use in the update API calls.

## Step 4: Rebase each PR

For each PR in the working list:

### 4a. Call the Gitea update-branch API

Use the Gitea API to rebase the PR branch onto the base branch server-side:

```bash
curl -s -w "\n%{http_code}" -X POST \
  "https://git.home.superwerewolves.ninja/api/v1/repos/{owner}/{repo}/pulls/{index}/update" \
  -H "Authorization: token {GITEA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"style": "rebase"}'
```

**Interpret the response:**
- **HTTP 200**: Rebase succeeded. Record as `rebased`.
- **HTTP 409 (Conflict)**: Rebase failed due to merge conflicts. Record as `conflicts`. The PR branch is unchanged.
- **HTTP 422**: PR is already up to date with the base branch. Record as `up-to-date`.
- **Other errors**: Record the status code and response body as `error`.

### 4b. If the API endpoint is not available

Fall back to local git operations using the repo's local checkout path (from the shorthand table):

1. `git fetch origin` — get latest remote state
2. Create a temporary worktree:
   ```bash
   git worktree add /tmp/update-pr-{index} origin/{head_branch}
   ```
3. In the worktree, rebase onto the base branch:
   ```bash
   cd /tmp/update-pr-{index}
   git rebase origin/{base_branch}
   ```
4. If rebase succeeds: force-push with lease:
   ```bash
   git push --force-with-lease origin HEAD:{head_branch}
   ```
5. If rebase has conflicts: abort and record as `conflicts`:
   ```bash
   git rebase --abort
   ```
6. Clean up the worktree:
   ```bash
   cd -
   git worktree remove /tmp/update-pr-{index}
   ```

### 4c. Log progress

After each PR, log the result:
```
#{index} {title} — {rebased|up-to-date|conflicts|error}
```

## Step 5: Wait for CI on rebased PRs

Use the shared check-ci procedure for accurate CI status:

!`cat $HOME/.claude/development-skills/lib/check-ci.md`

For each PR that was successfully rebased (status = `rebased`):

1. Wait 15 seconds for CI to trigger on the new head commit
2. Run the check-ci procedure (which re-fetches the PR for fresh HEAD SHA, checks commit statuses, and cross-references with action runs)
3. If state is `running`, poll every 30 seconds for up to 10 minutes
4. Record the final CI state: `passed`, `failed`, `running` (timed out), or `no-ci`

For PRs that were `up-to-date`, run the check-ci procedure to get their current CI status.

For PRs with `conflicts`, skip CI check.

## Step 6: Report results

Present a summary:

```
## PR Update Results — {owner}/{repo}

| PR | Title | Rebase | CI | Notes |
|----|-------|--------|----|-------|
| #{index} | {title} | ✅ Rebased | ✅ Passed | |
| #{index} | {title} | ⚠️ Up to date | ✅ Passed | Already on latest {base_branch} |
| #{index} | {title} | ❌ Conflicts | — | Manual rebase needed |
| #{index} | {title} | ✅ Rebased | ❌ Failed | {failing check name} |

### Summary
- **{N} rebased** successfully
- **{N} already up to date**
- **{N} have conflicts** (need manual resolution)
- **CI: {N} passed, {N} failed, {N} pending**
```

If any PRs have conflicts, suggest:
> PRs with conflicts need manual rebase. Check out the branch locally and resolve:
> ```
> git fetch origin
> git checkout {branch}
> git rebase origin/{base_branch}
> # resolve conflicts
> git push --force-with-lease
> ```

If any PRs have CI failures, suggest:
> PRs with CI failures may have been broken by the rebase. Check the failing workflow runs.
