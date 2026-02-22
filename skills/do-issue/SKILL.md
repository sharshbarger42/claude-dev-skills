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

## Step 1: Parse the issue reference

Extract `owner`, `repo`, and issue `index` from the argument.

### Repo resolution

!`cat $HOME/gitea-repos/development-skills/lib/resolve-repo.md`

## Step 2: Fetch issue metadata

Use `mcp__gitea__get_issue_by_index` with the parsed `owner`, `repo`, and `index` to get:
- Issue title
- Issue body/description
- Labels
- Milestone

If the issue is not found, report the error and stop.

## Step 3: Read repo AGENTS.md

Use `mcp__gitea__get_file_content` to fetch `AGENTS.md` from the repo's default branch. Get the default branch name from the issue metadata (`repository.default_branch`) — do NOT hardcode `master` or `main`.

If AGENTS.md doesn't exist, note that no repo-specific coding standards were found and proceed without it.

## Step 4: Confirm approach with user

Present the user with:
- Issue title and body summary
- Your proposed implementation approach (what files to change, what to build)
- Any open questions or ambiguities

Use `AskUserQuestion` to get the user's confirmation or refinement before writing any code. **Do NOT start coding until the user confirms.**

## Step 5: Set up workspace

Run these commands using the Bash tool:

1. `cd` to the local repo path from the shorthand table
2. Verify the directory exists — if not, tell the user to clone the repo first and stop
3. `git fetch origin`
4. Check for dirty working tree (`git status --porcelain`). If dirty, warn the user and ask how to proceed
5. `git checkout {default_branch} && git pull origin {default_branch}`
6. Create a feature branch: `git checkout -b feature/{index}-{short-slug}`
   - `short-slug`: lowercase, hyphenated, 3-5 words from the issue title (e.g., `add-tandoor-recipe-integration`)
7. Verify the branch was created with `git branch --show-current`
8. **Update status label:** Add `status: in-progress` to the issue and remove `status: backlog` if present.

!`cat $HOME/gitea-repos/development-skills/lib/status-labels.md`

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

## Step 8: Create PR

Use `mcp__gitea__create_pull_request` with:
- `owner`: from Step 1
- `repo`: from Step 1
- `title`: PR title derived from the issue (e.g., `feat(#18): add tandoor recipe integration`)
- `body`: Include:
  - Summary of what was changed and why
  - List of files changed
  - `Closes #{index}` to auto-close the issue on merge
- `head`: the feature branch name
- `base`: the repo's default branch

After creating the PR, **update the status label:** replace `status: in-progress` with `status: in-review` on the issue (see status-labels.md above for the swap procedure).

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
- For "separate issue" items: create the Gitea issue immediately using `mcp__gitea__create_issue`, link back to this PR
- For "won't fix" items: no action needed

## Step 11: Update documentation

After the code changes are finalized, check if the repo's README or other user-facing docs need updating to reflect the new functionality.

1. Read the repo's `README.md` (use `mcp__gitea__get_file_content` or the local file)
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

Tell the user:
1. **PR URL** — link to the new pull request
2. **Branch name** — the feature branch
3. **Summary of changes** — what was implemented
4. **Review results** — findings from `/review-pr`
5. **Review triage** — what was fixed, what became new issues, what was declined
6. **Docs** — whether README/docs were updated (and PR link if so)
