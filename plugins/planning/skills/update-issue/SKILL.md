---
name: update-issue
description: Fill in a single Gitea issue so its body matches the canonical format for its type (feature, bug, chore, polish, contract, sub-issue, design). Detects gaps, preserves existing prose, and adds missing sections grounded in the codebase.
argument-hint: <issue-ref> [--type=feature|bug|chore|polish|contract|sub-issue|design]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, AskUserQuestion, mcp__gitea__issue_read, mcp__gitea__issue_write, mcp__gitea__list_issues, mcp__gitea__list_pull_requests, mcp__gitea__pull_request_read, mcp__gitea__actions_run_read, mcp__gitea__get_file_contents, mcp__gitea__get_dir_contents, mcp__gitea__label_read, mcp__gitea__label_write, mcp__gitea-workflow__label_issue, mcp__gitea-workflow__set_issue_status
---

# Update Issue Skill

Bring a single Gitea issue up to the canonical format for its type. The skill detects which sections are missing, grounds new content in the actual repo, preserves every word of existing prose, and applies the correct type label. It's safe to run on the same issue repeatedly — idempotent.

**Input:** Issue reference as the skill argument. Accepted formats:
- Shorthand: `food-automation#18`
- Owner/repo: `super-werewolves/food-automation#18`
- Full URL: `https://git.home.superwerewolves.ninja/super-werewolves/food-automation/issues/18`

**Optional flags:**
- `--type={type}` — force the type classification (`feature`, `bug`, `chore`, `polish`, `contract`, `sub-issue`, `design`). Overrides type inference.

## Rules

- **Never fabricate requirements.** If a section can't be filled from existing prose, codebase, plan, or comments, insert a `> **Open question:** {the question}` line instead of inventing content.
- **Never overwrite existing prose.** Only fill empty sections or add missing ones. If a section already has content, leave it alone even if it disagrees with inferred content — surface the conflict as an Open question.
- **Every feature / bug must address all 7 coverage areas.** Walk through `data-model`, `api-contract`, `backend`, `frontend`, `tests`, `infra/ci`, `docs`. Each must either appear in Scope/Technical notes OR have an explicit "No {area} changes needed — {reason}" line. Never silently omit an area.
- **Design issues produce decisions, not code.** 7-area coverage is N/A for design. Readiness check is: Goal + Options under consideration + Decision criteria + Deliverable location + Downstream impact all present and non-empty.
- **Every issue must have an explicit contract posture.** Either a `BLOCKED BY #{contract}` line, or the literal line "No shared contracts involved — this is self-contained." — never empty.
- **Never silently overwrite a human-applied type label — ask, unless `--type` was passed explicitly.**
- **After fill-in completes, propose `status: backlog` if no lifecycle status label is present and the issue isn't blocked. Never override an existing status label.**
- **Checklist reconciliation auto-ticks only `[subtask-check]` and `[ci-check]` boxes, and only with user confirmation.** Other tagged boxes (`[ai-verify]`, `[local-test]`, `[human-verify]`, `[human-assist]`, `[post-merge]`) require human / test-run verification and are never auto-ticked. Stale `[x]` items (sub-issue reopened, CI now failing) are flagged in the report, never auto-unticked.
- **Feature-split detection runs for features only, uses agent judgment (not regex), and never auto-splits without confirmation.** If the user confirms a feature is intentionally multi-outcome, record that in the body (a short `## Notes` line) so future runs don't re-prompt.
- **GWT is for features only.** All other issue types use concrete implementation-level checklists in Acceptance Criteria. Never use `### Scenario:` + GIVEN/WHEN/THEN on bug/chore/polish/contract/design/sub-issue bodies. If an existing non-feature body has GWT, propose replacing with a checklist via `AskUserQuestion` (don't silently overwrite). Features are vertical slices — user-interaction behavior lives there, validated via GWT at the user level. Everything else (sub-issues are horizontal slices of a feature; bugs/chores/polish/contract/design are their own types) should have concrete implementation-level checklists, not GWT. Duplicating GWT scenarios at the sub-issue level just re-describes what the parent's GWT already says; the sub-issue needs specifics about inputs, outputs, layout, styling, state, etc.
- **When converting an existing non-feature body from GWT to checklist form, surface via `AskUserQuestion` — never silently rewrite human-authored scenarios.** Options: Replace with checklist / Keep as GWT with a note / Skip this issue.
- **For sub-issues, Acceptance Criteria body should contain only ONE area-subsection matching the declared `## Code area`.** Extra `### If Code area = {area}` subsections are prior-fill artifacts and are pruned during fill. If none of the present subsections match the declared area, surface via `AskUserQuestion` rather than silently picking one.

---

## Step 1: Resolve the issue reference

### Repo resolution

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/resolve-repo.md`

Parse `owner`, `repo`, and `index` from the first argument. Parse the optional `--type={value}` flag if present — reject any other unrecognized flag with an error.

## Step 2: Fetch issue, comments, and repo AGENTS.md

Use `mcp__gitea__issue_read` (method `get`) with the parsed owner/repo/index. Fetch:
- Issue title, body, labels, milestone, state
- All comments via `mcp__gitea__issue_read` method `get_comments` (or equivalent) — comments often contain decisions and context that should land in the body

Also fetch the repo's `AGENTS.md` on the default branch via `mcp__gitea__get_file_contents`. This grounds tech-stack and coding-standard references.

**AGENTS.md 404 handling:** If `mcp__gitea__get_file_contents` returns a not-found error for `AGENTS.md`, log the literal line `> **Open question:** No AGENTS.md found in repo — content grounding will be limited to the codebase structure only.` into the report's open-questions section and continue. Do not fail the skill.

If the issue is not found or is closed, report and stop.

## Step 3: Detect type

Priority order:

1. **`--type` flag** — if provided, use it (after validating it's one of the seven allowed types).
2. **Existing type label on the issue** — if the issue already has exactly one of `feature`, `bug`, `enhancement`, `chore`, `polish`, `contract`, `sub-issue`, `design`, use that. (Treat `enhancement` as `feature` for body-format purposes — both use `feature.md`.)
3. **Infer from title/body.** Heuristics:
   - Title begins with `contract:` or body has a `## Contract Definition` section → `contract`
   - Title begins with `sub:` or body has a `## Parent` section referencing `#N` → `sub-issue`
   - Title begins with `design:`, `spike:`, or `RFC:` — OR title/body uses words like "design", "spike", "RFC", "research", "evaluate", "pick" (as in "pick one of X/Y/Z"), "prototype" **combined with the absence of shipped-code intent** (the deliverable is a decision, doc, or prototype report — not a merged feature) — OR body has `## Options under consideration` / `## Decision criteria` / `## Deliverable` sections → `design`
   - Title begins with `fix:` or body describes broken behavior / steps to reproduce → `bug`
   - Title begins with `chore:` or body describes refactor / dep upgrade / infra-only work → `chore`
   - Title begins with `polish:` or body describes a visual/copy/styling-only change → `polish`
   - Title begins with `feat:` or `enhance:`, or body describes a new user-visible capability → `feature`
4. **Ambiguous** — use `AskUserQuestion` to confirm. Provide the top-2 candidates as options plus "Other (specify)".

When matching "design" keywords, be deliberate: a feature issue may mention "design" in passing (e.g., "update the design of the navbar") without being a design-type issue. The distinguishing test is **what the deliverable is** — if the issue closes when code merges, it's a `feature`/`enhancement`/`polish`; if it closes when a decision is recorded, it's a `design`.

### Apply the type label

If the issue lacks a type label, apply the detected type. If the issue already has a type label that differs from the detected type, the behavior depends on how the type was determined:

- **`--type` flag was passed explicitly** (user opt-in): proceed with replacement — the flag is treated as an explicit override.
- **Type came from inference** (existing label was absent/wrong OR title/body heuristic fired): do NOT silently replace the human-applied label. Use `AskUserQuestion` to confirm, showing the existing label and the inferred type. Options:
  - "Keep existing label" — leave the label untouched and adopt the existing type for body-format purposes.
  - "Replace with inferred type" — swap the label.
  - "Add open question to body and skip label change" — insert a `> **Open question:** type label conflict — human applied `{existing}`, inference suggests `{inferred}`. Which is correct?` line into the body and leave the label alone.

Once the decision is made:

1. Check with `mcp__gitea__label_read` (method `list`) whether the target label exists in the repo.
2. If not, create it with `mcp__gitea__label_write` method `create` (let the UI pick a default color if none is specified).
3. Apply it via `mcp__gitea-workflow__label_issue` with `type_label: "{detected}"`. This swaps existing type labels automatically.

## Step 4: Load the canonical template

Load the template for the detected type. These are the seven files in `plugins/planning/lib/issue-formats/`:

- **feature / enhancement** — !`cat ${CLAUDE_PLUGIN_ROOT}/lib/issue-formats/feature.md`
- **bug** — !`cat ${CLAUDE_PLUGIN_ROOT}/lib/issue-formats/bug.md`
- **chore** — !`cat ${CLAUDE_PLUGIN_ROOT}/lib/issue-formats/chore.md`
- **polish** — !`cat ${CLAUDE_PLUGIN_ROOT}/lib/issue-formats/polish.md`
- **contract** — !`cat ${CLAUDE_PLUGIN_ROOT}/lib/issue-formats/contract.md`
- **sub-issue** — !`cat ${CLAUDE_PLUGIN_ROOT}/lib/issue-formats/sub-issue.md`
- **design** — !`cat ${CLAUDE_PLUGIN_ROOT}/lib/issue-formats/design.md`

Extract the required top-level section headings from the template (`## Description`, `## Context`, `## Scope`, etc. in order). These are the sections the final body must contain.

## Step 5: Diff current body against template sections

For each required section in the template:

1. Does the current body contain an identically-named `## {heading}` section?
2. If yes, is its content non-empty (not just whitespace, placeholder `{...}`, or a single "TBD")?

Classify each section as:
- **present-and-filled** — leave alone entirely.
- **present-but-empty** — fill in.
- **missing** — add in canonical position.

**Do not reorder or rename existing sections** that are present-and-filled, even if their position differs from the template. Add missing sections in the template's order relative to the closest present sibling.

## Step 6: Ground fills in the codebase

Before filling, read repo structure and relevant files to ground new content:

1. `mcp__gitea__get_dir_contents` on the repo root and one or two levels deep — understand the module/file layout.
2. If the existing issue body or comments mention specific paths, APIs, or components, read those files via `mcp__gitea__get_file_contents`.
3. Pull the repo's `AGENTS.md` (already fetched in Step 2) for tech-stack hints.
4. If this is a sub-issue, also fetch the parent issue (from `## Parent` reference) so `## Contract compliance` can quote the parent's contract posture.

**Every filled section must cite real file paths.** Never invent a filename. If the right path is unknown, write `> **Open question:** Which file in the repo should own {thing}?` and stop filling that bullet.

### Filling `## Acceptance Criteria` — type-dependent form

GWT is ONLY valid on `feature` / `enhancement` issues. All other types use concrete implementation-level checklists per the type's format file in `plugins/planning/lib/issue-formats/`.

- **`feature` / `enhancement`** — produce `### Scenario:` + GIVEN / WHEN / THEN blocks (existing behavior). Each scenario tests exactly one user-observable behavior.
- **`bug`** — produce a checklist with "Fix verification", "Regression coverage", "Related paths" subsections (see `bug.md`).
- **`chore`** — produce a checklist with "Behavior preservation", "Code changes", "Side effects" subsections (see `chore.md`).
- **`polish`** — produce a checklist with "Visual", "Responsiveness", "Non-regression" subsections (see `polish.md`).
- **`contract`** — produce a checklist with "Artifact", "Dependent wiring", "Review" subsections (see `contract.md`).
- **`design`** — produce a checklist with "Decision", "Evaluation", "Downstream" subsections (see `design.md`).
- **`sub-issue`** — produce an area-aware checklist matching this sub-issue's `## Code area`. Pull the appropriate subsection (`backend` → inputs/outputs/errors; `frontend` → layout/styling/state; `data-model` → schema/indexes/migration; etc.) from `sub-issue.md` and drop the others. Do NOT emit GWT here — user-interaction behavior lives on the parent feature, already validated via that feature's GWT.

  **Prune stale area subsections on sub-issue fills.** If the current body contains MULTIPLE `### If Code area =` subsections under `## Acceptance Criteria` (a prior-fill artifact, or the author kept the template boilerplate), prune to keep ONLY the subsection matching the declared `## Code area`, removing the others. Pruning is safe when one of the present subsections matches the declared area. If NONE of the present subsections match the declared area, do not silently pick one — surface via `AskUserQuestion` with options: "Keep {declared area} subsection (add it; remove mismatched ones)" / "Update `## Code area` to match one of the present subsections" / "Skip pruning (leave body as-is)".

**Handling existing GWT on a non-feature body:** if the current body already contains `### Scenario:` + GWT and the detected type is NOT `feature` / `enhancement`, do not silently rewrite. Use `AskUserQuestion` with options:

- **Replace with checklist** — overwrite the GWT with the type-appropriate checklist form.
- **Keep as GWT with a note** — add a `> **Note:** GWT preserved at user request — does not match canonical {type} format.` line under the Acceptance Criteria heading and leave the scenarios.
- **Skip this issue** — make no changes to Acceptance Criteria on this pass.

**Handling missing GWT on a feature body:** if Acceptance Criteria is empty or missing on a `feature` / `enhancement`, produce GWT scenarios (existing behavior).

## Step 7: Coverage walk for features and bugs

When filling a `feature` or `bug` issue, explicitly walk all seven coverage areas:

| Area | What to check |
|------|---------------|
| `data-model` | New tables, migrations, ORM models, shared types, schema changes |
| `api-contract` | New routes, handler signatures, request/response shapes, validation |
| `backend` | Service logic, background jobs, integrations |
| `frontend` | UI components, pages, state, API clients |
| `tests` | Unit, integration, e2e — which kinds are needed |
| `infra/ci` | Env vars, CI workflow tweaks, secrets, deploy config |
| `docs` | AGENTS.md additions, README, API docs |

For each area, either include it in the filled Scope / Technical notes section, **or** add a literal line:

```
No {area} changes needed — {concrete reason}.
```

Never silently omit an area. If an area is impossible to determine, insert an Open question rather than guessing "not applicable".

**Design issues skip this step entirely.** Design work doesn't touch code — the deliverable is a decision, RFC, or research summary — so the 7-area walk doesn't apply. Instead, for `design` issues, ensure the body covers these five areas (all sections from `design.md`):

| Section | What to check |
|---------|---------------|
| `Goal` | The decision this issue will produce, or the artifact. Deliverable type is explicit (decision / doc / prototype), not "ship code". |
| `Options under consideration` | At least two named options with one-line descriptions and pros/cons headlines, OR the literal "Options to be enumerated during the investigation." line. |
| `Decision criteria` | How the options will be evaluated, prioritized (at least 2 criteria). |
| `Deliverable` | Location (e.g., `docs/design/...md`, ADR file, linked doc URL), format (RFC / ADR / prototype + report / inline comment), and optionally a timebox. |
| `Downstream impact` | Blocking issues listed (`Blocks: #N`), OR contract-produced note, OR the literal "No downstream blocking" line. |

If any of these five sections is missing or empty, flag as an Open question rather than fabricating content.

## Step 8: Contract references

If the issue body, comments, linked plan, or any issue in the same milestone suggests a shared interface / schema / API / protocol / event format:

1. Look for a `contract` issue in the same milestone via `mcp__gitea__list_issues` (filtered by milestone, label `contract`).
2. If a matching contract exists: add `- **BLOCKED BY** #{contract_index} — {contract title}. Do not begin work until the contract is merged.` in `## Dependencies` and ensure the `blocked` label is applied (via `mcp__gitea__issue_write` method `add_labels`; create the label first if needed). Uses `add_labels` (not `label_issue`) because `blocked` is not a `type_label` — `mcp__gitea-workflow__label_issue` is only for atomic type swaps (`feature`, `bug`, `chore`, `polish`, `contract`, `sub-issue`, `design`). Non-type labels like `blocked`, `status:*`, and code-area labels go through `add_labels`.
3. If no contract matches but one is clearly implied, insert an Open question asking whether a contract issue should be created and flag this for `update-milestone` to handle.
4. If nothing contract-shaped applies, insert the literal line matching the detected type's format file. The exact string differs per type — match the canonical form in `plugins/planning/lib/issue-formats/{type}.md` so readiness checks (including `update-milestone`'s per-type literal matching) succeed:
   - `feature` / `enhancement` / `bug` / `chore` — `- No shared contracts involved — this is self-contained.`
   - `polish` — `- No shared contracts involved — this is visual-only and self-contained.`
   - `design` — `- No shared contracts involved — this is self-contained investigation.`
   - `sub-issue` — `- No shared contract — this sub-issue is internal to the parent feature.` (singular "contract" — this lives under `## Contract compliance`, not `## Dependencies`)
   - `contract` — N/A; contract issues declare their own `## Dependent Issues` section rather than carrying a posture line.

Every final body must have an explicit posture — blocked-by-contract, or self-contained — using the exact literal for the detected type. `update-milestone` readiness checks match the same per-type literal.

## Step 9: Preview the diff

Build the merged body. Show the user a preview of exactly which sections are being added or filled. Prefer a summary table followed by the proposed section text:

```
## Proposed changes to #{index}: {title}

Type detected: {type}  (source: {--type / label / inference / confirmed})

Sections to ADD:
- ## Context (was missing)
- ## Dependencies (was missing)

Sections to FILL (were empty):
- ## Technical notes

Sections LEFT AS-IS (already filled):
- ## Description
- ## Scope

Open questions surfaced: {N}
Coverage-area lines added: {N}
Contract posture: {BLOCKED BY #N / self-contained / open-question}
```

Then use `AskUserQuestion`:

- **Apply changes** — write the merged body.
- **Review full body** — print the entire merged body, then confirm.
- **Abort** — make no changes.

## Step 10: Write

On confirmation, call `mcp__gitea__issue_write` with `method: "edit"` and the merged body. Reapply the type label if it was missing (Step 3). Reapply the `blocked` label if Step 8 added a BLOCKED BY line.

If the write fails, report the error verbatim and do not retry silently.

## Step 11: Detect multi-outcome features

**Runs only for `feature`-type issues.** Skip entirely for `bug`, `chore`, `polish`, `contract`, `sub-issue`, and `design` issues.

A feature issue is a vertical slice delivering **one** user-visible outcome. Some features accidentally bundle multiple distinct outcomes (e.g., "user can import recipes from URL, manage their library, and export to PDF" is three features). This step detects likely multi-outcome features and proposes splitting — always with user confirmation.

### Skip conditions

Before running the heuristic, check whether this issue has already been confirmed as intentionally multi-outcome. If the body (under `## Scope` or `## Notes`) contains a line like `> User confirmed this is intentionally a single feature despite multiple outcomes. Do not re-prompt.`, skip this step entirely.

### Detection heuristics (agent judgment, not regex)

Read the full issue — title, `## Description`, and `## Scope` sections — and judge whether ANY of these signals fire strongly enough to flag:

1. **Multiple "user can …" clauses** — the Description contains more than one distinct user-capability statement (e.g., two sentences each starting with "User can" / "Users can" / "The user can"), each describing a different outcome.
2. **Conjunctive title or description** — the title or Description contains coordinating conjunctions linking distinct verbs (e.g., "… and export …", "… plus …", "… as well as …") where each side describes a separable action on distinct nouns.
3. **Scope → In scope bullets describing disjoint outcomes** — bullets that could each stand alone as a "user can X" sentence without the others, rather than facets of one outcome.
4. **Multiple distinct verbs on distinct nouns in the title** (e.g., "Import and Export recipes" — `import` is one verb on recipes, `export` is another verb on recipes; these are separable outcomes).

These are **judgment calls**, not regex matches. Evaluate them by reading the whole issue, not by pattern-matching isolated strings. Use all the signals together rather than triggering on any single one too aggressively. **If uncertain, err on the side of NOT flagging** — false positives annoy users more than false negatives.

### If flagged

Compose a proposed split: the list of distinct outcomes, each as a one-line user-capability summary with a proposed scope slice carved from the original issue's Scope bullets / Technical notes.

Use `AskUserQuestion`:

```
Feature #{index} may bundle multiple user outcomes:

"{title}"

Detected outcomes (proposed split):
1. {outcome A — one-line summary}
2. {outcome B — one-line summary}
[...]

[Split into multiple features] [Keep as single feature] [Let me revise the body manually]
```

### Option: Split into multiple features

For each detected outcome, create a new Gitea issue via `mcp__gitea__issue_write` with `method: "create"`:

- Title: the outcome as a concise feature title
- Body: a fresh feature-format body with the original's scope divided — each new issue gets the scope bullets / technical-notes fragments that belong to its outcome. Open questions for anything not cleanly partitionable.
- Labels: `feature` (same label the original has / would have)
- Milestone: same milestone as the original

After the new issues are created, ask the user via a second `AskUserQuestion` what to do with the original:

```
Original #{index} — after splitting into #{A}, #{B}, … — should it become:

[Tracking umbrella] — rewrite body as a meta-issue linking the new issues; keep open
[Close with pointer] — add a comment "Split into #{A}, #{B}, …" and close
```

- **Tracking umbrella**: rewrite the body to a short meta-issue description listing the child outcomes as `- [ ] #{A} — {outcome A title}`, `- [ ] #{B} — {outcome B title}`, etc. Write via `mcp__gitea__issue_write` method `edit`.
- **Close with pointer**: add a comment via `mcp__gitea__issue_write` method `add_comment` pointing at the replacements, then close via `mcp__gitea__issue_write` method `edit` with `state: "closed"`.

### Option: Keep as single feature

Add a short note to the issue body (under `## Scope`, or append a `## Notes` section if one doesn't exist):

```
> User confirmed this is intentionally a single feature despite multiple outcomes. Do not re-prompt.
```

Write via `mcp__gitea__issue_write` method `edit`. This prevents future runs from re-prompting on the same issue.

### Option: Let me revise the body manually

Skip — make no changes. Log the choice for the Step 14 report (so the user has a record of which feature they deferred).

### Never auto-split without confirmation

Splitting is a heavy change — it creates new issues and potentially closes the original. The user must be in the loop via `AskUserQuestion` every time. If the agent cannot get confirmation (e.g., non-interactive context), it must skip the split and log the detection in the report.

### Record for Step 14

- `split_detected`: bool
- `split_decision`: `"split" | "keep" | "revise" | "n/a"`
- `new_issue_indices`: list of newly-created issue indices (if split)
- `original_disposition`: `"umbrella" | "closed" | "kept" | "unchanged" | "n/a"`

## Step 12: Reconcile Test Criteria checkboxes

After the body write settles, scan the (now-current) issue body for a `## Test Criteria` section and reconcile any deterministic checkboxes against live state. Only two tag types are auto-reconciled: `[subtask-check]` and `[ci-check]`. All other tags (`[ai-verify]`, `[local-test]`, `[human-verify]`, `[human-assist]`, `[post-merge]`) require human or test-run verification — skip them entirely (don't auto-tick, don't flag).

### Parse

Re-fetch the issue body (or reuse the merged body just written) and locate the `## Test Criteria` section. Extract every line matching:

```
- [ ] [subtask-check] {text}
- [x] [subtask-check] {text}
- [ ] [ci-check] {text}
- [x] [ci-check] {text}
```

Preserve the line number / character offset of the checkbox chars (`[ ]` or `[x]`) so the patch touches only those two characters — never any surrounding text.

### Resolve sub-issue state for `[subtask-check]`

Find every open sub-issue of this parent. Use the same pattern as `create-subtasks` / `update-milestone` Step 4:

1. **Primary pass (milestone-scoped):** `mcp__gitea__list_issues` with this repo, filtered by `milestone_id` (if the parent has a milestone) and `labels: ["sub-issue"]`, `state: "all"` (we need both open and closed to determine completeness).
2. For each returned issue, parse its `## Parent` section. A match is any line referencing `#{this_issue_index}` (e.g., `Sub-issue of #{index} — {title}`).
3. **Secondary pass (orphan recovery):** also run `mcp__gitea__list_issues` with `labels: ["sub-issue"]`, `state: "all"`, **without the milestone filter**, to catch any sub-issue whose `## Parent` body text references this parent's index even though its `milestone` field is null or different. For each such orphan found (not already in the primary-pass set), include it in `linked_subs` for completeness computation AND emit a warning for the Step 14 report: `"Sub-issue #N references parent via ## Parent body but is not in the parent's milestone — data integrity issue"`. Never silently ignore orphans — a sub-issue that references the parent but sits outside the milestone is a drift signal the user needs to see.
4. Build `linked_subs = {index, state}` for the union of primary-pass and secondary-pass matches.

Decision per `[subtask-check]` line:

- `linked_subs` is empty → leave unchanged. (If a user intentionally wrote "[ ] [subtask-check] N/A if no subtasks needed", it stays unchecked; we don't auto-tick in the no-subtasks case because we can't distinguish "done because empty" from "placeholder waiting for real subtasks".)
- Every sub-issue in `linked_subs` is `closed` → propose tick (`[ ]` → `[x]`).
- Any sub-issue is `open` → leave unchecked.

For every `[x] [subtask-check]` line, run the same query. If any linked sub-issue is now `open` (reopened since the box was ticked), emit a **stale finding**: `stale checkbox: [subtask-check] marked complete but sub-issue #{N} is now open`. Do not auto-untick.

### Resolve PR CI state for `[ci-check]`

Find the PR linked to this issue:

1. `mcp__gitea__list_pull_requests` with `owner`, `repo`, `state: "all"` (we want open **and** merged — a merged PR with green CI is a valid tick source).
2. For each PR, check whether it references this issue: inspect `body` for `Closes #{index}`, `Fixes #{index}`, `Resolves #{index}` (case-insensitive). PRs whose title or branch name contains `#{index}` are weaker hints — use them only if no body reference matches.
3. Filter PRs by BOTH `state` and `merged`. In Gitea, merged PRs report `state: "closed"` with `merged: true`, so filtering by `state` alone is insufficient. Select PRs where `state: "open"` OR (`state: "closed"` AND `merged: true`). Ignore PRs with `state: "closed"` AND `merged: false` (closed unmerged). If multiple PRs match, prefer the most recent by `updated_at`, with `state: "open"` preferred over merged.
4. If no PR is linked, leave the box unchecked — no proposal.

For the selected PR, run the CI-check procedure (same pattern as the `check-ci` skill in `dev-workflow`):

1. `mcp__gitea__pull_request_read` method `get` with `owner`, `repo`, `index: {pr_index}` — always re-fetch, never reuse a stale PR object. Capture `head.sha`.
2. `mcp__gitea__actions_run_read` method `list_runs` with `owner`, `repo`. Filter the returned runs to those with `head_sha` equal to the PR's current HEAD.
3. Determine CI state from the filtered runs:
   - Any run with `status: "running"` or `status: "waiting"` → **running**
   - All runs `status: "completed"` with `conclusion: "success"` (ignoring skipped jobs) → **passed**
   - Any run `status: "completed"` with `conclusion: "failure"` → **failed**
   - No runs match the HEAD SHA → **no-ci**

Decision per `[ci-check]` line:

- CI state `passed` (all completed runs for HEAD succeeded, none in-progress) → propose tick.
- CI state `running`, `failed`, `no-ci`, or no linked PR → leave unchecked.

For every `[x] [ci-check]` line, verify the latest CI run for the linked PR's current HEAD is still `passed`. If it's now `failed` (rare — can happen after a force-push that broke something), emit a **stale finding**: `stale checkbox: [ci-check] marked complete but latest CI for PR #{N} is now failing`. Do not auto-untick.

### Confirm and patch

If at least one proposed tick or stale finding exists, use `AskUserQuestion`:

```
#{index} "{title}" — Test Criteria reconciliation:

Proposed ticks ({N}):
  - line {L}: [subtask-check] {text}  — all {K} linked sub-issues closed
  - line {L}: [ci-check] {text}       — PR #{P} CI passed

Stale flags ({M}, surfaced only — will not auto-untick):
  - line {L}: [x] [subtask-check] — sub-issue #{S} is now open
```

Options:

- **Apply all proposed tick/flag changes** — patch each proposed `[ ]` → `[x]`. Stale findings are added to the report, not written to the body.
- **Review per-checkbox** — step through each proposed tick with its own confirm; stale findings are read-only.
- **Skip this issue** — no body change; stale findings still go to the report.

If the user applies any changes, build a patched body by replacing only the checkbox chars (`[ ]` ↔ `[x]`) at the recorded offsets. Do not touch anything else on the line. Write via `mcp__gitea__issue_write` method `edit`.

If the patch write fails, report the error verbatim and do not retry silently. Preserve the stale findings for the Step 14 report regardless.

Record for Step 14:

- `ticks_applied`: count of `[subtask-check]` and `[ci-check]` boxes changed to `[x]`
- `stale_flags`: list of stale findings (line, tag, reason)
- `orphan_subissue_warnings`: list of orphan-sub-issue findings surfaced by the secondary pass (`"Sub-issue #N references parent via ## Parent body but is not in the parent's milestone — data integrity issue"`)

## Step 13: Propose a lifecycle status label

After the body is written, inspect the issue's current labels (use the set fetched in Step 2, plus any labels applied in Steps 3/8/10) and determine whether a lifecycle status label is already present.

**Lifecycle status labels** (any of these counts as "already set"):

- `status: backlog`
- `status: in-progress`
- `status: ready-to-test`
- `status: in-review`
- `status: done`

`status: needs-human-review` is a skip/defer marker, NOT a lifecycle label — if the issue has it but no other status label, treat it as "no lifecycle label".

### Decision

1. **Lifecycle label already present** — do nothing. Never override an existing status label. Note this in the Step 14 report as "status label: {existing} (left unchanged)".
2. **Issue is blocked** — if the issue has the `blocked` label OR the merged body contains a `**BLOCKED BY** #N` line in `## Dependencies`, skip the prompt entirely. Leave status unlabeled — the `blocked` label is the posture. Note this in the Step 14 report as "status label: none (blocked — status deferred until unblock)".
3. **No lifecycle label and not blocked** — use `AskUserQuestion` to propose `status: backlog`:

   ```
   #{index} "{title}" has no lifecycle status label. Set one now?
   ```

   Options:
   - **Set to backlog (Recommended)** — apply via `mcp__gitea-workflow__set_issue_status` with `status: "backlog"`.
   - **Leave unlabeled** — do nothing; note in the report.
   - **Set to something else (free text)** — prompt for the specific status; must be one of `backlog`, `in-progress`, `ready-to-test`, `in-review`, `done`; apply via `mcp__gitea-workflow__set_issue_status`.

   Apply the chosen status via `mcp__gitea-workflow__set_issue_status`. This tool handles label ID lookup and swaps any existing `status:` label atomically.

Record the resulting status (or lack thereof) so the Step 14 report can include it.

## Step 14: Report

Print a concise report to the user:

```
## Updated #{index} — {title}

**Type:** {type} (label {applied/already set})
**Sections added:** {list}
**Sections filled:** {list}
**Open questions:** {count} — listed inline in the body
**Contract posture:** {BLOCKED BY #N / self-contained / open question}
**Labels changed:** {before → after}
**Status label:** {status: backlog applied / {existing} left unchanged / none — blocked / none — user declined}
**Checklist reconciliation:** {N ticks applied / none proposed / user skipped}
**Stale checkbox flags:** {list of "[x] [subtask-check] line L — sub-issue #S is now open" / "[x] [ci-check] line L — CI for PR #P is now failing", or "none"}
**Orphan sub-issue warnings:** {list of "Sub-issue #N references parent via ## Parent body but is not in the parent's milestone — data integrity issue", or "none"}
**Feature-split proposal:** {not applicable — not a feature / not flagged / flagged — user split into #{A}, #{B}, … (original → umbrella / closed) / flagged — user kept as single feature (note added to body) / flagged — user chose to revise manually (no changes)}

{If the issue now passes all readiness checks:}
Ready to start:
> `/do-issue {owner/repo}#{index}`

{If still blocked or has open questions:}
Still needs: {human decision on open questions | contract to resolve | sub-issues}
```
