## Parent

Sub-issue of #{parent_issue_number} — {parent title}

## Task

{Clear, specific description of exactly what to implement — 3-5 sentences.}

## Code area

One of: `backend` | `frontend` | `data-model` | `api-contract` | `infra/ci` | `tests` | `docs`

**This sub-issue is scoped to a single code area.** If work spans multiple areas, it must be split into multiple sub-issues.

## Files to create/modify

- `{file_path}` — {what to do in this file}
- `{file_path}` — {what to do in this file}

Keep to 1-3 files maximum.

## Technical details

- {specific implementation approach grounded in the existing codebase}
- {library/function to use}
- {existing patterns to follow — reference actual files}

## Contract

Inputs this sub-issue consumes:
- {function signature, HTTP request shape, event payload, DB column read}
- Source: {caller/producer — `consumed from #N` if cross-issue, or "internal"}

Outputs this sub-issue produces:
- {return type, response shape, emitted event, DB write}
- Consumer: {downstream — `produces for #N` if cross-issue, or "internal"}

## Contract compliance

{If parent is blocked by a contract:}
- **MUST follow contract defined in** #{contract_issue_number}
- Specifically implements: {which part of the contract}
- **If the contract doesn't exist yet or seems wrong, STOP WORK and escalate to a human.** Do not guess or create your own interface.

{If parent has no contract:}
- No shared contract — this sub-issue is internal to the parent feature.

## Dependencies

{If must come after another sub-issue:}
- Depends on #{other_sub_issue} — {why, what it provides}

{Otherwise:}
- No blockers — can be started immediately.

## Acceptance Criteria

Concrete, implementation-level checklist. No GWT here — user-interaction behavior lives on the parent feature. Fill in ONLY the subsection matching this sub-issue's **Code area**; delete the others when writing the body.

### If Code area = `backend`
- [ ] Accepts input: {shape, fields, types}
- [ ] Validates: {rules — required, length, format, range}
- [ ] Returns on success: {shape, status code}
- [ ] Returns on error: {each failure mode with its specific error response}
- [ ] Side effects: {DB writes, events emitted, logs, external calls}
- [ ] Idempotency: {if relevant — or "N/A"}

### If Code area = `frontend`
- [ ] Layout: {elements and their positions at each breakpoint}
- [ ] Styling: {design tokens / color refs / typography used}
- [ ] State: {state variables, initial values, transitions}
- [ ] Interactions: {event handlers, disabled states, loading states, empty states}
- [ ] Accessibility: {aria labels, keyboard navigation, focus management, contrast}

### If Code area = `data-model`
- [ ] Schema: {fields with types, nullability, constraints}
- [ ] Indexes: {fields — specify unique vs non-unique}
- [ ] Relationships: {foreign keys and their cascade behavior}
- [ ] Migration: {up migration applies cleanly; down migration reversible}
- [ ] Backfill: {approach for existing rows — or "N/A (new table)"}

### If Code area = `api-contract`
- [ ] Endpoints: {path, HTTP method, auth requirement}
- [ ] Request shape: {fields with types, required vs optional}
- [ ] Response shape: {success body + error body structures}
- [ ] Status codes: {each documented with its trigger condition}
- [ ] Versioning: {how versioned — or "N/A"}

### If Code area = `infra/ci`
- [ ] Env vars added: {list with where they're set}
- [ ] Secrets: {how managed}
- [ ] Workflow triggers: {events}
- [ ] Workflow steps: {ordered list}
- [ ] Success signals: {what exit condition means success}
- [ ] Failure/rollback: {what happens on failure}

### If Code area = `tests`
- [ ] Covers: {specific functions, scenarios, user paths}
- [ ] Fixtures/mocks: {what's used and why}
- [ ] Edge cases: {listed explicitly}
- [ ] Negative cases: {each error/validation branch tested}

### If Code area = `docs`
- [ ] Content added at {file path}
- [ ] Examples included for new features/APIs
- [ ] AGENTS.md updated if conventions changed
- [ ] README updated if user-facing setup changed

## Test Criteria

- [ ] [ai-verify] {specific testable criterion}
- [ ] [local-test] All existing tests still pass
- [ ] [ci-check] CI pipeline passes
