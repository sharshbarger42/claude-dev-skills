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

Load the deploy configuration table from `~/.config/development-skills/deploy-config.md` and look up the repo.

!`cat ~/.config/development-skills/deploy-config.md`

If the file doesn't exist, stop and tell the user:
> Deploy config not found at `~/.config/development-skills/deploy-config.md`. Run `/setup-env` to create it, or create it manually with a table mapping repos to deploy workflows, dev URLs, and smoke endpoints.

If the repo is **not in the table**, stop and tell the user:
> Repo `{owner}/{repo}` does not have a dev deploy configuration. Add it to `~/.config/development-skills/deploy-config.md`.

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

## Step 5: Verify deployment and post evidence

After the deploy path completes (whether full deploy, skip-build, or skip-entirely), verify that the correct version is running on dev and post a PR comment with the evidence. This creates an auditable record of what was actually deployed and tested.

### Gather verification evidence

Run these checks and record the results:

1. **HelmRelease version** (if kubeconfig available):
   ```bash
   kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig \
     get helmrelease {dev_chart_name} -n {dev_namespace} \
     -o jsonpath='{.status.lastAppliedRevision}' 2>/dev/null
   ```
   Record the chart version (e.g., `0.1.0-dev.205`).

2. **Pod image SHA** (if kubeconfig available):
   ```bash
   kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig \
     get pods -n {dev_namespace} -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null
   ```
   Record the full image reference (includes tag or SHA).

3. **Health endpoint response**:
   ```bash
   curl -sf {dev_health_url}
   ```
   Record the full JSON response (includes version/commit info if the service exposes it).

4. **Expected values from the deploy**:
   - PR head SHA: `{head_sha}`
   - Chart version (from Step 3.6 or 4b): `{chart_version}`
   - Deploy workflow run number (if applicable): `#{run_number}`

### Post deployment verification comment

Post a PR comment using `mcp__gitea__create_issue_comment` with the evidence:

```markdown
🔍 **Deploy Verification** — confirmed on dev

| Check | Value |
|-------|-------|
| PR head SHA | `{head_sha_short}` |
| Chart version | `{chart_version}` |
| HelmRelease applied | `{helmrelease_version}` |
| Pod image | `{pod_image}` |
| Health endpoint | `{health_status}` (HTTP {status_code}) |
| Deploy path | {deploy_path — "full deploy", "existing chart", or "already deployed"} |

<details>
<summary>Verification commands</summary>

```
# HelmRelease version
kubectl --kubeconfig=~/.kube/qa-readonly-kubeconfig get helmrelease {dev_chart_name} -n {dev_namespace} -o jsonpath='{.status.lastAppliedRevision}'
→ {helmrelease_version}

# Pod image
kubectl --kubeconfig=~/.kube/qa-readonly-kubeconfig get pods -n {dev_namespace} -o jsonpath='{.items[0].spec.containers[0].image}'
→ {pod_image}

# Health check
curl -sf {dev_health_url}
→ {health_response_truncated}
```

</details>
```

**If kubeconfig is unavailable:** Skip the kubectl checks and note it in the comment. The health endpoint check is still performed — post whatever evidence is available.

**If the chart version or image doesn't match expectations:** Add a warning line to the comment: `⚠️ Version mismatch — expected chart {expected}, got {actual}. The deployed version may not match the PR.` Still proceed to smoke tests, but the mismatch will be visible in the audit trail.

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

1. **Assess testability first:** Determine whether the criterion can be verified via HTTP requests (curl) against the dev environment. A criterion is **testable** if it can be checked with HTTP requests, JSON response inspection, or HTML content checks. A criterion is **untestable** if it requires browser JavaScript execution, DOM interaction, visual inspection, or client-side state that cannot be observed via HTTP alone.
2. If **testable**: interpret it as an HTTP check, execute it against the dev environment, and record pass/fail
3. If **untestable**: record the result as `"skipped"` with detail explaining why (e.g., "Requires browser DOM inspection — cannot verify via HTTP")
4. Mark the criterion source as `issue` (vs `smoke` for the default tests)

**Human verification criteria are NOT executed** — they are included in the results table as `PENDING` with a note that human signoff is required.

**CRITICAL:** A criterion marked `skipped` is NOT the same as `passed`. Skipped criteria count against the overall QA verdict — see Step 8.

### Collecting results

Build a results list. The `passed` field has four possible values:
- `true` — test executed and passed
- `false` — test executed and failed
- `"skipped"` — automated criterion that could not be tested via HTTP (requires browser, DOM, etc.)
- `"pending"` — human verification criterion (never executed)

```
[
  { "name": "Health check", "source": "smoke", "endpoint": "/api/health", "status": 200, "passed": true, "detail": "" },
  { "name": "Task list", "source": "smoke", "endpoint": "/api/tasks", "status": 500, "passed": false, "detail": "Internal server error: database locked" },
  { "name": "Dashboard loads under 5s", "source": "issue", "endpoint": "/", "status": 200, "passed": true, "detail": "Loaded in 1.2s" },
  { "name": "selectTask shows state: coding", "source": "issue", "endpoint": "-", "status": "-", "passed": "skipped", "detail": "Requires browser DOM inspection — cannot verify via HTTP" },
  { "name": "Human verification", "source": "issue", "endpoint": "-", "status": "-", "passed": "pending", "detail": "Owner confirms fix works" },
  ...
]
```

## Step 8: Post results as PR comment

Compose and post a PR comment using `mcp__gitea__create_issue_comment` with the QA results.

### Compute overall verdict

The verdict is determined by ALL results (smoke tests + issue criteria):

- **QA Passed** — every executed test passed AND zero criteria were skipped. All non-human criteria were verified.
- **QA Partial** — every executed test passed BUT some automated criteria were skipped (untestable via HTTP). The skipped criteria need manual or browser-based verification.
- **QA Failed** — one or more tests actually failed (returned wrong status, error, etc.)

**CRITICAL:** `skipped` criteria are NOT treated as passed. If any automated criterion was skipped, the verdict is **Partial** at best, never **Passed**.

### If ALL tests passed (no skipped, no failed)

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

All {N} tests passed. Ready for merge.
```

### Deploy summary line

The `{deploy_summary}` should reflect what happened:
- Full deploy: `Workflow run #{run_number} — {conclusion}`
- Chart existed, Flux waited: `Skipped build (chart from run #{existing_run_number}), waited for Flux rollout`
- Chart already deployed: `Skipped deploy (chart 0.1.0-dev.{run_number} already deployed)`

### If all executed tests passed BUT some criteria were skipped

```markdown
⚠️ **QA Partial** — some criteria could not be verified

**Branch:** `{head_branch}` ({head_sha_short})
**Deploy:** {deploy_summary}
**Environment:** dev

| Test | Endpoint | Status | Result |
|------|----------|--------|--------|
| Health check | `/api/health` | 200 | ✅ Pass |
| selectTask shows state | — | — | ⏭️ Skipped |
| ... | ... | ... | ... |

### Skipped criteria (require manual/browser verification)

| Criterion | Reason |
|-----------|--------|
| {criterion text} | {why it couldn't be tested — e.g., "Requires browser DOM inspection"} |
| ... | ... |

{passed_count}/{total_count} tests passed, {skipped_count} skipped. **Not ready for merge** — skipped criteria must be verified manually or via browser testing before approval.
```

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

### If all automated test criteria PASSED (none failed, none skipped):

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

### If no criteria failed BUT some were skipped:

1. Post a comment on the **issue**:

```markdown
⚠️ **QA Partial** — Some Test Criteria Could Not Be Verified

PR #{pr_number} was deployed to dev. No tests failed, but {skipped_count} automated criteria could not be verified via HTTP and need manual/browser verification:

| Criterion | Result | Detail |
|-----------|--------|--------|
| {criterion text} | ✅ Pass | |
| {criterion text} | ⏭️ Skipped | {reason — e.g., "Requires browser DOM inspection"} |
| ... | ... | ... |
| Human verification: {description} | ⏳ Pending | |

{passed_count}/{automated_count} automated criteria verified. **{skipped_count} criteria need manual/browser testing** before this can be approved.
```

2. **Do NOT update issue label** — leave it as-is (do NOT swap to `status: in-review`). The issue is not ready for human-only verification because automated criteria remain unverified.

### Step 8.6: Update issue checklist

After posting the issue comment, update the **issue body** to check off test criteria that passed during QA:

1. Fetch the current issue body via `mcp__gitea__get_issue_by_index`
2. For each automated criterion that **passed** (`passed: true`, actually executed and verified):
   - Find the matching `- [ ]` line in the issue body
   - Replace `- [ ]` with `- [x]`
   - Append a brief annotation: ` — *{verification_method} in PR #{pr_number}*`
     - `verification_method` is one of: `verified live`, `code-verified`, `smoke-tested`
3. For criteria that **failed**, leave them as `- [ ]` (unchecked)
4. For criteria that were **skipped** (untestable via HTTP), leave them as `- [ ]` (unchecked) — do NOT check them off. They were not verified.
5. For **human verification** criteria, always leave as `- [ ]`
6. Use `mcp__gitea__issue_write` with `method: "update"` to save the updated body

**Important:** Only modify the `- [ ]` / `- [x]` checkboxes and append annotations. Do not alter any other part of the issue body.

**CRITICAL:** Never mark a criterion as `[x]` unless it was actually executed and returned a passing result (`passed: true`). Criteria with `passed: "skipped"` or `passed: "pending"` must remain unchecked.

### If no linked issue:

Skip this step entirely — only post the PR comment from Step 8.

## Step 9: Report to user

After posting the PR comment, tell the user:
1. Whether QA passed, partially passed, or failed
2. How many tests passed/failed/skipped (split by smoke tests vs issue test criteria)
3. Link to the PR comment
4. If a linked issue was found: link to the issue comment and current label status
5. If failed, a brief summary of what broke
6. If partial, list which criteria were skipped and why — these need manual verification
7. If passed, remind that human verification is still pending (if applicable)
