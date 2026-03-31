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

**QA tests deployed code only.** Unit tests, linting, and formatting are development-phase checks run by `/do-issue`. QA verifies that the deployed application works end-to-end in the dev environment.

## Step 1: Parse the PR reference

Extract `owner`, `repo`, and PR `index` from the argument.

### Repo resolution

!`cat $HOME/.config/development-skills/lib/resolve-repo.md`

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
      GITEA_TOKEN=$(ps aux | grep 'gitea-mcp.*-token' | grep -v grep | head -1 | grep -oP '(?<=-token )\S+')
      curl -sf -H "Authorization: token $GITEA_TOKEN" \
        "https://git.home.superwerewolves.ninja/api/v1/repos/super-werewolves/homelab-setup/actions/runs/{run_id}/artifacts" | jq .

      # Download the artifact file
      curl -sf -H "Authorization: token $GITEA_TOKEN" \
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
3. Parse the issue body for a `## Test Criteria` section (also check `## Acceptance criteria` for older issues)
4. Extract all checklist items (`- [ ] ...` and `- [x] ...`) from that section — these are the **issue test criteria**

If no linked issue is found, or the issue has no Test Criteria section, proceed with smoke tests only.

### Test criteria labels

Every test criterion in the issue MUST start with one of these labels. These labels are the **sole determinant** of how the QA skill handles that criterion — there is no AI triage or judgment call.

| Label | Meaning | QA skill behavior | Verified on |
|-------|---------|-------------------|-------------|
| `[ai-verify]` | Fully testable by AI via HTTP requests against the dev environment | **Execute and report pass/fail.** No exceptions — the AI must run the test. | `dev` |
| `[local-test]` | Lint, unit tests, build, type-check (dev-phase) | **Not executed during QA — record as `skipped (dev-phase)`.** Verified during development by `/do-issue`. | `dev-phase` |
| `[ci-check]` | Verify CI/CD pipeline passed for this PR | **Check action run status via Gitea API and report pass/fail.** | `ci` |
| `[subtask-check]` | Verify all subtasks and/or blockers are completed | **Fetch linked issues, check all are closed. Report pass/fail.** | `n/a` |
| `[human-verify]` | Requires a human to verify (visual judgment, UX feel, interactive behavior) | **Skip execution.** Record as `pending`. The human will verify separately. | — |
| `[human-assist]` | AI sets up the environment and tells the human what to look for | **Execute setup, then describe expected outcome.** AI creates test data, hits APIs, and records what the human should see in the browser. Recorded as `pending-human-check` until the human confirms. | `dev` |
| `[post-merge]` | Can only be verified after merge to main (prod health checks, DNS, Flux reconciliation) | **Skip execution.** Record as `pending-post-merge`. These are verified by `/merge-prs` after merge. | `prod` (after merge) |

**Label rules:**
- If a criterion has no label, treat it as `[ai-verify]` (default — the AI tests it)
- The label must appear at the start of the criterion text, before any other content
- Labels are assigned when the issue is created (by `/create-issues`, `/gwt`, or manually). The QA skill does NOT reassign labels — it follows them exactly.

### Categorize criteria by label

Split extracted criteria into these lists:

1. **`ai_verify`** — criteria labeled `[ai-verify]` (or unlabeled). These MUST be executed against dev.
2. **`local_test`** — criteria labeled `[local-test]`. These are **not executed during QA** — they are verified during development by `/do-issue`. Record as `skipped (dev-phase)`.
3. **`ci_check`** — criteria labeled `[ci-check]`. These MUST be verified via Gitea API.
4. **`subtask_check`** — criteria labeled `[subtask-check]`. These MUST be verified via Gitea API.
5. **`human_verify`** — criteria labeled `[human-verify]`. These are recorded as pending.
6. **`human_assist`** — criteria labeled `[human-assist]`. The AI sets up the environment and documents what the human should see.
7. **`post_merge`** — criteria labeled `[post-merge]`. These are recorded as pending-post-merge.

### Step 6.7: Plan test execution

For each `[ai-verify]` and `[human-assist]` criterion, plan HOW to test it against the live dev environment. Do not plan execution for `[local-test]` criteria — those are development-phase checks handled by `/do-issue`.

1. **Read the criterion carefully** — understand what state or behavior it's verifying
2. **Identify prerequisite actions** — does the test require creating data first? (e.g., POST to ingest a ticket before checking its state)
3. **Identify the verification request** — what HTTP request proves the criterion? (e.g., GET the task and check `state` field)
4. **Plan the sequence** — prerequisite actions first, then verification
5. **For `[human-assist]`** — additionally plan what the human should observe in the browser after the AI sets up the state

**The dev environment exists for testing.** It is safe and expected to:
- Make POST/PUT/DELETE requests that create, modify, or delete data
- Trigger workflows, ingest tickets, advance tasks, etc.
- Create test data as needed to exercise the code path under test
- Check API responses that reflect frontend-visible state

Example plans:
- `[ai-verify]` criterion: `POST /support-tickets/ingest response includes "state": "coding"`
  → Plan: POST to `/support-tickets/ingest` with test payload, check response JSON for `state: "coding"`
- `[ai-verify]` criterion: `Task in coding column via API`
  → Plan: After ingesting a test ticket, GET `/api/tasks` and verify the task appears in the `coding` array
- `[human-assist]` criterion: `Task detail panel shows warning indicator for stuck task`
  → Plan: Create a stuck task via API (POST task, advance to coding, clear assigned_slot). Then tell the human: "Open the dashboard, click on task {id}. You should see: (1) a warning badge on the Kanban card, (2) 'none' in orange/red text for assigned_agent in the detail panel."

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

After running smoke tests, execute the issue test criteria by label. Follow the test execution plan from Step 6.7.

#### `[ai-verify]` criteria — execute and report

1. **Execute every `[ai-verify]` criterion live.** There is no "skip" option. The dev environment exists for testing — use it.
2. **Create test data if needed.** If a criterion requires specific state (e.g., a task in "coding" state), create that state by making the appropriate API calls before verifying.
3. **Test the API that drives the UI.** Frontend criteria that mention DOM elements, Kanban columns, or detail panels are testing that the API returns correct data. Verify the API response contains the expected values.
4. **Mark the criterion source as `issue`** and label as `ai-verify`.
5. **There is no "skipped" status.** Every `[ai-verify]` criterion must be either `passed` or `failed`. Infrastructure issues (endpoint down, 500 error) = `failed`.

#### `[local-test]` criteria — not executed during QA

**`[local-test]` criteria are not executed during QA.** They are verified during development by `/do-issue`. If present, record them as `skipped (dev-phase)` in the results.

For each `[local-test]` criterion:
1. **Record result** as `"skipped (dev-phase)"` with detail: `"Verified during development by /do-issue"`
2. **Set `verified_on: "dev-phase"`** for each result.

#### `[ci-check]` criteria — verify CI passed

1. **Run the shared check-ci procedure** (same as merge-prs Step 4):
   - Re-fetch the PR for fresh HEAD SHA
   - Check commit statuses and cross-reference with action runs
2. **Record result:**
   - CI `passed` → criterion passes
   - CI `failed` → criterion fails, include failing workflow name and run URL
   - CI `running` → criterion recorded as `pending-ci` (still in progress)
   - CI `no-ci` → criterion passes (no CI configured for this repo)
3. **Set `verified_on: ci`** for each result.

#### `[subtask-check]` criteria — verify subtasks and blockers completed

1. **Parse the PR body and linked issue body** for issue references:
   - Look for `Sub-issue of #N`, `Blocked by #N`, `Depends on #N`, `Part of #N`
   - Look for checklist items with `#N` references (e.g., `- [ ] #42 — description`)
   - Look for a `## Sub-tasks` or `## Dependencies` section with issue links
2. **Fetch each referenced issue** via `mcp__gitea__get_issue_by_index`
3. **Check status:**
   - If the issue is `closed` → OK
   - If the issue is `open` with label `status: done` → OK
   - Otherwise → blocker not resolved
4. **Record result:**
   - All referenced issues closed → criterion passes
   - Any open blockers → criterion fails, list the open issues by number and title
5. **Set `verified_on: n/a`** for each result.

#### `[post-merge]` criteria — record as pending

These cannot be executed before merge. For each `[post-merge]` criterion:
1. **Record as `pending-post-merge`** with a note that this will be verified after merge by `/merge-prs`.
2. **Set `verified_on: prod (pending)`**.
3. Include the criterion text verbatim so it can be picked up by the post-merge verification step.

#### `[human-assist]` criteria — set up environment, then describe

1. **Execute all setup steps** — create test data, make API calls, put the system into the state the criterion requires. This is AI work.
2. **Verify the API state** — confirm via API that the setup succeeded (e.g., the task exists, it's in the right state, the endpoint returns expected data).
3. **Document what the human should see** — write a clear, specific description of:
   - What URL to open in the browser
   - What to click or navigate to
   - What they should see (specific text, colors, indicators, layout)
   - What would indicate failure
4. **Record the result as `pending-human-check`** with the setup status (succeeded/failed) and the human instructions.
5. If the **setup itself fails** (API errors, can't create test data), record as `failed` — the AI part didn't work.

Example result for `[human-assist]`:
```
{
  "name": "Stuck task shows warning indicator on Kanban card",
  "label": "human-assist",
  "setup_status": "succeeded",
  "setup_detail": "Created task dd-test-1 in CODING state with empty assigned_slot via POST /api/tasks. Task has been in this state for >60s. API confirms: GET /api/action-required returns item with source:'stuck', task_id:'dd-test-1'.",
  "human_instructions": "Open https://dev-agents.apps.superwerewolves.ninja in browser. Look at the Kanban board 'coding' column. Task 'dd-test-1' should show: (1) a warning badge or icon indicating no assigned agent, (2) orange/red 'none' text for assigned_agent in the detail panel when clicked.",
  "passed": "pending-human-check"
}
```

#### `[human-verify]` criteria — record as pending

These are NOT executed. Record each as `pending` with a note that human signoff is required. The human will verify these independently.

### Collecting results

Build a results list. The `passed` field has these possible values:
- `true` — test executed and passed (smoke tests + `[ai-verify]` + `[ci-check]` + `[subtask-check]`)
- `false` — test executed and failed (any automated criterion)
- `"skipped (dev-phase)"` — `[local-test]` criterion (verified during development by `/do-issue`, not during QA)
- `"pending-human-check"` — `[human-assist]` criterion where AI setup succeeded, awaiting human confirmation
- `"pending"` — `[human-verify]` criterion (never executed)
- `"pending-post-merge"` — `[post-merge]` criterion (cannot run until after merge to main)
- `"pending-ci"` — `[ci-check]` criterion where CI is still running

Every result MUST include a `verified_on` field indicating where the test was executed:
- `"dev-phase"` — verified during development, not during QA (`[local-test]`)
- `"dev"` — ran against dev environment (`[ai-verify]`, `[human-assist]`, smoke tests)
- `"ci"` — verified via CI/CD pipeline status (`[ci-check]`)
- `"prod"` — verified on production (only after merge, used by `/merge-prs`)
- `"n/a"` — not environment-specific (`[subtask-check]`, `[human-verify]`)

```
[
  { "name": "Health check", "source": "smoke", "label": "smoke", "endpoint": "/api/health", "status": 200, "passed": true, "verified_on": "dev", "detail": "" },
  { "name": "Task list", "source": "smoke", "label": "smoke", "endpoint": "/api/tasks", "status": 500, "passed": false, "verified_on": "dev", "detail": "Internal server error: database locked" },
  { "name": "Lint passes", "source": "issue", "label": "local-test", "endpoint": "-", "status": "-", "passed": "skipped (dev-phase)", "verified_on": "dev-phase", "detail": "Verified during development by /do-issue" },
  { "name": "CI pipeline passes", "source": "issue", "label": "ci-check", "endpoint": "-", "status": "-", "passed": true, "verified_on": "ci", "detail": "All 3 action runs passed" },
  { "name": "All subtasks closed", "source": "issue", "label": "subtask-check", "endpoint": "-", "status": "-", "passed": false, "verified_on": "n/a", "detail": "#42 still open: 'Add error handling'" },
  { "name": "Stuck task in action-required", "source": "issue", "label": "ai-verify", "endpoint": "/api/action-required", "status": 200, "passed": true, "verified_on": "dev", "detail": "Created stuck task, confirmed in action-required with source:'stuck'" },
  { "name": "Warning indicator on stuck task card", "source": "issue", "label": "human-assist", "endpoint": "-", "status": "-", "passed": "pending-human-check", "verified_on": "dev", "detail": "Setup: created stuck task dd-test-1. Human: open dashboard, check coding column for warning badge." },
  { "name": "Human verification: UX feels intuitive", "source": "issue", "label": "human-verify", "endpoint": "-", "status": "-", "passed": "pending", "verified_on": "n/a", "detail": "Owner confirms fix works" },
  { "name": "Flux reconciles within 10m", "source": "issue", "label": "post-merge", "endpoint": "-", "status": "-", "passed": "pending-post-merge", "verified_on": "prod (pending)", "detail": "Verify after merge: kubectl get hr -n registry-cache" },
  ...
]
```

## Step 8: Post results as PR comment

Compose and post a PR comment using `mcp__gitea__create_issue_comment` with the QA results.

### Compute overall verdict

The verdict is determined by QA-phase automated criteria: smoke tests + `[ai-verify]` + `[ci-check]` + `[subtask-check]`. Non-blocking criteria (`[human-assist]`, `[human-verify]`, `[post-merge]`) are reported separately but do not affect the verdict. **`[local-test]` criteria do not affect the QA verdict** — they are development-phase checks verified by `/do-issue` and appear in the results table as "Verified during development" for informational purposes only.

- **QA Passed** — every smoke test, `[ai-verify]`, `[ci-check]`, and `[subtask-check]` criterion passed. `[human-assist]` setups succeeded (but human confirmation still needed). Ready for merge pending human checks and post-merge verification.
- **QA Failed** — one or more QA-phase automated criteria failed, OR a `[human-assist]` setup failed (AI couldn't create the test conditions).

There is no "Partial" or "Skipped" verdict. Every QA-phase automated criterion is either tested and passed, or tested and failed. `[local-test]` criteria are always `skipped (dev-phase)`. `[post-merge]` criteria are always deferred.

### Deploy summary line

The `{deploy_summary}` should reflect what happened:
- Full deploy: `Workflow run #{run_number} — {conclusion}`
- Chart existed, Flux waited: `Skipped build (chart from run #{existing_run_number}), waited for Flux rollout`
- Chart already deployed: `Skipped deploy (chart 0.1.0-dev.{run_number} already deployed)`

### If ALL automated tests passed

```markdown
✅ **QA Passed** — verified across CI and dev

**Branch:** `{head_branch}` ({head_sha_short})
**Deploy:** {deploy_summary}

### Pre-Deploy Checks

| Test | Type | Env | Result |
|------|------|-----|--------|
| CI pipeline passes | `[ci-check]` | ci | ✅ Pass |
| All subtasks closed | `[subtask-check]` | n/a | ✅ Pass |
| Lint passes | `[local-test]` | dev-phase | ⏭️ Verified during development |
| Unit tests pass | `[local-test]` | dev-phase | ⏭️ Verified during development |

### Smoke Tests (dev)

| Test | Endpoint | Status | Result |
|------|----------|--------|--------|
| Health check | `/api/health` | 200 | ✅ Pass |
| Task list | `/api/tasks` | 200 | ✅ Pass |
| ... | ... | ... | ... |

### `[ai-verify]` — Automated Criteria (dev)

| Criterion | Endpoint | Status | Result |
|-----------|----------|--------|--------|
| {criterion} | {endpoint} | {status} | ✅ Pass |
| ... | ... | ... | ... |

### `[human-assist]` — Environment Prepared, Awaiting Human Check

{For each human-assist criterion, render a block like this:}

**{criterion text}**
> **Setup:** {what the AI did — API calls, test data created, current state}
> **What to check:** {URL to open, what to look for, what indicates pass vs fail}
> **Setup status:** ✅ Succeeded

### `[human-verify]` — Awaiting Human Signoff

| Criterion | Status |
|-----------|--------|
| {criterion text} | ⏳ Pending |
| ... | ... |

### `[post-merge]` — Verify After Merge (prod)

| Criterion | How to verify | Status |
|-----------|---------------|--------|
| {criterion text} | {verification command or check} | ⏳ Pending merge |
| ... | ... | ... |

---

All {automated_count} QA tests passed ({ci_count} CI, {dev_count} dev). {local_test_count} `[local-test]` criteria verified during development (not counted in QA verdict). {human_assist_count} criteria ready for human spot-check. {human_verify_count} criteria awaiting human signoff. {post_merge_count} criteria deferred to post-merge.
```

### If ANY automated tests failed

```markdown
❌ **QA Failed** — issues found

**Branch:** `{head_branch}` ({head_sha_short})
**Deploy:** {deploy_summary}

### Pre-Deploy Checks

| Test | Type | Env | Result |
|------|------|-----|--------|
| CI pipeline passes | `[ci-check]` | ci | ✅ Pass / ❌ Fail |
| All subtasks closed | `[subtask-check]` | n/a | ✅ Pass / ❌ Fail |
| Lint passes | `[local-test]` | dev-phase | ⏭️ Verified during development |
| Unit tests pass | `[local-test]` | dev-phase | ⏭️ Verified during development |

### Smoke Tests (dev)

| Test | Endpoint | Status | Result |
|------|----------|--------|--------|
| Health check | `/api/health` | 200 | ✅ Pass |
| Task list | `/api/tasks` | 500 | ❌ Fail |
| ... | ... | ... | ... |

### `[ai-verify]` — Automated Criteria (dev)

| Criterion | Endpoint | Status | Result |
|-----------|----------|--------|--------|
| {criterion} | {endpoint} | {status} | ✅ Pass / ❌ Fail |
| ... | ... | ... | ... |

### Failures

**{test name}** ({env}) — {error summary}
```
{truncated output or error message}
```

### `[human-assist]` — Environment Prepared, Awaiting Human Check

{Same format as above — still render these even on failure, so the human can check}

### `[human-verify]` — Awaiting Human Signoff

| Criterion | Status |
|-----------|--------|
| {criterion text} | ⏳ Pending |

### `[post-merge]` — Verify After Merge (prod)

| Criterion | How to verify | Status |
|-----------|---------------|--------|
| {criterion text} | {verification command or check} | ⏳ Pending merge |

---

{passed_count}/{total_count} automated tests passed. See failures above for details.
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

!`cat $HOME/.config/development-skills/lib/pr-status-labels.md`

After posting the PR comment, update the PR's status label:

- **QA passed, no `[human-assist]` or `[human-verify]` criteria pending** → set `pr: ready-to-merge` (even if `[post-merge]` criteria exist — those are verified after merge by `/merge-prs`)
- **QA passed, but `[human-assist]` or `[human-verify]` criteria pending** → keep `pr: awaiting-dev-verification` (human steps remaining)
- **QA failed** → set `pr: comments-pending` (needs fixes before re-test)

Use the PR status label swap procedure from pr-status-labels.md.

## Step 8.5: Post results on linked issue and update labels

If a linked issue was found in Step 6.5:

### If any `[ai-verify]` criteria or smoke tests FAILED:

1. Post a comment on the **issue** (not just the PR) using `mcp__gitea__create_issue_comment`:

```markdown
❌ **QA Failed** — Test Criteria Failures

PR #{pr_number} was deployed to dev and tested.

### `[ai-verify]` Results

| Criterion | Result | Detail |
|-----------|--------|--------|
| {criterion text} | ❌ Fail | {failure detail} |
| {criterion text} | ✅ Pass | |
| ... | ... | ... |

{failed_count}/{ai_verify_count} `[ai-verify]` criteria failed. The fix needs to address these failures before retesting.
```

2. **Update issue label:** Swap `status: ready-to-test` or `status: in-review` to `status: in-progress` (signals that `/do-issue` should pick this up and fix the failures)

### If all `[ai-verify]` criteria PASSED:

1. Post a comment on the **issue**:

```markdown
✅ **QA Passed** — Automated Test Criteria Verified

PR #{pr_number} was deployed to dev. All `[ai-verify]` criteria passed.

### `[ai-verify]` Results

| Criterion | Result |
|-----------|--------|
| {criterion text} | ✅ Pass |
| ... | ... |

### `[human-assist]` — Ready for Human Spot-Check

{For each human-assist criterion:}

**{criterion text}**
> **Setup:** {what the AI did}
> **What to check:** {instructions for the human}
> **Setup status:** ✅ Succeeded / ❌ Failed

### `[human-verify]` — Awaiting Human Signoff

| Criterion | Status |
|-----------|--------|
| {criterion text} | ⏳ Pending |

---

All {ai_verify_count} `[ai-verify]` criteria passed. {human_assist_count} `[human-assist]` criteria ready for human spot-check. {human_verify_count} `[human-verify]` criteria awaiting signoff.
```

2. **Update issue label:** Swap current status to `status: in-review` (signals that human verification is the remaining gate)


### Step 8.6: Update issue checklist

After posting the issue comment, update the **issue body** to check off test criteria that passed during QA:

1. Fetch the current issue body via `mcp__gitea__get_issue_by_index`
2. For each `[ai-verify]` criterion that **passed** (`passed: true`, actually executed and verified):
   - Find the matching `- [ ]` line in the issue body
   - Replace `- [ ]` with `- [x]`
   - Append a brief annotation: ` — *verified live in PR #{pr_number}*`
3. For `[ai-verify]` criteria that **failed**, leave them as `- [ ]` (unchecked)
4. For `[local-test]` criteria, check them off and annotate: replace `- [ ]` with `- [x]` and append ` — *verified during development by /do-issue*`
5. For `[human-assist]` criteria where setup succeeded, leave as `- [ ]` but append: ` — *environment prepared in PR #{pr_number}, awaiting human check*`
6. For `[human-verify]` criteria, always leave as `- [ ]`
7. Use `mcp__gitea__issue_write` with `method: "update"` to save the updated body

**Important:** Only modify the `- [ ]` / `- [x]` checkboxes and append annotations. Do not alter any other part of the issue body.

**CRITICAL:** Never mark a criterion as `[x]` unless it was actually executed and returned a passing result (`passed: true`), OR it is a `[local-test]` criterion (which is attested by `/do-issue` during development). `[human-assist]` and `[human-verify]` criteria must remain unchecked until a human confirms them.

### If no linked issue:

Skip this step entirely — only post the PR comment from Step 8.

## Step 9: Report to user

After posting the PR comment, tell the user:
1. Whether QA passed or failed
2. Breakdown by environment and label type:
   - **CI** (`[ci-check]`): {passed}/{total}
   - **Pre-merge checks** (`[subtask-check]`): {passed}/{total}
   - **Dev** (smoke tests + `[ai-verify]`): {passed}/{total}
   - **Dev-phase** (`[local-test]`): {count} skipped (verified during development)
   - **`[human-assist]`:** {setup_succeeded}/{total} ready for human spot-check
   - **`[human-verify]`:** {count} pending human signoff
   - **`[post-merge]`:** {count} deferred to post-merge verification
3. Link to the PR comment
4. If a linked issue was found: link to the issue comment and current label status
5. If failed, a brief summary of what broke
6. If `[human-assist]` criteria exist, remind the user to check them — they have instructions in the PR/issue comments
7. If `[human-verify]` criteria exist, remind that human signoff is needed before merge
8. If `[post-merge]` criteria exist, note that `/merge-prs` will verify them after merge
