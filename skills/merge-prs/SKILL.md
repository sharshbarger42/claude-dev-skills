---
name: merge-prs
description: Find ready PRs, verify reviews and CI, merge them, monitor deploys, and run health checks.
---

# Merge PRs Skill

Find PRs that are ready to merge, verify all reviews are addressed and CI passes, merge them, monitor deployments, and run health checks. Auto-creates Gitea issues if deploys fail or health checks are unhealthy.

**Input:** Optional repo reference as the skill argument. Accepted formats:
- Shorthand: `food-automation`
- Owner/repo: `super-werewolves/food-automation`

If no argument is provided, ask which repos to scan.

## Step 1: Parse optional repo argument

If an argument was provided, extract `owner` and `repo`.

### Repo resolution

!`cat $HOME/gitea-repos/development-skills/lib/resolve-repo.md`

If **no argument** was provided, use `AskUserQuestion` with these options:
- **All repos** — scan every repo in the shorthand table above
- **Current repo** — detect from the current working directory using `git remote get-url origin` via Bash, then match to the shorthand table
- **A specific repo** — user types the shorthand name

Build the list of repos to scan (one or more `owner`/`repo` pairs).

## Step 2: List open PRs

For each repo in scope, call `mcp__gitea__list_repo_pull_requests` with `state: "open"`.

If a repo has no open PRs, skip it and note that in the final report.

Collect all open PRs into a working list with: `owner`, `repo`, `index`, `title`, `head.label` (branch name), `head.sha` (commit SHA), `user.login` (PR author), and `base.repo.default_merge_style`.

## Step 3: Check if review comments are addressed

For each open PR:

1. Call `mcp__gitea__list_pull_request_reviews` to get all reviews. For each review, record its `id`, `state` (`APPROVED`, `REQUEST_CHANGES`, `COMMENT`), and `user.login`.
2. For each review, call `mcp__gitea__list_pull_request_review_comments` to get inline comments. Record each comment's `id`, `review_id`, `path`, `position`, `body`, `user.login`, and `created_at`.
3. Call `mcp__gitea__get_issue_comments_by_index` to get top-level PR comments.

### Determining if a review is addressed

A review is **addressed** if any of these are true:
- The review `state` is `APPROVED` or `COMMENT` (only `REQUEST_CHANGES` reviews block merging)
- The review was **dismissed** (state shows as dismissed — this is how `/fix-pr` marks fully-addressed reviews)
- Every inline comment from the review has been addressed (see below)

An individual inline comment is **addressed** if any of these are true:
- A top-level PR comment from the PR author references the comment's `path` and contains a commit SHA (this is how `/fix-pr` posts its summary: `"Addressed review comments in {sha}: - path:position — description"`)
- A reply exists from the PR author on the same `path` + `position` with a later `created_at` timestamp
- New commits were pushed to the PR branch after the comment's `created_at` AND a top-level summary comment from the PR author lists the addressed items

### Ready vs not ready

A PR is **ready** if all `REQUEST_CHANGES` reviews are either dismissed or fully addressed, and no user comments (non-`code-review-agent`) are left without a response.

A PR is **not ready** if any `REQUEST_CHANGES` review has unaddressed inline comments, or if a user left a comment that has no response from the PR author.

Mark each PR as `ready` or `not ready ({N} unaddressed comments)`.

## Step 4: Check CI/action status

For each PR marked `ready` from Step 3:

1. Use the head commit SHA from the PR metadata
2. Call `mcp__gitea__list_repo_action_runs` to find workflow runs — look for runs where the branch matches the PR's head branch
3. Check that all completed runs have `status: "success"`
4. If any run has `status: "failure"`, mark the PR as `not mergeable (CI failed: {run name})`
5. If any run is still `running` or `pending`, mark the PR as `not mergeable (CI in progress)`
6. If no runs exist for the branch, treat CI as passed (repo may not have CI configured)

## Step 5: Confirm with user

Present a summary table of ALL open PRs across all scanned repos:

```
## PRs Ready to Merge

| Repo | PR | Title | Reviews | CI | Merge Style |
|------|----|-------|---------|----|-------------|
| food-automation | #39 | refactor: enforce layer boundary | All addressed | Passed | rebase |

## PRs Not Ready

| Repo | PR | Title | Reason |
|------|----|-------|--------|
| homelab-setup | #12 | feat: add backup | 2 unaddressed comments |
```

Use `AskUserQuestion` with `multiSelect: true` to let the user select which ready PRs to merge. List each ready PR as an option. If there are multiple ready PRs, include an "All ready PRs" convenience option.

If no PRs are ready, report this and stop.

## Step 6: Merge

### Read Gitea token

Extract the user's Gitea token from `~/.claude.json`:

```bash
jq -r '.mcpServers.gitea.args | to_entries[] | select(.value == "-token") | .key + 1 | tostring' ~/.claude.json | xargs -I{} jq -r ".mcpServers.gitea.args[{}]" ~/.claude.json
```

If the token cannot be extracted, stop and tell the user:
> Could not find Gitea token in `~/.claude.json`. Ensure the gitea MCP server is configured with a `-token` argument.

### Verify auth

Call `mcp__gitea__get_my_user_info` to confirm the token is valid and note the authenticated username.

### Merge each PR

For each selected PR, determine the merge strategy:
- Use `base.repo.default_merge_style` from the PR metadata if available
- Fall back to `rebase` if not set

Read the Gitea API URL from the infrastructure config:

!`cat $HOME/gitea-repos/development-skills/config/infrastructure.md`

Merge via the Gitea REST API using the Bash tool:

```bash
curl -s -X POST \
  -H "Authorization: token {GITEA_TOKEN}" \
  -H "Content-Type: application/json" \
  "{GITEA_API_URL}/repos/{owner}/{repo}/pulls/{index}/merge" \
  -d '{"Do": "{merge_style}", "delete_branch_after_merge": true}'
```

Check the HTTP response:
- **200/204**: merge succeeded
- **405**: merge not allowed (conflicts, branch protection, etc.) — report the error and skip
- **409**: conflict — report and skip

Record the merge timestamp for each successfully merged PR.

## Step 7: Check for deploy workflows

Use this mapping to determine if a merged repo has a deploy-on-merge workflow:

| Repo | Deploy workflow | Health check |
|------|----------------|--------------|
| `food-automation` | `deploy.yaml` | `curl -s http://food.baryonyx-walleye.ts.net/health` |
| `homelab-setup` | `deploy.yml` | None (infrastructure) |

If the merged repo is NOT in this table, skip to Step 10 for that PR.

## Step 8: Wait for deployment

For each merged PR in a deploy-on-merge repo:

1. Wait 30 seconds for the action to trigger
2. Call `mcp__gitea__list_repo_action_runs` and look for a run on the `main` branch (or the repo's default branch) with a `created_at` timestamp after the merge timestamp
3. If no run found yet, poll every 30 seconds for up to 5 minutes
4. Once the run is found, poll its status every 30 seconds for up to 10 minutes:
   - `success` — proceed to Step 9
   - `failure` — proceed to Step 9 (deploy failed)
   - Still running — keep polling

If no deploy run is found after 5 minutes, note this as "deploy not triggered" and continue.

## Step 9: Health check and failure handling

### If deploy succeeded

Run the repo-specific health check from the table in Step 7:

- **food-automation**: `curl -s http://food.baryonyx-walleye.ts.net/health` via Bash — verify the response contains `"status"` with value `"ok"` and services show `"ready"`
- **homelab-setup**: Skip (no single health endpoint)

If the health check **fails** (non-200 response, status not ok, or services not ready), create a Gitea issue:
```
Title: Health check failed after merging #{pr_index}
Body: PR #{pr_index} ({pr_title}) was merged and the deploy workflow completed successfully,
      but the health check at {health_url} returned an unexpected response:

      {response_body}

      Investigate and fix.
Labels: bug
```

Use `mcp__gitea__create_issue` with the appropriate `owner` and `repo`.

### If deploy failed

Create a Gitea issue:
```
Title: Deploy failed after merging #{pr_index}
Body: PR #{pr_index} ({pr_title}) was merged but the deploy workflow failed.

      Action run status: {status}
      Branch: {default_branch}

      Investigate and fix the deployment.
Labels: bug
```

Use `mcp__gitea__create_issue` with the appropriate `owner` and `repo`.

## Step 10: Report

For each PR that was in scope, report its final status:

```
## Merge Results

| Repo | PR | Title | Merge | Deploy | Health | Issue |
|------|----|-------|-------|--------|--------|-------|
| food-automation | #39 | refactor: enforce layer boundary | Merged (rebase) | Passed | Healthy | — |
| homelab-setup | #12 | feat: add backup | Merged (rebase) | Failed | — | #45 created |
| recipe-readiness | #8 | fix: parser edge case | Merged (rebase) | N/A | N/A | — |
| food-automation | #40 | feat: new endpoint | Skipped | — | — | — (2 unaddressed comments) |
```

Keep the output concise. No fluff.
