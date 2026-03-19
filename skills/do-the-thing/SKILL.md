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

## Step 1: Parse or infer the repo

### If an argument was provided

Extract `owner` and `repo` from the argument.

#### Repo resolution

!`cat $HOME/.claude/development-skills/lib/resolve-repo.md`

### If no argument was provided

Infer the repo from the current working directory:

1. Run `git remote get-url origin` via Bash to get the remote URL
2. Match the URL against the shorthand table from the repo resolution logic above
3. If a match is found, use `AskUserQuestion` to confirm:
   - Option 1: **Yes, use {repo}** — proceed with the inferred repo
   - Option 2: **Different repo** — user types the shorthand name
4. If no match is found (not in a git repo, or remote doesn't match any known repo), use `AskUserQuestion` to ask which repo to use, listing all repos from the shorthand table as options

## Step 1b: Establish identity and discover active work

!`cat $HOME/.claude/development-skills/lib/agent-identity.md`

Derive your `AGENT_NAME` for this session.

!`cat $HOME/.claude/development-skills/lib/agent-coordination.md`

!`cat $HOME/.claude/development-skills/lib/discord-notify.md`

Use the **Query Active Work** procedure from `agent-coordination.md` to discover what other agents are currently working on in this repo. Store the list of active items (issue index, agent name, started timestamp, staleness flag) for use in Step 3.

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

**Important:** Watch the do-issue output for the PR number. You'll need it for the next step. The PR number will appear in the report at the end (e.g., "PR URL" or "PR #N").

## Step 5: Fix PR review comments

After do-issue completes, invoke the fix-pr skill on the PR that was created:

```
Skill: fix-pr
Args: {repo_shorthand}#{pr_index}
```

This addresses any remaining review comments that do-issue's triage marked as "fix now".

**Note:** If do-issue's review triage showed zero "fix now" items (all comments were "won't fix" or "separate issue"), skip this step and tell the user:
> All review comments were addressed during implementation. Skipping /fix-pr.

## Step 6: Merge

Invoke the merge skill:

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
