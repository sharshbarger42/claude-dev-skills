---
name: add-future
description: Add an item to the FUTURE.md project list with optional Gitea issue reference.
---

# Add Future Project

Add a new project entry to `~/gitea-repos/productivity/FUTURE.md`.

**Input:** The skill argument, in one of these formats:
- `"Project Name"` — just a name
- `"Project Name" repo#N` — name with a Gitea issue reference
- `repo#N "Project Name"` — issue ref first, name second
- `repo#N` — issue ref only (fetch the title from Gitea)
- `"Project Name" --section "Section Name"` — specify which section to add under
- `repo#N --section "Section Name"` — issue ref with section

## Step 1: Parse the input

Extract the project name, optional repo/issue reference, and optional `--section` flag.

If only a `repo#N` reference is given with no name, fetch the issue title from Gitea using `mcp__gitea__get_issue_by_index` and use it as the project name.

### Repo resolution (if issue ref provided)

!`cat $HOME/gitea-repos/development-skills/lib/resolve-repo.md`

## Step 2: Fetch issue details (if ref provided)

If a Gitea issue reference was given, fetch the issue with `mcp__gitea__get_issue_by_index` to get:
- Title (use as project name if none given)
- Body (use first line or summary as notes)

## Step 3: Determine target section

FUTURE.md is organized into sections: `## Crafting`, `## Software`, `## Home`, `## Tech`, `## Hobbies`.

If `--section` was provided, use that section. Otherwise, infer from the project:
- If the issue is in a software repo or mentions code/app → `## Software`
- If it mentions crafting/building/printing → `## Crafting`
- If it mentions house/room/yard → `## Home`
- If it mentions hardware/devices/OS → `## Tech`
- Otherwise → ask the user which section

## Step 4: Build the entry

Format as:

```markdown
### {Project Name}
**Notes:** {one-line description from issue body, or user-provided name}
**Ref:** {repo}#{issue_number}
```

Only include `**Ref:**` if a Gitea issue was provided.

## Step 5: Insert into FUTURE.md

Read `~/gitea-repos/productivity/FUTURE.md`.

Find the target section heading (`## {Section}`) and append the new entry after the last `###` entry in that section (before the next `##` heading or end of file).

Do NOT create duplicate entries — if an entry with the same name or same issue ref already exists, tell the user and stop.

## Step 6: Confirm

Tell the user what was added:
> Added **{Project Name}** to FUTURE.md under {Section}{issue_ref_suffix}

Do not commit — the user will commit when ready.
