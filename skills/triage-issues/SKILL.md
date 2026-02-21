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

## Step 3: Fetch open PRs

Use `mcp__gitea__list_repo_pull_requests` with `state: "open"` to get all open pull requests. For each PR, note:
- PR number and title
- Head branch
- Whether it's mergeable (`mergeable` field)
- Number of comments

Filter out any PRs that also appeared in the Step 2 issues list (Gitea returns PRs in the issues endpoint too — match by `pull_request` field being present and skip those from the issues list).

## Step 4: Fetch milestones

Use `mcp__gitea__list_milestones` with `state: "open"` to get active milestones and their due dates.

## Step 5: Classify issues

For each open issue, determine if it is **blocked** or **actionable**.

An issue is **blocked** if any of these are true:
- It has a label whose name contains `blocked`, `waiting`, `on-hold`, or `depends` (case-insensitive)
- Its body contains an unchecked dependency like `- [ ] Depends on #N` or `Blocked by #N` where #N is still open
- It has a label whose name contains `wontfix`, `duplicate`, or `invalid`

Everything else is **actionable**.

Additionally, note issues with `status: in-progress` or `status: in-review` labels — these are already being worked on. Include them in the output but deprioritize them (they will receive a scoring penalty in Step 6).

## Step 6: Score and rank actionable issues

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
| In progress or in review | -3 | Has `status: in-progress` or `status: in-review` label |
| Oldest issue | +1 | Created more than 30 days ago (avoid staleness) |

Break ties by issue number (lower = older = higher priority).

## Step 7: Present results

Output a report in this format:

```
## {repo} Issue Triage

**{N} open issues** — {actionable_count} actionable, {blocked_count} blocked

### Open PRs

| PR | Title | Branch | Mergeable | Comments |
|----|-------|--------|-----------|----------|
| #{number} | {title} | {head_branch} | {Yes/No/Conflicts} | {comment_count} |

If there are open PRs, show this section with a note:
> These PRs should be reviewed/merged before starting new work. Run `/review-pr {repo}#{number}` to review, or `/merge-prs {repo}` to merge ready PRs.

If no open PRs, omit this section.

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
```

### Quick Actions

The very last section of the output. List all runnable commands together so the user can copy-paste without scrolling.

```
### Quick Actions

> `/review-pr {repo}#{pr_number}` — review PR #{pr_number}
> `/merge-prs {repo}` — merge ready PRs
> `/do-issue {repo}#{index}` — start #{index} {title}
> `/do-issue {repo}#{index}` — start #{index} {title}
> `/do-issue {repo}#{index}` — start #{index} {title}
```

Rules:
- If there are open PRs, list `/review-pr` for each PR first, then `/merge-prs` once
- Then list `/do-issue` for each of the top 5 recommended issues
- If there are no open PRs, omit the PR commands
- Each line is a blockquote so it renders as a distinct copyable block

Keep the output concise. No fluff.
