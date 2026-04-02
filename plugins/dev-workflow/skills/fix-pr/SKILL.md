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

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/session-state.md`

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

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/resolve-repo.md`

## Step 1b: Establish identity and register active work

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/agent-identity.md`

Derive your `AGENT_NAME` for this session.

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/agent-coordination.md`

Register active work on this PR using the **Register Active Work** procedure from `agent-coordination.md`. Use the PR index as the issue index and the PR title as the issue title.

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/discord-notify.md`

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

### 3a: Check for new comments since last push

Compare the PR's current HEAD SHA (`head.sha` from Step 2) against each review's `submitted_at` timestamp and `stale` field. A review is **stale** if the PR branch has been updated (force-pushed or new commits) since the review was submitted.

If **all** reviews are stale and there are no non-stale top-level user comments posted after the PR's latest commit, then all feedback has already been addressed. Report this to the user:

```
All reviews on PR #N are stale (submitted before the current HEAD {sha}).
No new comments found since the last push. Nothing to fix.
```

Then ask the user whether to proceed anyway or stop. Do NOT silently skip — always inform the user and let them decide.

### 3b: Gather comments

Gather every comment on the PR from these sources:

1. **Review comments (inline):** Use `mcp__gitea__list_pull_request_reviews` to get all reviews. For each review, use `mcp__gitea__list_pull_request_review_comments` to get the inline comments (these have `path`, `position`, and `body`).

2. **Top-level PR comments:** Use `mcp__gitea__get_issue_comments_by_index` to get non-review comments on the PR thread.

When processing reviews, record the `stale` field from each review. Stale reviews should still be included in the comment list but flagged — the user may want to re-address them or may have already handled them.

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
- `[warning]` → evaluate with disposition criteria below
- `[nit]` → evaluate with disposition criteria below
- No tag found → default to `warning` (backwards compatibility with older reviews)

### Disposition criteria (review-agent comments only)

After parsing severity, evaluate each review-agent `[warning]` and `[nit]` comment against these criteria **in order**. Assign the first matching disposition. User comments and `[critical]` comments always get disposition `fix`.

1. **`non-issue`** — The comment is wrong, irrelevant, based on a misunderstanding of the code, or describes something that isn't actually a problem. **Action:** skip entirely — do not fix, do not create an issue. Note the specific reason it's a non-issue.

2. **`complex-out-of-scope`** — The comment identifies a real improvement, but fixing it is **genuinely complex**: requires architectural changes, new dependencies, significant refactoring, touches multiple subsystems, or work that goes well beyond the scope of this PR. **This disposition may NOT be used for easy wins** — if the fix can be done in a few lines or a single straightforward change, it must get disposition `fix` instead, even if it's tangential to the PR's purpose. **Action:** create a Gitea issue tagged `[review]` for later. Label with type and priority per the labeling procedure below.

3. **`questionable-benefit`** — The comment suggests a change that is technically valid but the benefit is debatable — stylistic preferences, marginal improvements, trade-offs where reasonable people disagree. The user should decide whether it's worth doing. **Action:** create a Gitea issue tagged `[review][decision-needed]` with a brief explanation of the trade-off. Label with type `enhancement` and priority `low`. These issues are for human review, not auto-pickup.

4. **`fix`** — The comment identifies a real, clear improvement that can be implemented in this PR without significant complexity. **Action:** implement the fix.

**Documentation comments** are an exception: any comment requesting documentation updates (README, doc corrections, comments, docstrings, AGENTS.md, etc.) always gets disposition `fix` regardless of severity. Documentation fixes are low-risk and fast, so they should never be deferred.

### Threading

Group comments that share the same `path` + `position`. When a user replies to a review-agent comment on the same path/position, the user's reply modifies or overrides the agent's suggestion — use the user's intent.

### Comment record

For each comment, extract:
- `path` — file to change
- `position` — where in the file
- `body` — what to do
- `source` — `user` or `review-agent`
- `severity` — `critical`, `warning`, or `nit` (user comments: always `required`)
- `disposition` — `fix`, `non-issue`, `complex-out-of-scope`, or `questionable-benefit`
- `disposition_reason` — one-line explanation of why this disposition was chosen (required for all non-`fix` dispositions)

## Step 5: Read repo AGENTS.md

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/fetch-agents-md.md`

## Step 6: Present summary and confirm

Show the user a summary:
- Count: **X user comments**, **Y bot critical**, **Z bot warnings**, **N bot nits**
- Brief description of each comment grouped by disposition:
  - **Will fix** — comments with disposition `fix` (and all user/critical comments)
  - **Non-issue** — comments with disposition `non-issue`, with the specific reason
  - **Out of scope (→ issue)** — comments with disposition `complex-out-of-scope`, with why
  - **Needs your call (→ decision issue)** — comments with disposition `questionable-benefit`, with the trade-off

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

Read the relevant files and process comments by disposition:

1. **disposition: `fix`** — Implement the change. This includes all user comments, all `[critical]` comments, all documentation comments, and any `[warning]`/`[nit]` comments evaluated as worth fixing.
2. **disposition: `non-issue`** — Skip entirely. Do not fix, do not create an issue. The comment will appear in the report with the reason it was classified as a non-issue.
3. **disposition: `complex-out-of-scope`** — Create a Gitea issue using `mcp__gitea__create_issue` with title `"[review] {brief description}"` and body referencing the PR and quoting the original comment. Label with type and priority — see labeling procedure below.
4. **disposition: `questionable-benefit`** — Create a Gitea issue using `mcp__gitea__create_issue` with title `"[review][decision-needed] {brief description}"` and body explaining the trade-off and referencing the PR. Label with type `enhancement` and priority `low`. These issues are for human triage, not auto-pickup.
5. **Explicit issue requests** — comments that say "create a ticket for X" or similar: use `mcp__gitea__create_issue`. Label with type and priority.

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/label-issue.md`

Follow the repo's AGENTS.md coding standards when making changes.

## Step 9: Quality gate, commit, and push

### 9a: Run the quality gate

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/quality-gate.md`

Run the quality gate procedure on all files you changed in Step 8. Do NOT skip this step.

### 9b: Commit and push

Include any files that the quality gate auto-formatted when staging.

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/commit-push.md`

**Squashing review fixes into original commits:** Review fixes should not create new "address review" commits. Follow the Clean History Rules from `commit-push.md` above, with these fix-pr-specific additions:

1. **Quality gate first.** Run Step 9a before creating any fixup commits. If the quality gate auto-formats files, include those reformatted files in the same fixup commit as the code change they relate to (not a separate fixup).
2. **Find the target commit.** Use `git log --oneline {base_branch}..HEAD` to identify which original commit introduced the code being changed.
3. **Create fixup commits.** For each fix, stage the changed files (including any quality-gate reformats for the same code) and use `git commit --fixup {original_sha}`.
4. **Squash and force-push.** See the squash procedure in Clean History Rules above.

If the branch has only one commit, simply amend it: `git add <file1> <file2> ... && git commit --amend --no-edit && git push --force-with-lease`.

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

## Step 10b: Update PR status label

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/pr-status-labels.md`

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/deploy-aware-label.md`

After resolving comments, update the PR's status label:

- **All `REQUEST_CHANGES` reviews dismissed** (every review comment was addressed) → check deploy config:
  - Repo has dev deploy config → set `pr: awaiting-dev-verification`
  - Repo has no dev deploy config → set `pr: ready-to-merge`
- **Some `REQUEST_CHANGES` reviews remain** (comments were skipped or deferred) → set `pr: comments-pending`

Use the PR status label swap procedure from pr-status-labels.md.

## Step 11: Report

**Deregister active work:** Send an Agent Mail completion message using the **Deregister Active Work** procedure from `agent-coordination.md`. Post a Discord notification. Best-effort — skip silently if unavailable.

Tell the user, grouped by disposition:

### Fixed
- `[severity] path:line` — description (fixed in commit)

### Non-issue (skipped)
- `[severity] path:line` — description — **Reason:** {disposition_reason}

### Out of scope (issue created)
- `[severity] path:line` — description → Issue #N — **Reason:** {disposition_reason}

### Needs your call (decision issue created)
- `[severity] path:line` — description → Issue #N — **Trade-off:** {disposition_reason}

Also report:
- **Reviews dismissed** — list any `REQUEST_CHANGES` reviews that were dismissed
- **Files changed** — list of modified files
