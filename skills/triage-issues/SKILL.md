---
name: triage-issues
description: List open issues in a Gitea repo that aren't blocked, and recommend which to tackle next.
---

# Triage Issues Skill

List all open, unblocked issues in a Gitea repo and recommend which to work on next.

**Input:** Repo reference as the skill argument. Accepted formats:
- Shorthand: `food-automation`
- Owner/repo: `super-werewolves/food-automation`

If no argument is provided, ask the user which repo to triage.

## Step 1: Parse the repo reference

Extract `owner` and `repo` from the argument.

### Repo resolution

!`cat $HOME/gitea-repos/development-skills/lib/resolve-repo.md`

## Step 2: Fetch all open issues

Use `mcp__gitea__list_repo_issues` with `state: "open"` to get all open issues. If there are more than 100, paginate (increment `page`) until all are fetched.

## Step 3: Fetch milestones

Use `mcp__gitea__list_milestones` with `state: "open"` to get active milestones and their due dates.

## Step 4: Classify issues

For each open issue, determine if it is **blocked** or **actionable**.

An issue is **blocked** if any of these are true:
- It has a label whose name contains `blocked`, `waiting`, `on-hold`, or `depends` (case-insensitive)
- Its body contains an unchecked dependency like `- [ ] Depends on #N` or `Blocked by #N` where #N is still open
- It has a label whose name contains `wontfix`, `duplicate`, or `invalid`

Everything else is **actionable**.

## Step 5: Score and rank actionable issues

Score each actionable issue using these factors (higher = tackle sooner):

| Factor | Points | Condition |
|--------|--------|-----------|
| Milestone due soon | +3 | Issue is in a milestone due within 7 days |
| Milestone due eventually | +1 | Issue is in a milestone due within 30 days |
| Has `priority` or `urgent` label | +3 | Case-insensitive label match |
| Has `bug` or `fix` label | +2 | Bugs before features |
| Has `enhancement` or `feature` label | +1 | Nice to have |
| Low complexity signal | +1 | Body is under 500 characters (likely a small task) |
| High complexity signal | -1 | Body is over 2000 characters (likely a big task) |
| Already assigned | -2 | Someone else may be working on it |
| Oldest issue | +1 | Created more than 30 days ago (avoid staleness) |

Break ties by issue number (lower = older = higher priority).

## Step 6: Present results

Output a report in this format:

```
## {repo} Issue Triage

**{N} open issues** — {actionable_count} actionable, {blocked_count} blocked

### Recommended Next

| # | Priority | Issue | Labels | Milestone | Why |
|---|----------|-------|--------|-----------|-----|
| 1 | ★★★ | #{index} {title} | {labels} | {milestone or —} | {1-line reason} |
| 2 | ★★☆ | #{index} {title} | {labels} | {milestone or —} | {1-line reason} |
| 3 | ★☆☆ | #{index} {title} | {labels} | {milestone or —} | {1-line reason} |

Show up to 5 recommended issues. Use ★ to indicate relative priority (★★★ = highest).

### Blocked

| Issue | Reason |
|-------|--------|
| #{index} {title} | {why it's blocked — label name or dependency} |

If no blocked issues, omit this section.

### All Actionable (remaining)

If there are more actionable issues beyond the top 5, list them briefly:
- #{index} {title} ({labels})
```

### Top Recommendation Detail

After everything else, show the full details of the #1 recommended issue so the user sees it last (closest to their cursor, no scrolling needed):

```
### Up Next: #{index} {title}

{issue body — render the full body as-is}

> Run `/do-issue {repo}#{index}` to start working on this issue.
```

Keep the output concise. No fluff.
