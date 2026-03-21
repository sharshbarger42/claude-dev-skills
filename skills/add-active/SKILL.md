---
name: add-active
description: Add an item to the ACTIVE.md project tracker with optional Gitea issue reference.
---

# Add Active Project

Add a new project entry to `~/gitea-repos/productivity/ACTIVE.md`.

**Input:** The skill argument, in one of these formats:
- `"Project Name"` — just a name
- `"Project Name" repo#N` — name with a Gitea issue reference (e.g. `homelab-setup#668`)
- `repo#N "Project Name"` — issue ref first, name second
- `repo#N` — issue ref only (fetch the title from Gitea)

## Step 1: Parse the input

Extract the project name and optional repo/issue reference.

If only a `repo#N` reference is given with no name, fetch the issue title from Gitea using `mcp__gitea__get_issue_by_index` and use it as the project name.

### Repo resolution (if issue ref provided)

!`cat $HOME/gitea-repos/development-skills/lib/resolve-repo.md`

## Step 2: Fetch issue details (if ref provided)

If a Gitea issue reference was given, fetch the issue with `mcp__gitea__get_issue_by_index` to get:
- Title (use as project name if none given)
- Body (extract a one-line "next step" from the issue description)
- Milestone (include if present)

## Step 3: Build the entry

Format the new entry as:

```markdown
## {Project Name}
**Status:** Not Started
**Next step:** {first actionable item from issue body, or "Define scope and next steps"}
**Ref:** {repo}#{issue_number}{milestone_line}
```

Only include the `**Ref:**` line if a Gitea issue was provided.
Only include a `**Milestone:**` line if the issue has a milestone.

## Step 4: Insert into ACTIVE.md

Read `~/gitea-repos/productivity/ACTIVE.md`.

Insert the new entry **before** the `---` separator that precedes the `## Completed` section. If there's no Completed section, append to the end of the file.

Do NOT create duplicate entries — if an entry with the same name or same issue ref already exists, tell the user and stop.

## Step 5: Confirm

Tell the user what was added:
> Added **{Project Name}** to ACTIVE.md{issue_ref_suffix}

Where `{issue_ref_suffix}` is ` (ref: {repo}#{N})` if an issue was provided, or empty otherwise.

Do not commit — the user will commit when ready.
