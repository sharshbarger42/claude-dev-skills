---
name: review-pr
description: Review a Gitea PR using code-review-agent. Fetches diff, runs a four-pass review with severity tiers, posts via MCP.
---

# PR Review Skill

Review a Gitea pull request and post the review as `code-review-agent`.

**Input:** PR reference as the skill argument. Accepted formats:
- Shorthand: `food-automation#32`
- Owner/repo: `super-werewolves/food-automation#32`
- Full URL: `https://git.home.superwerewolves.ninja/super-werewolves/food-automation/pulls/32`

## Step 1: Parse the PR reference

Extract `owner`, `repo`, and PR `index` from the argument.

### Repo resolution

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/resolve-repo.md`

## Step 2: Fetch PR metadata

Use `mcp__gitea__get_pull_request_by_index` with the parsed `owner`, `repo`, and `index` to get:
- PR title
- PR body/description
- Base and head branches
- Default branch (`base.repo.default_branch`)

If the PR is not found, report the error and stop.

## Step 2b: Check for existing reviews on current HEAD

Before fetching the diff and running a new review, check if the PR already has a non-stale review covering the current HEAD:

1. Use `mcp__gitea__list_pull_request_reviews` to get all reviews.
2. Check each review's `stale` field. A review is **not stale** if the PR branch has not changed since it was submitted.
3. If a non-stale review from `code-review-agent` exists, the current code has already been reviewed. Report this to the user:

```
PR #N already has a review from code-review-agent covering the current HEAD ({sha}).
The existing review is not stale — no new commits since it was posted.
```

Then ask the user whether to run a fresh review anyway or stop. Do NOT silently skip — always inform the user and let them decide.

## Step 3: Fetch PR diff

Use `mcp__gitea__get_pull_request_diff` with the same `owner`, `repo`, and `index`.

If the diff is larger than 100KB, note this and focus the review on the largest changed files. Summarize smaller changes.

## Step 4: Extract review standards from AGENTS.md

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/fetch-agents-md.md`

Then extract review-specific standards:
1. Look for the `## Code Review Standards` heading in the file content.
2. Extract from that heading to the next `## ` heading or end of file.
3. If the `## Code Review Standards` section is not found, fall back to the full AGENTS.md content.
4. If no AGENTS.md exists at all, set `{review_standards}` to: `"No repository-specific coding standards found."`

Store the extracted text as `{review_standards}`.

## Step 5: Launch review subagent

Launch **one** Task subagent (`vern:paranoid` persona) that performs four sequential review passes.

Prompt:

```
You are reviewing a pull request. Perform four sequential review passes, "resetting your perspective" between each. For each pass, consult the relevant checklist section and tag every finding with a severity.

## Severity Tags
- **[critical]** — Security vulnerability, data loss risk, broken functionality, or correctness bug. Must be fixed before merge.
- **[warning]** — Meaningful improvement: missing validation, poor error handling, design issue, standards violation. Should be fixed.
- **[nit]** — Style, naming, minor readability. Fix if trivial, skip if not.

## PR: {title}
{pr_body}

## Review Standards
{review_standards}

## Diff
{diff}

## Review Checklists
```
!`cat ${CLAUDE_PLUGIN_ROOT}/lib/review-checklists.md`
```

## Behavioral Rules

Follow these rules strictly. Violating them produces false positives that waste the author's time.

### Do not flag scope or cleanups
- Documentation updates, refactors, and code cleanups included alongside a feature are WELCOME, not a problem. Do NOT flag them as "scope creep" or suggest they belong in a separate PR.
- The ONLY time to flag scope is if a commit message references the wrong issue number (e.g., a commit for issue #50 in a PR for issue #42).

### Validate before asserting
- Do NOT make conditional claims like "if X is true then this is a problem." Instead, CHECK whether X is true using the information available (the diff, the PR body, the repo structure). If you cannot determine the answer, say "I could not verify whether X — worth checking" rather than asserting a problem exists.
- Do NOT claim a version number is wrong without checking what the base branch actually has. The diff shows the change relative to the PR's base — trust it unless you have evidence otherwise.
- Do NOT claim a path or pattern "doesn't work" or is "untested" without evidence. If the PR author uses a pattern, assume they tested it unless the code is demonstrably broken.

### Do not assume things are untested
- If you think a feature might not work in some edge case, research how the system handles it before flagging. Read the code, check the diff context, and look at related files.
- Never say "this is untested" — you don't know what the author tested. Instead, flag specific scenarios that would fail based on the code logic.

### Focus on real problems
- Prioritize findings that would cause actual failures, security issues, or data loss.
- Style preferences, theoretical concerns, and "what if someday" scenarios are nits at most.
- If you're not confident a finding is real, downgrade it or skip it.

## Instructions

Perform the four passes below in order. After each pass, mentally reset — approach the next pass as if seeing the diff fresh.

### Pass 1: Security & Correctness
Review using the Pass 1 checklist. Focus on what could break or be exploited.

### Pass 2: Architecture & Design
Review using the Pass 2 checklist. Focus on structure, patterns, and maintainability. Remember: cleanups and documentation improvements are always welcome — do not flag them as scope issues.

### Pass 3: Standards Compliance
Review using the Pass 3 checklist. Compare against the Review Standards above. Validate any assumptions about versions, paths, or patterns before asserting they are wrong.

### Pass 4: Edge Cases & Robustness
Review using the Pass 4 checklist. Think about what happens at boundaries.

## Output Format

For each pass, list findings in this format. If a pass has no findings, write "No issues found."

### Pass 1: Security & Correctness

**[critical] path/to/file:LINE** — Description of the issue.

**[warning] path/to/file:LINE** — Description of the issue.

### Pass 2: Architecture & Design

**[nit] path/to/file:LINE** — Description of the issue.

### Pass 3: Standards Compliance

**[warning] path/to/file:LINE** — Description of the issue.

### Pass 4: Edge Cases & Robustness

**[warning] path/to/file:LINE** — Description of the issue.

### Summary

2-3 sentence overall assessment of the PR.

IMPORTANT: LINE must be the line number in the NEW version of the file (from the diff's @@ hunk headers, the + side). Only comment on lines that appear in the diff.
```

## Step 6: Synthesize and post review

### Parse findings

From the subagent output, extract all findings matching the pattern `**[severity] path:LINE** — description`. Count findings by severity.

### Compute verdict

- Any `[critical]` finding → verdict is `REQUEST_CHANGES`
- `[warning]` but no `[critical]` → verdict is `COMMENT`
- Only `[nit]` or no findings → verdict is `APPROVE`

### Build review body

Format the review as:

```
## Code Review

### Verdict: {VERDICT}
{count} critical, {count} warnings, {count} nits

### Findings

{All findings from all four passes, in order, preserving severity tags}

### Summary
{Summary from subagent}
```

### Build inline comments

Parse all findings that have a valid `path:LINE`. For each, build a comment object:
- `path` — the file path
- `body` — the full finding text including severity tag (e.g., `[warning] Missing resource limits on container.`)
- `new_line_num` — the line number (integer)

### Post review and set label

Use `mcp__gitea-workflow__post_review` which posts the review as the `code-review-agent` service account AND sets the correct PR label in one call:

- `owner`, `repo`, `index`
- `body`: the formatted review body
- `verdict`: the computed verdict (`"APPROVE"`, `"COMMENT"`, or `"REQUEST_CHANGES"`)
- `comments`: the inline comments array (each with `path`, `body`, `new_line_num`)

The tool automatically:
- Posts the review with `state: "COMMENT"` (verdict is informational, not a merge gate)
- Sets the PR label based on verdict and deploy config (`pr: comments-pending` for criticals/warnings, `pr: ready-to-merge` or `pr: awaiting-dev-verification` for approvals)

## Step 7: Report results

Tell the user:
1. The review was posted successfully (or report any errors)
2. The computed verdict and severity counts
3. A brief summary of key findings
4. How many inline comments were posted
