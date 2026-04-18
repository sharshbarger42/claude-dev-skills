---
name: update-milestone
description: Verify a Gitea milestone is ready to start work. Classifies each issue, runs per-type readiness checks, and auto-fixes gaps by calling update-issue and create-subtasks. Enforces contract references and siloed sub-issues.
argument-hint: <milestone-ref> [owner/repo]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, AskUserQuestion, Skill, mcp__gitea__issue_read, mcp__gitea__issue_write, mcp__gitea__list_issues, mcp__gitea__list_pull_requests, mcp__gitea__pull_request_read, mcp__gitea__actions_run_read, mcp__gitea__milestone_read, mcp__gitea__milestone_write, mcp__gitea__label_read, mcp__gitea__label_write, mcp__gitea__get_file_contents, mcp__gitea__get_dir_contents, mcp__gitea-workflow__label_issue, mcp__gitea-workflow__set_issue_status
---

# Update Milestone Skill

Audit a Gitea milestone and make it ready to hand off to AI agents. The skill classifies every open issue in the milestone, runs per-type readiness checks, and auto-fixes gaps by delegating to `update-issue` and `create-subtasks`. Contract issues are processed first — they define the seams other issues consume.

**Input:** Milestone reference + optional `owner/repo`. Accepted formats:
- Milestone ID: `42` (requires `owner/repo` as second arg)
- Milestone title: `"v0.1 — MVP"` (requires `owner/repo`)
- Full URL: `https://git.home.superwerewolves.ninja/super-werewolves/food-automation/milestones/42`
- Shorthand: `food-automation#milestone=42` or `food-automation milestone "v0.1 — MVP"`

## Rules

- **Contracts are processed first.** Their `## Dependent Issues` list is the source of truth for block markers, but drift is bidirectional — if a dependent says BLOCKED BY #{C} but #{C}'s list doesn't include it, fix the contract; and vice-versa.
- **Do not auto-create sub-issues for contract-blocked issues until the contract is defined.** Flag the issue for human review instead — creating sub-issues before the contract is stable produces work that needs to be redone.
- **Never mark an issue "ready" if any required section is empty or still contains placeholder text (`{...}`).** The per-type readiness checks are not advisory — they are blocking.
- **A feature with no sub-issues must either have explicit "no subtasks needed — {reason}" text in its body OR `create-subtasks` must run during auto-fix.**
- **Every issue needs an explicit contract posture** — either BLOCKED BY, or "No shared contracts involved — this is self-contained."
- **Multiple type labels are treated as a classification error, not a silent fallback.** The user must pick one before the audit proceeds.
- **Auto-fix runs in waves; within a wave, actions parallelize via `Agent` tool.** Contracts always run serially. Two actions never target the same issue concurrently.
- **Auto-fix is interactive by design — delegated skills may prompt the user mid-run.** `update-issue` and `create-subtasks` each surface their own `AskUserQuestion` prompts (type conflicts, GWT conversion, multi-outcome splits, status conflicts, checkbox reconciliation, sub-issue area pruning). There is no non-interactive mode — plan accordingly on large milestones.
- **User-skipped classifications persist across sessions via the `status: needs-human-review` label.** To re-trigger classification, remove the label manually.
- **Status labels are audited per-issue.** Missing labels on ready issues default to `backlog`. Conflicts (`in-progress` + `blocked`, `done` + open, etc.) are surfaced as `AskUserQuestion`, never silently resolved.
- **Checklist reconciliation runs in its own wave, after all body/status fixes settle** (see Step 9 Wave 6). Only `[subtask-check]` and `[ci-check]` are auto-ticked; only with user confirmation per the delegated `update-issue` call. Stale `[x]` items (sub-issue reopened, CI now failing) are surfaced but never auto-unticked.
- **Feature-split proposals run in their own wave, last** (see Step 9 Wave 7). Splits are never auto-applied — always via per-feature `AskUserQuestion` (delegated to `update-issue`'s Step 11). Confirmed-single features are marked in-body so they don't re-prompt on future runs.
- **GWT vs checklist — type rule.** `### Scenario:` + GWT is valid ONLY on feature / enhancement issues. Presence of GWT on any other type (bug, chore, polish, contract, design, sub-issue) is a readiness failure. Absence of GWT on a feature / enhancement is a readiness failure. When auditing an issue, the readiness check should: (1) look for `### Scenario:` headers in the Acceptance Criteria section; (2) require ≥1 scenario in GWT form for features; (3) for all other types, flag any `### Scenario:` as a violation and require checkbox items (`- [ ]`) under the type's appropriate subheadings instead.

---

## Step 1: Resolve the milestone reference

### Repo resolution

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/resolve-repo.md`

Parse the first argument and optional second:

- Full milestone URL → extract owner/repo/milestone-id from path segments
- `milestone-id` or `"milestone title"` + `owner/repo` → use as-is
- Bare milestone-id or title without repo → ask the user for `owner/repo` via `AskUserQuestion`

Use `mcp__gitea__milestone_read` to confirm the milestone exists, and capture:
- Milestone ID (`milestone_id`)
- Title
- State (open/closed — refuse to audit a closed milestone)
- Description, due date

If the milestone doesn't exist, stop and report.

## Step 2: Fetch all open issues in the milestone

Use `mcp__gitea__list_issues` filtered by `milestone_id` and `state: "open"`. Closed issues are ignored for readiness — they're already done or abandoned.

Capture for each:
- `index`, `title`, `body`, `labels`, `comments_count`
- `created_at`, `updated_at`, `state`

**Pre-filter deferred-for-human issues:** Any issue with the `status: needs-human-review` label goes into a "deferred for human" bucket. These are NOT re-prompted for classification (the user already chose to skip them) and they are NOT queued for auto-fix. They are listed in the final report under a "Deferred — human review needed" section. To re-trigger classification for a deferred issue, the user must remove the `status: needs-human-review` label manually.

If the milestone has zero open issues, report "Milestone is empty — nothing to audit" and stop.

## Step 3: Classify each issue

For every issue, derive its type:

1. **Exactly one known type label present** — if the issue has exactly one of `feature`, `bug`, `enhancement`, `chore`, `polish`, `contract`, `sub-issue`, `design`, use that.
2. **Two or more known type labels present** (e.g., both `feature` and `enhancement`, or `design` + `feature`) — classify as `conflicting-type-labels` and surface to the user via `AskUserQuestion` asking which one is correct. Options: each applied type label as a choice, plus "Other (specify)". Do NOT silently fall through to inference — the user must pick one before the audit proceeds for this issue. Apply the chosen label (and remove the other conflicting ones via `mcp__gitea__issue_write` method `remove_label`) before running readiness checks.
3. **No type label** — infer using the same heuristics as `/update-issue` Step 3 (title prefix → body shape).
4. **Ambiguous after inference** — add to an "untyped" list; surface all untyped issues in a single `AskUserQuestion` batch for the user to confirm (Step 6).

Maintain an in-memory map: `issues_by_index[index] = {type, title, body, labels, ...}`.

## Step 4: Contracts first pass

Iterate over issues where `type == "contract"`:

For each contract #{C}:

0. **Re-fetch the contract body immediately before reconciling.** Call `mcp__gitea__issue_read` method `get` on `#{C}` to get the current body — do NOT reuse the Step 2 body. The gap between classification (Step 3) and reconciliation (here, and often many waves later in Step 9) is wide enough that the contract may have been edited by another agent or a human. Re-fetching right before the read-modify-write step minimizes the race window with concurrent agents. `create-subtasks` Step 11 uses the same pattern (re-fetch immediately before editing the contract) for the same reason.
1. **Parse `## Dependent Issues`** from the freshly-fetched contract body. Each bullet should reference an issue (`- #{N} {title} — consumes: …`). Build `declared_dependents[C] = {N1, N2, …}`.
2. **Scan all other open issues** for `**BLOCKED BY** #{C}` in their `## Dependencies` section. Build `actual_dependents[C] = {M1, M2, …}`.
3. **Reconcile the two lists:**
   - If an issue is in `declared_dependents` but not `actual_dependents`: queue an `update-issue` pass on that issue to insert a `BLOCKED BY #{C}` line and the `blocked` label.
   - If an issue is in `actual_dependents` but not `declared_dependents`: queue an `update-issue` pass on the **contract** itself to extend `## Dependent Issues`. The delegated Wave 0 `update-issue` call MUST re-read the contract body via `mcp__gitea__issue_read` when it runs — delegated skills should not inherit this skill's Step 2 cached read, since the body may have changed again between this step and Wave 0 execution.
4. **For each dependent issue with sub-issues:**
   - Fetch sub-issues via two passes so orphan sub-issues aren't silently ignored:
     - **Primary (milestone-scoped):** `mcp__gitea__list_issues` filtered by label `sub-issue` + the same milestone, cross-referencing the parent index via `## Parent`.
     - **Secondary (orphan recovery):** `mcp__gitea__list_issues` with label `sub-issue`, `state: "all"`, **without the milestone filter**. Any sub-issue whose `## Parent` body text references the dependent issue but was NOT returned by the primary pass is an orphan. Include it in the audit AND record a warning for the report: `"Sub-issue #N references parent #{dep} via ## Parent body but is not in the parent's milestone — data integrity issue"`.
   - Audit every sub-issue body (primary + orphans) for a `## Contract compliance` section that references `#{C}` with a specific "implements: …" line. Queue `update-issue` on any that are missing.
5. **For dependent issues with NO sub-issues:** FLAG for human review. Do **not** auto-run `create-subtasks` while the contract is still open — contracts must be defined before work is sliced against them.
6. **For dependent issues with NO body at all (title-only):** FLAG for human review.

Record all queued actions for the auto-fix step.

## Step 5: Per-issue readiness checks by type

For each remaining (non-contract) open issue, run the type-specific checklist. A check fails if the body is missing a section, has an empty section, still contains `{…}` placeholder text, or fails a substantive check (e.g., Acceptance Criteria isn't in GWT form).

### Universal: Status label audit (runs on every issue, regardless of type)

Before the type-specific checks, audit the issue's lifecycle status label:

- [ ] Exactly one lifecycle status label present (`status: backlog`, `status: in-progress`, `status: ready-to-test`, `status: in-review`, `status: done`) **OR** the issue is `blocked` (has the `blocked` label, or a `**BLOCKED BY** #N` line in `## Dependencies`). `status: needs-human-review` is a skip marker and does NOT count as a lifecycle label.
- [ ] Status label is consistent with other state:
  - `status: in-progress` must not coexist with `blocked` (contract-blocked or dependency-blocked) — this is a conflict
  - `status: done` must not be on an open issue — this is a conflict (an open issue with `status: done` means the issue was reopened or the label is stale)
  - `status: in-review` requires at least one linked PR (best-effort check — if PR linkage can't be verified via `mcp__gitea__list_pull_requests` or issue cross-references, don't fail the audit; record a note instead)
  - **Contract-blocked issues should have NO lifecycle status label** (except `status: needs-human-review` if deferred). `blocked` is the posture — adding a lifecycle status on top muddies the state.
- [ ] New / recently-created issues with no status label and no `blocked` label → queue for auto-fix as "apply `status: backlog`" (this is a non-conflicting fix; it runs without a prompt).

Classify status-label failures into two buckets for the gap summary (Step 7) and auto-fix plan (Step 8):

1. **Missing (non-conflicting)** — unlabeled, non-blocked, passes type-readiness or will after auto-fix → queue to apply `status: backlog`.
2. **Conflict** — `in-progress` + `blocked`, `done` + open, `in-review` without a PR, or a lifecycle status on a contract-blocked issue → surface via `AskUserQuestion` during auto-fix. Never silently resolve.

### Universal: Checklist reconciliation (runs on every issue with a `## Test Criteria` section)

For every issue whose body contains a `## Test Criteria` section, preview whether any deterministic checkboxes can be reconciled against live state. This is a **dry-run preview here** — the actual body edit happens later in Wave 6 via delegated `update-issue` so the prompt flow is consistent with single-issue runs.

For each issue, scan `## Test Criteria` for:

- **`[ ] [subtask-check]` lines** — query sub-issues of this issue using TWO passes so a sub-issue with a null or mismatched milestone is not silently ignored:
  - **Primary (milestone-scoped):** `mcp__gitea__list_issues` filtered by `milestone_id` + `labels: ["sub-issue"]`, then parse each sub-issue's `## Parent` line to match the current issue index.
  - **Secondary (orphan recovery):** `mcp__gitea__list_issues` with `labels: ["sub-issue"]`, state `all`, **without the milestone filter**. Parse each result's `## Parent` line — any that references this parent's index but was NOT returned by the primary pass is an orphan. Include orphans in the completeness check AND surface a warning: `"Sub-issue #N references parent via ## Parent body but is not in the parent's milestone — data integrity issue"`. Never silently ignore. If every sub-issue (primary + orphans) is closed, record a proposed tick. If any are open, or no sub-issues are linked at all, skip.
- **`[ ] [ci-check]` lines** — find the linked PR for this issue: `mcp__gitea__list_pull_requests` filtered to `state: "all"`, then scan each PR body for `Closes #{index}` / `Fixes #{index}` / `Resolves #{index}`. Pick the most recent open PR, else the most recent merged PR. Then run the shared CI-check procedure against the PR's current HEAD (`mcp__gitea__pull_request_read` → `head.sha` → `mcp__gitea__actions_run_read` method `list_runs`). If CI is `passed`, record a proposed tick. Otherwise skip.
- **`[x] [subtask-check]` lines (stale check)** — re-query sub-issues. If any is now `open`, record a stale flag: "[subtask-check] marked complete but sub-issue #{N} is now open".
- **`[x] [ci-check]` lines (stale check)** — re-check CI for the linked PR's current HEAD. If it's now `failed`, record a stale flag: "[ci-check] marked complete but latest CI for PR #{P} is now failing".
- **All other tagged boxes** (`[ai-verify]`, `[local-test]`, `[human-verify]`, `[human-assist]`, `[post-merge]`) — skip entirely. Don't auto-tick, don't flag.

Record per-issue reconciliation preview: `{issue_index: {proposed_ticks: N, stale_flags: [...]}}`. The actual write happens in Wave 6.

### Feature / Enhancement

- [ ] `feature` or `enhancement` label applied
- [ ] All sections from `feature.md` present and non-empty: `Description`, `Context`, `Scope`, `Technical notes`, `Dependencies`, `Acceptance Criteria`, `Test Criteria`
- [ ] Acceptance Criteria uses `### Scenario:` + **GIVEN** / **WHEN** / **THEN** (not plain bullets)
- [ ] Test Criteria checkboxes are tagged (`[ai-verify]`, `[local-test]`, `[ci-check]`, `[subtask-check]`, `[human-verify]`, `[human-assist]`, `[post-merge]`)
- [ ] **Vertical slice** — Description frames a user-visible outcome, not a technical deliverable
- [ ] **Explicit contract posture** — Dependencies contains `BLOCKED BY #{N}` OR the literal line "No shared contracts involved — this is self-contained."
- [ ] Has ≥1 sub-issue in the milestone referencing this issue as parent, OR the body includes an explicit line "no subtasks needed — {reason}". The sub-issue query uses two passes (primary milestone-scoped + secondary milestone-less for orphan recovery); orphans count for completeness but trigger a data-integrity warning rather than passing silently.
- [ ] 7-area coverage explicitly addressed (for each of `data-model`, `api-contract`, `backend`, `frontend`, `tests`, `infra/ci`, `docs`: area appears in Scope / Technical notes, or a "No {area} changes needed — {reason}" line is present)

**Feature-only: multi-outcome detection (preview).** Run the same heuristics as `update-issue` Step 11 — read the title, `## Description`, and `## Scope` and judge whether the feature bundles multiple distinct user outcomes. These are **agent-judgment calls, not regex matches**: look for multiple "user can …" clauses, conjunctive titles linking distinct verbs on distinct nouns, disjoint outcomes in Scope bullets, etc. Use all signals together, and err on the side of NOT flagging when uncertain.

Skip this check if the body already contains a `> User confirmed this is intentionally a single feature despite multiple outcomes. Do not re-prompt.` note under `## Scope` or `## Notes`.

Record a per-issue preview: `{issue_index: {multi_outcome_flagged: bool, detected_outcomes: ["outcome A one-liner", "outcome B one-liner", ...]}}`. **No body edit happens here** — the actual split proposal runs in Wave 7 via delegated `update-issue` so the prompt flow matches a single-issue run.

### Bug

- [ ] `bug` label applied
- [ ] All sections from `bug.md` present and non-empty: `Summary`, `Reproduction`, `Environment`, `Root cause`, `Fix approach`, `Dependencies`, `Acceptance Criteria`, `Test Criteria`
- [ ] Reproduction has concrete numbered steps with **Expected** / **Actual**
- [ ] Fix approach cites specific files/functions
- [ ] Test Criteria includes at least one `[local-test] Regression test added` entry
- [ ] Acceptance Criteria uses checklist form with `Fix verification` + `Regression coverage` sections (`- [ ]` items under each); must NOT contain `### Scenario:` + GWT
- [ ] Explicit contract posture
- [ ] 7-area coverage explicitly addressed (same as feature)

### Chore

- [ ] `chore` label applied
- [ ] All sections from `chore.md` present and non-empty
- [ ] Scope is tight (single refactor / upgrade / infra change)
- [ ] Acceptance Criteria uses checklist form with `Behavior preservation` section (`- [ ]` items); must NOT contain `### Scenario:` + GWT
- [ ] Explicit contract posture

### Polish

- [ ] `polish` label applied
- [ ] All sections from `polish.md` present and non-empty, including Before / After and Files to change
- [ ] Scope explicitly excludes logic/behavior changes
- [ ] Acceptance Criteria uses checklist form with `Visual` + `Non-regression` sections (`- [ ]` items); must NOT contain `### Scenario:` + GWT
- [ ] Explicit contract posture (usually "self-contained")

### Contract

- [ ] `contract` label applied
- [ ] All sections from `contract.md` present and non-empty
- [ ] `## Dependent Issues` is populated (not an empty bullet list)
- [ ] `## Deliverable location` names a concrete path (`docs/contracts/…`, `.proto`, OpenAPI spec, shared types module)
- [ ] `## Must define` is concrete (field names, validation, error formats, versioning)
- [ ] Acceptance Criteria uses checklist form with `Artifact` + `Dependent wiring` sections (`- [ ]` items); must NOT contain `### Scenario:` + GWT

### Sub-issue

- [ ] `sub-issue` label applied
- [ ] At least one code-area label applied (`backend`, `frontend`, `data-model`, `api-contract`, `infra/ci`, `tests`, `docs`)
- [ ] `## Parent` references a valid parent issue in the same milestone
- [ ] `## Files to create/modify` lists 1-3 real paths
- [ ] `## Contract` section present with inputs (source) and outputs (consumer) — internal or `consumed from #N` / `produces for #N`
- [ ] `## Contract compliance` section present — either references a `#{contract}` with "implements: …", or the literal line "No shared contract — this sub-issue is internal to the parent feature."
- [ ] Explicit `## Dependencies` — `Depends on #N` or "No blockers"
- [ ] Acceptance Criteria uses checklist form appropriate to the sub-issue's `## Code area` (e.g., `backend` → inputs/outputs/errors items; `frontend` → layout/styling/state items; `data-model` → schema/indexes/migration items); must NOT contain `### Scenario:` + GWT
- [ ] Test Criteria tagged

### Design

- [ ] `design` label present
- [ ] All sections from `design.md` present and non-empty: `Summary`, `Goal`, `Context`, `Options under consideration`, `Decision criteria`, `Deliverable`, `Downstream impact`, `Dependencies`, `Acceptance Criteria`, `Test Criteria`
- [ ] `## Options under consideration` enumerates at least 2 named options — unless the body explicitly contains "Options to be enumerated during the investigation."
- [ ] `## Decision criteria` lists prioritized criteria (numbered or ordered), at least 2 entries
- [ ] `## Deliverable` specifies both a **Location** (e.g., `docs/design/...md`, ADR path, linked doc URL, "this issue comment") and a **Format** (RFC / ADR / prototype + report / inline decision comment / diagram)
- [ ] `## Downstream impact` declares the blocking posture — either lists `Blocks: #N {title}` entries, or contains the literal line "No downstream blocking" (or equivalent), or notes "Produces contract: …"
- [ ] Acceptance Criteria uses checklist form with `Decision` + `Evaluation` + `Downstream` sections (`- [ ]` items under each); must NOT contain `### Scenario:` + GWT — the deliverable is a decision artifact, not user-interaction code
- [ ] **Explicit contract posture** — almost always "No shared contracts involved — this is self-contained investigation." (design issues rarely consume a contract; they may produce one as an output)
- [ ] **7-area coverage walk does NOT apply** to design issues (deliverable is a decision/doc, not code). Do not flag missing coverage-area lines for design issues.
- [ ] **Sub-issues are NOT required** for design issues by default (they produce a decision, not code). If the design produces prototype code, benchmark scripts, or write-up chunks, sub-issues are allowed but optional. The "has ≥1 sub-issue or 'no subtasks needed' line" check from feature-readiness does not apply.

Record every failing check as a gap, with the issue index, type, check name, and proposed fix action (`update-issue` or `create-subtasks`).

## Step 6: Confirm untyped classifications

If Step 3 produced any "untyped" issues, surface them now in one `AskUserQuestion` batch:

```
{N} issues in this milestone have no type label. Please confirm:

#{X} "{title}"   → [feature] [bug] [chore] [polish] [contract] [sub-issue] [design] [skip]
#{Y} "{title}"   → [feature] [bug] [chore] [polish] [contract] [sub-issue] [design] [skip]
...
```

Apply confirmed labels before running readiness checks. If the user picks "skip" for any, apply the `status: needs-human-review` label via `mcp__gitea-workflow__set_issue_status` (status `needs-human-review`) — this persists the skip across sessions so subsequent `/update-milestone` runs automatically exclude the issue (see Step 2 pre-filter). Exclude skipped issues from this run's audit and list them under "needs human review" at the end.

## Step 7: Build gap summary

Build a table of all gaps:

| Issue | Type | Failing checks | Proposed fix |
|-------|------|----------------|--------------|
| #17 | feature | missing Context, Acceptance Criteria not GWT, no sub-issues | update-issue; then create-subtasks |
| #18 | bug | missing Reproduction, contract posture | update-issue |
| #22 | contract | Dependent Issues empty | update-issue |
| #31 | — | untyped (user said "skip") | needs human review |
| #34 | feature | blocked by #22, no sub-issues | wait — contract not ready |
| #40 | feature | no lifecycle status label | set-status (backlog) |
| #41 | bug | `status: in-progress` + `blocked` conflict | ask-user (resolve status conflict) |
| #45 | feature | flagged as possibly multi-outcome — 3 distinct outcomes detected | feature-split proposal (user confirms per-issue) |

## Step 8: Confirmation gate

> **Note:** delegated `update-issue` and `create-subtasks` calls may themselves surface `AskUserQuestion` prompts mid-run (type-label conflicts, GWT-form conversion on non-features, multi-outcome feature splits, status-label conflicts, checkbox reconciliation, sub-issue area pruning). On a milestone with 30+ issues, this could mean dozens of mid-run prompts. If that's disruptive, abort here and run the delegated skills manually, or file a follow-up for a non-interactive mode. Auto-fix is interactive by design — it does not batch user decisions.

Use `AskUserQuestion`:

```
Found {total} gaps across {count} issues. Auto-fix plan:

- {N} issues → update-issue (fill sections, apply labels, add contract posture)
- {M} features → create-subtasks (decompose into siloed sub-issues)
- {S} issues → set-status (apply `status: backlog` to unlabeled, non-blocked, readiness-passing issues)
- {C} issues → status-conflict resolution (surfaced per-issue via AskUserQuestion — never silently resolved)
- {R} issues → checklist reconciliation ({T} tick proposals, {F} stale flags across all issues — auto-ticks only `[subtask-check]` / `[ci-check]`, confirmed per-issue via delegated update-issue)
- {F} features → feature-split proposals ({F} features flagged as possibly multi-outcome — each proposal is confirmed per-feature via delegated update-issue; splits are never auto-applied)
- {K} issues → flagged, needs human review (contract-blocked, untyped-skipped, etc.)

Proceed?
```

The **status-label fixes** category covers:

- **Apply `status: backlog`**: any issue with no lifecycle status label, not `blocked`, and passing (or soon-to-pass after `update-issue`) readiness checks. Applied via `mcp__gitea-workflow__set_issue_status` during auto-fix. No per-issue prompt — this is the default for ready issues.
- **Status conflict resolution**: issues where the audit found a contradictory state (`in-progress` + `blocked`, `done` on an open issue, `in-review` without a PR, lifecycle status on a contract-blocked issue). Each is surfaced as its own `AskUserQuestion` during auto-fix with options like "Remove `status: in-progress` (keep blocked)", "Remove `blocked` (keep in-progress)", "Leave as-is", etc. The user picks the resolution; this skill never silently removes a conflicting label.

The **feature-split proposals** category lists every feature flagged as possibly multi-outcome by the Step 5 preview. Show the list with detected outcomes inline so the user can see what's coming before approving auto-fix — each line reads like:

```
- #{N} "{title}" — {K} outcomes detected:
    1. {outcome A one-liner}
    2. {outcome B one-liner}
    [...]
```

This is judgment-preview only — no split happens at the gate. Each flagged feature gets its own `AskUserQuestion` during Wave 7 (Split / Keep / Revise), and splits are never auto-applied.

Options:
- **Proceed with auto-fix** — run the plan as described
- **Review per-issue** — step through each queued action with a per-issue confirmation
- **Abort** — make no changes, just save the gap report

## Step 9: Auto-fix by waves

Partition the queued actions into waves. Waves run serially; actions within a wave run in parallel via the `Agent` tool (launch one Agent per action in a single message so they run concurrently).

### Wave 0 — Contracts (strictly serial, one at a time)

Contract-type issues affect other issues. For each contract issue queued for update, run `update-issue` sequentially — never parallel. After all contract updates finish, re-reconcile dependent block markers (repeat Step 4's Contracts-first pass).

### Wave 1 — Independent feature/bug/chore/polish/design issues

Issues that (a) are not contract-blocked, (b) do not share a parent with another queued issue, and (c) do not appear in any contract's Dependent Issues list. Run these in parallel via multiple concurrent Agent invocations, one per issue. Design issues schedule here alongside other non-contract, non-feature types — they don't have sub-issues by default, don't need contract wiring, and the `update-issue` delegation handles the design-specific readiness checks.

### Wave 2 — Contract-dependent features (serial per contract, parallel across contracts)

For each contract, its dependent features form a serial chain (per contract). Different contracts' chains can run in parallel. Use one Agent per chain.

### Wave 3 — Sub-issue fixes (parallel by parent)

Sub-issues that need `update-issue`. Group by parent feature — within a parent, sub-issues that share no files can run in parallel; ones with shared files go serial.

### Wave 4 — create-subtasks on features missing sub-issues

Must run after Wave 2 so contract-blocked features are already updated. Group by parent, run parallel where parents don't share contracts.

**Skip design issues.** Design issues don't require sub-issues (the deliverable is a decision/doc, not shipped code). If a design issue has produced prototype work, benchmark scripts, or write-up chunks that merit their own sub-issues, the user can invoke `/create-subtasks` on the design manually — do not auto-queue `create-subtasks` on design parents during `update-milestone` auto-fix.

### Wave 5 — Status-label fixes

Runs last so body/label changes from earlier waves settle first (an issue that went from "missing Dependencies" to "BLOCKED BY #N" in Wave 1 should NOT get `status: backlog` applied — the re-verify in Step 5 on the updated body drives the decision).

- **Apply-backlog actions**: for each issue queued for "apply `status: backlog`", call `mcp__gitea-workflow__set_issue_status` with `status: "backlog"`. Run these in parallel — they don't conflict across issues. Skip any issue that is now `blocked` post-Wave-1 (re-check labels before applying).
- **Conflict-resolution actions**: for each status-conflict issue, launch an `AskUserQuestion` with the specific conflict and resolution options. Apply the user's choice via `mcp__gitea-workflow__set_issue_status` or `mcp__gitea__issue_write` method `remove_label` as appropriate. Conflicts run serially so the user isn't hit with a wall of prompts at once.

### Wave 6 — Checklist reconciliation

Runs AFTER Wave 5 so body edits from earlier waves (new Test Criteria sections added by `update-issue`, new sub-issues created by `create-subtasks`) don't clobber the tick changes. By this point the bodies are stable.

For each issue that had a non-empty reconciliation preview in Step 5 (any proposed ticks or stale flags), delegate to `update-issue` on that single issue. The parent does NOT re-implement the reconciliation logic — it invokes `update-issue`'s Step 12 via the `Skill` tool (or the `Agent` tool fallback matching `update-issue`'s contract):

```
Skill: update-issue
args: {owner}/{repo}#{index}
```

`update-issue`'s Step 12 will re-query live state (sub-issues + linked PR CI), show the user the proposal, and write only the checkbox chars on confirmation. This keeps the prompt UX and safety rails identical to a standalone `/update-issue` call.

Run wave-6 actions in parallel across issues — they don't share state (different issue bodies, different sub-issue queries, different PRs). Issues with zero proposals and zero stale flags are skipped entirely (no delegation, no prompt).

Collect each delegated call's outcome — ticks applied and stale flags — for the Step 11 readiness report. Stale findings feed into the report's reconciliation table; they are never written to the body.

### Wave 7 — Feature-split proposals

Runs LAST, after all other fixes settle (body, status, checklist). By this point every other edit is committed, so the user's decision about whether to split is made against the final, up-to-date body — not a stale mid-fix snapshot.

**Serial, per flagged feature.** Each split proposal requires individual user confirmation via `AskUserQuestion`, so hitting the user with multiple simultaneous prompts would be chaotic. Processing features one at a time keeps each decision scoped to a single issue.

**Skip design issues.** Design issues are not features — the multi-outcome detector does not apply to them. Only `feature` / `enhancement` issues are eligible candidates for this wave.

For each feature with `multi_outcome_flagged: true` from Step 5's preview, delegate to `update-issue` on that single issue. The parent does NOT re-implement the detection / split logic — it invokes `update-issue`'s Step 11 ("Detect multi-outcome features") via the `Skill` tool so the logic lives in one place:

```
Skill: update-issue
args: {owner}/{repo}#{index}
```

`update-issue`'s Step 11 will re-run the heuristic against the current body, show the user the split proposal, and — on confirmation — create new Gitea issues and update/close the original per the user's choice. Features the user confirms as intentionally multi-outcome get a `## Notes` line added so future `update-milestone` runs don't re-flag them.

Features with zero flags from Step 5 are skipped entirely (no delegation, no prompt). The `update-issue` delegation also redundantly skips if its own heuristic doesn't fire — that's fine, it's cheap.

Collect each delegated call's outcome — split decision, new issue indices, original disposition — for the Step 11 readiness report.

**Never auto-split.** The `Skill` delegation is the only path; the parent milestone skill never bypasses the per-feature `AskUserQuestion` gate. If the user aborts at the gate or chooses "revise manually", the original issue is left untouched and the decision is logged in the report.

### Safety rail

Never run two actions concurrently that target the SAME issue index. If the partitioning produces such a case, collapse them to serial for that issue. Log the partitioning at the start of each wave so the user can audit.

### Per-action invocation

1. **For `update-issue` actions:** invoke the `update-issue` skill with the issue reference and (if inferred) the `--type` flag. Use the `Skill` tool if available, otherwise the `Agent` tool with explicit instructions matching `update-issue`'s contract. Pass through the `{owner}/{repo}#{index}` argument.
2. **For `create-subtasks` actions:** invoke the `create-subtasks` skill with the parent issue reference. Skip any parent that is contract-blocked where the contract is not yet merged — those stay on the "needs human review" list.
3. **After each delegated skill completes**, re-read the issue via `mcp__gitea__issue_read` and re-run the per-type checklist from Step 5. If the issue now passes, mark it ready. If it still has gaps, add it to a "partial" list — do not loop; the user can re-run `/update-milestone` after reviewing.

## Step 10: Re-verify

After the auto-fix loop, run the per-type checklist from Step 5 again across every issue (including the ones that weren't queued — someone may have edited them between passes). Build a before/after diff:

```
Before: {X} issues ready, {Y} issues with gaps
After:  {X'} issues ready, {Y'} issues with gaps
Changed: {list of issue indices whose status changed}
```

## Step 11: Save readiness report

Write a markdown report to `${HOME}/plans/$(date +%Y-%m-%d)-{repo}-milestone-{id}-readiness.md` (create the directory if missing — use `mkdir -p` via Bash). The date prefix means re-running on the same milestone on a different day keeps prior reports; re-running same day still overwrites (acceptable):

```markdown
# Milestone Readiness: {milestone title}

**Repo:** {owner}/{repo}
**Milestone:** #{milestone_id} — {title}
**Audited at:** {ISO timestamp}
**Total open issues:** {count}

## Summary

- Ready to start: {N}
- Still blocked: {N}
- Needs human review: {N}

## Ready to start

| # | Type | Title | Status label | Command |
|---|------|-------|--------------|---------|
| #{A} | feature | {title} | `backlog` | `/do-issue {repo}#{A}` |
| #{B} | bug | {title} | `in-progress` | `/do-issue {repo}#{B}` |
| ... | | | | |

## Blocked (waiting on contracts)

| # | Type | Title | Status label | Blocked by |
|---|------|-------|--------------|------------|
| #{C} | feature | {title} | none (blocked) | #{contract} — `contract: {name}` |
| ... | | | | |

## Needs human review

| # | Type | Title | Status label | Reason |
|---|------|-------|--------------|--------|
| #{D} | untyped | {title} | `needs-human-review` | user skipped classification |
| #{E} | feature | {title} | none | contract #{F} not yet defined — cannot create sub-issues safely |
| ... | | | | |

## Per-issue changes (this run)

| # | Before | After | Status label change | Actions taken |
|---|--------|-------|---------------------|---------------|
| #{A} | missing Context, no sub-issues | ready | none → `backlog` | update-issue; create-subtasks (5 sub-issues); set-status |
| #{B} | missing Reproduction | ready | `in-progress` (left) | update-issue |
| #{G} | `in-progress` + `blocked` conflict | ready | `in-progress` → none (user chose keep blocked) | status-conflict resolution |
| ... | | | | |

## Checklist reconciliation

| # | Title | Ticks applied | Stale flags |
|---|-------|---------------|-------------|
| #{A} | {title} | 2 ([subtask-check], [ci-check]) | — |
| #{B} | {title} | 1 ([ci-check]) | **[x] [subtask-check] — sub-issue #{S} now open** |
| #{H} | {title} | — | **[x] [ci-check] — PR #{P} CI now failing** |
| ... | | | |

Stale flags indicate drift — a checkbox was marked complete previously but the underlying state has regressed. They are surfaced here but never auto-unticked; a human should investigate.

## Data integrity warnings

Sub-issues that reference a parent in this milestone via `## Parent` body text but sit outside the parent's milestone (null milestone or different milestone) are listed here as drift signals. They count toward completeness checks, but the mismatch is surfaced so a human can reconcile the milestone assignment.

| # | Parent | Warning |
|---|--------|---------|
| #{S} | #{P} | Sub-issue references parent via `## Parent` body but is not in the parent's milestone |
| ... | | |

## Feature-split proposals

Surfaced prominently — splits create new issues and materially change the milestone shape. Every flagged feature is listed whether or not the user chose to split, so there's a permanent record of what was considered.

| # | Title | Detected outcomes | User decision |
|---|-------|-------------------|---------------|
| #{N} | {title} | 1. {outcome A}<br>2. {outcome B}<br>3. {outcome C} | **Split** → new issues #{A}, #{B}, #{C}; original → tracking umbrella |
| #{M} | {title} | 1. {outcome A}<br>2. {outcome B} | **Split** → new issues #{D}, #{E}; original closed with pointer |
| #{P} | {title} | 1. {outcome A}<br>2. {outcome B} | **Keep** — user confirmed intentionally multi-outcome (note added to body) |
| #{Q} | {title} | 1. {outcome A}<br>2. {outcome B} | **Revise manually** — user deferred; no changes |
| ... | | | |

## Still partial after auto-fix

| # | Remaining gaps |
|---|----------------|
| #{X} | Acceptance Criteria still not GWT — update-issue flagged open question |
| ... | |
```

## Step 12: Report to the user

Short summary in chat, with the path to the saved report:

```
## Milestone {title} — Readiness Audit

**Repo:** {owner}/{repo}
**Total open issues:** {count}

### Result
- Ready to start: {N}
- Still blocked: {N}
- Needs human review: {N}

### This run
- {count} issues updated via `/update-issue`
- {count} features broken down via `/create-subtasks`
- {count} new sub-issues created
- {count} issues had `status: backlog` applied
- {count} status-label conflicts resolved
- {count} checklist ticks applied across {count} issues ({count} stale flags surfaced)
- {count} feature-split proposals surfaced ({count} split / {count} kept as single / {count} revised manually)
- {count} flagged for human review

### Suggested next moves
> `/do-issue {repo}#{first_ready}` — {title}
> `/do-issue {repo}#{next_ready}` — {title}

Full readiness report saved to: {report_path}
```
