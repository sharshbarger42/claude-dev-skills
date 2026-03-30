---
name: do-issue
description: Take a Gitea issue, implement the work, create a PR, and run /review-pr for automated code review.
---

# Do Issue Skill

Implement a Gitea issue end-to-end: read the issue, write the code, create a PR, and review it.

**Input:** Issue reference as the skill argument. Accepted formats:
- Shorthand: `food-automation#18`
- Owner/repo: `super-werewolves/food-automation#18`
- Full URL: `https://git.home.superwerewolves.ninja/super-werewolves/food-automation/issues/18`

## Session persistence

!`cat $HOME/.claude/development-skills/lib/session-state.md`

At skill start, call **Session Read** to check for prior context. Then call **Session Write** after these milestones:
- After Step 2 (issue fetched — record issue title, body summary)
- After Step 4 (approach confirmed — record the chosen approach and user decisions)
- After Step 7 (commit and push — record branch name, commit SHA)
- After Step 8 (PR created — record PR number)
- After Step 10 (review triage — record what was fixed vs deferred)
At the end of Step 12 (report), call **Session Clear**.

**Parent-child note:** If invoked from `/do-the-thing`, the parent manages the session file. Check if the session file already exists with `Skill: do-the-thing` — if so, skip all Session Write/Read/Clear and let the parent handle it.

## Step 1: Parse the issue reference

Extract `owner`, `repo`, and issue `index` from the argument.

### Repo resolution

!`cat $HOME/.claude/development-skills/lib/resolve-repo.md`

## Step 1b: Establish identity and check for conflicts

!`cat $HOME/.claude/development-skills/lib/agent-identity.md`

Derive your `AGENT_NAME` for this session.

Then check if another agent is already working on this issue:

1. Fetch the issue's current labels. If `status: in-progress` is present, another agent may already be on it.
2. If Agent Mail is available, query for active work on this issue:

!`cat $HOME/.claude/development-skills/lib/agent-coordination.md`

!`cat $HOME/.claude/development-skills/lib/discord-notify.md`

Use the **Query Active Work** procedure from `agent-coordination.md`, filtered to this specific issue.

3. If a conflict is found (label set AND Agent Mail shows another agent):
   - Warn the user: `"Issue #{INDEX} appears to be in-progress by {OTHER_AGENT} (started {TIMESTAMP}). Continue anyway?"`
   - Use `AskUserQuestion` with options: **Continue anyway**, **Pick a different issue**
   - If the user says pick a different issue, stop and suggest running `/do-the-thing` instead
4. If the `started` timestamp is >2h old with no completion message, note it as possibly stale in the warning

If no conflict, proceed silently.

## Step 2: Fetch issue metadata

Use `mcp__gitea__get_issue_by_index` with the parsed `owner`, `repo`, and `index` to get:
- Issue title
- Issue body/description
- Labels
- Milestone

If the issue is not found, report the error and stop.

**Determine branch prefix:** Check the issue's labels. If the issue has a `bug` label, set `{branch_prefix}` to `fix`. Otherwise, set `{branch_prefix}` to `feature`. Use this prefix for all branch names throughout the workflow.

## Step 2a: Detect epic/parent issues

Check whether this issue is a **parent feature issue** with sub-tasks or blockers (an "epic"). Detection criteria — the issue body contains ANY of:

- A `## Sub-tasks` or `## Subtasks` section with checklist items (`- [ ] #N`)
- A `## Dependencies` section referencing other issues
- Multiple `#N` issue references in checklist format

**Also check:** Fetch all open issues in the same milestone (if the issue has one) via `mcp__gitea__list_issues` filtered by milestone. Issues that list this issue as "Parent" or "Part of #N" in their body are sub-tasks.

### If this IS an epic/parent issue → enter Epic Mode

1. **Build the work graph:** Collect all sub-task and dependency issue numbers. For each, fetch the issue metadata (title, labels, state). Build a list:

   ```
   Sub-tasks:
     - #110 MealMe API client wrapper [status: backlog] — no blockers
     - #111 PreferencesStore service [status: backlog] — no blockers
     - #112 Restaurant search endpoint [status: backlog] — blocked by #110, #111
     ...

   Already completed:
     - (none, or list closed issues)

   Blocked/decision-needed:
     - (any with blocking labels)
   ```

2. **Present to the user** with `AskUserQuestion`:

   ```
   Issue #{index} is a feature tracker with {N} sub-tasks ({M} remaining, {K} already done).

   {the work graph from above}

   Estimated work: {N} sub-issues will be implemented and PR'd into a feature branch.
   Blocked items ({B}) will be skipped unless resolved.
   ```

   Options:
   - **Yes, implement the full feature** — enter epic mode (continue below)
   - **Just implement this single issue** — treat it as a normal issue, proceed to Step 2b
   - **Cancel** — stop

3. **If user confirms epic mode**, set `EPIC_MODE = true` and proceed to **Step E1** (below). Skip Steps 2b through 12 — epic mode has its own flow.

### If this is NOT an epic → proceed normally to Step 2b.

---

## Epic Mode Flow

### Step E1: Create the integration branch

1. `cd` to the local repo path. Verify it exists.
2. `git fetch origin`
3. Create the integration branch from the default branch:
   ```
   git checkout {default_branch} && git pull origin {default_branch}
   git checkout -b feature/{index}-{short-slug}
   ```
   - `short-slug`: 3-5 words from the parent issue title
4. Push the integration branch: `git push -u origin feature/{index}-{short-slug}`
5. **Update status label** on the parent issue: swap `status: backlog` to `status: in-progress`

### Step E2: Plan execution order

Build a dependency-aware execution plan from the work graph:

1. **Tier 0 (no blockers):** Sub-tasks with no dependencies on other sub-tasks — these can start immediately
2. **Tier 1:** Sub-tasks whose only dependencies are in Tier 0 — start after Tier 0 completes
3. **Tier N:** Continue until all sub-tasks are scheduled
4. **Blocked/decision-needed:** Set aside — report at the end

Present the execution plan briefly:
```
Execution plan:
  Tier 0 (parallel): #110, #111, #115
  Tier 1 (parallel, after Tier 0): #112, #113, #114, #118
  Tier 2 (parallel, after Tier 1): #116, #117
  Tier 3 (after Tier 2): #119
  Tier 4 (after Tier 3): #120, #121
  Skipped: (none)
```

### Step E3: Execute sub-tasks

For each tier, run sub-tasks **as concurrently as possible** using the Agent tool:

1. For each sub-task in the current tier, launch an Agent with:
   - `subagent_type: "general-purpose"`
   - `isolation: "worktree"` — each sub-task gets its own worktree
   - Prompt: implement the sub-task issue using the do-issue workflow (Steps 3-11), but with these overrides:
     - **PR base branch:** `feature/{parent_index}-{short-slug}` (the integration branch), NOT `main`/`{default_branch}`
     - **PR body:** Include `Part of #{parent_index}` instead of `Closes #{parent_index}`
     - **PR body:** Include `Closes #{subtask_index}` to auto-close the sub-task on merge
     - **Skip Step 11** (doc updates) — docs will be updated once at the end
     - **Steps 9-10 are MANDATORY** — after creating the PR, the sub-task agent MUST invoke `/review-pr {repo}#{pr_number}` and triage the review comments (fix "fix now" items, create issues for "separate issue" items). Do NOT skip the review. Include this instruction verbatim in the agent prompt.

2. Wait for all agents in the tier to complete before starting the next tier.

3. After each tier completes:
   - Check which sub-tasks succeeded and which failed
   - **Verify reviews were posted:** For each successful sub-task PR, check that a code review comment exists on the PR (look for "## Code Review" in PR comments). If a sub-task agent skipped the review, run `/review-pr {repo}#{pr_number}` yourself before merging.
   - For failed sub-tasks, record the error and continue with the next tier (don't block the whole run)
   - Merge successful PRs into the integration branch via `mcp__gitea__pull_request_write` with `merge_style: "merge"` and `delete_branch: true`

4. After all tiers complete, pull the integration branch to get all merged work:
   ```
   git checkout feature/{parent_index}-{short-slug}
   git pull origin feature/{parent_index}-{short-slug}
   ```

### Step E4: Verify completeness

After all sub-tasks have been executed, verify the integration branch has complete feature coverage:

1. **Check sub-task status:** Fetch all sub-task issues and verify they are closed (auto-closed by merged PRs). List any that are still open.

2. **Review the integration branch diff:** Run `git diff {default_branch}...feature/{parent_index}-{short-slug}` and compare it against the parent issue's description and acceptance criteria.

3. **Run tests:** If the repo has a test suite, run it against the integration branch to verify nothing is broken:
   ```bash
   # Detect and run tests (same detection logic as /test skill)
   # Python: pytest
   # Node: npm test
   # Go: go test ./...
   ```

4. **Gap analysis:** Check whether the integration branch fully implements what the parent issue describes. Look for:
   - Features described in the parent issue that aren't covered by any sub-task
   - Sub-tasks that failed and weren't implemented
   - Integration gaps (sub-tasks work individually but aren't wired together)
   - Missing imports, configuration, or glue code between sub-task implementations

### Step E5: Handle gaps

If gaps are found in Step E4:

1. Present the gaps to the user:

   ```
   Feature verification found {N} gaps:

   1. {gap description} — {which sub-task was supposed to cover this, or "no sub-task covers this"}
   2. ...

   Failed sub-tasks (not implemented):
   - #{index} {title} — {error reason}
   ```

2. Use `AskUserQuestion`:
   - **Create bug issues for gaps** — use `/investigate-bug` style issue creation (with `bug` label, Test Criteria section, human verification gate) for each gap. Link each bug to the parent feature issue (`Part of #{parent_index}`)
   - **Fix gaps now** — attempt to fix the gaps directly on the integration branch (simpler/faster for small glue-code gaps)
   - **Skip — accept as-is** — proceed without addressing gaps

3. If bug issues are created, list them and note they'll need to be fixed before the feature is complete.

### Step E6: Create the feature PR

If all sub-tasks passed (or gaps are accepted/fixed):

1. Create a PR from the integration branch to the default branch:
   - **Title:** `feat(#{parent_index}): {parent issue title}`
   - **Body:**
     ```
     ## Summary

     {Parent issue description summary}

     ## Sub-tasks completed

     - #{sub1} {title} — merged via PR #{pr1}
     - #{sub2} {title} — merged via PR #{pr2}
     ...

     ## Sub-tasks skipped/failed

     - #{subN} {title} — {reason}
     (or "None — all sub-tasks completed successfully")

     ## Gaps found

     - {gap description} → #{bug_issue}
     (or "None — feature is complete")

     Closes #{parent_index}
     ```
   - **base:** `{default_branch}`
   - **head:** `feature/{parent_index}-{short-slug}`

2. Run `/review-pr` on the feature PR.

3. **Update status label:** Swap `status: in-progress` to `status: in-review` on the parent issue.

### Step E7: Report and offer QA

Present the epic run summary:

```
## Epic Complete: #{parent_index} {parent_title}

**Integration branch:** feature/{parent_index}-{short-slug}
**Feature PR:** #{pr_number}

### Sub-task results
| Issue | Title | Status | PR |
|-------|-------|--------|-----|
| #{sub1} | {title} | ✅ Done | #{pr1} |
| #{sub2} | {title} | ✅ Done | #{pr2} |
| #{subN} | {title} | ❌ Failed | — |

### Summary
- {completed}/{total} sub-tasks completed
- {gap_count} gaps found → {bug_count} bug issues created
- Feature PR #{pr_number} ready for review
```

If the run was fully successful (no failed sub-tasks, no gap bugs created):

Use `AskUserQuestion`:
- **Run QA now** — invoke `/qa-pr {repo}#{feature_pr_number}`
- **Skip QA** — done for now

If there were failures or bugs created, inform the user that QA should wait until the bugs are resolved.

---

## Step 2b: Check for pending decisions

If the issue has a `decision-needed` label:

1. Fetch the issue comments using `mcp__gitea__get_issue_comments`.
2. Identify comments that contain open questions or decision requests (look for "Decision needed", question marks, options/alternatives being presented).
3. Present the pending decision to the user:
   ```
   Issue #{index} has a `decision-needed` label. Before implementing, a human decision is required:

   **Open question:** {summarize the decision from the comments}

   {quote the relevant comment(s)}
   ```
4. Use `AskUserQuestion` with options:
   - **Resolve and proceed** — the user provides their decision; remove the `decision-needed` label, post the decision as a comment on the issue, then continue with implementation
   - **Skip this issue** — stop and suggest picking a different issue
5. If the user resolves the decision, remove the `decision-needed` label from the issue before proceeding to Step 3.

## Step 2c: Check for existing work and QA feedback

Check whether this issue already has implementation work and/or QA feedback:

1. **Check for existing branches:** Run `git ls-remote origin "refs/heads/{branch_prefix}/{index}-*"` to see if a branch already exists for this issue.
2. **Fetch issue comments:** Use `mcp__gitea__get_issue_comments` to read all comments on the issue.
3. **Detect QA failure comments:** Look for comments that match the QA failure pattern — comments containing "QA Failed" or "Test Criteria Failures" posted by an agent or the QA skill. These indicate a previous fix attempt was rejected by QA.

**If a QA failure comment is found:**

This means a previous fix was attempted but QA found problems. Enter **fix mode**:

- Extract the specific test failures from the QA comment (look for the failures table or list)
- Set `FIX_MODE = true` — this changes the flow:
  - **Skip Step 4** (approach confirmation) — the approach was already confirmed; now you're fixing specific test failures
  - In **Step 5**, check out the existing feature branch instead of creating a new one. If a PR already exists, work on the same branch.
  - In **Step 6**, focus specifically on fixing the QA failures identified in the comment
  - After **Step 7** (commit and push), post a comment on the issue: `"Fixed QA failures — ready to test again. See commit {sha_short}."`
  - Swap the issue label from `status: in-progress` to `status: ready-to-test`
  - **Skip Steps 8-11** (PR already exists, review already done) — jump to Step 12 (report)

**If an existing branch is found but no QA failure:**

Ask the user whether to:
- **Continue on the existing branch** — check it out and resume where it left off
- **Start fresh** — delete the branch and start over

**If neither:** Proceed normally to Step 3.

## Step 3: Read repo AGENTS.md

!`cat $HOME/.claude/development-skills/lib/fetch-agents-md.md`

## Step 4: Confirm approach with user

Present the user with:
- Issue title and body summary
- Your proposed implementation approach (what files to change, what to build)
- Any open questions or ambiguities

Use `AskUserQuestion` to get the user's confirmation or refinement before writing any code. **Do NOT start coding until the user confirms.**

## Step 5: Set up workspace (worktree isolation)

Use worktree isolation so the main working tree stays clean:

1. `cd` to the local repo path from the shorthand table. Verify the directory exists — if not, tell the user to clone the repo first and stop.
2. Check if the session is **already inside a worktree** (`git rev-parse --git-common-dir` differs from `git rev-parse --git-dir`). If so, you're already isolated — skip straight to creating the feature branch (step 5).
3. Use the `EnterWorktree` tool with `name: issue-{index}` to create an isolated worktree.
   - EnterWorktree handles creating the worktree, switching the session's working directory, and cleanup on exit.
   - If `EnterWorktree` fails (e.g., already in a worktree), fall back to **in-place mode** below.
4. Verify you're in the worktree with `git branch --show-current` and `pwd`
5. Create the branch: `git checkout -b {branch_prefix}/{index}-{short-slug}`
   - `short-slug`: lowercase, hyphenated, 3-5 words from the issue title (e.g., `add-tandoor-recipe-integration`)
6. **Update status label:** Add `status: in-progress` to the issue and remove `status: backlog` or `status: ready-to-test` if present.

**In-place fallback** (only if EnterWorktree fails):

1. `git fetch origin`
2. Check for dirty working tree (`git status --porcelain`). If dirty, warn the user and ask how to proceed.
3. `git checkout {default_branch} && git pull origin {default_branch}`
4. Create the branch: `git checkout -b {branch_prefix}/{index}-{short-slug}`

!`cat $HOME/.claude/development-skills/lib/status-labels.md`

9. **Register active work:** After setting `status: in-progress`, register via Agent Mail and post a "Started Work" Discord notification using the procedures from `agent-coordination.md` and `discord-notify.md` (loaded in Step 1b). This is best-effort — if either fails, continue.

**If the branch already exists**, ask the user whether to continue on it or delete and recreate it.

## Step 6: Implement the changes

This is the main work phase. Use your judgment to implement the issue based on:
- The issue title and description from Step 2
- The repo's AGENTS.md coding standards from Step 3
- The user's confirmed approach from Step 4
- Existing code patterns in the repo (read files as needed)

Read relevant files, write code, edit files. Do the actual implementation work here.

## Step 7: Quality gate, commit, and push

### 7a: Run the quality gate

!`cat $HOME/.claude/development-skills/lib/quality-gate.md`

Run the quality gate procedure on all files you changed in Step 6. Do NOT skip this step.

### 7b: Commit and push

Include any files that the quality gate auto-formatted when staging.

!`cat $HOME/.claude/development-skills/lib/commit-push.md`

**Iterative fix-ups during implementation:** If the quality gate finds issues caused by your code in Step 6, fix them and fold the fix into the original commit using the Clean History Rules above. The branch should have one clean commit per logical change when you push.

The worktree will be automatically cleaned up when the session ends (you'll be prompted to keep or remove it).

## Step 8: Create PR

Use `mcp__gitea__pull_request_write` with method `create`:
- `owner`: from Step 1
- `repo`: from Step 1
- `title`: PR title derived from the issue (e.g., `feat(#18): add tandoor recipe integration`)
- `body`: Include:
  - Summary of what was changed and why
  - List of files changed
  - `Closes #{index}` to auto-close the issue on merge
- `head`: the feature branch name
- `base`: the repo's default branch

**IMPORTANT — PR body formatting:** Pass the `body` parameter as a real multi-line string with actual newlines. Do NOT use `\n` escape sequences — the Gitea MCP tool stores them literally, producing a single-line blob of `\n` characters instead of rendered markdown. Just write the body naturally across multiple lines in the parameter value.

After creating the PR:

1. **Update the issue status label:** replace `status: in-progress` with `status: in-review` on the issue (see status-labels.md above for the swap procedure).
2. **Apply PR status label:** set `pr: needs-review` on the PR (see pr-status-labels.md for the swap procedure).

!`cat $HOME/.claude/development-skills/lib/pr-status-labels.md`

**Fix mode note:** If `FIX_MODE = true`, the PR already exists — skip PR creation entirely. Instead, swap `status: in-progress` to `status: ready-to-test` on the issue, and set the PR label based on deploy config:
- Repo has dev deploy config → set `pr: awaiting-dev-verification`
- Repo has no dev deploy config → set `pr: ready-to-merge`

!`cat $HOME/.claude/development-skills/lib/deploy-aware-label.md`

Then jump to Step 12.

**Discord notification:** Post a "PR Created" Discord notification using the purple embed template from `discord-notify.md`. Include the PR number, title, branch, and agent name. Best-effort — skip silently if webhook is not configured.

## Step 9: Run /review-pr

Invoke the `/review-pr` skill on the newly created PR. Pass it as `{repo}#{pr_number}` using the shorthand format (e.g., `food-automation#35`).

## Step 10: Triage review comments

After `/review-pr` posts its review, read the review comments and respond with a single PR comment triaging each one. For each comment, assess:

1. **Fix now** — Worth addressing in this PR. Small, correct, and directly relevant to the issue scope.
2. **Separate issue** — Valid concern but out of scope. Create a new Gitea issue for it (link the PR and review comment for context).
3. **Won't fix** — Not worth doing at all. Explain why (e.g., YAGNI, acceptable risk for the environment, already handled elsewhere, over-engineering).

Format the response as a single PR comment:

```
Responding to review comments:

---

**Re: {file}:{line} — {short description of the comment}**

{Your reasoning — 1-3 sentences}

**Verdict: {fix now | separate issue | won't fix}** ({brief justification})

---

(repeat for each comment)
```

**After posting the triage comment:**
- For "fix now" items: implement the fixes, commit, and push to the same branch
- For "separate issue" items: create the Gitea issue immediately using `mcp__gitea__create_issue`, link back to this PR. Then label it: call `mcp__gitea__list_repo_labels` to find label IDs, then `mcp__gitea__add_issue_labels`. Apply: a type label (`bug` if broken behavior/correctness problem, `enhancement` if improvement, `feature` if new capability) and a priority label (`priority: high`, `priority: medium`, or `priority: low` based on severity/impact). Skip silently if labels don't exist in the repo.
- For "won't fix" items: no action needed

## Step 11: Update documentation

After the code changes are finalized, check if the repo's README or other user-facing docs need updating to reflect the new functionality.

1. Read the repo's `README.md` (use `mcp__gitea__get_file_contents` or the local file)
2. Check whether the changes from this issue introduce:
   - New commands, endpoints, or features that users interact with
   - New configuration options
   - Changes to existing behavior that's documented
3. If docs need updating:
   - Create a new branch from the default branch: `docs/{index}-update-readme` (or similar)
   - Make the edits (add new commands to examples, add endpoints to API section, update project structure, etc.)
   - Commit with format: `docs(#{index}): {short description}`
   - Push and create a PR
   - Wait for CI, then merge (or leave for `/merge-prs` if CI takes too long)
4. If no docs changes are needed, skip this step silently

**Keep doc changes minimal and focused** — only document what this issue added. Don't rewrite unrelated sections.

## Step 12: Report

**Deregister active work:** Send an Agent Mail completion message using the **Deregister Active Work** procedure from `agent-coordination.md`. Best-effort — skip silently if Agent Mail is unavailable.

Tell the user:
1. **PR URL** — link to the new pull request
2. **Branch name** — the feature branch
3. **Summary of changes** — what was implemented
4. **Review results** — findings from `/review-pr`
5. **Review triage** — what was fixed, what became new issues, what was declined
6. **Docs** — whether README/docs were updated (and PR link if so)
