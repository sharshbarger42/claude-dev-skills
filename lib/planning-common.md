# Planning Common Library

Shared logic for planning skills. Include via `!cat $HOME/gitea-repos/development-skills/lib/planning-common.md`.

## Plan storage

Plans are stored as markdown files in a local directory. The default location is `~/plans/`.

```bash
PLANS_DIR="$HOME/plans"
mkdir -p "$PLANS_DIR"
```

Each plan gets its own directory named with a date prefix and slug:
```
~/plans/2026-03-17-recipe-sync-service/
├── analysis.md       # Output of analyze-idea
├── plan.md           # Output of plan-project
└── issues-created.md # Output of create-issues (log of what was created)
```

## Plan directory naming

Generate the plan directory name from the project name:

```
PLAN_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
PLAN_DIR="$PLANS_DIR/$(date +%Y-%m-%d)-$PLAN_SLUG"
mkdir -p "$PLAN_DIR"
```

## Repo creation (optional)

When a planning skill offers to create a Gitea repo, follow these rules:

1. **Always confirm with the user** — never auto-create without explicit approval
2. Present the proposed repo name, owner, and visibility
3. After creation, add the repo to `config/repos.md` in development-skills
4. Initialize with README, .gitignore, and AGENTS.md

### Pros of auto repo creation
- Seamless flow from plan to execution
- Consistent repo setup (README, CI templates, labels, AGENTS.md)
- Milestones and issues can be created immediately in the same flow
- No manual steps between planning and execution

### Cons of auto repo creation
- Repo names are hard to undo — wrong name means delete and recreate
- Risk of accidental creation if skill is run casually or with bad input
- Separation of concerns — planning and provisioning are different responsibilities
- Could clutter the Gitea org with abandoned project repos

### Recommendation
Offer repo creation as an **opt-in step** with safeguards:
- Show the full repo config before creating
- Require explicit confirmation
- Default to NOT creating (user must say yes)
- If the user declines, the plan is still valid — issues can be created later manually or in an existing repo

## Information gathering pattern

All planning skills follow the same upfront-gathering pattern:

1. **Collect all inputs** — ask all questions at the start, before doing any work
2. **Confirm understanding** — present a summary of what was gathered and get user approval
3. **Execute autonomously** — do the full job without further human interaction
4. **Report results** — present a structured summary at the end

Use `AskUserQuestion` for gathering. Bundle related questions into a single prompt where possible to minimize back-and-forth. Use multiple-choice options with an "Other" escape hatch for open-ended input.
