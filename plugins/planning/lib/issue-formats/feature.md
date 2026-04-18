## Description

{What the user can do after this feature is implemented — 2-3 sentences from their perspective. User-visible outcome, not technical description.}

## Context

{Relevant architecture decisions, tech stack details, design notes, and background. Why this feature matters.}

## Scope

**In scope:**
- {specific deliverable}
- {specific deliverable}

**Out of scope:**
- {what this does NOT include}

## Technical notes

- {relevant architecture decision — reference real files/patterns in the repo}
- {library/framework to use and why}
- {data model or API endpoint involved}

## Dependencies

{If blocked by a contract:}
- **BLOCKED BY** #{contract_issue_number} — `contract: {name}`. Do not begin work until the contract is merged. Follow the contract exactly; if unclear, stop and escalate.

{If depends on another feature/issue:}
- Depends on #{issue_number} — {why}

{If no external dependencies:}
- No shared contracts involved — this is self-contained.

## Acceptance Criteria

Written in GIVEN / WHEN / THEN form. Each scenario tests exactly one behavior.

### Scenario: {short descriptive title}

**GIVEN** {existing system state or precondition}
**WHEN**  {single action taken by user or system}
**THEN**  {directly observable outcome}
**AND**   {additional outcome if needed}

### Scenario: {negative/error case}

**GIVEN** {precondition}
**WHEN**  {invalid action}
**THEN**  {expected error behavior}

## Test Criteria

- [ ] [ai-verify] {testable criterion from user perspective — verifiable via API on dev}
- [ ] [local-test] Lint and type-check pass
- [ ] [local-test] Unit/integration tests pass
- [ ] [ci-check] CI pipeline passes
- [ ] [subtask-check] All sub-issues are closed (or N/A if no subtasks needed)
- [ ] [post-merge] {any prod-only verification}

**Label guide:**
- `[ai-verify]` — AI tests this live against the dev API
- `[local-test]` — runnable locally (lint, tests, build, type-check)
- `[ci-check]` — verify CI/CD passed
- `[subtask-check]` — all sub-issues and blockers completed
- `[human-verify]` — requires human judgment (visual, UX, feel)
- `[human-assist]` — AI sets up environment, human spot-checks
- `[post-merge]` — can only be verified after merge to main (prod checks)
