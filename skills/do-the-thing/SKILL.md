---
name: do-the-thing
description: Full dev loop — triage issues, pick one, implement it, review, fix, and merge. One command to rule them all.
---

# Do The Thing Skill

Full development loop in one command: triage open issues, pick one, implement it, get it reviewed, fix review comments, and merge the PR.

**Input:** Optional repo reference as the skill argument. Accepted formats:
- Shorthand: `food-automation`
- Owner/repo: `super-werewolves/food-automation`

If no argument is provided, infer the repo from context (see Step 1).

## Inter-skill Variables

These variables flow between skill invocations. Extract them explicitly after each step — do NOT rely on reading your own prior output, as context compaction may erase it. All variables are also persisted in the session file (see Session persistence below) so they survive compaction.

| Variable | Set by | Used by | Description |
|----------|--------|---------|-------------|
| `{owner}` | Step 1 | All steps | Repo owner (e.g., `super-werewolves`) |
| `{repo}` | Step 1 | All steps | Repo name as used in Gitea API calls (e.g., `food-automation`) |
| `{repo_shorthand}` | Step 1 | Steps 2-7 | Shorthand used in skill args — may be the same as `{repo}` or a configured alias from `config/repos.md` |
| `{repo_local_path}` | Step 1 | Session file, workspace | Local checkout path from the shorthand table (e.g., `~/gitea-repos/food-automation`) |
| `{issue_index}` | Step 3 | Steps 4-7 | Selected issue number |
| `{issue_title}` | Step 3 | Step 7 | Selected issue title |
| `{branch_name}` | Step 4 | Steps 5-7 | Feature branch created by do-issue |
| `{pr_index}` | Step 4 | Steps 5-7 | PR number created by do-issue |
| `{review_has_fixes}` | Step 4 | Step 5 | Whether review triage found "fix now" items (`true`/`false`). **Default: `true`** — if unset or extraction failed, run fix-pr defensively. |
| `{fix_commit_sha}` | Step 5 | Step 7 | Last commit SHA from fix-pr (if run; if fix-pr made multiple commits, use the final one) |
| `{merge_style}` | Step 6 | Step 7 | How the PR was merged (squash/rebase/merge) |
| `{deploy_status}` | Step 6 | Step 7 | Deploy result (passed/failed/no deploy) |

**On context compaction:** If you lose context, re-read the session file at `{repo_local_path}/SESSION-{AGENT_ID}.md`. All variables above are recorded in the session file's "Context" section after each step. If the session file is missing or unreadable, ask the user which step you were on — they can check the PR and issue state to reconstruct context.

## Session persistence

!`cat $HOME/.config/development-skills/lib/session-state.md`

At skill start, call **Session Read** to check for prior context. Then call **Session Write** after these milestones, recording the inter-skill variables in the Context section:
- After Step 1 (repo resolved — record `{owner}`, `{repo}`, `{repo_shorthand}`)
- After Step 3 (issue chosen — record `{issue_index}`, `{issue_title}`)
- After Step 4 (do-issue complete — record `{pr_index}`, `{branch_name}`, `{review_has_fixes}`)
- After Step 5 (fix-pr complete — record `{fix_commit_sha}`)
- After Step 6 (merge complete — record `{merge_style}`, `{deploy_status}`)
At the end of Step 7 (report), call **Session Clear**.

**Parent-child note:** This skill invokes `do-issue`, `fix-pr`, and `merge-prs` as child skills. Those child skills also include `session-state.md`. To avoid the child overwriting this parent's session state, child skills should **skip Session Write/Read/Clear when invoked from a parent skill**. The child can detect this by checking if the session file already exists with a different `Skill:` header — if so, leave it alone and let the parent manage the session file.

## Step 1: Parse or infer the repo

### If an argument was provided

Extract `owner` and `repo` from the argument.

#### Repo resolution

!`cat $HOME/.config/development-skills/lib/resolve-repo.md`

### If no argument was provided

Infer the repo from the current working directory:

1. Run `git remote get-url origin` via Bash to get the remote URL
2. Match the URL against the shorthand table from the repo resolution logic above
3. If a match is found, use `AskUserQuestion` to confirm:
   - Option 1: **Yes, use {repo}** — proceed with the inferred repo
   - Option 2: **Different repo** — user types the shorthand name
4. If no match is found (not in a git repo, or remote doesn't match any known repo), use `AskUserQuestion` to ask which repo to use, listing all repos from the shorthand table as options

## Step 1b: Establish identity and discover active work

!`cat $HOME/.config/development-skills/lib/agent-identity.md`

Derive your `AGENT_NAME` for this session.

!`cat $HOME/.config/development-skills/lib/discord-notify.md`

The `/triage-issues` child skill includes `agent-coordination.md` and will report any in-progress items from other agents. Use that output in Step 3 to exclude them from the options.

## Step 2: Triage issues

Invoke the triage skill:

```
Skill: triage-issues
Args: {repo_shorthand}
```

Read the triage output carefully. It will contain:
- A ranked list of recommended issues
- Any open PRs that should be handled first
- Quick action commands

**Important:** Note the triage results — you'll present them to the user in the next step.

## Step 3: Ask the user which issue to work on

**Exclude in-progress issues:** Remove any issues from the triage recommendations that are currently being worked on by another agent (from the active work list in Step 1b). These should not appear as options.

**Exclude decision-needed issues:** Remove any issues with the `decision-needed` label from the triage recommendations. These require a human decision before implementation and should not be auto-suggested. If there are decision-needed issues, show a note:
> **Awaiting human decision ({N} issues):**
> - #{index} {title} — {1-line summary of pending question}
>
> Run `/do-issue {repo}#{index}` to resolve the decision and start work.

If there are active items from Step 1b, show a note before the options:
> **Other agents currently working on:**
> - #{index} {title} — {agent_name} (started {relative_time}, {stale_warning if applicable})

If any active item is flagged as possibly stale (>2h), append to that line: `(possibly stale — no completion after {duration})`

Use `AskUserQuestion` to let the user pick an issue. Present the top recommended issues (excluding in-progress and decision-needed ones) from the triage output as options:

- Option 1: **#{index} {title}** (the #1 recommended issue) — with description: "{1-line reason from triage}"
- Option 2: **#{index} {title}** (the #2 recommended issue) — with description: "{1-line reason from triage}"
- Option 3: **#{index} {title}** (the #3 recommended issue) — with description: "{1-line reason from triage}"

The user can also type a custom issue number via the "Other" option.

If the triage showed open PRs that should be reviewed/merged first, mention this before the question:
> Note: There are open PRs that could be reviewed/merged first. Proceeding with a new issue anyway.

## Step 4: Implement the issue

Invoke the do-issue skill with the selected issue:

```
Skill: do-issue
Args: {repo_shorthand}#{issue_index}
```

This will:
- Read the issue
- Confirm the approach with the user
- Implement the changes
- Create a PR
- Run `/review-pr` automatically
- Triage the review comments

### Extract outputs and persist

After do-issue completes, extract `{pr_index}`, `{branch_name}`, and `{review_has_fixes}` from its report (see Inter-skill Variables table for descriptions). Then write a **Session Write** recording them — this is the authoritative record that survives compaction.

## Step 5: Fix PR review comments

**Check `{review_has_fixes}`:** If unset (extraction failed or lost to compaction), default to `true` and run fix-pr defensively. If `false` (all comments were "won't fix" or "separate issue"), skip this step and tell the user:
> All review comments were addressed during implementation. Skipping /fix-pr.

Otherwise, invoke the fix-pr skill using the `{pr_index}` extracted in Step 4:

```
Skill: fix-pr
Args: {repo_shorthand}#{pr_index}
```

This addresses any remaining review comments that do-issue's triage marked as "fix now".

### Extract outputs and persist

After fix-pr completes, extract `{fix_commit_sha}` from its report (see Inter-skill Variables table). Then write a **Session Write**.

## Step 6: Merge

Invoke the merge skill using `{repo_shorthand}`:

```
Skill: merge-prs
Args: {repo_shorthand}
```

This will:
- Check that all reviews are addressed
- Verify CI passes
- Ask the user to confirm the merge
- Merge the PR
- Monitor deployment (if applicable)
- Run health checks (if applicable)

### Extract outputs and persist

After merge-prs completes, extract `{merge_style}` and `{deploy_status}` from its report (see Inter-skill Variables table). Then write a **Session Write**.

## Step 7: Report

**Discord notification:** Post a "Loop Complete" Discord notification using the gold embed template from `discord-notify.md`. Include the repo, issue, PR, and final status. Best-effort — skip silently if webhook is not configured.

Present a final summary of the entire loop:

```
## Done!

**Repo:** {owner}/{repo}
**Issue:** #{issue_index} — {issue_title}
**PR:** #{pr_index} — {pr_title}
**Status:** Merged and deployed
**Agent:** {AGENT_NAME}

### What happened
1. Triaged {N} open issues in {repo}
2. Picked #{issue_index}: {issue_title}
3. Implemented on branch `{branch_name}`
4. Created PR #{pr_index}, reviewed by code-review-agent
5. Fixed {N} review comments
6. Merged via {merge_style}, deploy {status}

### Follow-up issues created
- #{new_issue} — {title} (from review comment)
(or "None" if no follow-up issues were created)
```

Keep the output concise. No fluff.
