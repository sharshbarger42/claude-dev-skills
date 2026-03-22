---
name: list-prs
description: List open PRs across repos with workflow status — needs-review, comments-pending, needs-qa, ready-to-merge.
---

# List PRs Skill

Show all open pull requests with their current workflow status so the user knows what needs attention.

**Input:** Optional repo reference as the skill argument. Accepted formats:
- Shorthand: `food-automation`
- Owner/repo: `super-werewolves/food-automation`
- `all` — scan every repo in the shorthand table

If no argument is provided, scan all repos.

## Step 1: Resolve repos

### Repo resolution

!`cat $HOME/.claude/development-skills/lib/resolve-repo.md`

If a specific repo was given, scan only that repo. Otherwise scan every repo in the shorthand table.

## Step 2: Fetch open PRs

For each repo in scope, call `mcp__gitea__list_repo_pull_requests` with `state: "open"`. Paginate if needed (increment `page` until results are empty).

If a repo has no open PRs, skip it silently.

Collect each PR's: `owner`, `repo`, `index`, `title`, `head.ref` (branch), `head.sha`, `user.login` (author), `created_at`, `mergeable`, and `labels`.

## Step 3: Gather review and comment state

For each open PR, fetch review and comment data:

1. **Reviews:** Call `mcp__gitea__list_pull_request_reviews` to get all reviews. For each review, record `id`, `state` (`APPROVED`, `REQUEST_CHANGES`, `COMMENT`), `user.login`, and `submitted_at`.

2. **Review comments:** For each `REQUEST_CHANGES` review, call `mcp__gitea__list_pull_request_review_comments` to get inline comments.

3. **Top-level comments:** Call `mcp__gitea__get_issue_comments_by_index` to get PR thread comments.

### Determine if REQUEST_CHANGES reviews are addressed

A `REQUEST_CHANGES` review is **addressed** if:
- It has been dismissed
- A top-level comment from the PR author references the review's comments and includes a commit SHA (the `/fix-pr` summary pattern: `"Addressed review comments in {sha}"`)
- A reply from the PR author exists on the same `path` + `position` with a later timestamp for every inline comment

Track the count of **unaddressed** `REQUEST_CHANGES` reviews and **unaddressed** inline comments per PR.

## Step 4: Check CI status

For each PR:

1. Use the head commit SHA
2. Call `mcp__gitea__list_repo_action_runs` and find runs matching the PR's head branch
3. Record: `passed` (all runs succeeded), `failed` (any run failed), `running` (any run still in progress), or `none` (no CI configured)

## Step 5: Check for QA status

For each PR, check its labels for QA indicators:
- **QA passed:** has a label containing `qa-passed` or `qa: passed` (case-insensitive)
- **QA failed:** has a label containing `qa-failed` or `qa: failed`
- **QA pending:** no QA label present

Also check top-level comments for QA results:
- A comment containing `✅ **QA Passed**` → QA passed
- A comment containing `❌ **QA Failed**` → QA failed

Use whichever signal is more recent (label timestamp vs comment timestamp). If neither exists, QA is pending.

## Step 6: Assign workflow status

Evaluate each PR and assign exactly one status, checked in this order:

### `comments-pending`
The PR has unaddressed `REQUEST_CHANGES` reviews or unresolved user comments. Something needs to be fixed before it can move forward.

**Criteria:** Any `REQUEST_CHANGES` review is not addressed, OR a non-bot user left a comment that has no response from the PR author.

### `needs-review`
The PR has no reviews yet, or only has `COMMENT` reviews (no approvals and no outstanding changes requested). It needs someone to review it.

**Criteria:** No `APPROVED` or `REQUEST_CHANGES` reviews exist, OR all `REQUEST_CHANGES` reviews are addressed but there are no `APPROVED` reviews.

### `needs-qa`
The PR is approved and review comments are addressed, but QA hasn't been done (or QA failed and needs re-testing).

**Criteria:** At least one `APPROVED` review exists, all `REQUEST_CHANGES` reviews are addressed, and QA status is not `passed`.

### `ready-to-merge`
The PR is approved, comments are addressed, and QA is done (or not required). It's good to go.

**Criteria:** At least one `APPROVED` review exists, all `REQUEST_CHANGES` reviews are addressed, QA status is `passed` or the repo has no QA process (no QA labels exist in the repo and no QA comments on any PR), and CI is not `failed`.

### Additional flags

Add these as suffixes when applicable:
- `(ci-failed)` — CI is failing, regardless of other status
- `(merge-conflict)` — `mergeable` is `false`

## Step 7: Present the dashboard

Display results grouped by status. Use a compact table format.

```
## PR Dashboard — {date}

### Ready to Merge ✅
| Repo | PR | Title | Author | Age | CI |
|------|----|-------|--------|-----|----|
| food-automation | #39 | refactor: enforce layer boundary | selina | 2d | passed |

### Needs QA 🧪
| Repo | PR | Title | Author | Age | Reviews |
|------|----|-------|--------|-----|---------|
| homelab-setup | #45 | feat: add monitoring | selina | 5d | 1 approved |

### Needs Review 👀
| Repo | PR | Title | Author | Age | CI |
|------|----|-------|--------|-----|----|
| food-automation | #41 | feat: new endpoint | selina | 1d | passed |

### Comments Pending 💬
| Repo | PR | Title | Author | Age | Unresolved |
|------|----|-------|--------|-----|------------|
| homelab-setup | #12 | feat: add backup | selina | 8d | 3 comments |

### Summary
- **X** ready to merge
- **Y** needs QA
- **Z** needs review
- **W** has pending comments
```

**Age** is calculated from `created_at` to now, displayed as `Nd` (days) or `Nh` (hours if < 1 day).

If any PRs have the `(ci-failed)` or `(merge-conflict)` flags, add a **Warnings** section below the summary listing them.

Omit any status group that has zero PRs — don't show empty tables.

If no open PRs exist across all scanned repos, just say "No open PRs found."
