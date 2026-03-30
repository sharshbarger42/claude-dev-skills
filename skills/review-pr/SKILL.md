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

!`cat $HOME/.claude/development-skills/lib/resolve-repo.md`

## Step 2: Fetch PR metadata

Use `mcp__gitea__get_pull_request_by_index` with the parsed `owner`, `repo`, and `index` to get:
- PR title
- PR body/description
- Base and head branches
- Default branch (`base.repo.default_branch`)

If the PR is not found, report the error and stop.

## Step 3: Fetch PR diff

Use `mcp__gitea__get_pull_request_diff` with the same `owner`, `repo`, and `index`.

If the diff is larger than 100KB, note this and focus the review on the largest changed files. Summarize smaller changes.

## Step 4: Extract review standards from AGENTS.md

!`cat $HOME/.claude/development-skills/lib/fetch-agents-md.md`

Then extract review-specific standards:
1. Look for the `## Code Review Standards` heading in the file content.
2. Extract from that heading to the next `## ` heading or end of file.
3. If the `## Code Review Standards` section is not found, fall back to the full AGENTS.md content.

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
!`cat $HOME/.claude/development-skills/lib/review-checklists.md`
```

## Instructions

Perform the four passes below in order. After each pass, mentally reset — approach the next pass as if seeing the diff fresh.

### Pass 1: Security & Correctness
Review using the Pass 1 checklist. Focus on what could break or be exploited.

### Pass 2: Architecture & Design
Review using the Pass 2 checklist. Focus on structure, patterns, and maintainability.

### Pass 3: Standards Compliance
Review using the Pass 3 checklist. Compare against the Review Standards above.

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

### Post via MCP

Use `mcp__gitea-reviewer__create_pull_request_review` with:
- `owner`, `repo`, `index`
- `state`: always `"COMMENT"` — the agent recommends but never gates merges
- `body`: the formatted review body
- `comments`: the inline comments array

**Important:** Always post with `state: "COMMENT"` regardless of the computed verdict. The verdict is informational (shown in the review body), not a merge gate.

If the MCP tool is not available (new session without restart), fall back to curl:

```bash
curl -s -X POST \
  -H "Authorization: token $(cat $HOME/.config/code-review-agent/token)" \
  -H "Content-Type: application/json" \
  "https://git.home.superwerewolves.ninja/api/v1/repos/{owner}/{repo}/pulls/{index}/reviews" \
  -d @/tmp/review-payload.json
```

Where `/tmp/review-payload.json` contains `{"body": "...", "event": "COMMENT", "comments": [...]}` with `new_position` (NOT `new_line_num`) for the REST API.

**CRITICAL:** The Gitea REST API uses `new_position` for inline comment line numbers. The MCP tool uses `new_line_num`. These are different field names for the same concept — using the wrong one causes comments to silently collapse to position 0.

## Step 6b: Update PR status label

!`cat $HOME/.claude/development-skills/lib/pr-status-labels.md`

!`cat $HOME/.claude/development-skills/lib/deploy-aware-label.md`

After posting the review, update the PR's status label based on the computed verdict:

- **Verdict has any `[critical]` or `[warning]` findings** → set `pr: comments-pending`
- **Verdict `APPROVE`** (only nits or no findings) → check deploy config:
  - Repo has dev deploy config → set `pr: awaiting-dev-verification`
  - Repo has no dev deploy config → set `pr: ready-to-merge`

Use the PR status label swap procedure from pr-status-labels.md.

## Step 7: Report results

Tell the user:
1. The review was posted successfully (or report any errors)
2. The computed verdict and severity counts
3. A brief summary of key findings
4. How many inline comments were posted
