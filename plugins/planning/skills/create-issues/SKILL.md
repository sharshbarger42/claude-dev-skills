---
name: create-issues
description: "Turn a project plan into Gitea milestones, vertically-sliced feature issues, and AI-ready sub-issues with dependency tracking. (To decompose a single existing issue, use `create-subtasks` instead.)"
args: "<plan-dir> [owner/repo]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, AskUserQuestion, Skill, mcp__gitea__issue_read, mcp__gitea__issue_write, mcp__gitea__list_issues, mcp__gitea__milestone_read, mcp__gitea__milestone_write, mcp__gitea__label_read, mcp__gitea__label_write, mcp__gitea__get_file_contents, mcp__gitea__get_dir_contents, mcp__gitea__create_repo, mcp__gitea__create_or_update_file, mcp__gitea-workflow__label_issue
---

# Create Issues Skill

Transform a project plan into a structured set of Gitea milestones, feature issues, and sub-issues ready for parallel AI execution.

**Input:**
1. Path to the plan directory (containing `plan.md` from `/plan-project`) — **required**
2. Target `owner/repo` or shorthand — **optional** (will ask if not provided)

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/planning-common.md`

### Repo resolution

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/resolve-repo.md`

## Shared issue body formats

Issue body formats live in `plugins/planning/lib/issue-formats/` — one file per type (`feature.md`, `bug.md`, `chore.md`, `polish.md`, `contract.md`, `sub-issue.md`, `design.md`). This is the single source of truth shared across all planning skills (`create-issues`, `update-issue`, `create-subtasks`). When creating an issue, include the template for its type via `!cat ${CLAUDE_PLUGIN_ROOT}/lib/issue-formats/{type}.md` and fill in the placeholders. Never inline a template in a skill — always pull it from this directory so updates flow through all skills.

## Mode Detection

Inspect the first argument:

- If the argument contains `#` or is a URL with `/issues/` → **this input is an issue reference.** Delegate to the `create-subtasks` skill via the `Skill` tool with the same issue reference as its argument. Stop here after invoking `create-subtasks` — do not continue with the plan-directory flow below.
- If the argument is a file path or directory → continue with the plan-directory flow below.
- If ambiguous, ask the user.

---

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

For each contract identified in Step 5, create a Gitea issue.

Load the contract body template:

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/issue-formats/contract.md`

Fill in every `{...}` placeholder with the specifics from Step 5 (type, name, dependent issue list, must-define bullets, deliverable location). List the dependent features in `## Dependent Issues` so the `update-milestone` skill can later audit contract wiring.

Use `mcp__gitea__issue_write` method `create`:
- `title`: `contract: {name} — define {type}`
- `body`: filled-in template above
- `milestone`: assign to the earliest milestone that contains a dependent feature
- `labels`: apply `contract` via `mcp__gitea-workflow__label_issue` with `type_label: "contract"` and `priority: "high"` (contracts block other work). If the `contract` label doesn't exist in the repo, create it first with `mcp__gitea__label_write` method `create`.

Store the created issue numbers — these will be referenced as blockers on dependent feature issues.

## Step 7: Create feature / bug / chore / polish / design issues

For each item in each phase/milestone, classify it and create the right kind of issue. The plan may contain more than just new features — bug-fix items, refactors, dep upgrades, visual polish, and design/research spikes all belong in their own issue type rather than being shoehorned into a feature.

**Classification heuristics (derive from plan content):**

| Plan item looks like… | Type | Title prefix |
|-----------------------|------|--------------|
| New user-visible capability | `feature` | `feat:` |
| Improvement to existing user-facing functionality | `enhancement` | `enhance:` |
| Broken behavior that needs fixing | `bug` | `fix:` |
| Internal refactor, dep upgrade, infra/tooling, no user-visible change | `chore` | `chore:` |
| Visual/copy/styling tweak, no logic change | `polish` | `polish:` |
| Spike / RFC / research / library evaluation / architecture decision — deliverable is a decision or doc, not shipped code (e.g., "pick a vector DB", "can we use WebRTC?", "RFC: new auth flow") | `design` | `design:` / `spike:` / `RFC:` |

**Vertical slicing rules for features / enhancements:**
- Each feature issue must deliver a user-visible change.
- A user should be able to see/use something new after this feature is complete.
- No "set up database" or "create models" feature issues — those are sub-issues.
- Frame from the user's perspective: "User can {do thing}" not "Implement {technical thing}".

Chore and polish issues are allowed to be small and scoped — they don't need to be user-visible (chore) or deliver new capability (polish). Bug issues center on a concrete reproduction.

**Design issues** capture spikes, RFCs, research, library/tool evaluations, and architecture decisions — anything whose deliverable is a decision, RFC, ADR, prototype report, or research summary rather than shipped code. Signals: plan item frames a question ("which X should we use?", "can we do Y?"), lists options to choose between, or calls for a prototype/evaluation. Design issues typically **precede** their dependent feature issues — if a feature depends on the outcome of a design, mark the feature as `Depends on #{design_issue}` in its `## Dependencies` section. This is softer than a contract dependency: a design doesn't require re-escalation if changed (it's a decision, not an interface), but dependent features should wait for the decision to land before starting. A design issue often produces a `contract` issue as one of its outputs, but not always.

### Body templates (by type)

Load the template for each issue's type and fill in placeholders:

- **feature / enhancement** — !`cat ${CLAUDE_PLUGIN_ROOT}/lib/issue-formats/feature.md`
- **bug** — !`cat ${CLAUDE_PLUGIN_ROOT}/lib/issue-formats/bug.md`
- **chore** — !`cat ${CLAUDE_PLUGIN_ROOT}/lib/issue-formats/chore.md`
- **polish** — !`cat ${CLAUDE_PLUGIN_ROOT}/lib/issue-formats/polish.md`
- **design** — !`cat ${CLAUDE_PLUGIN_ROOT}/lib/issue-formats/design.md`

For each issue, pull the matching template, replace every `{...}` placeholder with content grounded in `plan.md` / `analysis.md` and the target repo's actual architecture. Never invent file paths or library choices — cite what the plan says.

Use `mcp__gitea__issue_write` method `create` for each:
- `title`: `{prefix}: {short description}` (per table above)
- `body`: filled-in template above
- `milestone`: the milestone ID for this phase (for design issues, assign to the earliest milestone that contains a dependent feature — the decision must land before the feature work starts)
- `labels`: apply via `mcp__gitea-workflow__label_issue` with `type_label` set to `feature`, `enhancement`, `bug`, `chore`, `polish`, or `design`, plus a `priority` (`high` / `medium` / `low`) based on milestone urgency and user impact. If a label doesn't exist in the repo, create it first with `mcp__gitea__label_write` method `create`.

Store created issue numbers for sub-issue references.

## Step 8: Create sub-issues

For each feature issue, break it down into sub-issues that are small enough for an AI agent to complete in a single session (via `/do-issue`). For a deeper breakdown of an existing issue — especially one with contract references — prefer the dedicated `/create-subtasks` skill; this step performs the same work inline during the plan-to-issues flow.

**Sub-issue sizing rules:**
- Scoped to exactly ONE code area (`backend`, `frontend`, `data-model`, `api-contract`, `infra/ci`, `tests`, `docs`). If work spans multiple areas, split into multiple sub-issues.
- Touches 1-3 files maximum.
- Completable in roughly 30-60 minutes of focused work.
- Independently testable.
- Parallel-safe: two agents working on different sub-issues should never edit the same file.

Load the sub-issue body template:

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/issue-formats/sub-issue.md`

Fill in every placeholder — especially the `## Contract` section (inputs/outputs with producers/consumers) and, if the parent is blocked by a contract, the `## Contract compliance` section pointing at that contract issue.

Use `mcp__gitea__issue_write` method `create`:
- `title`: `sub: {specific task}` (e.g., `sub: add recipe URL parser with validation`)
- `body`: filled-in sub-issue template above
- `milestone`: same milestone as the parent feature
- `labels`: apply `sub-issue` via `mcp__gitea-workflow__label_issue` with `type_label: "sub-issue"`. Also add a code-area label (e.g., `backend`, `frontend`) via `mcp__gitea__issue_write` method `add_labels` — create the label first with `mcp__gitea__label_write` method `create` if it doesn't exist in the repo. NO priority label — sub-issues inherit priority from their parent feature.
- If the parent is blocked by a contract, also add the `blocked` label so the sub-issue inherits the block.

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
