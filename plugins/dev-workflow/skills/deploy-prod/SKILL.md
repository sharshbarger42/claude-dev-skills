---
name: deploy-prod
description: Tag a repo's main branch with a semver release, trigger the prod deploy workflow, and verify the rollout.
args: "[repo] [--version vX.Y.Z]"
allowed-tools: Read, Bash, Grep, AskUserQuestion, mcp__gitea__pull_request_read, mcp__gitea__list_pull_requests, mcp__gitea__actions_run_write, mcp__gitea__actions_run_read, mcp__gitea__list_repo_action_runs
---

# Prod Deploy

Tag the latest main commit with a semver release tag, trigger the prod deploy workflow, wait for rollout, and verify the deployment is healthy.

## Repo and Issue Resolution

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/resolve-repo.md`

## Step 1: Parse arguments

Parse `$ARGUMENTS` using the resolution logic above. The user can provide:

- **Repo shorthand** (`MAC`, `food-automation`): deploy the repo's main branch
- **Explicit version** (`MAC --version v0.3.0`): use the specified version tag

If no arguments are provided, ask the user which repo to deploy.

## Step 2: Load deploy config

Load the deploy configuration from `~/.config/development-skills/deploy-config.md`.

```bash
cat ~/.config/development-skills/deploy-config.md
```

If the file doesn't exist, stop and tell the user:
> Deploy config not found at `~/.config/development-skills/deploy-config.md`.

Look up the repo in the **Prod Environment** table. The table has these columns:

| Repo | Deploy workflow | Prod health URL | Prod base URL | Version endpoint | Prod chart name | Prod namespace |
|------|----------------|-----------------|---------------|------------------|-----------------|----------------|

If the repo is **not in the table**, stop and tell the user:
> Repo `{owner}/{repo}` does not have a prod deploy configuration.

## Step 3: Determine the version tag

**Semver regex used everywhere in this step** (rejects leading zeros like `v01.02.03` per the [semver spec](https://semver.org/#spec-item-2)):

```
^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$
```

Prerelease suffixes (e.g., `-rc1`, `-beta`, `-dev`, `-123.1`) are intentionally rejected: prod tags are immutable releases. Release-candidate / staging promotion belongs in a separate workflow that this skill doesn't cover.

Also capture the current main HEAD SHA at the start of this step — it will be tagged literally in Step 5 to avoid race conditions if anyone pushes between confirmation and tag:

```bash
cd {local_path}
git fetch origin main
HEAD_SHA="$(git rev-parse origin/main)"
HEAD_SHA_SHORT="$(git rev-parse --short origin/main)"
```

### If `--version` was provided

Validate `{version}` against the semver regex above. If the input does not match, stop and tell the user the regex it must satisfy. Do NOT proceed with an invalid version — this value is later interpolated into shell commands.

### If no version specified

1. Fetch existing tags:

   ```bash
   cd {local_path}
   git fetch origin --tags
   LATEST_TAGS="$(git tag --sort=-v:refname | grep -E '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' | head -5)"
   LATEST_TAG="$(echo "$LATEST_TAGS" | head -1)"
   ```

2. **First-release case**: if `LATEST_TAGS` is empty (no existing semver tags), this is the first prod release. Show all commits on `origin/main` and suggest `v0.1.0`:

   ```bash
   git log origin/main --oneline | head -20
   ```

   Present to the user with `AskUserQuestion`:

   ```
   No existing semver tags found in this repo. This is the first prod release.

   Recent commits on main:
   {commit list}
   ```

   Options:
   - **v0.1.0** (recommended) — first stable release
   - **v0.0.1** — first prerelease-style patch
   - **Custom** — enter a specific version

3. **Subsequent-release case**: show the latest prod tags and the commits since the last one:

   ```bash
   git log "${LATEST_TAG}..origin/main" --oneline
   ```

   Suggest the next patch version (e.g., `v0.2.8` -> `v0.2.9`). Present with `AskUserQuestion`:

   ```
   Latest prod tag: {latest_tag}
   Commits since: {count}

   {commit list}
   ```

   Options:
   - **v{next_patch}** (recommended) — bump patch version
   - **v{next_minor}.0** — bump minor version (for significant features)
   - **Custom** — enter a specific version

In both cases, validate the chosen version against the semver regex above.

## Step 4: Confirm deployment

Present the deployment plan with `AskUserQuestion`. Use the captured `HEAD_SHA_SHORT` from Step 3:

```
Deploy to PROD:

  Repo:    {owner}/{repo}
  Tag:     {version} on {HEAD_SHA_SHORT} (captured at Step 3)
  Health:  {prod_health_url}

  Commits in this release:
  {commit list since last prod tag}
```

Options:
- **Yes, deploy to prod** — proceed
- **Cancel** — stop

**Do NOT proceed without explicit confirmation.** This goes to production.

## Step 5: Create and push the tag

**Pre-check**: confirm the tag does not already exist on the remote. This prevents creating a local tag that then fails to push:

```bash
if git ls-remote --tags origin "{version}" | grep -q "refs/tags/{version}"; then
  echo "Tag {version} already exists on origin — stop." >&2
  exit 1
fi
```

If the pre-check passes, create the tag against the captured `HEAD_SHA` (not `origin/main`, to honor the SHA the user actually confirmed in Step 4):

```bash
cd {local_path}
git tag "{version}" "${HEAD_SHA}"
git push origin "{version}"
```

Do not force-push tags. If the push fails for any other reason (network, permissions), delete the local tag before continuing or retrying:

```bash
git tag -d "{version}"
```

## Step 6: Trigger deploy workflow (if configured)

If the prod deploy config has a `Deploy workflow` value:

```
mcp__gitea__actions_run_write
  method: dispatch_workflow
  owner: {owner}
  repo: {repo}
  workflow_id: {deploy_workflow}
  ref: main
  inputs: { "tag": "{version}" }
```

**If the dispatch call itself fails** (HTTP 404 / 422 / 500 — e.g., wrong workflow filename, missing `workflow_dispatch` trigger, insufficient permissions), the tag has already been pushed in Step 5 but the deploy will not run. Recovery options for the user:

- **Most common cause**: workflow filename in `deploy-config.md` doesn't match an actual file in `.gitea/workflows/`. Fix the config and re-run `/deploy-prod {repo} --version {version}` (the version-already-pushed case is handled in Step 5's pre-check by aborting; pass the existing tag explicitly to skip Step 5).
- **If the tag should not have been pushed**: delete the remote tag (`git push origin :refs/tags/{version}`) and re-run when fixed.
- Tell the user explicitly which fix path applies and stop. Do not silently continue to Step 7.

If no deploy workflow is configured, the tag push itself may trigger the deploy (e.g., via Flux image automation or a tag-triggered workflow). Note this to the user and continue to Step 7 — Step 7.1's discovery step will detect any tag-triggered runs.

## Step 7: Wait for rollout

1. **Find the dispatched (or tag-triggered) workflow run.** Wait 15 seconds for the run to register, then list recent runs:

   ```
   mcp__gitea__list_repo_action_runs
     owner: {owner}
     repo: {repo}
     status: ""    # all states; filter on workflow + recency client-side
   ```

   Pick the most recent run whose `workflow_id` matches `{deploy_workflow}` (if Step 6 dispatched one) OR whose `event` is `push` and `head_branch`/`head_commit` corresponds to the tag (if no workflow was configured and the tag triggered something).

   - If **no matching run is found within 60 seconds**: report this to the user. The workflow filename in `deploy-config.md` may be wrong, the tag-trigger may not be wired up, or runner availability may be the issue. Recovery options match Step 6's "dispatch failed" guidance. Stop polling and skip to Step 8 — verification will confirm whether anything actually rolled out.

   - If **a matching run is found**: poll its status using `mcp__gitea__actions_run_read` every 30 seconds for up to 10 minutes. Report success, failure, or running (timeout).

2. If using Flux-based deploys, force reconciliation. (Note: prod and dev currently share the homelab k3s cluster, so the same `qa-readonly-kubeconfig` is used for both verification paths. If/when prod moves to a separate cluster, this needs a dedicated `prod-readonly-kubeconfig`.)

   ```bash
   kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig \
     annotate helmrelease {prod_chart_name} -n {prod_namespace} \
     reconcile.fluxcd.io/requestedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite 2>&1
   ```

3. Poll the prod health URL every 30 seconds for up to 10 minutes:

   ```bash
   curl -sf {prod_health_url}
   ```

   **On health-poll timeout** (10 minutes elapsed without a 2xx response): print a clear warning and continue to Step 8. Verification may surface a partial deploy that helps diagnose. After Step 9's report, prompt the user with `AskUserQuestion` whether to roll back (using the previous-tag command from Step 9's footer) or wait longer.

## Step 8: Verify deployment

Gather verification evidence. All `kubectl` calls use `2>&1` (not `2>/dev/null`) so an auth/namespace failure surfaces in the output rather than producing a confusingly-empty value in the report.

1. **Health endpoint**:

   ```bash
   curl -sf {prod_health_url}
   ```

2. **Version endpoint** (if configured):

   ```bash
   curl -sf {prod_base_url}{version_endpoint}
   ```

   Verify the reported version matches the deployed tag.

3. **HelmRelease version** (if kubeconfig available):

   ```bash
   kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig \
     get helmrelease {prod_chart_name} -n {prod_namespace} \
     -o jsonpath='{.status.lastAppliedRevision}' 2>&1
   ```

4. **Pod status** (if kubeconfig available):

   ```bash
   kubectl --kubeconfig=$HOME/.kube/qa-readonly-kubeconfig \
     get pods -n {prod_namespace} -o wide 2>&1
   ```

## Step 9: Report

Tell the user:

```
## Prod Deploy: {version}

| Check | Result |
|-------|--------|
| Tag | `{version}` on `{HEAD_SHA_SHORT}` |
| Workflow | {status} |
| Health | {health_status} |
| Version | {reported_version} ({match_status}) |
| HelmRelease | {helmrelease_version} |
| Pods | {pod_count} running |
```

If any check failed, clearly flag it and suggest next steps (check logs, rollback to previous tag, etc.).

If the health or version check fails after the Step 7.3 timeout:
> Deployment may still be rolling out. The previous prod version was `{previous_tag}`. To rollback, redeploy the previous tag: `/deploy-prod {repo} --version {previous_tag}`
