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

Collect all open PRs into a working list with: `owner`, `repo`, `index`, `title`, `head.label` (branch name), `head.sha` (commit SHA), and `user.login` (PR author).

Also count the number of commits in each PR by calling `mcp__gitea__list_repo_commits` filtered to the PR's head branch (commits since the merge base). Record the commit count for each PR.

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

| Repo | PR | Title | Commits | Reviews | CI | Merge Style |
|------|----|-------|---------|---------|----|----|
| food-automation | #39 | refactor: enforce layer boundary | 1 | All addressed | Passed | rebase |
| homelab-setup | #45 | feat(#40): add monitoring stack | 3 | All addressed | Passed | squash |

## PRs Not Ready

| Repo | PR | Title | Reason |
|------|----|-------|--------|
| homelab-setup | #12 | feat: add backup | 2 unaddressed comments |
```

Use `AskUserQuestion` with `multiSelect: true` to let the user select which ready PRs to merge. List each ready PR as an option. If there are multiple ready PRs, include an "All ready PRs" convenience option.

If no PRs are ready, report this and stop.

## Step 6: Merge

### Merge each PR

For each selected PR, determine the merge strategy based on commit count (ignore the repo's `default_merge_style`):
- **1 commit** → `rebase` (clean single commit, no squash needed)
- **2+ commits** → `squash` (collapse into one clean commit with a composed message)

### Compose squash commit message (multi-commit PRs only)

For PRs being squash-merged, compose a custom commit title and body. Do NOT use the Gitea default (which dumps the PR description and all commit messages).

**Title format:** Follow the repo's conventional commit format:
```
type(#issue): short description
```

To build the title:
1. Use the PR title if it already follows the `type(#N): description` format
2. Otherwise, derive the type from the PR content:
   - `feat` — new functionality
   - `fix` — bug fix
   - `refactor` — restructuring without behavior change
   - `docs` — documentation only
   - `chore` — maintenance, deps, CI
3. Extract the issue number from the PR branch name (`feature/{index}-*`) or PR body (`Closes #N`)
4. Write a concise description (imperative mood, lowercase, no period)

**Body format:** Summarize what the final PR accomplishes — NOT a list of every intermediate commit. Exclude iterative fix-up commits (e.g., "address review comments", "fix lint", "fix CI"). Focus on the end result:

```
Summary of the meaningful changes:
- Added X to handle Y
- Updated Z configuration for W
- Removed deprecated Q

Closes #{issue_number}
```

To build the body:
1. Fetch the PR diff with `mcp__gitea__get_pull_request_diff`
2. Read the PR's commit list from `mcp__gitea__list_repo_commits` (filter by the PR branch)
3. Identify the substantive changes from the diff — group by component/area
4. Write 2-6 bullet points summarizing what changed and why
5. Append `Closes #N` if an issue number is linked

**Example:**

For a PR titled `feat(#114): add K8s manifests for multi-agent-coordinator` with 5 commits (initial implementation + 4 review fixes):

```
Title: feat(#114): add K8s manifests for multi-agent-coordinator

Body:
- Add deployment, service, ingress, and networkpolicy for API and frontend
- Add SOPS-encrypted secret for application credentials
- Configure shared-api-keys replication to multi-agent-coordinator namespace
- Add DNS zone entry for multi-agent-coordinator.apps.superwerewolves.ninja

Closes #114
```

### Send the merge request

Use `mcp__gitea__merge_pull_request` with:
- `owner`, `repo`, `index` from the PR metadata
- `merge_style`: the determined merge strategy
- `delete_branch`: `true`
- For squash merges, also pass:
  - `title`: the composed squash commit title
  - `message`: the composed squash commit body

If the merge fails, report the error and skip to the next PR.

Record the merge timestamp for each successfully merged PR.

**Discord notification:** After each successful merge, post a "PR Merged" Discord notification using the green embed template:

!`cat $HOME/gitea-repos/development-skills/lib/discord-notify.md`

Read the webhook URL from `~/.config/development-skills/discord-webhook`. If the file doesn't exist, skip silently. Include the PR title, repo, PR number, and merge style in the notification. Use your agent name (derive it once at the start of the skill using the agent identity logic from `agent-identity.md`).

### Update local branch

After merging, if the current working directory is inside the merged repo (check with `git remote get-url origin`), update the local default branch to match:

```bash
git checkout {default_branch} && git pull origin {default_branch}
```

If the current branch is a feature branch that was just merged and deleted remotely, switch to the default branch first. This ensures the local repo stays in sync and avoids stale branch references.

If the current working directory is NOT inside the merged repo, check if the repo has a known local path (from the shorthand table). If it does, run the pull from that directory:

```bash
git -C {local_path} checkout {default_branch} && git -C {local_path} pull origin {default_branch}
```

If the local path doesn't exist or isn't a git repo, skip this step silently.

## Step 7: Check for deploy workflows

Dynamically discover whether each merged repo has a deploy workflow — do NOT rely on a hardcoded list.

For each merged repo:

1. Call `mcp__gitea__actions_run_read(method="list_workflows", owner="{owner}", repo="{repo}")` to get the list of workflow files in the repo
2. Look for any workflow with a filename matching `deploy*` (e.g., `deploy.yml`, `deploy.yaml`, `deploy-prod.yml`)
3. If a matching deploy workflow is found, record its filename and proceed to Step 8 for that PR
4. If no deploy workflow is found, skip to Step 10 for that PR

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

Dynamically discover whether the repo defines a post-merge health check — do NOT rely on a hardcoded list.

#### Discovering health checks from AGENTS.md

For each merged repo:

1. Fetch the repo's `AGENTS.md` from the default branch using `mcp__gitea__get_file_contents(owner, repo, ref=default_branch, filePath="AGENTS.md")`
2. Look for a `## Post-Merge Checklist` section in the file content
3. If the section exists, parse it for:
   - **Health check command** — a fenced code block after "Health check command:" (e.g. `scripts/check-managed.sh` or `curl -s http://example.com/health`)
   - **How to evaluate** — instructions below the command explaining how to interpret the output (exit codes, JSON parsing, expected response fields)
4. If the section does **not** exist, or `AGENTS.md` is missing, skip the health check — report deploy status only

#### Running the health check

If a health check command was found:
- If the command starts with `curl`, run it directly via Bash
- If the command is a script path (e.g. `scripts/check-managed.sh`), run it from the repo's local checkout (use the `Local path` from the shorthand table in `config/repos.md`)
- Follow the "How to evaluate" instructions from the same section to determine pass/fail

For repos **without a Post-Merge Checklist**: report deploy as "Passed" or "Failed" with no Health column value (use `—`).

If the health check **fails** (non-200 response, status not ok, services not ready, or script exits non-zero), create a Gitea issue:
```
Title: Health check failed after merging #{pr_index}
Body: PR #{pr_index} ({pr_title}) was merged and the deploy workflow completed successfully,
      but the health check returned an unexpected response:

      {response_body_or_script_output}

      Failed items: {failed_list}

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
| food-automation | #39 | refactor: enforce layer boundary | Merged (rebase, 1 commit) | Passed | Healthy | — |
| homelab-setup | #45 | feat(#40): add monitoring stack | Merged (squash, 3→1) | Failed | — | #46 created |
| recipe-readiness | #8 | fix: parser edge case | Merged (rebase, 1 commit) | N/A | N/A | — |
| food-automation | #40 | feat: new endpoint | Skipped | — | — | — (2 unaddressed comments) |
```

Keep the output concise. No fluff.
