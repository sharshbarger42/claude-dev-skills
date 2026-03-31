---
name: verify-pr
description: Verify PR implements issue requirements — catch missing features, inaccurate descriptions, pattern violations
args: "<repo#N>"
---

# Verify PR

Verify that a PR's code actually does what the linked issue requires and what the PR description claims. Catches implementation drift, scope creep, missing requirements, inaccurate descriptions, pattern violations, and incomplete work.

Unlike `/review-pr` (which judges code quality), this skill checks **truthfulness** — does the code match the stated intent?

**Input:** PR reference as the skill argument.

**Accepted formats:**
- Shorthand: `food-automation#34`
- Owner/repo: `super-werewolves/food-automation#34`
- Full URL: `https://git.home.superwerewolves.ninja/super-werewolves/food-automation/pulls/34`

## Step 1: Gather context

### Repo resolution

!`cat $HOME/.config/development-skills/lib/resolve-repo.md`

### 1a. Fetch PR metadata

Use `mcp__gitea__pull_request_read` with `method: "get"` to get:
- Title, body/description
- Head branch, base branch, head SHA
- Changed files count, additions, deletions
- Mergeable status

### 1b. Ensure local repo is on latest

```bash
cd {repo_local_path}
git fetch origin
git rev-parse origin/{base_branch} >/dev/null 2>&1 || echo "FETCH FAILED — remote unreachable"
```

Verify the fetch succeeded before proceeding. If the fetch fails, warn the user that verification will use potentially stale data. This ensures we can read both the base branch and the PR branch locally.

### 1c. Fetch the linked issue

Parse the PR body, title, and branch name for issue references. Check all sources — any match is valid:

- **Branch name patterns:** `feature/{N}-*`, `fix/{N}-*`, `feat/{N}-*` — extract the numeric portion after the prefix. If the branch doesn't contain a number (e.g., `feature/add-caching`), skip this source gracefully.
- **PR body patterns:** `fixes #N`, `closes #N`, `resolves #N`, `Part of #N`, `Sub-issue of #N`
- **PR title patterns:** `feat(#{N})`, `fix(#{N})`

If an issue is found, fetch it via `mcp__gitea__issue_read`. Extract:
- Issue title and body (the requirements)
- `## Test Criteria` section (if present) — these are the labeled acceptance criteria
- `## Acceptance criteria` section (older format)
- Sub-issue references and parent issue references

If the issue has a parent (`Sub-issue of #N`), fetch the parent too for broader context.

If no linked issue is found, note this as a finding — PRs without linked issues have no verifiable requirements. Skip Steps 2 and 5a, and continue with PR description verification only (Steps 3-6). In the report, omit the Requirements Coverage section and show "No linked issue — requirements coverage not applicable" instead.

### 1d. Fetch the diff

Use `mcp__gitea__pull_request_read` with `method: "get_diff"` to get the full diff.

Parse the diff to extract:
- List of files added, modified, deleted
- For each file: the actual changes (added/removed lines with context)

### 1e. Read changed files in full

For each file in the diff, read the complete file on the PR branch to understand full context. Use `mcp__gitea__get_file_contents` with `ref: "{head_branch}"`, or locally:

```bash
git show origin/{head_branch}:{file_path}
```

### 1f. Read existing codebase patterns

For each changed file, read nearby files to understand conventions:
- Sibling files in the same directory — naming, structure, patterns
- Related test files — test structure and assertion patterns
- AGENTS.md — repo-specific coding standards (fetch from default branch)
- Config files — linting rules, formatting config

## Step 2: Verify requirements coverage

Compare the issue requirements against the actual code changes.

### 2a. Requirement → Code mapping

For each item in the issue's test criteria or acceptance criteria:

1. **Search the diff** for code that implements this requirement
2. **Read the relevant code** to confirm it actually does what the requirement asks
3. **Verdict:**
   - `[implemented]` — code clearly addresses this requirement. Cite the file:line as evidence.
   - `[partially-implemented]` — some aspects addressed, others missing. State exactly what's missing.
   - `[not-implemented]` — no code in the diff addresses this requirement at all.
   - `[cant-verify]` — requirement is too vague to map to specific code. This flags the requirement as needing clarification, not the PR.

**Be rigorous.** Don't mark something `[implemented]` just because a file was touched in the right area. Read the code and confirm it actually satisfies the requirement's intent.

### 2b. Code → Requirement mapping (reverse check)

For each significant change in the diff (skip trivial: imports, formatting, whitespace):

1. **Does this change map to a stated requirement?**
2. **Verdict:**
   - `[required]` — directly implements a stated requirement
   - `[supporting]` — not explicitly required but necessary for the implementation (e.g., adding a helper function, updating a type definition)
   - `[unrelated]` — change doesn't map to any requirement. Could be scope creep, or a legitimate fix discovered during implementation. Flag for review.

## Step 3: Verify PR description accuracy

### 3a. Claimed changes vs actual diff

For each concrete claim in the PR description (e.g., "Updated X to do Y", "Added new endpoint Z", "Fixed bug where..."):

1. **Verify the change exists in the diff**
2. **Verify the description is accurate** — does the code actually do what was described?
3. **Verdict:**
   - `[accurate]` — the description matches the code
   - `[inaccurate]` — the change exists but the description mischaracterizes it (e.g., says "added" but it's actually a modification, or says "fixed" but only added a workaround)
   - `[missing-from-diff]` — the PR description claims this change but it's not in the diff at all

### 3b. Undocumented changes

For each file in the diff that isn't mentioned in the PR description:
- Flag as `[undocumented]`
- Assess: trivial (formatting, auto-generated, lockfiles) vs substantial (new logic, API changes, schema modifications)
- Substantial undocumented changes should be called out — the reviewer might miss them

## Step 4: Verify code-codebase consistency

Check that new code follows existing patterns. Only flag genuine inconsistencies, not style preferences.

### 4a. Naming conventions
- Do new functions/variables follow the existing naming style?
- Do new files follow the directory structure and naming conventions?
- Are new constants, enums, or types named consistently with existing ones?

### 4b. Pattern consistency
- **API endpoints** — same auth pattern, error handling, response format as siblings?
- **Models/schemas** — same field naming, validation approach, serialization pattern?
- **Tests** — same setup/teardown, assertion style, fixture patterns?
- **Config** — same format, same location as similar config in the repo?

### 4c. Import and dependency consistency
- Are new imports consistent with how the codebase does imports? (absolute vs relative, barrel imports, etc.)
- Are new dependencies justified? Could an existing dependency serve the same purpose?

### 4d. Error handling patterns
- Does new code handle errors the way existing code does?
- Are there bare `except:` or `catch(e)` blocks where the codebase uses specific error types?
- Missing error handling where the pattern requires it?

For each inconsistency: cite the existing pattern (file:line) and what the PR does differently.

## Step 5: Verify test coverage

### 5a. Test criteria from issue

If the linked issue has `## Test Criteria` with labeled criteria:

| Label | What to check |
|-------|--------------|
| `[local-test]` | Is there a corresponding test in the diff that runs this check? |
| `[ai-verify]` | Does the code make the described behavior possible? (verify the plumbing exists) |
| `[ci-check]` | Are CI workflows configured to run the relevant checks? |
| `[post-merge]` | Do the infrastructure changes exist to support post-merge verification? |
| `[human-verify]` | Skip — can't verify programmatically |
| `[human-assist]` | Does the code set up the state the human needs to verify? |
| `[subtask-check]` | Are the referenced subtasks/dependencies actually closed? |

### 5b. New code without tests

For each new function, endpoint, class, or significant logic branch added in the diff:
- Is there a corresponding test? Flag `[untested]` if not.
- Exception: trivial changes (config, docs, formatting, type-only changes) don't need tests.

### 5c. Existing test modifications

If tests were modified or deleted:
- Were they updated to reflect code changes? Or weakened/removed?
- Flag `[test-weakened]` if assertions were removed, test cases deleted, or error cases dropped without replacement.
- Flag `[test-removed]` if a test file was deleted without replacement.

## Step 6: Check for leftovers

Scan the **added lines** in the diff for signs of incomplete work:

| Pattern | Type | Flag as |
|---------|------|---------|
| `TODO`, `FIXME`, `HACK`, `XXX`, `TEMP` in comments | Incomplete work | `[todo]` |
| Commented-out code blocks (>2 lines) | Dead code | `[dead-code]` |
| `console.log`, `print("DEBUG"`, `print(f"DEBUG` | Debug logging | `[debug-log]` |
| Hardcoded IPs, URLs, credentials, API keys | Hardcoded secrets/config | `[hardcoded]` |
| `pass`, `return None`, `...`, `raise NotImplementedError` in new functions | Placeholder | `[placeholder]` |
| `# type: ignore`, `# noqa`, `// @ts-ignore` added | Suppressed warnings | `[suppressed]` |

Only flag leftovers in **new code** (added lines), not pre-existing code that wasn't changed.

## Step 7: Generate report

```markdown
## PR Verification Report

**PR:** {owner}/{repo}#{index} — {title}
**Issue:** #{issue_index} — {issue_title} (or "No linked issue found")
**Checked:** {timestamp}
**Diff:** +{additions} -{deletions} across {files_changed} files

### Requirements Coverage

| # | Requirement | Status | Evidence |
|---|-------------|--------|----------|
| 1 | {requirement text} | [implemented] | `{file}:{line}` |
| 2 | {requirement text} | [not-implemented] | — |
| 3 | {requirement text} | [partially-implemented] | {what's missing} |

**Coverage: {X}/{Y} requirements fully implemented ({Z}%)**

### Reverse Check — Code → Requirements

| Change | Files | Maps to |
|--------|-------|---------|
| {description of change} | `{file}` | [required] — requirement #N |
| {description of change} | `{file}` | [supporting] — needed for #N |
| {description of change} | `{file}` | [unrelated] — no matching requirement |

### PR Description Accuracy

| Claim | Status | Notes |
|-------|--------|-------|
| {claimed change} | [accurate] | — |
| {claimed change} | [inaccurate] | {what's actually different} |
| {claimed change} | [missing-from-diff] | not in the diff |

**Undocumented changes:** {list of substantial files changed but not mentioned}

### Codebase Consistency

{If no issues: "No pattern inconsistencies found."}

| File | Issue | Existing Pattern | PR Code |
|------|-------|-----------------|---------|
| `{file}` | {naming/pattern/error handling} | {what exists} `{ref_file}:{line}` | {what PR does} |

### Test Coverage

| New Code | Test | Status |
|----------|------|--------|
| `{function/endpoint}` | `{test_file}:{line}` | [tested] |
| `{function/endpoint}` | — | [untested] |

{If test criteria from issue:}

| Test Criterion | Label | Covered | Evidence |
|---------------|-------|---------|----------|
| {criterion text} | [local-test] | Yes/No | `{test_file}` or — |

### Leftovers

{If none: "No leftovers found."}

| File:Line | Type | Content |
|-----------|------|---------|
| `{file}:{line}` | [todo] | {text} |
| `{file}:{line}` | [hardcoded] | {description, not the actual value} |

### Verdict

**Requirements:** {X}% covered ({implemented}/{total})
**Description:** {Y}% accurate ({accurate}/{total claims})
**Consistency:** {Z} inconsistencies
**Tests:** {W}% of new code tested
**Leftovers:** {N} items

{One-paragraph assessment: does this PR faithfully implement what was required? What needs to change before merge?}
```

## Step 8: Post report

Offer to post the report as a comment on the PR via `mcp__gitea__issue_write` with `method: "add_comment"`.

If the user declines, just display the report.

## Rules

- **Read-only** — never modify code, push commits, or change PR state. This skill only reads and reports.
- **No secrets in output** — if you find credentials during pattern checking, note their presence but never print values.
- **Evidence-based verdicts** — every `[implemented]`, `[inaccurate]`, or `[inconsistent]` verdict must cite specific file:line evidence. No vibes-based assessments.
- **Don't overlap with /review-pr** — this skill checks truthfulness and completeness, not code quality. Don't duplicate review-pr's security/architecture/robustness checks. If you spot a quality issue incidentally, mention it briefly but don't make it the focus.
- **Flag the source of the problem** — if a requirement is too vague to verify against code, flag the requirement (`[cant-verify]`), not the PR. If the PR description is wrong, flag the description, not the code.
- **Be specific about what's missing** — "not implemented" is not enough. State exactly which part of the requirement has no corresponding code and what code would need to be added.
