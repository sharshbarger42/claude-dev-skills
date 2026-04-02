---
name: list-prs
description: List open PRs across repos with workflow status — needs-review, comments-pending, awaiting-dev-verification, awaiting-prod-verification, ready-to-merge.
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

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/resolve-repo.md`

If a specific repo was given, scan only that repo. Otherwise scan every repo in the shorthand table.

## Step 2: Fetch open PRs

For each repo in scope, call `mcp__gitea__list_repo_pull_requests` with `state: "open"`. Paginate if needed (increment `page` until results are empty).

If a repo has no open PRs, skip it silently.

Collect each PR's: `owner`, `repo`, `index`, `title`, `head.ref` (branch), `head.sha`, `user.login` (author), `created_at`, `mergeable`, and `labels`.

## Step 3: Determine status — label fast path

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/pr-status-labels.md`

Check each PR's labels for a `pr:` status label (`pr: needs-review`, `pr: comments-pending`, `pr: awaiting-dev-verification`, `pr: awaiting-prod-verification`, `pr: ready-to-merge`).

- **If a `pr:` label exists:** use it as the PR's status. These labels are kept in sync by `/do-issue`, `/review-pr`, `/fix-pr`, and `/qa-pr` as PRs move through the pipeline.
- **If no `pr:` label exists:** fall through to Steps 4-6 to compute the status from review/comment/CI/QA state.

This fast path avoids expensive API calls for PRs that are already labeled. Most PRs created by the dev workflow skills will have labels.

## Step 4: Gather review and comment state (unlabeled PRs only)

For each PR without a `pr:` label, fetch review and comment data:

1. **Reviews:** Call `mcp__gitea__list_pull_request_reviews` to get all reviews. For each review, record `id`, `state` (`APPROVED`, `REQUEST_CHANGES`, `COMMENT`), `user.login`, and `submitted_at`.

2. **Review comments:** For each `REQUEST_CHANGES` review, call `mcp__gitea__list_pull_request_review_comments` to get inline comments.

3. **Top-level comments:** Call `mcp__gitea__get_issue_comments_by_index` to get PR thread comments.

### Determine if REQUEST_CHANGES reviews are addressed

A `REQUEST_CHANGES` review is **addressed** if:
- It has been dismissed
- A top-level comment from the PR author references the review's comments and includes a commit SHA (the `/fix-pr` summary pattern: `"Addressed review comments in {sha}"`)
- A reply from the PR author exists on the same `path` + `position` with a later timestamp for every inline comment

Track the count of **unaddressed** `REQUEST_CHANGES` reviews and **unaddressed** inline comments per PR.

## Step 5: Check CI and QA status (unlabeled PRs only)

### CI status

For each unlabeled PR:

1. Use the head commit SHA
2. Call `mcp__gitea__list_repo_action_runs` and find runs matching the PR's head branch
3. Record: `passed` (all runs succeeded), `failed` (any run failed), `running` (any run still in progress), or `none` (no CI configured)

### QA status

Check PR labels for QA indicators:
- **QA passed:** has a label containing `qa-passed` or `qa: passed` (case-insensitive)
- **QA failed:** has a label containing `qa-failed` or `qa: failed`
- **QA pending:** no QA label present

Also check top-level comments for QA results:
- A comment containing `✅ **QA Passed**` → QA passed
- A comment containing `❌ **QA Failed**` → QA failed

Use whichever signal is more recent (label timestamp vs comment timestamp). If neither exists, QA is pending.

## Step 6: Assign workflow status (unlabeled PRs only)

Evaluate each unlabeled PR and assign exactly one status, checked in this order:

### `comments-pending`
The PR has unaddressed `REQUEST_CHANGES` reviews or unresolved user comments. Something needs to be fixed before it can move forward.

**Criteria:** Any `REQUEST_CHANGES` review is not addressed, OR a non-bot user left a comment that has no response from the PR author.

### `needs-review`
The PR has no reviews yet, or only has `COMMENT` reviews (no approvals and no outstanding changes requested). It needs someone to review it.

**Criteria:** No `APPROVED` or `REQUEST_CHANGES` reviews exist, OR all `REQUEST_CHANGES` reviews are addressed but there are no `APPROVED` reviews.

### `awaiting-dev-verification`
The PR is approved and review comments are addressed, but dev deploy verification hasn't been done (or failed and needs re-testing). Only applies to repos with a dev deploy config.

**Criteria:** At least one `APPROVED` review exists, all `REQUEST_CHANGES` reviews are addressed, QA status is not `passed`, and the repo has a dev deploy config.

### `awaiting-prod-verification`
The PR was merged but prod deploy health checks haven't passed yet. Only applies to repos with a prod deploy config.

**Criteria:** PR is merged, repo has a prod deploy config, and prod verification hasn't completed.

### `ready-to-merge`
The PR is approved, comments are addressed, and QA is done (or not required). It's good to go.

**Criteria:** At least one `APPROVED` review exists, all `REQUEST_CHANGES` reviews are addressed, QA status is `passed` or the repo has no QA process (no QA labels exist in the repo and no QA comments on any PR), and CI is not `failed`.

### Additional flags

Add these as suffixes when applicable (for both labeled and unlabeled PRs):
- `(ci-failed)` — CI is failing, regardless of other status
- `(merge-conflict)` — `mergeable` is `false`

## Step 7: Present the dashboard

Display results grouped by status. Use a compact table format.

```
## PR Dashboard — {date}

### Ready to Merge
| Repo | PR | Title | Author | Age | CI |
|------|----|-------|--------|-----|----|
| food-automation | #39 | refactor: enforce layer boundary | selina | 2d | passed |

### Awaiting Dev Verification
| Repo | PR | Title | Author | Age | Reviews |
|------|----|-------|--------|-----|---------|
| multi-agent-coordinator | #45 | feat: add monitoring | selina | 5d | 1 approved |

### Awaiting Prod Verification
| Repo | PR | Title | Author | Merged | Deploy |
|------|----|-------|--------|--------|--------|
| food-automation | #38 | fix: parser edge case | selina | 1h | pending |

### Needs Review
| Repo | PR | Title | Author | Age | CI |
|------|----|-------|--------|-----|----|
| food-automation | #41 | feat: new endpoint | selina | 1d | passed |

### Comments Pending
| Repo | PR | Title | Author | Age | Unresolved |
|------|----|-------|--------|-----|------------|
| homelab-setup | #12 | feat: add backup | selina | 8d | 3 comments |

### Summary
- **X** ready to merge
- **Y** awaiting dev verification
- **Z** awaiting prod verification
- **A** needs review
- **B** has pending comments
```

**Age** is calculated from `created_at` to now, displayed as `Nd` (days) or `Nh` (hours if < 1 day).

If any PRs have the `(ci-failed)` or `(merge-conflict)` flags, add a **Warnings** section below the summary listing them.

Omit any status group that has zero PRs — don't show empty tables.

If no open PRs exist across all scanned repos, just say "No open PRs found."
