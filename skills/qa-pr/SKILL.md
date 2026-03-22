---
name: qa-pr
description: Deploy a PR to dev environment and verify it's working. Posts QA results as PR comments.
args: "<repo>#<pr_number>"
---

# QA PR Skill

Deploy a pull request to the dev environment and run smoke tests. Posts results as a PR comment — pass or fail with details.

**Input:** PR reference as the skill argument. Accepted formats:
- Shorthand: `food-automation#32`
- Owner/repo: `super-werewolves/food-automation#32`
- Full URL: `https://git.home.superwerewolves.ninja/super-werewolves/food-automation/pulls/32`

## Step 1: Parse the PR reference

Extract `owner`, `repo`, and PR `index` from the argument.

### Repo resolution

!`cat $HOME/.claude/development-skills/lib/resolve-repo.md`

## Step 2: Fetch PR metadata

Use `mcp__gitea__get_pull_request_by_index` with the parsed `owner`, `repo`, and `index` to get:
- PR title
- Head branch and head SHA
- Base branch
- Whether the PR is still open

If the PR is not found, report the error and stop.
If the PR is already merged or closed, stop and tell the user.

## Step 3: Resolve deploy config

Look up the repo in this deploy configuration table:

| Repo | Deploy workflow | Dev health URL | Dev base URL | Smoke endpoints | Dev chart name | Dev namespace | Dev chart version pattern |
|------|----------------|----------------|--------------|-----------------|----------------|---------------|--------------------------|
| `multi-agent-coordinator` | `deploy.yml` | `https://agents.apps.superwerewolves.ninja/api/health` | `https://agents.apps.superwerewolves.ninja` | `/api/health`, `/api/tasks`, `/api/metrics`, `/api/agents`, `/` | `multi-agent-coordinator-dev` | `multi-agent-coordinator-dev` | `0.1.0-dev.{run_number}` |
| `food-automation` | `deploy.yaml` | `https://food-dev.apps.superwerewolves.ninja/api/health` | `https://food-dev.apps.superwerewolves.ninja` | `/api/health` | `food-automation-dev` | `food-automation-dev` | `0.1.0-dev.{run_number}` |

If the repo is **not in this table**, stop and tell the user:
> Repo `{owner}/{repo}` does not have a dev deploy configuration. Add it to the qa-pr skill's deploy config table.

Store the resolved config for use in later steps.

## Step 3.5: Ensure kubeconfig

A read-only kubeconfig is needed to query the k3s dev cluster. Check if one exists and is usable:

1. Check if `~/.kube/qa-readonly-kubeconfig` exists and works:
   ```bash
   kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig get nodes --request-timeout=5s 2>&1
   ```
2. If it succeeds (exit code 0), the kubeconfig is valid — proceed to Step 3.6.
3. If it fails or the file doesn't exist:
   a. Trigger the `generate-kubeconfig.yml` workflow in `super-werewolves/homelab-setup`:
      ```
      mcp__gitea__actions_run_write
        action: dispatch_workflow
        owner: super-werewolves
        repo: homelab-setup
        workflow: generate-kubeconfig.yml
        ref: main
      ```
   b. Wait 10 seconds, then poll for the workflow run (same pattern as Step 5 — look for the most recent `workflow_dispatch` run, poll every 15 seconds for up to 5 minutes)
   c. Once the run succeeds, download the kubeconfig artifact:
      ```bash
      # List artifacts for the run
      curl -sf -H "Authorization: token $(cat ~/.gitea-token 2>/dev/null || echo $GITEA_TOKEN)" \
        "https://git.home.superwerewolves.ninja/api/v1/repos/super-werewolves/homelab-setup/actions/runs/{run_id}/artifacts" | jq .

      # Download the artifact file
      curl -sf -H "Authorization: token $(cat ~/.gitea-token 2>/dev/null || echo $GITEA_TOKEN)" \
        "https://git.home.superwerewolves.ninja/api/v1/repos/super-werewolves/homelab-setup/actions/artifacts/{artifact_id}" \
        -o /tmp/kubeconfig-artifact.zip

      # Extract and install
      mkdir -p ~/.kube
      unzip -o /tmp/kubeconfig-artifact.zip -d /tmp/kubeconfig-extract
      cp /tmp/kubeconfig-extract/qa-readonly-kubeconfig ~/.kube/qa-readonly-kubeconfig
      chmod 600 ~/.kube/qa-readonly-kubeconfig
      ```
   d. Verify the new kubeconfig works with the same `kubectl get nodes` test
   e. If it still fails, warn the user but continue — Steps 3.6 and 3.7 will be skipped and the full deploy path will be used

## Step 3.6: Check if chart already exists for this SHA

Check whether a deploy workflow has already built a chart for the PR's head SHA:

1. Use `mcp__gitea__actions_run_read` with `list_runs` to list workflow runs for the repo, filtering to the head branch
2. Look for a run with ALL of:
   - `head_sha` matching the PR's head SHA
   - `event: "workflow_dispatch"`
   - `conclusion: "success"`
   - `status: "completed"` (not waiting/running)
3. If a matching run is found:
   - Extract `run_number` from the run
   - Compute the chart version using the pattern from deploy config: e.g., `0.1.0-dev.{run_number}`
   - Record: `chart_exists = true`, `chart_version`, `existing_run_number`, `existing_run_id`
4. If no matching run is found:
   - Record: `chart_exists = false`

## Step 3.7: Check what's currently deployed on k3s dev

If kubeconfig is available (Step 3.5 succeeded), query the Flux HelmRelease to see what version is currently deployed:

```bash
kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig \
  get helmrelease {dev_chart_name} -n {dev_namespace} \
  -o jsonpath='{.status.lastAppliedRevision}' 2>/dev/null
```

This returns the currently deployed chart version (e.g., `0.1.0-dev.202`).

- If the command succeeds, record `deployed_version` (the output)
- If it fails (HelmRelease not found, kubeconfig issue), record `deployed_version = unknown`

## Step 4: Deploy decision

Based on Steps 3.6 and 3.7, decide what to do:

| Chart exists? (3.6) | Matches deployed? (3.7) | Action |
|---|---|---|
| No | N/A | **Full deploy** — trigger workflow, wait for build, wait for Flux (Steps 4a + 4b + 4c) |
| Yes | Yes (same version) | **Skip entirely** — go straight to smoke tests (Step 7). Post comment: "Chart `{dev_chart_name}:{chart_version}` already built and deployed — skipping to smoke tests." |
| Yes | No (different version) | **Skip build, wait for Flux** — skip workflow trigger, go to Step 4c only. Post comment: "Chart `{dev_chart_name}:{chart_version}` already exists from run #{existing_run_number}. Currently deployed: `{deployed_version}` — waiting for Flux to reconcile." |

If kubeconfig was unavailable (Step 3.5 failed) and chart exists, treat as "Yes / No" (skip build, wait for Flux) since we can't confirm what's deployed.

### Step 4a: Trigger dev deployment (only if chart does NOT exist)

Dispatch the deploy workflow targeting the **dev** environment from the PR's **head branch**:

```
mcp__gitea__dispatch_repo_action_workflow
  owner: {owner}
  repo: {repo}
  workflow_id: {deploy_workflow}
  ref: {head_branch}
  inputs: { "environment": "dev" }
```

If the dispatch fails, post a PR comment with the error and stop.

After dispatching, post a brief PR comment:
```
🔄 **QA deploy started** — deploying `{head_branch}` ({head_sha_short}) to dev environment.
```

### Step 4b: Wait for build + deploy workflow to complete (only if chart does NOT exist)

1. Wait 15 seconds for the action to register
2. Call `mcp__gitea__list_repo_action_runs` and look for a run:
   - On the head branch (matching `head_sha` or `head_branch`)
   - With `event: "workflow_dispatch"`
   - Created after the dispatch timestamp
3. If no run found yet, poll every 30 seconds for up to 5 minutes
4. Once the run is found, poll its status every 30 seconds for up to 10 minutes:
   - `success` — proceed to Step 4c
   - `failure` — jump to Step 8 (report failure)
   - Still running — keep polling

If no run is found after 5 minutes, jump to Step 8 with error: "Deploy workflow did not trigger within 5 minutes."

Record the run ID and conclusion for the report.

### Step 4c: Wait for Flux rollout (skip if chart already deployed)

Flux CD picks up new Helm chart versions from the OCI registry. After a chart is pushed, Flux needs time to detect and apply it.

1. Wait 30 seconds for the chart to propagate to the registry
2. Poll the dev health URL (from Step 3) every 30 seconds for up to 15 minutes:
   - Make a `curl -sf {dev_health_url}` request via Bash
   - Parse the JSON response
   - Check if the service is healthy (HTTP 200 with expected status)
3. The rollout is considered complete when:
   - The health endpoint returns HTTP 200
   - The response indicates healthy status

**Timeout behavior:** If the health endpoint doesn't return a healthy response within 15 minutes, proceed to Step 7 with a warning that Flux rollout may not have completed. The smoke tests will catch any remaining issues.

**Note:** Flux polls every 30 minutes, so this step may take a while. If the health endpoint was already healthy before the deploy (from a previous deployment), the smoke tests in Step 7 are the real validation — the health check here is just a gate to ensure the service is reachable.

## Step 6.5: Fetch issue test criteria

If the PR body contains `Closes #N` or `Fixes #N`, extract the linked issue number and fetch it:

1. Parse the PR body for issue references matching `Closes #(\d+)` or `Fixes #(\d+)` (case-insensitive)
2. If found, fetch the issue via `mcp__gitea__get_issue_by_index` with the parsed `owner`, `repo`, and issue `index`
3. Parse the issue body for a `## Test Criteria` section
4. Extract all checklist items (`- [ ] ...`) from that section — these are the **issue test criteria**
5. Separate them into:
   - **Automated criteria** — all items except the last "Human verification" item
   - **Human verification** — the final item starting with "Human verification:"
6. Store both lists for use in Step 7

If no linked issue is found, or the issue has no Test Criteria section, proceed with smoke tests only.

## Step 7: Run smoke tests

Run a series of smoke tests against the dev environment. Each test is a simple HTTP request that validates the endpoint returns a successful response with expected content.

### Test framework

For each test:
1. Make the HTTP request via Bash (`curl -sf -w "\n%{http_code}" {url}`)
2. Record: test name, URL, HTTP status code, pass/fail, and response body (truncated to 500 chars if large)
3. A test **passes** if:
   - HTTP status is 2xx
   - Response body is valid JSON (for API endpoints) or HTML (for frontend)
4. A test **fails** if:
   - HTTP status is non-2xx
   - Connection refused or timeout
   - Response body is not parseable or indicates an error state

### Test list

Run ALL smoke endpoints from the deploy config table (Step 3) against `{dev_base_url}`.

**For multi-agent-coordinator**, the tests are:

| Test | Endpoint | Pass criteria |
|------|----------|---------------|
| Health check | `GET /api/health` | HTTP 200, `status` is `"healthy"` or `"degraded"`, all components present |
| Task list | `GET /api/tasks` | HTTP 200, response is valid JSON with `tasks` array |
| Metrics | `GET /api/metrics` | HTTP 200, response is valid JSON |
| Agent slots | `GET /api/agents` | HTTP 200, response is valid JSON with `agents` array |
| Dashboard | `GET /` | HTTP 200, response contains `<html` |

**For food-automation**, the tests are:

| Test | Endpoint | Pass criteria |
|------|----------|---------------|
| Health check | `GET /api/health` | HTTP 200, response contains `"status"` |

### Issue test criteria (from Step 6.5)

After running smoke tests, run each **automated criterion** from the issue's Test Criteria section. For each criterion:

1. Interpret the criterion as a testable check (e.g., "GET /api/health returns HTTP 200" → `curl` the endpoint and check status)
2. Execute the check against the dev environment
3. Record result with same pass/fail structure as smoke tests
4. Mark the criterion source as `issue` (vs `smoke` for the default tests)

**Human verification criteria are NOT executed** — they are included in the results table as `PENDING` with a note that human signoff is required.

### Collecting results

Build a results list:
```
[
  { "name": "Health check", "source": "smoke", "endpoint": "/api/health", "status": 200, "passed": true, "detail": "" },
  { "name": "Task list", "source": "smoke", "endpoint": "/api/tasks", "status": 500, "passed": false, "detail": "Internal server error: database locked" },
  { "name": "Dashboard loads under 5s", "source": "issue", "endpoint": "/", "status": 200, "passed": true, "detail": "Loaded in 1.2s" },
  { "name": "Human verification", "source": "issue", "endpoint": "-", "status": "-", "passed": "pending", "detail": "Owner confirms fix works" },
  ...
]
```

## Step 8: Post results as PR comment

Compose and post a PR comment using `mcp__gitea__create_issue_comment` with the QA results.

### If ALL tests passed

```markdown
✅ **QA Passed** — dev deployment verified

**Branch:** `{head_branch}` ({head_sha_short})
**Deploy:** {deploy_summary}
**Environment:** dev

| Test | Endpoint | Status | Result |
|------|----------|--------|--------|
| Health check | `/api/health` | 200 | ✅ Pass |
| Task list | `/api/tasks` | 200 | ✅ Pass |
| ... | ... | ... | ... |

All {N} smoke tests passed. Ready for merge.
```

### Deploy summary line

The `{deploy_summary}` should reflect what happened:
- Full deploy: `Workflow run #{run_number} — {conclusion}`
- Chart existed, Flux waited: `Skipped build (chart from run #{existing_run_number}), waited for Flux rollout`
- Chart already deployed: `Skipped deploy (chart 0.1.0-dev.{run_number} already deployed)`

### If ANY tests failed

```markdown
❌ **QA Failed** — dev deployment has issues

**Branch:** `{head_branch}` ({head_sha_short})
**Deploy:** {deploy_summary}
**Environment:** dev

| Test | Endpoint | Status | Result |
|------|----------|--------|--------|
| Health check | `/api/health` | 200 | ✅ Pass |
| Task list | `/api/tasks` | 500 | ❌ Fail |
| ... | ... | ... | ... |

### Failures

**Task list** (`/api/tasks`) — HTTP 500
```
{truncated response body or error message}
```

**{other failures...}**

{passed_count}/{total_count} tests passed. See failures above for details.
```

### If deploy itself failed

```markdown
❌ **QA Failed** — dev deployment failed

**Branch:** `{head_branch}` ({head_sha_short})
**Deploy:** Workflow run #{run_number} — failure
**Environment:** dev

The deploy workflow failed before smoke tests could run. Check the [workflow run]({run_url}) for details.
```

## Step 8.25: Update PR status label

!`cat $HOME/.claude/development-skills/lib/pr-status-labels.md`

After posting the PR comment, update the PR's status label:

- **QA passed, no human verification needed** → set `pr: ready-to-merge`
- **QA passed, human verification still needed** → keep `pr: needs-qa` (human step remaining)
- **QA failed** → set `pr: comments-pending` (needs fixes before re-test)

Use the PR status label swap procedure from pr-status-labels.md.

## Step 8.5: Post results on linked issue and update labels

If a linked issue was found in Step 6.5:

### If any automated test criteria FAILED:

1. Post a comment on the **issue** (not just the PR) using `mcp__gitea__create_issue_comment`:

```markdown
❌ **QA Failed** — Test Criteria Failures

PR #{pr_number} was deployed to dev and tested. The following test criteria from this issue failed:

| Criterion | Result | Detail |
|-----------|--------|--------|
| {criterion text} | ❌ Fail | {failure detail} |
| {criterion text} | ✅ Pass | |
| ... | ... | ... |

{failed_count}/{automated_count} automated criteria failed. The fix needs to address these failures before retesting.
```

2. **Update issue label:** Swap `status: ready-to-test` or `status: in-review` to `status: in-progress` (signals that `/do-issue` should pick this up and fix the failures)

### If all automated test criteria PASSED:

1. Post a comment on the **issue**:

```markdown
✅ **QA Passed** — Automated Test Criteria Verified

PR #{pr_number} was deployed to dev. All automated test criteria passed:

| Criterion | Result |
|-----------|--------|
| {criterion text} | ✅ Pass |
| ... | ... |
| Human verification: {description} | ⏳ Pending |

All {automated_count} automated criteria passed. **Human verification still required** — this issue needs manual signoff before it can be closed.
```

2. **Update issue label:** Swap current status to `status: in-review` (signals that human verification is the remaining gate)

### Step 8.6: Update issue checklist

After posting the issue comment, update the **issue body** to check off test criteria that passed during QA:

1. Fetch the current issue body via `mcp__gitea__get_issue_by_index`
2. For each automated criterion that **passed** (including code-verified):
   - Find the matching `- [ ]` line in the issue body
   - Replace `- [ ]` with `- [x]`
   - Append a brief annotation: ` — *{verification_method} in PR #{pr_number}*`
     - `verification_method` is one of: `verified live`, `code-verified`, `smoke-tested`
3. For criteria that **failed**, leave them as `- [ ]` (unchecked)
4. For **human verification** criteria, always leave as `- [ ]`
5. Use `mcp__gitea__issue_write` with `method: "update"` to save the updated body

**Important:** Only modify the `- [ ]` / `- [x]` checkboxes and append annotations. Do not alter any other part of the issue body.

### If no linked issue:

Skip this step entirely — only post the PR comment from Step 8.

## Step 9: Report to user

After posting the PR comment, tell the user:
1. Whether QA passed or failed
2. How many tests passed/failed (split by smoke tests vs issue test criteria)
3. Link to the PR comment
4. If a linked issue was found: link to the issue comment and current label status
5. If failed, a brief summary of what broke
6. If passed, remind that human verification is still pending (if applicable)
