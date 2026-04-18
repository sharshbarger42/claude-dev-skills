## Summary

{The visual/copy/styling change in one line.}

## Before / After

**Before:** {current state — quote text or describe styling}
**After:** {desired state — quote text or describe styling}

{Screenshot reference if available}

## Scope

**In scope:**
- {specific change — e.g., button copy, spacing on card, color of status pill}

**Out of scope:**
- {logic/behavior changes — this is visual only}

## Files to change

- `{file_path}` — {what to change}

## Dependencies

- No shared contracts involved — this is visual-only and self-contained.

## Acceptance Criteria

Concrete, verifiable checklist of what the visual result must be. No GWT — this is a visual-only change with no logic modification.

### Visual
- [ ] {element} reads "{new text}" (was "{old text}")
- [ ] {element} uses color token `{token}` / hex `{hex}`
- [ ] {element} spacing/size matches {spec/screenshot}

### Responsiveness
- [ ] Renders correctly at {breakpoints}
- [ ] Layout doesn't break at min-width / max-width

### Non-regression
- [ ] No logic change — behavior before/after identical
- [ ] Accessibility not regressed (contrast, tab order, aria labels, keyboard nav)

## Test Criteria

- [ ] [human-verify] Visual change matches the "After" description / screenshot
- [ ] [local-test] Lint passes
- [ ] [local-test] Existing tests still pass (no behavior change)
- [ ] [ci-check] CI pipeline passes
