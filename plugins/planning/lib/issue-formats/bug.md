## Summary

{One-line description of the bug from the user's perspective.}

## Reproduction

Steps to reproduce:
1. {step}
2. {step}
3. {observed behavior}

**Expected:** {what should happen}
**Actual:** {what does happen}

## Environment

- {where observed — dev, prod, local}
- {affected version/commit if known}
- {browser/OS/device if relevant}

## Root cause

{Known or suspected root cause. If unknown, write "Unknown — investigation required" and list what's been ruled out.}

## Fix approach

{Planned fix — specific about files/functions to change. If multi-part, list each part.}

## Dependencies

{Any contract/issue dependencies, or:}
- No shared contracts involved — this is self-contained.

## Acceptance Criteria

Concrete, verifiable checklist of what must be true for this bug to be considered fixed. No GWT — this is an implementation-level bug fix, not a user-interaction slice.

### Fix verification
- [ ] Reproduction steps no longer trigger the bug
- [ ] {specific input/state} now produces {correct behavior}
- [ ] {any related failure modes also verified}

### Regression coverage
- [ ] Regression test added at {test file/location}
- [ ] Test fails on the broken code, passes on the fix
- [ ] Test covers the specific failure mode described in Reproduction

### Related paths
- [ ] {nearby edge cases tested, if any}
- [ ] {or: "No nearby edge cases — fix is isolated"}

## Test Criteria

- [ ] [local-test] Regression test added that fails before the fix and passes after
- [ ] [local-test] Existing tests still pass
- [ ] [ai-verify] Bug reproduction steps no longer trigger the bug on dev
- [ ] [ci-check] CI pipeline passes
- [ ] [post-merge] {prod verification if applicable}
