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

## Step 3: Read repo AGENTS.md

Use `mcp__gitea__get_file_contents` to fetch `AGENTS.md` from the repo's default branch. Get the default branch name from the issue metadata (`repository.default_branch`) — do NOT hardcode `master` or `main`.

If AGENTS.md doesn't exist, note that no repo-specific coding standards were found and proceed without it.

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
5. Create the feature branch: `git checkout -b feature/{index}-{short-slug}`
   - `short-slug`: lowercase, hyphenated, 3-5 words from the issue title (e.g., `add-tandoor-recipe-integration`)
6. **Update status label:** Add `status: in-progress` to the issue and remove `status: backlog` if present.

**In-place fallback** (only if EnterWorktree fails):

1. `git fetch origin`
2. Check for dirty working tree (`git status --porcelain`). If dirty, warn the user and ask how to proceed.
3. `git checkout {default_branch} && git pull origin {default_branch}`
4. Create the feature branch: `git checkout -b feature/{index}-{short-slug}`

!`cat $HOME/.claude/development-skills/lib/status-labels.md`

9. **Register active work:** After setting `status: in-progress`, register via Agent Mail and post a "Started Work" Discord notification using the procedures from `agent-coordination.md` and `discord-notify.md` (loaded in Step 1b). This is best-effort — if either fails, continue.

**If the feature branch already exists**, ask the user whether to continue on it or delete and recreate it.

## Step 6: Implement the changes

This is the main work phase. Use your judgment to implement the issue based on:
- The issue title and description from Step 2
- The repo's AGENTS.md coding standards from Step 3
- The user's confirmed approach from Step 4
- Existing code patterns in the repo (read files as needed)

Read relevant files, write code, edit files. Do the actual implementation work here.

## Step 7: Commit and push

1. Stage changed files individually (use `git add <file1> <file2> ...`, NOT `git add -A` or `git add .`)
2. Commit using the repo's commit format from AGENTS.md. Typical format: `feat(#{index}): short description`
   - **IMPORTANT:** Per AGENTS.md Rule 3 — NO Claude/AI/co-authored-by references in commit messages
3. Push the feature branch: `git push -u origin feature/{index}-{short-slug}`

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

After creating the PR, **update the status label:** replace `status: in-progress` with `status: in-review` on the issue (see status-labels.md above for the swap procedure).

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
- For "separate issue" items: create the Gitea issue immediately using `mcp__gitea__create_issue`, link back to this PR. If the issue describes a bug (broken behavior, correctness problem), add the `bug` label: call `mcp__gitea__list_repo_labels` to find the label ID, then `mcp__gitea__add_issue_labels`. Skip silently if the label doesn't exist.
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
