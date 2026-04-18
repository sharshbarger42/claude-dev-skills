---
name: create-subtasks
description: Break a feature (or other parent) issue into siloed, AI-ready sub-issues. Each sub-issue is scoped to exactly one code area with explicit contract (inputs/outputs). Enforces parallel-safety and contract references.
argument-hint: <feature-issue-ref>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, AskUserQuestion, mcp__gitea__issue_read, mcp__gitea__issue_write, mcp__gitea__list_issues, mcp__gitea__get_file_contents, mcp__gitea__get_dir_contents, mcp__gitea__label_read, mcp__gitea__label_write, mcp__gitea-workflow__label_issue, mcp__gitea-workflow__set_issue_status
---

# Create Subtasks Skill

Decompose a parent issue (typically a feature) into a set of siloed sub-issues that can be worked on in parallel by independent AI agents. Each sub-issue is scoped to exactly one code area, touches 1-3 files, and declares its inputs/outputs as an explicit contract so the seam between sub-issues is unambiguous.

**Input:** Parent issue reference as the skill argument. Accepted formats:
- Shorthand: `food-automation#18`
- Owner/repo: `super-werewolves/food-automation#18`
- Full URL: `https://git.home.superwerewolves.ninja/super-werewolves/food-automation/issues/18`

## Rules

- **One code area per sub-issue.** If work spans multiple areas, it must be split into multiple sub-issues. Allowed areas: `backend`, `frontend`, `data-model`, `api-contract`, `infra/ci`, `tests`, `docs`.
- **1-3 files per sub-issue, 30-60 min of work.** If either bound can't be met, split further.
- **Parallel-safe.** No two sub-issues edit the same file. If a shared file is unavoidable, serialize them with a `Depends on #N` dependency.
- **Explicit contract.** Every sub-issue body has a `## Contract` section listing inputs (what it consumes, and from whom) and outputs (what it produces, and for whom). Cross-issue links use `consumed from #N` / `produces for #N`; internal seams say "internal".
- **Contract compliance.** If the parent is BLOCKED BY a `contract` issue, every sub-issue body MUST include `## Contract compliance` pointing at that contract with the specific part it implements. No silent omissions.
- **Coverage walk is required.** Walk all 7 areas and either propose a sub-issue or state explicitly that the area isn't needed for this parent.
- **Sub-issues never use GWT.** Acceptance Criteria is a concrete checklist scoped to the sub-issue's Code area (`backend` → inputs/outputs/errors; `frontend` → layout/styling/state; `data-model` → schema/indexes/migration; etc.). User-interaction behavior lives on the parent feature, validated via that feature's GWT — duplicating it on each sub-issue just re-describes what the parent already says. The sub-issue needs specifics about inputs, outputs, layout, styling, state.

---

## Step 1: Resolve the parent issue reference

### Repo resolution

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/resolve-repo.md`

Parse `owner`, `repo`, and `index`.

## Step 2: Fetch parent issue, comments, and repo AGENTS.md

Use `mcp__gitea__issue_read`:
- Title, body, labels, milestone, state
- All comments (they often contain clarifying decisions that matter for sub-issue scope)

Also fetch the repo's `AGENTS.md` via `mcp__gitea__get_file_contents` on the default branch.

If the parent is not found, closed, or has no body, stop and report.

## Step 3: Read codebase structure

Call `mcp__gitea__get_dir_contents` on the repo root and drill into directories referenced in the parent body (e.g., `src/`, `backend/`, `frontend/`, `migrations/`). The goal is to cite real file paths in every sub-issue — never invent paths.

If the parent references specific files or modules, read them to understand existing patterns (naming conventions, test style, state-management pattern).

## Step 4: Ensure parent has a type label

If the parent lacks a type label, detect one the same way `/update-issue` does:
- Title `feat:` / user-visible capability → `feature`
- Title `enhance:` / improvement to existing → `enhancement`
- Title `fix:` / broken behavior → `bug`
- Title `chore:` / internal refactor → `chore`
- Title `polish:` / visual tweak → `polish`
- Title `design:` / `spike:` / `RFC:` / research or decision with no shipped-code deliverable → `design`

Apply it via `mcp__gitea-workflow__label_issue`. Create the label first with `mcp__gitea__label_write` if it doesn't exist in the repo.

**Design parents are a valid but atypical case.** Sub-issues of a design are rare — the design's deliverable is usually a single decision doc or RFC that the human writes, and no decomposition is needed. Sub-issues ARE appropriate when the design requires prototype code, benchmark scripts, or multiple write-up chunks across areas. When the parent is a design issue:

- The 7-area coverage walk in Step 5 does not strictly apply — design parents rarely need all 7 areas covered.
- Allowed sub-issue areas are typically `docs` (for the write-up), `infra/ci` (for benchmark setup), and `backend` / `frontend` (for prototype code only — not production implementation).
- The "not applicable" entries in the coverage worksheet will dominate. That's fine — flag this in the breakdown proposal (Step 8) so the user can confirm it's what they want.

If the parent is a design issue with no clear need for sub-issues, ask the user whether to proceed with decomposition at all — it's often simpler to close the design with a decision doc and create follow-on `feature` / `chore` issues for any implementation work.

## Step 5: Coverage walk (REQUIRED)

Walk through all 7 code areas. For each, either propose a sub-issue or explicitly state it's not applicable. Never silently skip.

| Area | What belongs here |
|------|-------------------|
| `data-model` | Migrations, ORM models, shared types, schema changes |
| `api-contract` | Route definitions, handler signatures, request/response shapes, validation |
| `backend` | Service/business logic, background jobs, integrations |
| `frontend` | UI components, pages, state, API clients |
| `tests` | Unit, integration, e2e (may split across areas if heavy) |
| `infra/ci` | Env vars, CI workflow edits, secrets, deploy config |
| `docs` | AGENTS.md, README, API docs |

Produce an internal worksheet like:

```
data-model     → sub-issue #A: add Recipe table migration (migrations/20260417_recipes.sql)
api-contract   → sub-issue #B: define POST /recipes request/response types (src/api/recipes/types.ts)
backend        → sub-issue #C: implement RecipeService.create (src/services/recipeService.ts)
frontend       → not applicable — parent is backend-only
tests          → sub-issue #D: integration tests for POST /recipes (tests/integration/recipes.test.ts)
infra/ci       → not applicable — no new env vars, existing CI picks up new tests
docs           → sub-issue #E: document POST /recipes in AGENTS.md + API docs (AGENTS.md, docs/api.md)
```

## Step 6: Enforce siloing rules

For each proposed sub-issue:

1. **Exactly one code area.** If the task touches two (e.g., backend + frontend), split into two.
2. **Files list (1-3 files).** If more than 3 files are required, split.
3. **30-60 min sizing.** If larger, split; if smaller, consider merging with another sub-issue in the same area.
4. **Parallel-safe file set.** Scan all proposed sub-issues together — if any two list the same file, either merge them or add a `Depends on #N` dependency so they can't both run at once.
   - **Also fetch existing open sub-issues of the parent and include THEIR file sets in the collision check.** Use `mcp__gitea__list_issues` filtered by the parent's milestone and the `sub-issue` label, narrow to those whose `## Parent` line references this parent, and parse each one's `## Files to create/modify` section. Include those files in the collision check against the new batch. If a new sub-issue proposes a file already owned by an existing sub-issue, either merge/redirect the work into the existing sub-issue OR add `Depends on #{existing_sub}` so they can't run in parallel. Re-running this skill on a previously decomposed parent must not produce overlapping file ownership.
5. **Contract section.** Draft the `## Contract` inputs/outputs for each. Cross-issue seams explicit (e.g., sub-issue #C consumes the types produced by sub-issue #B → `consumed from #B`).

## Step 7: Contract enforcement

Check the parent body's `## Dependencies` section for a `**BLOCKED BY** #N` line pointing at a `contract` issue.

**If the parent IS blocked by a contract:**

1. Fetch the contract issue with `mcp__gitea__issue_read` — get its title and `## Dependent Issues` list.
2. For each sub-issue, the `## Contract compliance` section MUST:
   - Point at `#{contract_index}`.
   - Specifically list which part of the contract this sub-issue implements (e.g., "implements the POST /recipes request shape from §3 of the contract").
3. Inherit the parent's block:
   - Apply the `blocked` label to every new sub-issue (create the label with `mcp__gitea__label_write` if the repo lacks it).
   - Include a line in `## Contract compliance`: "Inherits block from parent — contract must merge first."

**If the parent is NOT blocked by a contract:**

Every sub-issue's `## Contract compliance` section is the literal line:
```
- No shared contract — this sub-issue is internal to the parent feature.
```

## Step 8: Propose breakdown to the user

Use `AskUserQuestion` to present the proposed breakdown. Include:

- A table of proposed sub-issues (area, title, files, depends-on, ready/blocked status)
- The coverage-walk worksheet from Step 5 (including "not applicable — {reason}" entries)
- Explicit parallel-work callouts ("#A, #B, #D can all start immediately; #C waits on #A's migration; #E waits on everything else")

Options:

- **Yes, create all** — proceed
- **Adjust breakdown** (free text) — re-draft with the user's notes, re-confirm
- **Abort** — stop

## Step 9: Create sub-issues

For each confirmed sub-issue, load the sub-issue template and fill it in:

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/issue-formats/sub-issue.md`

Fill in every placeholder, specifically:
- `## Parent` — `Sub-issue of #{parent_index} — {parent title}`
- `## Code area` — exactly one area
- `## Files to create/modify` — 1-3 real paths
- `## Technical details` — cite actual patterns from Step 3
- `## Contract` — inputs and outputs with producer/consumer refs
- `## Contract compliance` — per Step 7
- `## Dependencies` — depends-on sub-issues if any, else "No blockers"
- `## Acceptance Criteria` — an area-aware concrete checklist (NOT GWT). The `sub-issue.md` template lists a subsection per code area (`backend`, `frontend`, `data-model`, `api-contract`, `infra/ci`, `tests`, `docs`). Pick the subsection matching this sub-issue's `## Code area` and drop the others from the filled body. Each `- [ ]` item must be specific: for `backend`, spell out accepted input shape, validation rules, success response, each error response, side effects; for `frontend`, spell out layout per breakpoint, styling tokens, state variables, interactions, accessibility; and so on per the template. Do NOT emit `### Scenario:` + GIVEN / WHEN / THEN — user-interaction behavior is already validated on the parent feature's Acceptance Criteria.
- `## Test Criteria` — at least one `[ai-verify]` or `[local-test]` line

Create each issue with `mcp__gitea__issue_write` method `create`:
- `title`: `sub: {specific task}`
- `body`: filled-in template
- `milestone`: same milestone as the parent (if it has one)
- `labels`: apply `sub-issue` via `mcp__gitea-workflow__label_issue` with `type_label: "sub-issue"`. Also add the code-area label (e.g., `backend`, `frontend`) via `mcp__gitea__issue_write` method `add_labels` — create the label first with `mcp__gitea__label_write` if the repo doesn't have it. Add `blocked` if the parent is contract-blocked (per Step 7).

After each sub-issue is created, apply a lifecycle status label:

- **If the sub-issue is NOT contract-blocked** (parent wasn't BLOCKED BY a contract in Step 7): call `mcp__gitea-workflow__set_issue_status` with `status: "backlog"` on the newly-created sub-issue. This is the default starting state — it lets `update-milestone`'s status-label audit find a lifecycle label and keeps the issue eligible for triage/pickup.
- **If the sub-issue IS contract-blocked** (inherited the `blocked` label per Step 7): do NOT apply a status label. Leave it unlabeled — the `blocked` label is sufficient posture. Record an internal note: "no status label while blocked; will be set to backlog when contract merges." This note is also included in the Step 12 report so the human reviewer knows the status will need to be set once the contract is resolved.

Record the created issue indices so the parent comment and cross-dependencies can reference them.

## Step 10: Update the parent with a comment

Do NOT overwrite the parent body. Use `mcp__gitea__issue_write` method `add_comment` (or equivalent comment-creation method) on the parent:

```
## Sub-issues

This issue has been broken down into {N} sub-issues:

- [ ] #{A} — sub: {title}  [area: {area}]
- [ ] #{B} — sub: {title}  [area: {area}]
- [ ] #{C} — sub: {title}  [area: {area}]  (blocked by #{A})
...

### Parallel work opportunities

- #{A}, #{B}, #{D} can start immediately — no shared files
- #{C} waits on #{A}'s migration
- #{E} waits on all others (docs last)

### Suggested order

1. #{A} — no deps, unlocks #{C}
2. #{B} — parallel with #{A}
3. #{C} — after #{A}
4. #{D} — parallel with #{C}
5. #{E} — after all
```

## Step 11: Update the contract issue (if applicable)

If the parent was BLOCKED BY a `contract` issue, check the contract's `## Dependent Issues` section:

1. **Re-fetch the contract body immediately before edit** via `mcp__gitea__issue_read` method `get`. Do NOT reuse the earlier-fetched body from Step 7 — the contract may have been modified by another process in the interim. Use the freshly-fetched body as the base.
2. If the parent issue is not listed in `## Dependent Issues`, append a new bullet for it via `mcp__gitea__issue_write` method `edit`. Preserve all other content in the body — this skill only appends to `## Dependent Issues`, never rewrites other sections.

> **Note:** Re-fetch immediately before edit to minimize the read-modify-write race window. If the contract body has changed since the initial read, the new content wins — this skill only appends to `## Dependent Issues`, never rewrites other sections.

This keeps the contract's dependent-issue list authoritative so `update-milestone`'s audit pass finds no drift.

## Step 12: Report

```
## Sub-issues Created for #{parent_index} — {parent title}

**Repo:** {owner}/{repo}
**Total:** {N} sub-issues
**Contract:** {#contract | none}

### Ready to start
> `/do-issue {repo}#{A}` — {title}
> `/do-issue {repo}#{B}` — {title}

### Blocked
- #{C} — waits on #{A}
- #{D} — waits on #{B}

### Coverage
- data-model: #{A}
- api-contract: #{B}
- backend: #{C}
- frontend: not applicable — {reason}
- tests: #{D}
- infra/ci: not applicable — {reason}
- docs: #{E}
```
