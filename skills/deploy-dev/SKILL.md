---
name: deploy-dev
description: Deploy a PR or branch to the dev environment for a repo.
args: "[repo#PR | repo branch-name]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, mcp__gitea__get_pull_request_by_index, mcp__gitea__list_repo_action_runs, mcp__gitea__actions_run_write, mcp__gitea__actions_run_read, mcp__gitea__create_issue_comment
---

# Dev Deploy

Deploy a PR or branch to the dev environment. Triggers the configured deploy workflow, waits for completion, verifies the deployment is healthy, and optionally posts a PR comment with results.

## Repo and Issue Resolution

!`cat $HOME/.claude/development-skills/lib/resolve-repo.md`

## Step 1: Parse arguments

Parse `$ARGUMENTS` using the resolution logic above. The user can provide:

- **PR reference** (`repo#N`, `owner/repo#N`, or a URL): deploy the PR's head branch
- **Branch reference** (`repo branch-name`): deploy the named branch directly

If a PR reference is provided, fetch the PR using `mcp__gitea__get_pull_request_by_index` and extract:
- Head branch name
- Head SHA
- PR title
- Whether the PR is still open

If a branch name is provided directly, use it as-is. There will be no PR context for comments.

If no arguments are provided, ask the user what to deploy.

## Step 2: Load deploy config

Load the deploy configuration from `~/.config/development-skills/deploy-config.md`.

```bash
cat ~/.config/development-skills/deploy-config.md
```

If the file doesn't exist, stop and tell the user:
> Deploy config not found at `~/.config/development-skills/deploy-config.md`. Run `/setup-env deploy` to create it, or create it manually.

Look up the repo in the deploy configuration table. The table has these columns:

| Repo | Deploy workflow | Dev health URL | Dev base URL | Dev chart name | Dev namespace | Dev chart version pattern |
|------|----------------|----------------|--------------|----------------|---------------|--------------------------|

If the repo is **not in the table**, stop and tell the user:
> Repo `{owner}/{repo}` does not have a dev deploy configuration. Run `/setup-env deploy` to add it, or edit `~/.config/development-skills/deploy-config.md` manually.

Store the resolved config for use in later steps.

## Step 3: Check current deployment state

If a kubeconfig is available, check what's currently deployed to avoid unnecessary deploys:

1. Check if `~/.kube/qa-readonly-kubeconfig` exists and works:
   ```bash
   kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig get nodes --request-timeout=5s 2>&1
   ```

2. If the kubeconfig works, check the currently deployed chart version:
   ```bash
   kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig \
     get helmrelease {dev_chart_name} -n {dev_namespace} \
     -o jsonpath='{.status.lastAppliedRevision}' 2>/dev/null
   ```

3. Check the health endpoint:
   ```bash
   curl -sf {dev_health_url}
   ```

Report current state to the user before proceeding.

## Step 3b: Ensure branch is up to date with base

Before deploying, check if the head branch includes the latest changes from the base branch (usually `main`). Deploying a stale branch risks testing code that's missing recent fixes or has hidden conflicts.

1. Resolve the Gitea API token (needed for the update-branch API):
   ```bash
   ps aux | grep 'gitea-mcp.*-token' | grep -v grep | head -1 | grep -oP '(?<=-token )\S+'
   ```

2. If a PR reference was provided, use the Gitea update-branch API to rebase server-side:
   ```bash
   curl -s -w "\n%{http_code}" -X POST \
     "https://git.home.superwerewolves.ninja/api/v1/repos/{owner}/{repo}/pulls/{index}/update" \
     -H "Authorization: token {GITEA_TOKEN}" \
     -H "Content-Type: application/json" \
     -d '{"style": "rebase"}'
   ```

   Interpret the response:
   - **HTTP 200**: Branch was rebased onto latest base. Wait 5 seconds for the ref to update, then re-fetch the PR to get the new head SHA.
   - **HTTP 409**: Merge conflicts — warn the user and stop. The branch needs manual conflict resolution before deploying.
   - **HTTP 422**: Already up to date — proceed.

3. If a branch name was provided directly (no PR context), use the local repo checkout to check:
   ```bash
   cd {local_path}
   git fetch origin
   git merge-base --is-ancestor origin/{default_branch} origin/{head_branch}
   ```
   - If the check passes (exit 0): branch already contains latest base — proceed.
   - If it fails: warn the user that the branch is behind the base branch. Use `AskUserQuestion` with options:
     - **Deploy anyway** — proceed without rebasing
     - **Cancel** — stop and suggest running `/update-prs` first

## Step 4: Trigger deploy workflow

Dispatch the deploy workflow using the Gitea Actions API:

```
mcp__gitea__actions_run_write
  method: dispatch_workflow
  owner: {owner}
  repo: {repo}
  workflow_id: {deploy_workflow}
  ref: {head_branch}
  inputs: { "environment": "dev" }
```

Tell the user the workflow has been dispatched.

## Step 5: Wait for workflow completion

1. Wait 15 seconds for the action to register.
2. Call `mcp__gitea__list_repo_action_runs` looking for a run with:
   - `event: "workflow_dispatch"`
   - Branch matching the dispatched branch
   - Created after the dispatch timestamp
3. Poll every 30 seconds for up to 5 minutes to find the run.
4. Once found, poll every 30 seconds for up to 10 minutes for completion.
5. Report the result:
   - **success** — proceed to Step 6
   - **failure** — report the failure and stop. Suggest checking the workflow run logs.

If the run cannot be found after 5 minutes, stop and tell the user:
> Could not find the workflow run. Check the Actions tab for `{owner}/{repo}` manually.

## Step 6: Force Flux reconciliation and wait for rollout

After the workflow succeeds, force Flux to pick up the new chart immediately instead of waiting for the next poll cycle (which can be up to 30 minutes):

1. Wait 30 seconds for the chart to propagate to the OCI registry.
2. If kubeconfig is available, force Flux to reconcile the HelmRelease:
   ```bash
   kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig \
     annotate helmrelease {dev_chart_name} -n {dev_namespace} \
     reconcile.fluxcd.io/requestedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite 2>&1
   ```
   This triggers an immediate reconciliation without needing the `flux` CLI. If this fails (permissions, kubeconfig issues), fall back to passive polling in step 3.
3. Poll the dev health URL every 30 seconds for up to 10 minutes:
   ```bash
   curl -sf {dev_health_url}
   ```
4. Check if the service is healthy (HTTP 200).

**Timeout behavior:** If the health endpoint doesn't return a healthy response within 10 minutes, report that Flux rollout may not have completed but the deploy workflow itself succeeded. Suggest checking the HelmRelease status manually.

## Step 7: Verify deployment

Gather verification evidence:

1. **HelmRelease version** (if kubeconfig available):
   ```bash
   kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig \
     get helmrelease {dev_chart_name} -n {dev_namespace} \
     -o jsonpath='{.status.lastAppliedRevision}' 2>/dev/null
   ```

2. **Pod image** (if kubeconfig available):
   ```bash
   kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig \
     get pods -n {dev_namespace} -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null
   ```

3. **Health endpoint response**:
   ```bash
   curl -sf {dev_health_url}
   ```

## Step 8: Post PR comment (if PR context exists)

If the deploy was triggered from a PR reference, post a verification comment using `mcp__gitea__create_issue_comment`:

```markdown
**Dev Deploy** — deployed to dev

| Check | Value |
|-------|-------|
| Branch | `{head_branch}` (`{head_sha_short}`) |
| Workflow | `{deploy_workflow}` — {conclusion} |
| HelmRelease | `{helmrelease_version}` |
| Pod image | `{pod_image}` |
| Health | {health_status} (HTTP {status_code}) |
```

If kubeconfig was unavailable, omit the kubectl-based rows and note it.

## Step 9: Report to user

Tell the user:
1. Whether the deploy succeeded or failed
2. Workflow run status and link
3. Health endpoint status
4. HelmRelease and pod info (if kubeconfig available)
5. Link to the PR comment (if posted)
