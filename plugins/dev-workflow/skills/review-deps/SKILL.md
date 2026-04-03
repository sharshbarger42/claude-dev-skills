---
name: review-deps
description: Review dependency update PRs — research changelogs, assess breaking changes, analyze codebase usage, classify risk, and approve or flag.
---

# Dependency Update Review

Review a dependency update PR (Renovate, Dependabot, or manual bumps). Research what changed, check if our code is affected, and classify risk.

**Input:** PR reference as the skill argument. Accepted formats:
- Shorthand: `dragon-den#42`
- Owner/repo: `super-werewolves/dragon-den#42`
- Full URL: `https://git.home.superwerewolves.ninja/super-werewolves/dragon-den/pulls/42`

## Step 1: Parse the PR reference

Extract `owner`, `repo`, and PR `index` from the argument.

### Repo resolution

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/resolve-repo.md`

## Step 2: Fetch PR metadata and diff

1. Use `mcp__gitea__get_pull_request_by_index` with parsed `owner`, `repo`, and `index` to get:
   - PR title, body/description, labels
   - Base and head branches

2. Use `mcp__gitea__get_pull_request_diff` with the same `owner`, `repo`, and `index`.

3. **Validate this is a dependency update PR.** Check if the diff modifies any of these files:
   - Node.js: `package.json`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`
   - Go: `go.mod`, `go.sum`
   - Python: `requirements.txt`, `requirements*.txt`, `pyproject.toml`, `poetry.lock`, `Pipfile`, `Pipfile.lock`
   - Ruby: `Gemfile`, `Gemfile.lock`
   - Rust: `Cargo.toml`, `Cargo.lock`
   - Java/Kotlin: `pom.xml`, `build.gradle`, `build.gradle.kts`
   - .NET: `*.csproj`, `packages.config`, `Directory.Packages.props`
   - Helm: `Chart.yaml`, `Chart.lock`
   - Docker: `Dockerfile` (base image version changes)
   - General: `flake.nix`, `flake.lock`

   If none of these files appear in the diff, warn the user:
   ```
   This PR doesn't appear to contain dependency changes. Would you like to run /review-pr instead?
   ```
   Use `AskUserQuestion` with options: **Continue anyway** or **Switch to /review-pr**. If the user picks switch, stop and tell them to run `/review-pr {owner}/{repo}#{index}`.

## Step 3: Parse dependency changes from the diff

Extract every dependency change from the diff. For each changed dependency, determine:

1. **Package name** — the dependency identifier
2. **Old version** → **New version** (or "added" / "removed")
3. **Bump type** — classify using semver:
   - **Major**: first number changed (e.g., 2.x → 3.x)
   - **Minor**: second number changed, first unchanged (e.g., 2.1 → 2.2)
   - **Patch**: third number changed, first two unchanged (e.g., 2.1.3 → 2.1.4)
   - **New**: dependency added (no old version)
   - **Removed**: dependency deleted (no new version)
4. **Dependency scope** — classify as:
   - **Production**: listed in `dependencies`, main go.mod requires, install_requires, default Cargo deps, compile/runtime scope
   - **Dev-only**: listed in `devDependencies`, `[tool.pytest]`, `[dev-dependencies]`, test scope, build plugins, linting tools

### Handling lock files

Lock files (package-lock.json, go.sum, yarn.lock, etc.) contain transitive dependency changes. Do NOT analyze every transitive change individually — instead:
- Note the count of transitive changes (e.g., "42 transitive dependencies updated")
- Only flag transitive changes if a well-known critical package changed (e.g., openssl, libxml, crypto libraries)

Focus the detailed analysis on **direct** dependency changes from manifest files (package.json, go.mod, pyproject.toml, etc.).

## Step 4: Research each dependency update

For each **direct** dependency change, research what changed between the old and new versions:

1. **Search for release notes / changelog.** Use `WebSearch` to find:
   - `"{package-name}" changelog {new_version}`
   - `"{package-name}" release notes {new_version}`
   - The package's GitHub/GitLab releases page

2. **Fetch and read the changelog.** Use `WebFetch` on the most relevant result to extract:
   - Summary of changes between old and new version
   - Any **breaking changes** explicitly listed
   - Any **deprecation** notices
   - Any **security fixes** (CVEs, advisories)

3. **If no changelog is found**, note "No changelog found — manual review recommended" for that dependency.

**Parallelism:** Research up to 5 dependencies concurrently using the Agent tool. For PRs with more than 10 direct dependency changes, prioritize:
1. Major version bumps
2. Production dependencies
3. Security-related packages
Then summarize the rest as "N minor/patch updates with no known breaking changes."

## Step 5: Analyze codebase usage

For each changed dependency, check how the codebase uses it:

1. **`cd` to the local repo path** (from the shorthand table resolved in Step 1).

2. **Search for imports/usage** using Grep:
   - Node.js: `require('pkg')`, `from 'pkg'`, `import 'pkg'`
   - Go: `"module/path"` in import blocks
   - Python: `import pkg`, `from pkg import`
   - Rust: `use crate_name::`, `extern crate`
   - General: search for the package name in source files (exclude lock files, node_modules, vendor)

3. **Record usage details:**
   - Which files import/use the package
   - Which specific APIs or functions are referenced (if identifiable from the import statements)
   - If the package is NOT directly imported anywhere, note "Not directly imported — transitive or build-time dependency"

4. **Cross-reference with breaking changes:** If Step 4 found breaking changes, check whether any of the specific APIs mentioned in the breaking changes appear in our code.

## Step 6: Risk assessment

Classify each dependency update into a risk level:

### Low Risk
- Patch version bump with no breaking changes
- Dev-only dependency (linting, testing, build tools)
- Dependency not directly imported in our code
- Minor bump with no breaking changes and no deprecations

### Medium Risk
- Minor version bump for a production dependency with deprecation warnings
- Transitive dependency with broad reach (e.g., a core HTTP library updated transitively)
- New dependency added (review what it does and why)
- No changelog found for a production dependency (unknown changes)
- Security fix that doesn't indicate our code was vulnerable

### High Risk
- Major version bump for a production dependency
- Known breaking changes that affect APIs our code uses
- Dependency removed that our code imports
- Security advisory indicating our code path was vulnerable
- Changes to authentication, encryption, or data-handling libraries

**Overall PR risk** = the highest risk level among all individual dependency changes.

## Step 7: Post the review

### Build the review body

Format as:

```
## Dependency Update Review

**Overall Risk: {LOW|MEDIUM|HIGH}**

{count} direct dependencies analyzed, {transitive_count} transitive updates.

---

### {package-name}: {old_version} → {new_version} ({bump_type})
- **Scope:** production / dev-only
- **Usage in codebase:** {list of files that import it, or "not directly imported"}
- **What changed:** {summary from changelog research}
- **Breaking changes:** {none found / specific breaking changes}
- **Deprecations:** {none / specific deprecations}
- **Security:** {no advisories / CVE details}
- **Risk: {Low|Medium|High}** — {one-line rationale}

---

### {next package...}

---

### Transitive Updates
{N} transitive dependencies updated via lock file changes. {Notable ones if any, otherwise "No notable transitive changes."}

### Summary
{2-3 sentence overall assessment. Note any action items if risk is medium or high.}
```

### Post the review via MCP

**If overall risk is Low (no medium or high findings):**

Use `mcp__gitea-reviewer__create_pull_request_review` with:
- `owner`, `repo`, `index`
- `state`: `"APPROVED"`
- `body`: the formatted review body

**If overall risk is Medium or High:**

Use `mcp__gitea-reviewer__create_pull_request_review` with:
- `owner`, `repo`, `index`
- `state`: `"COMMENT"`
- `body`: the formatted review body

Do NOT use `REQUEST_CHANGES` — the agent recommends but never gates merges.

**IMPORTANT:** This skill must NEVER merge the PR, even if risk is low. Approval is a recommendation — a human must decide to merge. Do not invoke `/merge-prs` or any merge action.

### Fallback if MCP is unavailable

If the MCP tool is not available, fall back to curl:

```bash
curl -s -X POST \
  -H "Authorization: token $(cat $HOME/.config/code-review-agent/token)" \
  -H "Content-Type: application/json" \
  "https://git.home.superwerewolves.ninja/api/v1/repos/{owner}/{repo}/pulls/{index}/reviews" \
  -d @/tmp/review-payload.json
```

Where `/tmp/review-payload.json` contains `{"body": "...", "event": "APPROVE"}` or `{"body": "...", "event": "COMMENT"}`.

## Step 8: Update PR status label

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/pr-status-labels.md`

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/deploy-aware-label.md`

After posting the review, update the PR's status label:

- **Overall risk Low (approved)** → check deploy config:
  - Repo has dev deploy config → set `pr: awaiting-dev-verification`
  - Repo has no dev deploy config → set `pr: ready-to-merge`
- **Overall risk Medium or High (flagged)** → set `pr: comments-pending`

Use the PR status label swap procedure from pr-status-labels.md.

## Step 9: Report to user

**If approved (Low risk):**
```
Approved dependency update PR #{index} — all {count} updates are low risk.
Review posted with full analysis. Label set to {label}.
```

**If flagged (Medium or High risk):**
```
Left a full dependency analysis on PR #{index}.

{count} dependencies assessed:
- {high_count} high risk: {list of high-risk package names}
- {medium_count} medium risk: {list of medium-risk package names}
- {low_count} low risk

Key concerns:
- {top concern 1}
- {top concern 2}

Review posted as COMMENT with label set to `pr: comments-pending`.
```
