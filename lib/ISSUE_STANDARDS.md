# Issue Standards

Canonical standards for creating Gitea issues across all super-werewolves repos. Read this before creating an issue via API, MCP, or the web UI.

Related:
- [PR_STANDARDS.md](./PR_STANDARDS.md) — pull request standards
- [label-issue.md](./label-issue.md) — label mechanics
- [status-labels.md](./status-labels.md) — issue lifecycle labels

---

## Issue Hierarchy

Issues fall into one of four tiers. Pick the right tier before writing the title.

| Tier | Prefix | Purpose | Scope |
|------|--------|---------|-------|
| **Milestone** | — (Gitea milestone, not an issue) | Groups issues into a release phase | `v0.1 — MVP`, `v0.2 — {theme}` |
| **Contract** | `contract:` | Defines a shared interface two or more features depend on | Blocks dependent features until merged |
| **Feature** | `feat:` | Vertically-sliced, user-visible capability | Deliverable in a single PR or via sub-issues |
| **Sub-issue** | `sub:` | AI-sized implementation task | 1–3 files, 30–60 min of focused work |

**Bug fixes and enhancements** that aren't large enough to need sub-issues live at the feature tier with the appropriate type label (`bug` or `enhancement`) instead of `feat:`.

---

## Title Format

| Tier | Template | Example |
|------|----------|---------|
| Contract | `contract: {name} — define {type}` | `contract: recipe-import — define API schema` |
| Feature | `feat: {user-facing description}` | `feat: user can import recipes from URL` |
| Bug | `fix: {what is broken}` | `fix: login fails with trailing whitespace` |
| Enhancement | `enhance: {what improves}` | `enhance: recipe list loads 3x faster` |
| Sub-issue | `sub: {specific task}` | `sub: add recipe URL parser with validation` |

Rules:
- Frame features from the user's perspective — "User can X", not "Implement X".
- Keep titles under ~70 characters; put details in the body.
- No trailing period.

---

## Body Structure

### Feature issue

```markdown
## Description

{What the user can do after this is implemented — 2–3 sentences from their perspective.}

## Context

{Relevant architecture decisions, tech stack, design notes.}

## Scope

**In scope:**
- {specific deliverable}

**Out of scope:**
- {what this does NOT include — link later milestone features}

## Technical notes

- {library to use and why}
- {data model or API endpoint involved}

## Dependencies

- Depends on #{N} — {why}
- BLOCKED BY #{contract_N} — do not begin work until contract is merged

## Acceptance Criteria

{GIVEN/WHEN/THEN scenarios — see "Acceptance Criteria Format" below.}

## Test Criteria

- [ ] [ai-verify] {testable via API on dev}
- [ ] [local-test] Lint and type-check pass
- [ ] [local-test] Unit/integration tests pass
- [ ] [ci-check] CI pipeline passes
- [ ] [subtask-check] All sub-issues closed
- [ ] [post-merge] {prod-only verification, if any}
```

### Sub-issue

```markdown
## Parent

Sub-issue of #{parent_N} — {parent title}

## Task

{3–5 sentence description of exactly what to implement.}

## Files to create/modify

- `{path}` — {what to do}

## Technical details

- {implementation approach}
- {existing patterns to follow — reference real files}

## Dependencies

- Depends on #{N} — {why}, or: No blockers — can start immediately

## Acceptance Criteria

- [ ] {specific, testable criterion}
- [ ] All existing tests still pass
```

### Contract issue

```markdown
## Contract Definition

**Type:** {API spec / data schema / event format / interface}

**Context:**
Shared by these features: {list with brief descriptions}

**Must define:**
- {specific thing}
- {validation rules, error formats, versioning}

## Acceptance Criteria

- [ ] Contract documented in {location}
- [ ] Contract reviewed and approved
- [ ] Versioning strategy included
- [ ] Example request/response provided

**Blocks:** #{dependent_N}, #{dependent_N}. Do not begin dependent work until this is merged.
```

### Bug issue

```markdown
## Summary

{One sentence: what's broken.}

## Steps to reproduce

1. {step}
2. {step}

## Expected vs actual

- **Expected:** {what should happen}
- **Actual:** {what does happen}

## Environment

- {version, branch, deploy target, relevant config}

## Acceptance Criteria

- [ ] {bug no longer reproduces under the steps above}
- [ ] Regression test added
```

---

## Acceptance Criteria Format

Use **GIVEN/WHEN/THEN** (BDD) scenarios for any issue with testable behavior. One scenario per behavior — no compound WHEN.

```
### Scenario: {short descriptive title}

**GIVEN** {existing system state or precondition}
**WHEN**  {single action taken by user or system}
**THEN**  {directly observable outcome}
[AND     {additional outcome, if needed}]
```

Rules:
- **GIVEN** describes what is already true — not what the user does.
- **WHEN** is a single action: API call, button click, scheduled job, submission.
- **THEN** is directly observable: response body, DB change, UI state, event.
- Use the issue's own domain language. Don't invent terminology.
- Include negative/error scenarios (invalid input, unauthorized, missing data).
- If a requirement is ambiguous, write the most reasonable interpretation and add `> **Note:**` flagging it.

For detailed guidance and optional data enrichment, see the `/gwt` skill.

---

## Test Criteria Tags

Each checkbox in **Test Criteria** must be tagged with how it gets verified:

| Tag | Meaning |
|-----|---------|
| `[ai-verify]` | AI tests live against the dev API |
| `[local-test]` | Runnable locally (lint, tests, build, type-check) |
| `[ci-check]` | Verify CI/CD passed |
| `[subtask-check]` | All sub-issues and blockers completed |
| `[human-verify]` | Requires human judgment (visual, UX, feel) |
| `[human-assist]` | AI sets up environment, human spot-checks |
| `[post-merge]` | Only verifiable after merge (prod health, DNS, Flux) |

---

## Labels

Every issue gets a **type** label and (for feature/bug/enhancement) a **priority** label. Sub-issues inherit priority from their parent.

### Type (applied via `label_issue`)

The `mcp__gitea-workflow__label_issue` tool only accepts these three values for `type_label`:

| Label | When |
|-------|------|
| `bug` | Broken behavior, security vulnerability, correctness problem |
| `enhancement` | Improvement to existing functionality |
| `feature` | New capability |

### Priority

| Label | When |
|-------|------|
| `priority: high` | Blocks users or other work, service down, data at risk |
| `priority: medium` | Degraded functionality, normal queue |
| `priority: low` | Cosmetic, nice-to-have |

### Tier markers (informational)

`contract` and `sub-issue` are **not** part of the `label_issue` taxonomy — `label_issue` will reject them. Apply them via the generic `mcp__gitea__issue_write` (`add_labels`) if the repo defines them. The tier is also obvious from the title prefix (`contract:` / `sub:`), so these labels are mainly an aid for filtering in the Gitea UI.

| Label | When |
|-------|------|
| `contract` | Cross-cutting interface definition |
| `sub-issue` | AI-sized implementation task |

### Sub-issue subtype (optional, repo-specific)

If your repo defines these labels, pair `sub-issue` with one of: `implementation`, `test`, `config`, `docs`. Apply via `add_labels`. Skip if the repo doesn't have them — these are not part of the standard label taxonomy.

### Status (lifecycle)

Applied and swapped automatically by the workflow skills. Don't set manually unless the skill isn't running.

| Label | Meaning |
|-------|---------|
| `status: backlog` | Not yet started |
| `status: in-progress` | Actively being worked on |
| `status: ready-to-test` | Fix pushed, awaiting QA |
| `status: in-review` | PR open, awaiting review/merge |
| `status: done` | Completed |

### Blocking

| Label | Meaning |
|-------|---------|
| `decision-needed` | A human decision is required before implementation can proceed. The issue comments contain the open question. Agents must not implement without the decision being resolved first. |

When an agent encounters an issue with `decision-needed`, it must surface the open question to the user before any implementation work — see [status-labels.md](./status-labels.md) for per-skill behavior (`/do-issue`, `/triage-issues`, `/do-the-thing`).

Use `mcp__gitea-workflow__label_issue` and `set_issue_status` — they handle label ID lookups and swap existing `status:` labels automatically.

---

## Dependencies

- State dependencies in the **Dependencies** section of the body, using `#{N}` references.
- For hard blockers (contracts), write `BLOCKED BY #{N}` in caps in the Dependencies section.
- For soft dependencies ("should be done after"), say so explicitly.
- When breaking down an existing issue into sub-issues, add a comment on the parent listing all sub-issues and parallel-work opportunities.

---

## Vertical Slicing Rules

Feature issues must be vertically sliced:

- Each feature delivers a user-visible change.
- A user can see or use something new when it's done.
- No "set up database" or "create models" at the feature tier — those are sub-issues.
- Frame from the user's perspective.

Sub-issues must be:

- 1–3 files maximum
- 30–60 minutes of focused work
- Independently testable
- Parallel-safe (two agents working on different sub-issues don't conflict)

---

## Checklist Before Creating

- [ ] Title uses the correct prefix (`feat:`, `fix:`, `sub:`, `contract:`, `enhance:`)
- [ ] Body follows the tier's template
- [ ] Acceptance Criteria uses GIVEN/WHEN/THEN where behavior is testable
- [ ] Test Criteria checkboxes are tagged (`[ai-verify]`, `[local-test]`, etc.)
- [ ] Type label + priority label applied (priority omitted for sub-issues)
- [ ] Dependencies stated with `#{N}` references
- [ ] Assigned to a milestone if the repo uses them
