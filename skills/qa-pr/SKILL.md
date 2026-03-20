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

| Repo | Deploy workflow | Dev health URL | Dev base URL | Smoke endpoints |
|------|----------------|----------------|--------------|-----------------|
| `multi-agent-coordinator` | `deploy.yml` | `https://agents.apps.superwerewolves.ninja/api/health` | `https://agents.apps.superwerewolves.ninja` | `/api/health`, `/api/tasks`, `/api/metrics`, `/api/agents`, `/` |
| `food-automation` | `deploy.yaml` | `http://food.baryonyx-walleye.ts.net/health` | `http://food.baryonyx-walleye.ts.net` | `/health` |

If the repo is **not in this table**, stop and tell the user:
> Repo `{owner}/{repo}` does not have a dev deploy configuration. Add it to the qa-pr skill's deploy config table.

Store the resolved config for use in later steps.

## Step 4: Trigger dev deployment

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

## Step 5: Wait for build + deploy workflow to complete

1. Wait 15 seconds for the action to register
2. Call `mcp__gitea__list_repo_action_runs` and look for a run:
   - On the head branch (matching `head_sha` or `head_branch`)
   - With `event: "workflow_dispatch"`
   - Created after the dispatch timestamp
3. If no run found yet, poll every 30 seconds for up to 5 minutes
4. Once the run is found, poll its status every 30 seconds for up to 10 minutes:
   - `success` — proceed to Step 6
   - `failure` — jump to Step 8 (report failure)
   - Still running — keep polling

If no run is found after 5 minutes, jump to Step 8 with error: "Deploy workflow did not trigger within 5 minutes."

Record the run ID and conclusion for the report.

## Step 6: Wait for Flux rollout

Flux CD picks up new Helm chart versions from the OCI registry. After the deploy workflow pushes a new chart, Flux needs time to detect and apply it.

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
| Health check | `GET /health` | HTTP 200, response contains `"status"` |

### Collecting results

Build a results list:
```
[
  { "name": "Health check", "endpoint": "/api/health", "status": 200, "passed": true, "detail": "" },
  { "name": "Task list", "endpoint": "/api/tasks", "status": 500, "passed": false, "detail": "Internal server error: database locked" },
  ...
]
```

## Step 8: Post results as PR comment

Compose and post a PR comment using `mcp__gitea__create_issue_comment` with the QA results.

### If ALL tests passed

```markdown
✅ **QA Passed** — dev deployment verified

**Branch:** `{head_branch}` ({head_sha_short})
**Deploy:** Workflow run #{run_number} — {conclusion}
**Environment:** dev

| Test | Endpoint | Status | Result |
|------|----------|--------|--------|
| Health check | `/api/health` | 200 | ✅ Pass |
| Task list | `/api/tasks` | 200 | ✅ Pass |
| ... | ... | ... | ... |

All {N} smoke tests passed. Ready for merge.
```

### If ANY tests failed

```markdown
❌ **QA Failed** — dev deployment has issues

**Branch:** `{head_branch}` ({head_sha_short})
**Deploy:** Workflow run #{run_number} — {conclusion}
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

## Step 9: Report to user

After posting the PR comment, tell the user:
1. Whether QA passed or failed
2. How many tests passed/failed
3. Link to the PR comment
4. If failed, a brief summary of what broke
