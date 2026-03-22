---
name: issue-summary
description: Summarize all issues in a Gitea repo — features, bugs, enhancements, sub-task progress, and status breakdown.
---

# Issue Summary Skill

Provide a high-level summary of all issues in a Gitea repo: feature breakdown with sub-task progress, bug/enhancement counts, and status distribution.

**Input:** Repo reference as the skill argument. Accepted formats:
- Shorthand: `food-automation`
- Owner/repo: `super-werewolves/food-automation`

If no argument is provided, ask the user which repo to summarize.

## Step 1: Parse the repo reference

Extract `owner` and `repo` from the argument.

### Repo resolution

!`cat $HOME/.claude/development-skills/lib/resolve-repo.md`

## Step 2: Fetch all issues

Use `mcp__gitea__list_issues` with `state: "open"` to get all open issues. Paginate (increment `page`) until all are fetched.

Then fetch closed issues with `state: "closed"`. Paginate until all are fetched.

For each issue, collect: `number`, `title`, `body`, `labels`, `state`, `milestone`.

**Filter out pull requests:** Gitea's issue list includes PRs. Skip any issue where the `pull_request` field is present and non-null.

## Step 3: Classify issues

Classify each issue by its labels:

### By type (from labels)
- **Feature**: has `feature` label
- **Bug**: has `bug` label
- **Enhancement**: has `enhancement` label
- **Sub-issue**: has `sub-issue` label
- **Other**: none of the above type labels

### By status (from labels)
- **Backlog**: has `status: backlog` label
- **In Progress**: has `status: in-progress` label
- **In Review**: has `status: in-review` label
- **Ready to Test**: has `status: ready-to-test` label
- **Done**: has `status: done` label OR issue state is `closed`
- **No status**: no `status:` label and issue is open

### Special flags
- **Decision Needed**: has `decision-needed` label
- **Contract**: has `contract` label

## Step 4: Identify features and their sub-tasks

For each **feature** issue (open or closed):

1. **Check the issue body** for sub-task references:
   - Checklist items with issue references: `- [ ] #N` or `- [x] #N`
   - A `## Sub-tasks` or `## Subtasks` section

2. **Check all sub-issues** (issues with `sub-issue` label): look for references to this feature in their body (`Part of #N`, `Parent: #N`, or the feature issue number in the body).

3. For each feature, build:
   - Total sub-task count
   - Completed sub-task count (closed issues or `- [x]` checked items)
   - List of sub-task issue numbers

## Step 5: Build the summary

Present the summary in this format:

```
## Issue Summary: {owner}/{repo}

### Overview
| Metric | Count |
|--------|-------|
| Total open issues | {N} |
| Total closed issues | {N} |
| Ready to work (backlog) | {N} |
| In progress | {N} |
| In review | {N} |
| Awaiting decision | {N} |

### Features ({N} total, {M} open)

| # | Title | Status | Sub-tasks | Progress |
|---|-------|--------|-----------|----------|
| #{index} | {title} | {status} | {completed}/{total} | {progress_bar} |
| #{index} | {title} | {status} | — | — |

{For each feature with sub-tasks, show the progress bar as a simple visual:}
{e.g., "5/8 (62%)" or "3/3 (done)"}

### Bugs ({N} total, {M} open)

| # | Title | Status | Priority |
|---|-------|--------|----------|
| #{index} | {title} | {status} | {priority label or "—"} |

### Enhancements ({N} total, {M} open)

| # | Title | Status | Priority |
|---|-------|--------|----------|
| #{index} | {title} | {status} | {priority label or "—"} |

### Other Issues ({N} total, {M} open)

| # | Title | Status |
|---|-------|--------|
| #{index} | {title} | {status} |
```

### Formatting rules

- **Progress bars**: Show as `{completed}/{total} ({percent}%)`. If all done, show `{total}/{total} (done)`.
- **Status**: Use the `status:` label value (e.g., "backlog", "in-progress"). If closed, show "done". If no status label, show "—".
- **Priority**: Extract from `priority:` labels (e.g., "high", "medium", "low"). If none, show "—".
- **Sort order within each section**: Open issues first (sorted by priority: high > medium > low > none), then closed issues.
- **Empty sections**: If a section has zero issues, omit it entirely.
- **Features without sub-tasks**: Show "—" in the Sub-tasks and Progress columns.

## Step 6: Offer next actions

After the summary, suggest relevant next actions based on what was found:

- If there are bugs with `priority: high`: "High-priority bugs to fix: `/do-issue {repo}#{index}`"
- If there are features with incomplete sub-tasks: "Continue feature work: `/do-issue {repo}#{index}`"
- If there are issues awaiting decision: "Issues needing decisions — review before implementing"
- If there are many backlog items: "Run `/triage-issues {repo}` to prioritize the backlog"
