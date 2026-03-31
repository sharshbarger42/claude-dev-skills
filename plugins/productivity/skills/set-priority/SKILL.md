---
name: set-priority
description: Set a Gitea issue as the current priority so triage recommends it (and its blockers/subtasks) first.
---

# Set Priority

Save a Gitea issue as the current top priority. The `/triage-issues` skill reads this file and boosts the priority issue — plus any blockers or subtasks — to the top of its recommendations.

**Input:** Issue reference as the skill argument. Accepted formats:
- Shorthand: `food-automation#42`
- Owner/repo: `super-werewolves/food-automation#42`
- Full URL: `https://git.home.superwerewolves.ninja/super-werewolves/food-automation/issues/42`
- `clear` — remove the current priority

## Step 1: Parse the input

If the argument is `clear`, delete `$HOME/gitea-repos/development-skills/config/current-priority.json` and confirm:
> Priority cleared. Triage will use default scoring.

Then stop.

Otherwise, extract `owner`, `repo`, and `issue_index` from the argument.

### Repo resolution

!`cat $HOME/.config/development-skills/lib/resolve-repo.md`

## Step 2: Fetch the issue

Use `mcp__gitea__get_issue_by_index` to fetch the issue. Verify it exists and is open.

If the issue is closed, warn the user and ask if they still want to set it as priority.

## Step 3: Identify subtasks and blockers

Scan the issue body for:
- **Sub-task references:** Lines like `- [ ] #N` or `- [x] #N` — these are subtasks
- **Blocker references:** Lines like `Blocked by #N`, `Depends on #N`, or `- [ ] Depends on #N`
- **Dependency graph references:** Issue numbers mentioned in code blocks labeled as dependency graphs

Collect all referenced issue numbers. For each, note whether it's a subtask or blocker.

## Step 4: Save the priority file

Write `$HOME/gitea-repos/development-skills/config/current-priority.json`:

```json
{
  "owner": "{owner}",
  "repo": "{repo}",
  "issue": {issue_index},
  "title": "{issue title}",
  "subtasks": [669, 670, 671],
  "blockers": [],
  "set_at": "{ISO 8601 timestamp}",
  "set_by": "user"
}
```

- `subtasks`: issue numbers from the body that are sub-tasks (unchecked checkboxes)
- `blockers`: issue numbers explicitly marked as blockers
- Both lists are repo-local (same owner/repo as the parent issue)

## Step 5: Confirm

Tell the user:

> Priority set: **{title}** ({repo}#{issue_index})
> Subtasks: {comma-separated list of #N, or "none"}
> Blockers: {comma-separated list of #N, or "none"}
>
> `/triage-issues {repo}` will now prioritize this issue and its unfinished subtasks.
> Run `/set-priority clear` to remove.

Do not commit — this is a local config file.
