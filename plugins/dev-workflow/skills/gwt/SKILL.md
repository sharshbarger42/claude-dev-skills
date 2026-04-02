---
name: gwt
description: Format Gitea issue requirements into GIVEN/WHEN/THEN acceptance criteria scenarios, optionally enriched with real data from the codebase. Use when the user asks to "format requirements", "write acceptance criteria", "generate BDD scenarios", "create given when then for", or "write gwt for [issue]".
argument-hint: [repo#issue] [--with-data]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, mcp__gitea__get_issue_by_index, mcp__gitea__get_issue_comments_by_index, mcp__gitea__get_file_contents
---

# GIVEN / WHEN / THEN Formatter

Format the requirements from Gitea issue **$ARGUMENTS** into BDD-style acceptance criteria and write them to a markdown file in the current directory.

If `--with-data` is included in the arguments, also explore the codebase to annotate each scenario with realistic example data.

## Step 1 — Resolve the issue

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/resolve-repo.md`

Parse the issue reference from `$ARGUMENTS` using the resolution logic above. Then fetch the issue using `mcp__gitea__get_issue_by_index`.

Capture:
- Title
- Body (requirements, acceptance criteria, notes)
- Labels (may indicate feature area, priority, etc.)
- Comments (may contain clarifications or additional requirements) — fetch with `mcp__gitea__get_issue_comments_by_index`

## Step 2 — Extract scenarios

Read through the requirements and convert each testable behavior into one or more GIVEN/WHEN/THEN scenarios. Use this structure:

```
### Scenario: [short descriptive title]

**GIVEN** [existing system state or precondition]
**WHEN**  [action taken by user or system]
**THEN**  [expected observable outcome]
[AND      [additional outcome, if needed]]
```

Guidelines for writing good scenarios:
- Each scenario tests exactly one behavior. If a requirement has multiple outcomes, write multiple scenarios.
- GIVEN describes *what is already true* before the action — not what the user does.
- WHEN is a single action: an API call, a button click, a scheduled job running, a data submission.
- THEN is the directly observable outcome: a response body, a database change, a UI state, an event emitted.
- Use domain language from the issue. Don't invent terminology.
- Include negative/error scenarios (invalid input, missing data, unauthorized access) wherever the requirements imply them.
- If a requirement is ambiguous, write the scenario that reflects the most reasonable interpretation and add a `> **Note:**` line flagging the ambiguity.

## Step 3 — (Optional) Enrich with data

Only do this step if `--with-data` was passed.

Search the codebase to find:
- **Existing state**: What records or state would realistically exist in GIVEN? Look for seed data, fixtures, migration files, or schema definitions.
- **Input values**: What would realistic WHEN inputs look like? Check request models, validation rules, enum values, type definitions.
- **Output/state**: What should THEN produce? Check response models, return types, event payloads.

Use Glob and Grep to explore — start with the area of the codebase most relevant to the issue's domain, then broaden if needed. Look for:
- Migration files or schema files describing relevant tables/models
- Model/entity classes showing field names and types
- Factory, fixture, or seeder files showing example data
- Request/response types showing input/output shapes
- Config files showing feature flags or environment-specific values

Add a `**Data:**` block beneath each scenario when you find useful concrete values:

```
**Data:**
- GIVEN: `recipes` row with `id=42`, `status='published'`, `servings=4`
- WHEN: POST body `{ "recipeId": 42, "scale": 2 }`
- THEN: scaled ingredients list with `quantity` values doubled
```

If you can't find enough data to fill a scenario confidently, omit the Data block rather than guessing.

## Step 4 — Write the output file

Determine the output filename: `{repo}-{issue_number}-gwt.md` (e.g., `food-automation-15-gwt.md`). Write it to the current working directory.

Use this document structure:

```markdown
# {repo}#{issue_number} — {Issue Title}

> **Source**: {Gitea issue URL}
> **Generated**: {today's date}

## Acceptance Criteria

[one or more scenarios in GIVEN/WHEN/THEN format]

## Open Questions

[list any ambiguities flagged during scenario writing, or "None" if clean]
```

After writing the file, report:
- Path to the file written
- Number of scenarios generated
- Any open questions surfaced

## Rules

- Never fabricate requirements. If the issue is vague, flag it as an open question rather than inventing behavior.
- Use the issue's own language and terminology.
- If `--with-data` finds nothing useful, that's fine — skip the Data blocks silently.
- Keep scenarios atomic — one behavior per scenario, no compound WHEN clauses.
