---
name: deploy-status
description: Check deploy pipeline health — CI workflows on main, Flux reconciliation, and deployed app version. Offers to investigate and fix failures.
args: "[repo]"
allowed-tools: Read, Bash, Glob, Grep, Agent, AskUserQuestion, WebFetch, mcp__gitea__actions_run_read, mcp__gitea__actions_run_write, mcp__gitea__pull_request_read, mcp__gitea__get_file_contents, mcp__gitea__search_repos
---

# Deploy Status

Verify the full deployment pipeline for a repo: CI on main, Flux reconciliation, and deployed app version. Reports any failures and offers to investigate.

## Repo and Issue Resolution

!`cat $HOME/.claude/development-skills/lib/resolve-repo.md`

## Step 1: Parse arguments

Parse `$ARGUMENTS` using the resolution logic above. The user can provide:

- **Repo reference** (`repo`, `owner/repo`): check deploy status for that repo
- **No argument**: use `AskUserQuestion` to ask which repo (list repos from deploy config that have deploy workflows)

Resolve the `owner` and `repo`. Also resolve the local path from the repos shorthand table (optional — only needed for `git ls-remote` in Step 3d).

## Step 2: Load deploy config

Load the deploy configuration:

```bash
cat ~/.config/development-skills/deploy-config.md
```

If the file doesn't exist, stop and tell the user:
> Deploy config not found at `~/.config/development-skills/deploy-config.md`. Run `/setup-env deploy` to create it, or create it manually.

Look up the repo in **both** the Dev and Prod environment tables. If the repo is not in either table, it may not be a deployed service — report this and check CI only (skip Flux and version verification steps).

Store the resolved config for use in later steps.

## Step 3: Check latest CI workflows on main

**Always fetch fresh from remote — never rely on local git state.**

### 3a: List workflows in the repo

Use `mcp__gitea__actions_run_read` with `method: "list_workflows"` to discover all workflow files in the repo.

### 3b: Fetch latest runs for each workflow

For each workflow file discovered, fetch the latest run on the default branch:

```
mcp__gitea__actions_run_read
  method: list_runs
  owner: {owner}
  repo: {repo}
```

Filter results to runs on the default branch (`main` or `master`). For each workflow, find the **most recent** run by `created_at`.

### 3c: Check run status

For each latest run:
- `status: "completed"` + `conclusion: "success"` → **passed**
- `status: "completed"` + `conclusion: "failure"` → **failed**
- `status: "running"` or `status: "waiting"` → **in progress**
- No runs found → **no runs**

Record the run number, conclusion, commit SHA, created_at, and updated_at for each.

### 3d: Cross-reference deploy workflow

If the repo has a deploy config, verify that the deploy workflow specifically ran. Check that the deploy workflow's latest run SHA matches the latest commit on the default branch. If the deploy workflow is missing or hasn't run for the latest commit, flag this as a potential issue.

To get the latest commit on the default branch (always fresh from remote):

```bash
git ls-remote origin refs/heads/{default_branch} | cut -f1
```

Run this from the repo's local path. **If the result is empty** (branch doesn't exist or remote is unreachable), report "Unable to determine latest commit on {default_branch}" and skip version comparison in Step 5 — do not proceed with an empty SHA.

If the local path doesn't exist, use the Gitea API instead:

```
mcp__gitea__actions_run_read
  method: list_runs
  owner: {owner}
  repo: {repo}
```

Filter to runs on the default branch and extract the `head_sha` from the most recent run.

## Step 4: Check Flux status (deployed services only)

Skip this step if the repo is not in the deploy config tables.

Check if `~/.kube/qa-readonly-kubeconfig` exists and works:

```bash
kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig get nodes --request-timeout=5s 2>&1
```

If kubeconfig is unavailable, note this and skip to Step 5.

### 4a: Check prod HelmRelease

```bash
kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig \
  get helmrelease {prod_chart_name} -n {prod_namespace} \
  -o jsonpath='{.status.conditions[*].type} {.status.conditions[*].status} {.status.conditions[*].message}' 2>/dev/null
```

Also get the last applied revision:

```bash
kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig \
  get helmrelease {prod_chart_name} -n {prod_namespace} \
  -o jsonpath='{.status.lastAppliedRevision}' 2>/dev/null
```

### 4b: Check dev HelmRelease

```bash
kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig \
  get helmrelease {dev_chart_name} -n {dev_namespace} \
  -o jsonpath='{.status.conditions[*].type} {.status.conditions[*].status} {.status.conditions[*].message}' 2>/dev/null
```

```bash
kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig \
  get helmrelease {dev_chart_name} -n {dev_namespace} \
  -o jsonpath='{.status.lastAppliedRevision}' 2>/dev/null
```

### 4c: Check pod status

For each environment (prod and dev), check that pods are running:

```bash
kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig \
  get pods -n {namespace} -o wide --no-headers 2>/dev/null
```

Check for pods in CrashLoopBackOff, ImagePullBackOff, or other error states.

Also get the deployed image tag (filter to running pods to avoid stale data from terminating pods during rollouts):

```bash
kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig \
  get pods -n {namespace} --field-selector=status.phase=Running -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null
```

## Step 5: Verify deployed app version

Skip this step if the repo is not in the deploy config tables.

### 5a: Check prod version

Hit the prod health/version endpoint:

```bash
curl -sf --max-time 10 {prod_health_url}
```

If the repo has a version endpoint, also check it:

```bash
curl -sf --max-time 10 {prod_base_url}{version_endpoint}
```

Extract the `commit` or `BUILD_COMMIT` field from the response. Compare it against the **latest commit SHA on the default branch** (from Step 3d) — this is the authoritative target. If the deployed commit doesn't match, also check the latest successful deploy workflow run SHA to distinguish between "deploy hasn't run yet" vs "deploy ran but Flux hasn't rolled out."

If they don't match, flag as **version mismatch** — the deployed version is behind.

### 5b: Check dev version

```bash
curl -sf --max-time 10 {dev_health_url}
```

Extract version info and compare similarly.

### 5c: Smoke test endpoints

For each smoke endpoint listed in the deploy config, make a quick HTTP request:

```bash
curl -sf --max-time 10 -o /dev/null -w "%{http_code}" {base_url}{endpoint}
```

Record the HTTP status code. Flag any non-2xx responses.

## Step 6: Build status report

Present a comprehensive status report:

```
## Deploy Status: {owner}/{repo}

### CI Workflows (main branch)

| Workflow | Status | Run # | SHA | Age |
|----------|--------|-------|-----|-----|
| {workflow_name} | {passed/failed/running} | #{run_number} | {sha_short} | {time_ago} |
| {workflow_name} | {passed/failed/running} | #{run_number} | {sha_short} | {time_ago} |

Latest commit on main: {sha_short} ({time_ago})
CI coverage: {all workflows ran for latest commit / some missing}

### Flux Status

| Environment | HelmRelease | Status | Chart Version | Pod Image |
|-------------|-------------|--------|---------------|-----------|
| Prod | {prod_chart_name} | {Ready/Not Ready} | {version} | {image_tag} |
| Dev | {dev_chart_name} | {Ready/Not Ready} | {version} | {image_tag} |

### App Verification

| Environment | Health | Version (deployed) | Version (expected) | Match |
|-------------|--------|--------------------|--------------------|-------|
| Prod | {healthy/unhealthy} | {commit_short} | {expected_short} | {yes/no} |
| Dev | {healthy/unhealthy} | {commit_short} | {expected_short} | {yes/no} |

### Smoke Tests

| Environment | Endpoint | Status |
|-------------|----------|--------|
| Prod | {endpoint} | {200/404/timeout} |
| Dev | {endpoint} | {200/404/timeout} |
```

Adapt the report based on what data is available — if kubeconfig is unavailable, omit the Flux and pod sections. If the repo isn't a deployed service, show only the CI section.

## Step 7: Handle failures

If any checks failed or show issues, present a summary of problems:

```
### Issues Found

1. {description of issue — e.g., "Deploy workflow failed on run #45"}
2. {description of issue — e.g., "Prod version (abc1234) does not match latest main (def5678)"}
3. {description of issue — e.g., "Dev health endpoint returning 502"}
```

Use `AskUserQuestion` with options tailored to the failures found:

- **Investigate failures** — launch an Agent to dig into the specific failures (fetch workflow logs, check pod logs, examine recent commits)
- **Force Flux reconcile** — trigger a Flux reconciliation for the affected environment
- **Redeploy** — trigger the deploy workflow manually (dispatch via Gitea Actions API)
- **Everything looks fine** — no action needed

### If user chooses "Investigate failures"

Launch an Agent with `subagent_type: "general-purpose"` to:

1. For CI failures: fetch the failing job's logs using `mcp__gitea__actions_run_read` with `method: "get_job_log"`, identify the error, and suggest a fix
2. For version mismatches: check if a deploy workflow ran for the latest commit, check if Flux has pending reconciliation, check HelmRelease events for errors
3. For health check failures: check pod logs via kubectl, check recent pod restarts, check HelmRelease status conditions for error messages

Present the findings and ask if the user wants to:
- **Fix it** — attempt to fix the identified issue (create a PR, re-trigger workflow, etc.)
- **Create an issue** — create a Gitea issue documenting the problem
- **Skip** — take no action

### If user chooses "Force Flux reconcile"

> **Note:** Despite the name `qa-readonly-kubeconfig`, this kubeconfig has write permissions for Flux annotation operations. The naming is a legacy artifact.

```bash
kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig \
  annotate helmrelease {chart_name} -n {namespace} \
  reconcile.fluxcd.io/requestedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite
```

Wait for Flux to process the reconciliation:

```bash
sleep 60
```

Then re-check the HelmRelease status and health endpoint. Report whether reconciliation resolved the issue.

### If user chooses "Redeploy"

Use `AskUserQuestion` to confirm before dispatching: "This will trigger a production deploy of `{owner}/{repo}` from `{default_branch}`. Proceed?"

If confirmed, dispatch the deploy workflow:

```
mcp__gitea__actions_run_write
  method: dispatch_workflow
  owner: {owner}
  repo: {repo}
  workflow_id: {deploy_workflow}
  ref: {default_branch}
```

Then follow the same wait-and-verify pattern as the `/deploy-dev` skill (poll for run completion, check health).

## Step 8: Summary

If no issues were found, report concisely:

> All clear — CI passing{", Flux healthy" if Flux was checked}{", deployed version matches latest main" if version was verified}.

If issues were found and addressed, report what was done. If issues remain unresolved, list them clearly.
