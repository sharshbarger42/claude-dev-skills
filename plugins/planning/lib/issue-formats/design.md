## Summary

{One-line description of what's being designed / investigated. Question being answered or artifact being produced.}

## Goal

{What decision this issue will produce, or what artifact. 2-3 sentences. Be clear about the deliverable — this is not shipped code, it's a decision/doc/prototype.}

## Context

{Why this design work is needed now. What downstream features/issues depend on the outcome. Constraints from stakeholders, business, existing architecture, or tech stack.}

## Options under consideration

- **Option A: {name}** — {one-line description} — {pros/cons headline}
- **Option B: {name}** — {one-line description} — {pros/cons headline}
- **Option C: {name}** — {one-line description} — {pros/cons headline}

{If still being discovered, note: "Options to be enumerated during the investigation."}

## Decision criteria

How the options will be evaluated. Prioritized.

1. {criterion — e.g., operational cost at current scale}
2. {criterion — e.g., developer ergonomics}
3. {criterion — e.g., future-proofing for scale X}

## Deliverable

**Location:** {where the artifact will live — e.g., `docs/design/vector-db-selection.md`, an ADR file, a comment on this issue, a linked Google Doc URL}
**Format:** {RFC / ADR / prototype code + report / inline decision comment / diagram}
**Timebox:** {optional — if this is a spike with a fixed investigation budget}

## Downstream impact

- Blocks: #{N} {title}, #{N} {title}
- Produces contract: {if the design will result in a contract issue being created}
- No downstream blocking: {if exploratory only}

## Dependencies

{Any contract/issue dependencies, or:}
- No shared contracts involved — this is self-contained investigation.

## Acceptance Criteria

Concrete, verifiable checklist of what the design deliverable must contain. No GWT — this produces a decision artifact, not user-interaction code.

### Decision
- [ ] Chosen option stated clearly in {Deliverable location}
- [ ] Reasoning references each item in Decision criteria
- [ ] Rejected options listed with reasons they were not chosen

### Evaluation
- [ ] Each option evaluated against every criterion (no criteria skipped)
- [ ] Trade-offs made explicit

### Downstream
- [ ] Each blocked issue notified / unblocked
- [ ] Follow-up work surfaced (e.g., "produces contract #N", "spawns feature #N")

## Test Criteria

- [ ] [human-verify] Deliverable exists at the stated location and records the decision with reasoning
- [ ] [human-verify] Rejected options are enumerated with rationale
- [ ] [subtask-check] Any sub-issues (e.g., prototype work, benchmark scripts) are closed
- [ ] [post-merge] Downstream blocked issues have been notified / unblocked

**Label guide:**
- `[ai-verify]` — AI tests this live against the dev API
- `[local-test]` — runnable locally (lint, tests, build, type-check)
- `[ci-check]` — verify CI/CD passed
- `[subtask-check]` — all sub-issues and blockers completed
- `[human-verify]` — requires human judgment (visual, UX, feel)
- `[human-assist]` — AI sets up environment, human spot-checks
- `[post-merge]` — can only be verified after merge to main (prod checks)
