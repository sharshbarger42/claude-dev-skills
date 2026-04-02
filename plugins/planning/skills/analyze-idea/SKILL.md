---
name: analyze-idea
description: Critical analysis of a problem/solution idea — validates assumptions, identifies risks, and proposes refined solutions within requirements.
args: "[idea-description]"
---

# Analyze Idea Skill

Perform a rigorous critical analysis of a problem/solution idea. Challenge assumptions, identify risks, and propose alternative solutions that fit within the stated requirements.

**Input:** Optional idea description as the skill argument. If not provided, the skill will gather it interactively.

!`cat ${CLAUDE_PLUGIN_ROOT}/lib/planning-common.md`

## Step 1: Gather information

All information must be collected upfront before analysis begins. Use `AskUserQuestion` for each gap.

### If an argument was provided

Use the argument as the initial idea description. Then ask a single follow-up question to fill in gaps:

Use `AskUserQuestion` with a free-text prompt:

```
I have the initial idea. To do a thorough analysis, I need a few more details.
Please provide (skip any that aren't applicable):

1. **Problem statement** — What specific problem does this solve? Who experiences it?
2. **Current state** — How is this handled today (if at all)?
3. **Requirements / constraints** — Must-haves, budget limits, timeline, tech constraints, team size
4. **Target users** — Who will use this? How technical are they?
5. **Success criteria** — How will you know this worked?
6. **Existing systems** — What does this need to integrate with?
```

### If no argument was provided

Use `AskUserQuestion` to ask:

```
What idea would you like me to analyze? Describe the problem you're trying to solve and any solution you have in mind.

Include as much context as you can:
- The problem and who it affects
- Your proposed solution (if any)
- Requirements and constraints
- What systems it needs to work with
```

After receiving the response, ask the follow-up question above for any gaps.

## Step 2: Confirm scope

Present a brief summary of what you understood:

```
## Understanding Check

**Problem:** {1-2 sentence problem statement}
**Proposed solution:** {1-2 sentence solution summary}
**Key constraints:** {bullet list}
**Target users:** {who}
**Must integrate with:** {systems}

Does this capture it correctly, or should I adjust anything?
```

Use `AskUserQuestion` with options:
- **Correct, proceed with analysis**
- **Needs adjustment** (free text)

If adjustments are needed, incorporate them and re-confirm. Once confirmed, proceed without further interaction.

## Step 3: Critical analysis

Perform a structured analysis. Be honest and direct — the goal is to find weaknesses now, not after implementation.

### 3a: Assumption audit

List every assumption the idea relies on. For each:
- State the assumption explicitly
- Rate confidence: **validated** (evidence exists), **plausible** (reasonable but unverified), **risky** (could easily be wrong)
- For risky assumptions, explain what breaks if the assumption is wrong

### 3b: Problem validation

- Is this a real problem or a perceived one? What evidence exists?
- How severe is the problem? (blocking, painful, annoying, cosmetic)
- How many people/systems are affected?
- Is the problem growing, stable, or shrinking?
- Are there existing solutions the user might not be aware of?

### 3c: Solution critique

Evaluate the proposed solution against:

| Criterion | Assessment |
|-----------|-----------|
| **Solves the stated problem** | Does it actually address the root cause? |
| **Proportional effort** | Is the solution proportional to the problem's severity? |
| **Complexity** | How complex is the build vs. the ongoing maintenance? |
| **Failure modes** | What happens when this breaks? |
| **Security surface** | Does this introduce new attack vectors? |
| **Operational burden** | Who maintains this? What monitoring is needed? |
| **Reversibility** | How hard is it to undo this if it doesn't work? |

### 3d: Risk register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| {risk description} | Low/Med/High | Low/Med/High | {what to do about it} |

Include at least: technical risks, integration risks, scope creep risks, and operational risks.

## Step 4: Alternative solutions

Propose 2-4 alternative approaches that still meet the stated requirements. For each:

### Alternative {N}: {Name}

**Approach:** {2-3 sentence description}

**How it meets requirements:**
- {requirement} → {how this alternative addresses it}

**Advantages over original:**
- {advantage}

**Disadvantages vs original:**
- {disadvantage}

**Effort estimate:** {relative: smaller/similar/larger than the original}

**Best if:** {when this alternative makes more sense than the original}

Alternatives should range from simpler (could you solve this with a script?) to more robust (what if you built for scale from the start?). At least one alternative should be dramatically simpler than the original.

## Step 5: Recommendation

Provide a clear recommendation:

```
## Recommendation

**Recommended approach:** {Original / Alternative N}

**Why:** {2-3 sentences — the key deciding factors}

**Key risks to watch:**
1. {most important risk and its mitigation}
2. {second most important risk}

**Before proceeding, validate:**
- {risky assumption that should be tested first}
- {integration point that should be verified}

**Estimated scope:** {Small (days) / Medium (1-2 weeks) / Large (weeks+)}
```

## Step 6: Save and report

Save the analysis to the plans directory:

```bash
PLAN_DIR="$PLANS_DIR/$(date +%Y-%m-%d)-$PLAN_SLUG"
mkdir -p "$PLAN_DIR"
```

Write the full analysis to `$PLAN_DIR/analysis.md` with this structure:

```markdown
# Idea Analysis: {Project Name}

**Date:** {date}
**Status:** Analysis complete

## Problem
{problem statement}

## Proposed Solution
{solution summary}

## Requirements & Constraints
{bullet list}

## Critical Analysis
{sections 3a-3d from above}

## Alternative Solutions
{section 4}

## Recommendation
{section 5}
```

Report to the user:

```
## Analysis Complete

**Saved to:** {plan_dir}/analysis.md

**Recommendation:** {recommended approach — 1 sentence}
**Key risk:** {top risk — 1 sentence}
**Scope:** {estimated scope}

To proceed with detailed planning, run:
> `/plan-project {plan_dir}`
```
