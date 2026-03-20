---
name: create-issues
description: Turn a project plan into Gitea milestones, vertically-sliced feature issues, and AI-ready sub-issues with dependency tracking.
args: "<plan-dir> [owner/repo]"
---

# Create Issues Skill

Transform a project plan into a structured set of Gitea milestones, feature issues, and sub-issues ready for parallel AI execution.

**Input:** Two arguments:
1. Path to the plan directory (containing `plan.md` from `/plan-project`) — **required**
2. Target `owner/repo` or shorthand — **optional** (will ask if not provided)

!`cat $HOME/.claude/development-skills/lib/planning-common.md`

### Repo resolution

!`cat $HOME/.claude/development-skills/lib/resolve-repo.md`

## Step 1: Read the plan

Read `plan.md` from the provided plan directory. Extract:
- Project name and overview
- MVP features and enhancement phases
- Architecture decisions (components, data models, APIs)
- Technology stack
- Dependencies between features

If `plan.md` doesn't exist, stop and tell the user to run `/plan-project` first.

Also read `analysis.md` if it exists, for additional context on requirements and constraints.

## Step 2: Determine target repo

### If owner/repo was provided as second argument

Resolve it using the repo resolution logic above.

### If no repo was provided

Use `AskUserQuestion`:

```
Where should I create the issues?

1. **Existing repo** — enter the repo name (e.g., `food-automation` or `super-werewolves/food-automation`)
2. **Create new repo** — I'll set up a new Gitea repo for this project
```

If the user chooses to create a new repo:

1. Propose a repo name derived from the project name (lowercase, hyphenated)
2. Ask for confirmation with `AskUserQuestion`:

```
I'll create a new repo with these settings:

- **Name:** {proposed-name}
- **Owner:** {default org or user from config}
- **Visibility:** private
- **Description:** {1-line from plan overview}
- **Initialize with:** README.md, .gitignore, AGENTS.md

Create this repo?
```

Options:
- **Yes, create it**
- **Change name** (free text)
- **Don't create — I'll specify an existing repo**

3. If confirmed, use `mcp__gitea__create_repo` to create the repo
4. After creation, initialize it:
   - Use `mcp__gitea__create_file` to add a basic `AGENTS.md` with the tech stack and coding standards from the plan
   - Use `mcp__gitea__create_file` to add a `.gitignore` appropriate for the chosen language
5. Add the new repo to `config/repos.md` in development-skills (edit the file locally)

If creation fails or user declines, ask for an existing repo name instead.

## Step 3: Analyze plan into milestones

Read the plan's phase structure and map each phase to a Gitea milestone:

| Phase | Milestone name | Due date logic |
|-------|---------------|----------------|
| Phase 1: MVP | `v0.1 — MVP` | No due date unless user specified timeline |
| Phase 2: {theme} | `v0.2 — {theme}` | After MVP |
| Phase 3: {theme} | `v0.3 — {theme}` | After Phase 2 |

Present the proposed milestone structure to the user with `AskUserQuestion`:

```
## Proposed Milestones

| # | Milestone | Features | Notes |
|---|-----------|----------|-------|
| 1 | v0.1 — MVP | {N features} | {key scope note} |
| 2 | v0.2 — {theme} | {N features} | {key scope note} |
| ... | ... | ... | ... |

Proceed with creating these milestones and all issues?
```

Options:
- **Yes, create everything**
- **Adjust milestones** (free text)

**Once confirmed, the rest executes without further interaction.**

## Step 4: Create milestones

For each milestone, use `mcp__gitea__create_milestone`:
- `owner`, `repo`: from Step 2
- `title`: milestone name (e.g., `v0.1 — MVP`)
- `description`: list of features in this milestone
- `due_on`: if a timeline was specified

Store the returned milestone IDs for use when creating issues.

## Step 5: Identify contracts and dependencies

Before creating feature issues, analyze the plan for **cross-cutting contracts** — interfaces, APIs, data schemas, or protocols that multiple features depend on.

A contract issue is needed when:
- Two or more features need to communicate through a shared interface
- A data model is used by multiple components
- An API endpoint is consumed by multiple clients
- A message format or event schema is shared

For each contract identified:

```
CONTRACT: {name}
- Used by: {list of features that depend on this}
- Type: {API spec, data schema, event format, interface definition}
- Must define: {what the contract must specify}
```

## Step 6: Create contract issues (if any)

For each contract identified in Step 5, create a Gitea issue:

Use `mcp__gitea__create_issue`:
- `title`: `contract: {name} — define {type}`
- `body`:
```markdown
## Contract Definition

**Type:** {API spec / data schema / event format / interface definition}

**Context:**
This contract is needed because the following features depend on a shared {type}:
{list of dependent features with brief descriptions}

**Must define:**
- {specific thing the contract must specify}
- {validation rules, error formats, versioning}

**Acceptance criteria:**
- [ ] Contract is documented in {location — e.g., docs/contracts/, OpenAPI spec, protobuf}
- [ ] Contract is reviewed and approved
- [ ] Contract includes versioning strategy
- [ ] Example request/response or usage is provided

**IMPORTANT:** This contract MUST be completed and merged before any dependent issues can begin work. Dependent issues are tagged with `depends-on: #{this_issue_number}`.
```
- `milestone`: assign to the earliest milestone that contains a dependent feature
- `labels`: add `contract`, `priority: high` (contracts block other work), and `feature`

Store the created issue numbers — these will be referenced as blockers.

## Step 7: Create feature issues

For each feature in each phase/milestone, create a vertically-sliced feature issue.

**Vertical slicing rules:**
- Each feature issue must deliver a user-visible enhancement
- A user should be able to see/use something new after this feature is complete
- No "set up database" or "create models" issues — those are sub-issues
- Frame everything from the user's perspective: "User can {do thing}" not "Implement {technical thing}"

Use `mcp__gitea__create_issue`:
- `title`: `feat: {user-facing description}` (e.g., `feat: user can import recipes from URL`)
- `body`:
```markdown
## Description

{What the user can do after this feature is implemented — 2-3 sentences from their perspective}

## Context from plan

{Relevant architecture decisions, tech stack details, and design notes from plan.md}

## Scope

**In scope:**
- {specific deliverable}
- {specific deliverable}

**Out of scope:**
- {what this does NOT include — reference later milestone features}

## Technical notes

- {relevant architecture decision from plan}
- {library to use and why}
- {data model or API endpoint involved}

## Dependencies

{If this feature depends on a contract issue:}
- **BLOCKED BY** #{contract_issue_number} — `contract: {name}`. **Do not begin work until the contract is merged.** When implementing, follow the contract exactly as specified. If the contract is unclear or seems wrong, **stop work and escalate to a human** — do not improvise a different interface.

{If this feature depends on another feature:}
- Depends on #{other_issue_number} — {why}

## Acceptance criteria

- [ ] {testable criterion from user perspective}
- [ ] {testable criterion}
- [ ] Tests pass
- [ ] No regressions
```
- `milestone`: the milestone ID for this phase
- `labels`: type label (`feature`, `enhancement`, or `bug`), plus a priority label (`priority: high`, `priority: medium`, or `priority: low` — based on milestone urgency and user impact)

Store created issue numbers for sub-issue references.

## Step 8: Create sub-issues

For each feature issue, break it down into sub-issues that are small enough for an AI agent to complete in a single session (via `/do-issue`).

**Sub-issue sizing rules:**
- Each sub-issue should touch 1-3 files maximum
- Each should be completable in roughly 30-60 minutes of focused work
- Each should be independently testable
- Parallel-safe: two agents should be able to work on different sub-issues simultaneously without merge conflicts (different files or clearly separated code sections)

**Sub-issue types:**
- `implementation` — write new code
- `test` — write tests for existing code
- `config` — CI/CD, deployment, configuration
- `docs` — documentation updates

Use `mcp__gitea__create_issue`:
- `title`: `sub: {specific task}` (e.g., `sub: add recipe URL parser with validation`)
- `body`:
```markdown
## Parent

Sub-issue of #{parent_feature_issue_number} — {parent title}

## Task

{Clear, specific description of exactly what to implement — 3-5 sentences}

## Files to create/modify

- `{file_path}` — {what to do in this file}
- `{file_path}` — {what to do in this file}

## Technical details

- {specific implementation approach}
- {library/function to use}
- {data model or schema reference}

## Contract compliance

{If the parent depends on a contract:}
- **MUST follow contract defined in** #{contract_issue_number}
- Specifically: {which part of the contract applies to this sub-issue}
- **If the contract doesn't exist yet or seems wrong, STOP WORK and escalate to a human.** Do not guess or create your own interface.

## Dependencies

{If this sub-issue must be done after another sub-issue:}
- Depends on #{other_sub_issue} — {why, what it provides}

{If this sub-issue can be done in parallel:}
- No blockers — can be started immediately

## Acceptance criteria

- [ ] {specific, testable criterion}
- [ ] {specific, testable criterion}
- [ ] All existing tests still pass
```
- `milestone`: same milestone as the parent feature
- `labels`: `sub-issue`, `{sub-issue type}` (NO priority label — sub-issues inherit priority from their parent feature)

## Step 9: Add dependency labels

After all issues are created, go back and add blocking relationships:

1. For each contract issue, edit all dependent feature issues to add a comment:
   ```
   Blocked by #{contract_issue_number} — contract must be defined first.
   ```

2. For feature issues with sequential dependencies, add labels:
   - `blocked` label on the dependent issue
   - Comment explaining what it's blocked by

3. For sub-issues with ordering requirements, ensure the dependency chain is clear in the issue body.

## Step 10: Create issue map

Generate a visual map of all created issues and their relationships:

```markdown
## Issue Map

### Contracts (do first)
- #{N} contract: {name} ← blocks #{list of dependent issues}

### Milestone: v0.1 — MVP
#### Feature: #{N} {title}
  - #{N} sub: {task} {🔒 blocked by #N | ✅ ready}
  - #{N} sub: {task} {✅ ready}
  - #{N} sub: {task} {🔒 depends on #N}

#### Feature: #{N} {title}
  - #{N} sub: {task} {✅ ready}
  ...

### Milestone: v0.2 — {theme}
...

### Dependency Chain
#{contract} → #{feature} → #{sub-issues}
#{feature_a} → #{feature_b} (sequential)

### Parallel Work Opportunities
These sub-issues can be worked on simultaneously:
- #{N}, #{N}, #{N} (different files, no shared state)
- #{N}, #{N} (different components)
```

## Step 11: Save and report

Write the issue map and creation log to `$PLAN_DIR/issues-created.md`:

```markdown
# Issues Created: {Project Name}

**Date:** {date}
**Repo:** {owner}/{repo}
**Total issues created:** {count}

## Summary
- Milestones: {count}
- Contract issues: {count}
- Feature issues: {count}
- Sub-issues: {count}

## Issue Map
{from Step 10}

## All Issues

| # | Type | Title | Milestone | Blocked by | Labels |
|---|------|-------|-----------|------------|--------|
| {N} | contract | {title} | {milestone} | — | contract, priority |
| {N} | feature | {title} | {milestone} | #{N} | enhancement |
| {N} | sub-issue | {title} | {milestone} | — | sub-issue |
...
```

Report to the user:

```
## Issues Created

**Repo:** {owner}/{repo}
**Total:** {count} issues across {milestone_count} milestones

### Breakdown
- {N} contract issues (must be done first)
- {N} feature issues (vertically sliced, user-facing)
- {N} sub-issues (AI-ready, parallelizable)

### Ready to start (no blockers)
> `/do-issue {repo}#{first_ready_issue}` — {title}
> `/do-issue {repo}#{next_ready_issue}` — {title}

### Blocked (waiting on contracts)
- #{N} {title} ← waiting on #{contract_issue}

**Issue map saved to:** {plan_dir}/issues-created.md
```
