---
name: plan-project
description: Research and create a detailed project plan — tech stack, architecture, code flow, CI/CD, APIs, MVP vs enhancements.
args: "[plan-dir-or-idea]"
---

# Plan Project Skill

Create a comprehensive, implementation-ready project plan. Research modern standards, evaluate libraries, document architecture decisions, and separate MVP from enhancements.

**Input:** Either a path to an existing plan directory (containing `analysis.md` from `/analyze-idea`), or a free-text idea description to plan from scratch.

!`cat $HOME/gitea-repos/development-skills/lib/planning-common.md`

## Step 1: Gather context

### If a plan directory was provided

Read `analysis.md` from the plan directory to get:
- Problem statement
- Recommended solution approach
- Requirements and constraints
- Key risks and mitigations
- Target users and integrations

Use this as the foundation — no need to re-ask.

Ask one follow-up with `AskUserQuestion`:

```
I've read the analysis. A few more details for the technical plan:

1. **Target deployment environment** — Where will this run? (K3s cluster, standalone VM, Docker, serverless, etc.)
2. **Language/framework preferences** — Any strong preferences or existing team expertise?
3. **Auth requirements** — Does this need auth? SSO integration? API keys?
4. **Data storage needs** — What kind of data? Volume? Relational, document, key-value?
5. **Existing services to integrate** — APIs, databases, message queues already in place?
6. **Team context** — Who will maintain this? Solo dev, small team, AI agents via /do-issue?

Skip any that aren't applicable.
```

### If a free-text idea was provided (no analysis.md)

Use `AskUserQuestion` to gather both the idea context and technical context in one prompt:

```
To create a detailed project plan, I need:

**About the idea:**
1. Problem being solved and for whom
2. Proposed solution approach
3. Must-have requirements and constraints

**Technical context:**
4. Target deployment environment
5. Language/framework preferences
6. Auth and data storage needs
7. Existing services to integrate with
8. Who will maintain this
```

## Step 2: Confirm planning scope

Present the planning scope for confirmation:

```
## Planning Scope

**Project:** {name}
**Problem:** {1-2 sentences}
**Solution approach:** {from analysis or user input}
**Deploy target:** {environment}
**Language/framework:** {preferences}
**Integrations:** {list}

I'll research and document:
- Technology stack with justifications
- Project structure and code architecture
- API design and data models
- CI/CD pipeline
- MVP scope vs enhancement phases
- Libraries to use (avoiding reinventing wheels)
- Common gotchas for this tech stack

Proceed?
```

Use `AskUserQuestion` with options:
- **Yes, proceed**
- **Adjust scope** (free text)

Once confirmed, execute the full plan without further interaction.

## Step 3: Research phase

Use `WebSearch` and `WebFetch` to research:

### 3a: Technology landscape

For each major technology choice (language, framework, database, etc.):
- Search for current best practices and community recommendations (as of the current year)
- Check for recent breaking changes, deprecations, or migrations
- Verify the technology is actively maintained (last release, GitHub activity)
- Look for known issues or gotchas specific to the use case

### 3b: Library evaluation

For each significant capability needed (auth, API framework, ORM, testing, etc.):
- Search for top libraries/packages in the chosen ecosystem
- Compare 2-3 options on: maturity, maintenance, community size, API quality
- Check for compatibility with other chosen technologies
- **Prefer established libraries over custom code** — only build custom when no library fits

Document the evaluation as a decision record:

| Capability | Library | Why | Alternatives considered |
|-----------|---------|-----|----------------------|
| {what} | {chosen} | {reason} | {others and why not} |

### 3c: Gotchas and pitfalls

Search for common mistakes and pitfalls with the chosen stack:
- "{framework} common mistakes"
- "{framework} + {database} gotchas"
- "{deployment target} best practices {year}"

Compile a gotchas list with mitigations.

## Step 4: Architecture design

### 4a: System architecture

Document the high-level system design:

```
## System Architecture

### Components
{diagram description — list each component, its responsibility, and how it communicates with others}

### Data flow
{describe the primary data flows through the system, step by step}

### External integrations
{for each external system: what protocol, what data is exchanged, error handling approach}
```

### 4b: Project structure

Define the directory layout:

```
project-name/
├── src/                    # or appropriate convention for the language
│   ├── {module}/           # {what this module does}
│   └── ...
├── tests/
├── config/
├── ci/                     # CI/CD pipeline definitions
├── docs/
├── Dockerfile / compose.yaml
├── AGENTS.md               # AI agent coding standards
└── README.md
```

Justify structural choices — why this layout over alternatives.

### 4c: Code flow

For each major user-facing operation, document the code flow:

```
### {Operation name} (e.g., "User creates a recipe")

1. {Entry point} receives {input}
2. {Validation layer} checks {what}
3. {Business logic} performs {action}
4. {Data layer} persists {what, where}
5. {Response} returns {what}

Error cases:
- {error scenario} → {handling}
```

### 4d: API design

If the project has APIs, define them:

```
### API Endpoints

| Method | Path | Purpose | Auth | Request | Response |
|--------|------|---------|------|---------|----------|
| POST | /api/v1/{resource} | Create {thing} | {auth type} | {body schema summary} | {response schema summary} |
```

For each endpoint, note any contracts that downstream consumers must follow.

### 4e: Data model

```
### Data Models

{Entity name}
- {field}: {type} — {purpose}
- {field}: {type} — {purpose}
- Relationships: {what relates to what}
- Indexes: {what needs indexing and why}
```

### 4f: CI/CD pipeline

```
### CI/CD

**Pipeline stages:**
1. {stage}: {what it does, what tools}
2. {stage}: {what it does}

**Deployment:**
- Target: {environment}
- Strategy: {rolling, blue-green, recreate}
- Rollback: {how}

**Secrets management:** {approach}
```

## Step 5: MVP vs Enhancements

This is a critical step. Separate features into phases with clear rationale.

### MVP criteria

A feature belongs in MVP if:
- It's required for the core use case to function
- Without it, the project is not usable for its primary purpose
- It addresses a must-have requirement

### Promotion to MVP

A feature should be **promoted from enhancement to MVP** if:
- Skipping it now would require a **significant refactor** later (e.g., adding multi-tenancy after building single-tenant)
- It's a **security or stability concern** that's much cheaper to build in from the start (e.g., rate limiting, input validation, auth)
- It's an **architectural decision** that's hard to change later (e.g., database schema design, API versioning strategy)
- The incremental effort to include it now is **small compared to retrofitting** later

### Phase structure

```
## Phases

### Phase 1: MVP
**Goal:** {what the user can do after MVP is complete}
**Estimated scope:** {relative size}

Features:
1. {feature} — {why MVP}
2. {feature} — {why MVP}
3. {feature} — **promoted from enhancement** because {reason}

### Phase 2: {Enhancement theme}
**Goal:** {what this adds}
**Depends on:** MVP complete

Features:
1. {feature} — {why deferred}
2. {feature} — {why deferred}

### Phase 3: {Enhancement theme}
...
```

## Step 6: Gotchas and recommendations

```
## Gotchas

| # | Gotcha | Impact | Mitigation |
|---|--------|--------|------------|
| 1 | {specific pitfall for this stack} | {what goes wrong} | {how to avoid it} |

## Recommendations

- {key recommendation for implementation}
- {recommendation about testing approach}
- {recommendation about deployment}
```

## Step 7: Save and report

Write the full plan to `$PLAN_DIR/plan.md`:

```markdown
# Project Plan: {Project Name}

**Date:** {date}
**Status:** Plan complete
**Based on:** analysis.md (if applicable)

## Overview
{2-3 sentence project summary}

## Technology Stack
{section 3a-3b decisions}

## Architecture
{section 4a-4f}

## MVP vs Enhancements
{section 5}

## Library Decisions
{decision table from 3b}

## Gotchas & Recommendations
{section 6}
```

Report to the user:

```
## Plan Complete

**Saved to:** {plan_dir}/plan.md

### Tech Stack
{key technology choices — 3-5 bullets}

### MVP Scope
{number of MVP features, 1-sentence summary}

### Phases
{number of phases, brief description}

### Key Gotchas
{top 2-3 gotchas to watch for}

To create Gitea issues from this plan, run:
> `/create-issues {plan_dir}`
```
