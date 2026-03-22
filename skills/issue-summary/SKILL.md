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

## Step 2: Fetch open issues

Use `mcp__gitea__list_issues` with `state: "open"` to get all open issues. Paginate (increment `page`) until all are fetched.

**Do NOT fetch closed issues.** This skill focuses on active/remaining work only.

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
- **No status**: no `status:` label

### Special flags
- **Decision Needed**: has `decision-needed` label
- **Contract**: has `contract` label

## Step 4: Identify features and their sub-tasks

For each **feature** issue:

1. **Check the issue body** for sub-task references:
   - Checklist items with issue references: `- [ ] #N` or `- [x] #N`
   - A `## Sub-tasks` or `## Subtasks` section

2. **Check all sub-issues** (issues with `sub-issue` label): look for references to this feature in their body (`Part of #N`, `Parent: #N`, or the feature issue number in the body).

3. For each feature, build:
   - Total sub-task count
   - Completed sub-task count: a sub-task is "done" if its `- [x]` checkbox is checked in the parent body, OR if the sub-task issue number does NOT appear in the open issues list (meaning it was closed). Do NOT fetch closed issues to check — simply compare against the open issue numbers already fetched.

**Do NOT list individual sub-tasks** — only show the count (e.g., "3/12 done"). Sub-tasks are rolled up into their parent feature's progress.

## Step 5: Build the summary

Present the summary in this format:

```
## Issue Summary: {owner}/{repo}

### Overview
| Metric | Count |
|--------|-------|
| Total open issues | {N} |
| Ready to work (backlog) | {N} |
| In progress | {N} |
| In review | {N} |
| Awaiting decision | {N} |

### Features ({N})

| # | Title | Status | Sub-tasks |
|---|-------|--------|-----------|
| #{index} | {title} | {status} | {completed}/{total} done |
| #{index} | {title} | {status} | — |

### Bugs ({N})

| # | Title | Status | Priority |
|---|-------|--------|----------|
| #{index} | {title} | {status} | {priority label or "—"} |

### Enhancements ({N})

| # | Title | Status | Priority |
|---|-------|--------|----------|
| #{index} | {title} | {status} | {priority label or "—"} |

### Other Issues ({N})

| # | Title | Status |
|---|-------|--------|
| #{index} | {title} | {status} |
```

### Formatting rules

- **Sub-tasks**: Show as `{completed}/{total} done`. If all done, show `{total}/{total} done`. If no sub-tasks, show "—".
- **Status**: Use the `status:` label value (e.g., "backlog", "in-progress"). If no status label, show "—".
- **Priority**: Extract from `priority:` labels (e.g., "high", "medium", "low"). If none, show "—".
- **Sort order within each section**: Sorted by priority: high > medium > low > none.
- **Empty sections**: If a section has zero issues, omit it entirely.

## Step 6: Offer next actions

After the summary, suggest relevant next actions based on what was found:

- If there are bugs with `priority: high`: "High-priority bugs to fix: `/do-issue {repo}#{index}`"
- If there are features with incomplete sub-tasks: "Continue feature work: `/do-issue {repo}#{index}`"
- If there are issues awaiting decision: "Issues needing decisions — review before implementing"
- If there are many backlog items: "Run `/triage-issues {repo}` to prioritize the backlog"
