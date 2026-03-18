---
name: plan-the-thing
description: Full planning loop — analyze an idea, create a project plan, and generate Gitea issues. One command from idea to actionable work.
args: "[idea-description]"
---

# Plan The Thing Skill

Full planning pipeline in one command: critically analyze an idea, create a detailed project plan, and generate structured Gitea issues ready for implementation.

**Input:** Optional idea description as the skill argument. If not provided, the first skill in the chain will gather it interactively.

!`cat $HOME/.claude/development-skills/lib/planning-common.md`

## Step 1: Analyze the idea

Invoke the analyze-idea skill:

```
Skill: analyze-idea
Args: {idea_description or empty}
```

This will:
- Gather all context about the problem and proposed solution
- Perform critical analysis (assumptions, risks, alternatives)
- Produce a recommendation
- Save `analysis.md` to the plan directory

**Watch the output for:**
- The plan directory path (`$PLAN_DIR`) — you'll need it for subsequent steps
- The recommended approach — this feeds into the planning phase

Note the plan directory path from the analyze-idea output.

## Step 2: Review analysis with user

After analyze-idea completes, present a checkpoint:

```
## Analysis Phase Complete

**Recommendation:** {recommended approach from analysis}
**Key risk:** {top risk}
**Scope estimate:** {size}
**Plan saved to:** {plan_dir}/analysis.md

Ready to proceed with detailed technical planning, or would you like to adjust the direction first?
```

Use `AskUserQuestion` with options:
- **Proceed to planning** — continue with the recommended approach
- **Adjust direction** — user provides feedback, then re-run analyze-idea with adjustments
- **Stop here** — analysis is enough for now

If the user wants to adjust, incorporate their feedback and re-invoke analyze-idea. If they want to stop, present the plan directory path and exit.

## Step 3: Create the project plan

Invoke the plan-project skill with the plan directory:

```
Skill: plan-project
Args: {plan_dir}
```

This will:
- Read the analysis
- Research technology choices and libraries
- Design architecture, APIs, data models
- Define CI/CD pipeline
- Separate MVP from enhancements
- Save `plan.md` to the plan directory

## Step 4: Review plan with user

After plan-project completes, present a checkpoint:

```
## Planning Phase Complete

**Tech stack:** {key choices}
**MVP features:** {count} features
**Enhancement phases:** {count} phases
**Plan saved to:** {plan_dir}/plan.md

Ready to create Gitea issues from this plan?
```

Use `AskUserQuestion` with options:
- **Create issues** — proceed to issue creation
- **Adjust plan** — user provides feedback, re-run plan-project
- **Stop here** — plan is enough for now

## Step 5: Create Gitea issues

Invoke the create-issues skill:

```
Skill: create-issues
Args: {plan_dir}
```

This will:
- Read the plan
- Ask which repo to target (or create a new one)
- Create milestones, feature issues, and sub-issues
- Set up dependency tracking and contracts
- Save `issues-created.md` to the plan directory

## Step 6: Final report

After all three phases complete, present the full summary:

```
## Planning Complete

**Project:** {name}
**Plan directory:** {plan_dir}/

### Artifacts
| File | Contents |
|------|----------|
| analysis.md | Problem analysis, risk assessment, alternatives |
| plan.md | Tech stack, architecture, MVP/enhancement phases |
| issues-created.md | Issue map and creation log |

### Gitea ({owner}/{repo})
- **Milestones:** {count}
- **Issues:** {total} ({contracts} contracts, {features} features, {sub_issues} sub-issues)

### Ready to implement
> `/do-issue {repo}#{first_ready}` — {title}
> `/do-issue {repo}#{second_ready}` — {title}
> `/do-the-thing {repo}` — let AI triage and pick

### What's next
1. Start with contract issues if any exist (they block other work)
2. Pick feature issues from the MVP milestone
3. Sub-issues within each feature can be parallelized across agents
```
