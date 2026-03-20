---
name: fix-pr
description: Fetch all comments on a Gitea PR, classify them, implement fixes, commit, and push. Handles both user directives and review-agent suggestions.
---

# Fix PR Skill

Address all review comments on a Gitea pull request: fetch comments, classify by source, implement fixes, and push to the PR branch.

**Input:** PR reference as the skill argument. Accepted formats:
- Shorthand: `food-automation#34`
- Owner/repo: `super-werewolves/food-automation#34`
- Full URL: `https://git.home.superwerewolves.ninja/super-werewolves/food-automation/pulls/34`

## Session persistence

!`cat $HOME/.claude/development-skills/lib/session-state.md`

At skill start, call **Session Read** to check for prior context. Then call **Session Write** after these milestones:
- After Step 2 (PR metadata fetched — record PR title, branches)
- After Step 4 (comments classified — record comment counts and planned actions)
- After Step 6 (user confirmed plan — record what will be fixed vs deferred)
- After Step 9 (committed and pushed — record commit SHA, files changed)
At the end of Step 11 (report), call **Session Clear**.

**Parent-child note:** If invoked from `/do-the-thing`, the parent manages the session file. Check if the session file already exists with `Skill: do-the-thing` — if so, skip all Session Write/Read/Clear and let the parent handle it.

## Step 1: Parse the PR reference

Extract `owner`, `repo`, and PR `index` from the argument.

### Repo resolution

!`cat $HOME/.claude/development-skills/lib/resolve-repo.md`

## Step 1b: Establish identity and register active work

!`cat $HOME/.claude/development-skills/lib/agent-identity.md`

Derive your `AGENT_NAME` for this session.

!`cat $HOME/.claude/development-skills/lib/agent-coordination.md`

Register active work on this PR using the **Register Active Work** procedure from `agent-coordination.md`. Use the PR index as the issue index and the PR title as the issue title.

!`cat $HOME/.claude/development-skills/lib/discord-notify.md`

Post a "Started Work" Discord notification for this PR.

## Step 2: Fetch PR metadata

Use `mcp__gitea__get_pull_request_by_index` with the parsed `owner`, `repo`, and `index` to get:
- Title, body
- Head branch (this is the branch we'll check out and push to)
- Base branch
- Default branch (`base.repo.default_branch`)

If the PR is not found, report the error and stop.

## Step 2b: Check for merge conflicts

Check the `mergeable` field from the PR metadata. If `mergeable` is `false`, the PR has conflicts with the base branch that must be resolved before review comments can be addressed.

### Resolve conflicts

1. `cd` to the local repo path from the shorthand table
2. `git fetch origin`
3. `git checkout {head_branch} && git pull origin {head_branch}`
4. Attempt to rebase onto the base branch: `git rebase origin/{base_branch}`
5. If the rebase produces conflicts:
   - Read each conflicting file and resolve the conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`)
   - For each conflict, determine the correct resolution by understanding what both sides intended:
     - The base branch side (`HEAD` / `ours` during rebase) has changes that were merged to main after the PR was created
     - The PR branch side (`theirs` during rebase) has the PR's changes
     - Usually the correct resolution is to keep **both** sets of changes merged together
   - After resolving all conflicts in a file, `git add {file}`
   - Run `git rebase --continue` to proceed to the next commit
   - Repeat until the rebase completes
6. Force-push the rebased branch: `git push origin {head_branch} --force-with-lease`
7. Verify the PR is now mergeable by re-fetching PR metadata

Report which files had conflicts and how they were resolved.

If `mergeable` is `true`, skip this step entirely.

## Step 3: Fetch all comments

Gather every comment on the PR from three sources:

1. **Review comments (inline):** Use `mcp__gitea__list_pull_request_reviews` to get all reviews. For each review, use `mcp__gitea__list_pull_request_review_comments` to get the inline comments (these have `path`, `position`, and `body`).

2. **Top-level PR comments:** Use `mcp__gitea__get_issue_comments_by_index` to get non-review comments on the PR thread.

Collect all comments into a single list with these fields per comment:
- `id` (comment ID — needed for resolving later)
- `review_id` (the parent review ID, if inline comment)
- `review_state` (the parent review's state: `APPROVED`, `REQUEST_CHANGES`, `COMMENT`)
- `path` (file path, if inline comment; empty for top-level)
- `position` (line position, if inline)
- `body` (comment text)
- `user.login` (who posted it)
- `source` (see Step 4)

## Step 4: Classify comments

Split comments by `user.login`:

- **User comments** — any comment where `user.login` is NOT `code-review-agent`. These are directives and MUST be addressed. Top priority. User comments have no severity concept — they are always required.
- **Review agent comments** — comments where `user.login` IS `code-review-agent`. Parse severity from the comment body.

### Severity parsing (review-agent comments only)

Scan the comment `body` for severity tags:
- `[critical]` → required — treat same as user comments, must be fixed
- `[warning]` → fix if straightforward, create issue if complex
- `[nit]` → skip unless the fix is trivially mechanical (e.g., rename, whitespace)
- No tag found → default to `warning` (backwards compatibility with older reviews)

### Documentation comments (always fix)

Any comment requesting documentation updates — README changes, doc corrections, adding/updating comments, fixing docstrings, updating AGENTS.md, or similar — is **always addressed directly** in this PR regardless of severity. Documentation fixes are low-risk and fast to implement, so they should never be deferred to a separate issue. This applies to both user comments and review-agent comments at any severity level.

**Threading:** Group comments that share the same `path` + `position`. When a user replies to a review-agent comment on the same path/position, the user's reply modifies or overrides the agent's suggestion — use the user's intent.

For each actionable comment, extract:
- `path` — file to change
- `position` — where in the file
- `body` — what to do
- `source` — `user` or `review-agent`
- `severity` — `critical`, `warning`, or `nit` (user comments: always `required`)
- `action` — what change is needed (fix code, create issue, skip, etc.)

## Step 5: Read repo AGENTS.md

Use `mcp__gitea__get_file_contents` to fetch `AGENTS.md` from the repo's default branch (from Step 2 metadata — do NOT hardcode `master` or `main`).

If AGENTS.md doesn't exist, note that no repo-specific coding standards were found and proceed without it.

## Step 6: Present summary and confirm

Show the user a summary:
- Count: **X user comments**, **Y bot critical**, **Z bot warnings**, **N bot nits**
- Brief description of each comment and the proposed action (fix / create issue / skip)
- Nits planned to skip (with reason: "nit — not trivially mechanical")
- Warnings planned as issues (with reason: "complex — will create issue instead")

Use `AskUserQuestion` to get confirmation. **Do NOT start coding until the user confirms.**

## Step 7: Set up workspace

Run these commands using the Bash tool:

1. `cd` to the local repo path from the shorthand table
2. Verify the directory exists — if not, tell the user to clone the repo first and stop
3. `git fetch origin`
4. `git checkout {head_branch} && git pull origin {head_branch}`
5. Verify clean working tree (`git status --porcelain`) — if dirty, warn the user and ask how to proceed

No new branch creation — we push directly to the existing PR branch.

## Step 8: Implement the changes

Read the relevant files and address comments in priority order:

1. **User comments** (always required) — implement exactly what the user asked for
2. **Documentation comments** (always fix) — any comment requesting doc updates (README, AGENTS.md, code comments, docstrings, etc.) is always addressed directly regardless of severity. Never create a separate issue for documentation.
3. **Bot `[critical]`** (required) — treat same as user comments, must be fixed
4. **Bot `[warning]`** (fix or defer) — fix if the change is straightforward. If complex (requires architectural changes, new dependencies, or significant refactoring), create a Gitea issue instead using `mcp__gitea__create_issue` with title `"[review] {brief description}"` and body referencing the PR. If the issue describes a bug (broken behavior, correctness problem), label it with `bug` — see labeling procedure below.
5. **Bot `[nit]`** (skip unless trivial) — only fix if the change is purely mechanical (rename, whitespace, typo). Skip all others
6. **Issue creation** — for comments that explicitly say "create a ticket for X" or similar, use `mcp__gitea__create_issue`. If the issue describes a bug, label it with `bug`.

### Labeling created issues

When creating an issue that represents a bug (broken behavior, security vulnerability, correctness problem — NOT feature requests or refactoring):
1. Call `mcp__gitea__list_repo_labels` to find the `bug` label ID for the repo
2. Call `mcp__gitea__add_issue_labels` with the new issue index and the `bug` label ID
3. If no `bug` label exists in the repo, skip labeling silently

Follow the repo's AGENTS.md coding standards when making changes.

## Step 9: Commit and push

1. Stage changed files individually (`git add <file1> <file2> ...` — NOT `git add -A` or `git add .`)
2. Commit with message format: `fix(#{pr_index}): address PR review — {brief summary}`
   - **IMPORTANT:** Per AGENTS.md Rule 3 — NO Claude/AI/co-authored-by references in commit messages
3. Push to the head branch: `git push origin {head_branch}`

## Step 10: Resolve addressed comments

After pushing, mark addressed comments as resolved on the PR:

1. **Reply to each inline comment** that was addressed: use `mcp__gitea__create_issue_comment` to post a brief top-level comment summarizing which comments were fixed and the commit SHA. Format:

   ```
   Addressed review comments in {commit_sha}:
   - {path}:{position} — {brief description of fix}
   - {path}:{position} — {brief description of fix}
   ```

2. **Dismiss `REQUEST_CHANGES` reviews** that are now fully addressed: use `mcp__gitea__dismiss_pull_request_review` with the `review_id` from Step 3 and message `"All requested changes addressed in {commit_sha}"`. Only dismiss reviews where **every** inline comment from that review was addressed.

   Do NOT dismiss reviews where some comments were skipped — those still need attention.

3. **Re-request review** (optional): if the review was from `code-review-agent` and changes were significant, note in the report that the user may want to re-run `/review-pr` to verify.

## Step 11: Report

**Deregister active work:** Send an Agent Mail completion message using the **Deregister Active Work** procedure from `agent-coordination.md`. Post a Discord notification. Best-effort — skip silently if unavailable.

Tell the user, grouped by outcome:

### Addressed
- `[severity] path:line` — description (fixed in commit)

### Issues Created
- `[warning] path:line` — description → Issue #N

### Skipped
- `[nit] path:line` — description (not trivially mechanical)

Also report:
- **Reviews dismissed** — list any `REQUEST_CHANGES` reviews that were dismissed
- **Files changed** — list of modified files
