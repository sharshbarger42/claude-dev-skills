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

Present the diagnosis to the user for confirmation before creating issues. Use `AskUserQuestion` with options:
- **Confirmed — create issues** — proceed to Step 6
- **Needs more investigation** — go back to Step 4 with user guidance
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
```

### Labeling procedure

1. Call `mcp__gitea__list_repo_labels` to find the `bug` label ID for the target repo
2. Create the issue with `mcp__gitea__create_issue`
3. Call `mcp__gitea__add_issue_labels` with the new issue index and the `bug` label ID
4. If no `bug` label exists in the repo, skip labeling silently

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
3. **Issues created** — list with repo, issue number, title, and link
4. **Suggested next steps** — which issue to fix first, dependencies between them
