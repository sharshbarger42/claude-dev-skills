---
name: investigate-bug
description: Investigate a bug report — reproduce, diagnose root cause across repos and infrastructure, verify findings, and create Gitea issues with bug labels.
argument-hint: "<description or repo#issue>"
---

# Investigate Bug Skill

Investigate a bug report end-to-end: gather symptoms, diagnose root cause across repos and infrastructure, verify findings, and create actionable Gitea issues.

**Input:** Bug description or issue reference as the skill argument. Accepted formats:
- Free-text bug description: `"grafana dashboards showing no data"`
- Existing issue reference: `homelab-setup#45`
- Owner/repo: `super-werewolves/homelab-setup#45`
- Full URL: `https://git.home.superwerewolves.ninja/super-werewolves/homelab-setup/issues/45`

## Step 1: Parse input and establish context

### Repo resolution

!`cat $HOME/.claude/development-skills/lib/resolve-repo.md`

### Agent identity

!`cat $HOME/.claude/development-skills/lib/agent-identity.md`

Derive your `AGENT_NAME` for this session.

### Discord notifications

!`cat $HOME/.claude/development-skills/lib/discord-notify.md`

### Infrastructure reference

!`cat $HOME/.claude/development-skills/config/infrastructure.md`

Load the infrastructure reference table — needed to map services to IPs, containers, and nodes.

### Parse the input

Determine the input type:

1. **Issue reference** (contains `#` or is a URL with `/issues/`): extract `owner`, `repo`, and `index` using the repo resolution logic above. Fetch the issue via `mcp__gitea__get_issue_by_index` and extract symptoms from the title, body, and comments (fetch with `mcp__gitea__get_issue_comments_by_index`).
2. **Free-text description** (everything else): use it directly as the symptom description. No repo context yet — it will be determined during investigation.

Store the symptom description for use in later steps.

### Symptom inventory (multi-symptom input)

When the input contains **multiple distinct symptoms** (bullet lists, numbered items, or clearly separate issues):

1. **Extract and number every symptom** — create a numbered inventory list. Each distinct symptom the user reported gets its own entry, no matter how minor it seems. Preserve the user's **exact wording** as a direct quote for each symptom.
2. **Track each symptom through the investigation.** Every symptom must end in one of these dispositions:
   - **Filed** — a Gitea issue was created for it
   - **Grouped** — folded into another symptom's issue (note which one)
   - **Not reproducible** — investigated but could not confirm
   - **Deferred** — user chose to skip it
3. **Never silently discard a symptom.** If investigation suggests a reported symptom is not a code bug (e.g., infrastructure issue, configuration problem, expected behavior, or user error), you must still present it to the user in Step 5 with your reasoning and let them decide whether to file an issue anyway.
4. **Present the full inventory in Step 5** (root cause determination) and again in **Step 8** (report). The user should see every symptom they reported and what happened to it.

If any symptom would be dropped or grouped, the user must explicitly confirm. Use `AskUserQuestion` to confirm any symptom you plan to NOT file as a separate issue — present your reasoning and let the user override.

## Step 2: Ensure kubeconfig

A read-only kubeconfig is needed to query the K3s cluster. Check if one exists and is usable:

1. Check if `~/.kube/qa-readonly-kubeconfig` exists and works:
   ```bash
   kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig get nodes --request-timeout=5s 2>&1
   ```
2. If it succeeds (exit code 0), the kubeconfig is valid — proceed to Step 3.
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
   b. Wait 10 seconds, then poll for the workflow run (look for the most recent `workflow_dispatch` run, poll every 15 seconds for up to 5 minutes).
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
   d. Verify the new kubeconfig works with the same `kubectl get nodes` test.
   e. If it still fails, note kubeconfig as unavailable but continue — some investigations don't need K8s access.

## Step 3: Classify the symptom

Categorize the bug to guide investigation:

| Category | Indicators | Investigation tools |
|----------|-----------|-------------------|
| K8s workload | pod, deploy, helm, flux, namespace mentioned | kubectl, helm |
| Network/DNS | can't reach, timeout, DNS, domain, 502/503 | curl, dig, nslookup |
| Service health | service name, UI broken, API error | curl, service logs |
| Infrastructure | LXC, VM, proxmox, disk, NFS, mount | SSH via Bash |
| CI/CD | workflow, action, runner, build, deploy | Gitea MCP `actions_run_read` |
| Config/code | specific file, function, behavior | Grep, Read, Glob in repo |

Present the classification to the user and confirm before investigating. Use `AskUserQuestion` with the detected category and a brief explanation. If the user corrects the category, use their choice instead.

## Step 4: Investigate — gather evidence

**Investigation round budget:** Track a shared round counter starting at 0. Increment it each time investigation loops back here from Step 5 ("Needs more investigation") or Step 6 (verification contradiction). If the counter reaches 2, do not loop again — proceed with what's known or offer the user the "Abandon" option.

Run diagnostic commands based on the category. Collect structured evidence.

### K8s investigation toolkit

```bash
KUBECONFIG=$HOME/.kube/qa-readonly-kubeconfig
# Pod status
kubectl --kubeconfig=$KUBECONFIG get pods -n {namespace} -o wide
# Recent events
kubectl --kubeconfig=$KUBECONFIG get events -n {namespace} --sort-by='.lastTimestamp' | tail -20
# Pod logs (last 100 lines)
kubectl --kubeconfig=$KUBECONFIG logs -n {namespace} {pod} --tail=100
# Describe failing resource
kubectl --kubeconfig=$KUBECONFIG describe {resource_type} {name} -n {namespace}
# HelmRelease status
kubectl --kubeconfig=$KUBECONFIG get helmrelease -n {namespace} -o wide
# Flux reconciliation
kubectl --kubeconfig=$KUBECONFIG get kustomization -A
```

### Network investigation

```bash
# DNS resolution
dig +short {domain} @192.168.0.225
# HTTP health check
curl -sf -o /dev/null -w "%{http_code}\n%{time_total}s" https://{url}
# TCP connectivity
nc -zv {ip} {port} 2>&1
```

### Service investigation

```bash
# Health endpoints (use IPs from infrastructure reference)
curl -sf http://{service_ip}:{port}/health
curl -sf http://{service_ip}:{port}/api/health
```

### CI/CD investigation

- Use `mcp__gitea__actions_run_read` with `list_runs` to check recent workflow runs
- Use `mcp__gitea__actions_run_read` with `get_job_log_preview` to read failure logs

### Code investigation

- Search across repos using `mcp__gitea__get_file_contents` or local Grep/Read
- Check recent commits on relevant branches via `mcp__gitea__list_commits`
- Check recent merged PRs that could have introduced the issue via `mcp__gitea__list_pull_requests`

### Recording evidence

For each piece of evidence collected, record:
- **Source**: what command/tool produced it
- **Finding**: what it shows
- **Implication**: what it means for the diagnosis

## Step 5: Determine root cause

Synthesize evidence into a diagnosis:

1. **Root cause** — what's actually broken and why
2. **Affected repos** — which repo(s) need fixes (could be multiple)
3. **Impact** — what's broken for users right now
4. **Confidence** — high/medium/low based on evidence strength

### Symptom accounting

Before presenting the diagnosis, review the symptom inventory from Step 1. For **every** reported symptom, state:
- Which root cause it maps to (if any)
- Whether it will get its own issue, be grouped into another issue, or not be filed
- If not filed: **why** (with evidence), and flag it for user confirmation

Present the full accounting table:

```
| # | Symptom (user's words) | Disposition | Rationale |
|---|------------------------|-------------|-----------|
| 1 | "exact quote from user" | Filed as issue | Root cause identified |
| 2 | "exact quote from user" | Grouped with #1 | Same root cause |
| 3 | "exact quote from user" | Needs confirmation | Appears to be config issue, not code bug |
```

**Any symptom marked "Needs confirmation" must be explicitly confirmed by the user** before proceeding. Do not assume a symptom is not a real bug — the user reported it for a reason. Even if you believe it's a configuration issue, infrastructure problem, or expected behavior, present your reasoning and ask.

Present the diagnosis and accounting to the user for confirmation. Use `AskUserQuestion` with options:
- **Confirmed — create issues** — proceed to Step 6
- **Needs more investigation** — go back to Step 4 with user guidance (user can specify which symptoms need more work)
- **Wrong direction** — user provides corrected hypothesis
- **Abandon — do not file issues** — investigation inconclusive, stop without creating issues

## Step 6: Verify the bug

Before creating issues, attempt to verify the diagnosis with targeted tests:

1. **Reproduce the symptom** — run the specific failing operation and confirm it fails as described
2. **Confirm the root cause** — check the specific file/config/resource identified as the cause
3. **Test the theory** — if possible, check whether the proposed fix would work (e.g., check if the correct value exists elsewhere, verify a config change would resolve it)

Record each verification as:
- **Test**: what was checked
- **Expected**: what should happen if diagnosis is correct
- **Actual**: what happened
- **Verdict**: CONFIRMED / PARTIAL / UNCONFIRMED

If verification contradicts the diagnosis, go back to Step 4 with new information (this increments the shared round counter). If the round budget is exhausted (2 rounds), proceed with what's known and note the uncertainty in the issue.

## Step 7: Create Gitea issues

For each affected repo, create a well-structured bug issue.

### Issue format

**Title:** `bug: {concise description of the problem}`

**Body:**
```markdown
## Symptom
{What the user reported or what was observed}

## Reported by human
{Direct quotes from the user's bug report that this issue addresses. Use blockquotes to preserve the user's exact words. Each quote should be the verbatim text from the human's input that led to this issue being filed.}

> "{exact quote from user's report — symptom 1}"

> "{exact quote from user's report — symptom 2, if multiple symptoms map to this issue}"

## Root Cause
{What's actually broken and why — include evidence}

## Evidence
{Key diagnostic output, truncated to relevant lines}

## Verification
{Results from Step 6 — what was confirmed}

## Suggested Fix
{Specific files/configs to change, with expected values}

## Impact
{What's broken for users, severity}

## Test Criteria
{A checklist of testable conditions that must pass before this bug can be considered fixed. Each criterion should be specific and verifiable by automated QA or a human tester. The `/qa-pr` skill will use this list to validate the fix.}

- [ ] {Criterion 1: e.g., "GET /api/health returns HTTP 200 with status: healthy"}
- [ ] {Criterion 2: e.g., "Dashboard loads within 5 seconds without JS errors"}
- [ ] ...
- [ ] Human verification: {owner confirms the fix works in their environment}
```

**IMPORTANT:** The `Test Criteria` section is mandatory for all bug issues. Each criterion must be:
- **Specific** — a concrete check, not "it works"
- **Verifiable** — can be tested with a command, HTTP request, or UI interaction
- **Ordered** — automated checks first, human verification always last

The final criterion must always be: `Human verification: {brief description of what the human should confirm}`. This ensures no bug is auto-closed without a human signoff.

### Labeling procedure

1. Call `mcp__gitea__list_repo_labels` to find label IDs for `bug` and a priority label (`priority: high` if service is down or data at risk, `priority: medium` for degraded functionality, `priority: low` for cosmetic or minor issues)
2. Create the issue with `mcp__gitea__create_issue`
3. Call `mcp__gitea__add_issue_labels` with the new issue index and both label IDs (bug + priority)
4. If any label doesn't exist in the repo, skip it silently

### Cross-referencing

If the source bug was an existing Gitea issue (parsed in Step 1), add a comment on the original issue linking to the newly created issues:

```
Investigation complete. Created the following issues:
- {owner}/{repo}#{index} — {title}
- {owner}/{repo}#{index} — {title}
```

Use `mcp__gitea__create_issue_comment` with the original issue's owner, repo, and index.

## Step 8: Report

### Discord notification

Post a Discord notification (orange/red embed, color 15158332) for bug investigation complete:

```bash
SAFE_BUG_SUMMARY="${BUG_SUMMARY//\"/\\\"}"
SAFE_ROOT_CAUSE="${ROOT_CAUSE//\"/\\\"}"
curl -s -X POST "$DISCORD_WEBHOOK" \
  -H "Content-Type: application/json" \
  -d "$(cat <<EOF
{
  "embeds": [{
    "title": "Bug Investigated: ${SAFE_BUG_SUMMARY}",
    "description": "**Agent:** ${AGENT_NAME}\n**Diagnosis:** ${SAFE_ROOT_CAUSE}\n**Issues created:** ${ISSUE_COUNT}\n**Confidence:** ${CONFIDENCE}",
    "color": 15158332,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }]
}
EOF
)"
```

This is best-effort — skip silently if webhook is not configured.

### User report

Tell the user:
1. **Diagnosis** — root cause summary
2. **Verification results** — what was confirmed, with verdicts
3. **Symptom inventory** — the full accounting table from Step 5 with final dispositions for every reported symptom. Every symptom the user reported must appear here with a clear outcome (filed, grouped, deferred, or not reproducible). If any symptoms were not filed, restate why.
4. **Issues created** — list with repo, issue number, title, and link
5. **Suggested next steps** — which issue to fix first, dependencies between them
