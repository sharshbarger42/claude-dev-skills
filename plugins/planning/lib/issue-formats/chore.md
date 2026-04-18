## Summary

{What's being changed internally and why. No user-visible change.}

## Motivation

{Why this is worth doing — tech debt, maintainability, performance, dependency upgrade, etc.}

## Scope

**In scope:**
- {specific change}

**Out of scope:**
- {what this does NOT touch}

## Technical approach

- {specific files/modules affected}
- {approach to the refactor/upgrade}
- {backward-compatibility plan if any}

## Dependencies

{Any contract/issue dependencies, or:}
- No shared contracts involved — this is self-contained.

## Acceptance Criteria

Concrete, verifiable checklist of what must be true after the refactor/upgrade. No GWT — this is an internal code change with no user-visible behavior.

### Behavior preservation
- [ ] All existing tests pass without modification to assertions
- [ ] No user-visible behavior change (spot-check on {affected area})

### Code changes
- [ ] {specific change} applied to {files}
- [ ] {obsolete code removed / dependency upgraded / API migration applied / etc.}

### Side effects
- [ ] {any intentional side effect documented}
- [ ] No unintended side effects observed

## Test Criteria

- [ ] [local-test] All existing tests still pass
- [ ] [local-test] Lint and type-check pass
- [ ] [ci-check] CI pipeline passes
- [ ] [human-verify] Spot-check no user-visible change
