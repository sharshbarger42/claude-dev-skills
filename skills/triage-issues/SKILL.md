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

!`cat $HOME/.claude/development-skills/lib/resolve-repo.md`

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

An issue is **awaiting decision** if it has the `decision-needed` label. These are NOT blocked in the traditional sense — they need a human to make a call before an agent can implement. Track them separately for the "Awaiting Decision" section in Step 7.

Separately, flag issues that appear to be **duplicates** of each other — these are handled interactively in Step 5b rather than silently blocked.

Everything else is **actionable**.

Additionally, **exclude** issues with `status: in-progress` or `status: in-review` labels entirely from the recommended list — these are already being worked on and should not be suggested. Track them separately for the "Currently Active" section in Step 7.

Also **exclude** `decision-needed` issues from the recommended list and scoring — they cannot be auto-implemented until the decision is resolved. Track them for the "Awaiting Decision" section in Step 7.

## Step 5b: Detect duplicates

Compare all open issues pairwise looking for likely duplicates. Two issues are **likely duplicates** if any of these are true:
- Their titles are identical or near-identical (ignoring case and punctuation)
- Their bodies share the same core content (e.g., same error message, same PR reference, same root cause)
- One issue's body references the other (e.g., "same as #N" or "duplicate of #N")

For each duplicate group found:
1. Pick the **recommended survivor** — prefer the issue that has: more labels, a milestone, more comments, or a lower issue number (older = canonical)
2. Mark the others as duplicate candidates

Present duplicates to the user using `AskUserQuestion` **before** showing the triage report. For each duplicate group, ask what to do:

- **Close #{duplicate} as duplicate of #{survivor} (Recommended)** — close the duplicate issue with a comment linking to the survivor
- **Close #{survivor} as duplicate of #{duplicate}** — close the other one instead (if the newer issue is better scoped)
- **Keep both** — they look similar but are actually distinct; leave them open

If the user chooses to close a duplicate:
1. Post a comment on the issue being closed: `Closing as duplicate of #{survivor}.`
2. Close the issue using `mcp__gitea__edit_issue` with `state: "closed"`
3. Remove the closed issue from the triage results

If there are no duplicates detected, skip this step silently.

## Step 6: Score and rank actionable issues

Score each actionable issue using these factors (higher = tackle sooner):

| Factor | Points | Condition |
|--------|--------|-----------|
| Milestone due soon | +3 | Issue is in a milestone due within 7 days |
| Milestone due eventually | +1 | Issue is in a milestone due within 30 days |
| Has `priority: high` label | +3 | Tackle first |
| Has `priority: medium` label | +1 | Normal queue |
| Has `priority: low` label | -1 | Nice to have, deprioritize |
| Has `bug` or `fix` label | +2 | Bugs before features |
| Has `enhancement` or `feature` label | +1 | Nice to have |
| Low complexity signal | +1 | Body is under 500 characters (likely a small task) |
| High complexity signal | -1 | Body is over 2000 characters (likely a big task) |
| Already assigned | -2 | Someone else may be working on it |
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

### Currently Active

Show issues that are currently being worked on (have `status: in-progress` or `status: in-review` labels). If Agent Mail is available, query for richer context:

!`cat $HOME/.claude/development-skills/lib/agent-coordination.md`

Use the **Query Active Work** procedure to get agent names and timestamps.

| Issue | Status | Agent | Started | Note |
|-------|--------|-------|---------|------|
| #{index} {title} | in-progress | {agent_name or "unknown"} | {relative_time} | {stale_warning if >2h} |
| #{index} {title} | in-review | — | — | PR open |

If no issues are currently active, omit this section.

### Awaiting Decision

Show issues that have the `decision-needed` label. For each, briefly summarize the pending question (from the issue comments or body):

| Issue | Decision Needed |
|-------|----------------|
| #{index} {title} | {1-line summary of the open question} |

If no decision-needed issues, omit this section.

> To resolve a decision and start work: `/do-issue {repo}#{index}` — you'll be prompted with the open question first.

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
