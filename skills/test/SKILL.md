---
name: test
description: Plan, document, and execute end-to-end tests for a Gitea issue. Reads the issue and codebase, builds a test plan, handles test data setup, and runs tests. Use when the user says "test this issue", "write e2e tests for", "run tests for [issue]", or "verify [issue] works".
argument-hint: [repo#issue]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, AskUserQuestion, mcp__gitea__get_issue_by_index, mcp__gitea__get_issue_comments_by_index, mcp__gitea__get_file_contents
---

# End-to-End Test

Plan, document, and execute end-to-end tests for Gitea issue **$ARGUMENTS**.

---

## Phase 1: Understand the Issue

1. **Resolve and fetch the issue.**

   !`cat $HOME/.claude/development-skills/lib/resolve-repo.md`

   Parse `$ARGUMENTS` using the resolution logic above. Fetch with `mcp__gitea__get_issue_by_index`. Also fetch comments with `mcp__gitea__get_issue_comments_by_index`. Capture:
   - Title, body, acceptance criteria
   - Labels (may indicate affected area)
   - Any linked PRs or related issues mentioned

2. **Find the repo locally.** Check the repo shorthand table for the local path. If it's the current directory, use that. If the repo isn't cloned, tell the user and stop.

3. **Read the codebase** for the affected area:
   - Find relevant entry points (controllers, handlers, CLI commands, main functions)
   - Trace the data flow from input through processing to output/storage
   - Identify any existing tests — look for common patterns: `test/`, `tests/`, `__tests__/`, `*_test.*`, `*.test.*`, `*.spec.*`, `Test*.py`, `test_*.py`

---

## Phase 2: Discover Project Conventions

Detect the project's tech stack and testing setup automatically:

1. **Language and framework detection:**
   - Check for `package.json` (Node.js/TypeScript), `pyproject.toml`/`setup.py`/`requirements.txt` (Python), `go.mod` (Go), `Cargo.toml` (Rust), `*.csproj`/`*.sln` (.NET), `Makefile`, `docker-compose.yml`
   - Read the relevant config to understand dependencies and scripts

2. **Test framework detection:**
   - Node.js: look for jest, vitest, mocha, playwright, cypress in package.json
   - Python: look for pytest, unittest patterns, tox.ini, conftest.py
   - Go: native `go test`, check for testify
   - Rust: native `cargo test`
   - .NET: look for xUnit, NUnit, MSTest references
   - Check for a `Makefile` or `scripts/` with test commands

3. **Config and secrets:**
   - Look for `.env`, `.env.example`, `config/`, `appsettings*.json`, `settings.py`, etc.
   - **SECURITY: Never print secret values.** Report only key names and whether they are set or missing.
   - If required config is missing, tell the user exactly what to add (file path, key name, expected format — not the value).

4. **Check if services need to be running:**
   - Look for docker-compose.yml, Procfile, or similar
   - If the project has a health endpoint, check if it's responding

---

## Phase 3: Build the Test Plan

Create a structured test plan document at `{repo}-{issue_number}-test-plan.md` in the current directory:

```markdown
# {repo}#{issue_number} — Test Plan

> **Issue**: {title}
> **Tech stack**: {detected languages, frameworks, test tools}
> **Generated**: {today's date}
> **Status**: Draft

## Scope

{1-3 sentences describing what this test plan covers}

## Prerequisites

- [ ] {required services running}
- [ ] {required config/secrets set}
- [ ] {test data setup reviewed — see Phase 4}

## Local Tests

{List locally runnable checks discovered in Phase 2. Each gets a `[local-test]` label.}

| Check | Command | Label |
|-------|---------|-------|
| Lint | `{lint command}` | `[local-test]` |
| Type-check | `{type-check command}` | `[local-test]` |
| Unit tests | `{test command}` | `[local-test]` |
| Build | `{build command}` | `[local-test]` |

## Pre-Merge Checks

| Check | Label |
|-------|-------|
| CI pipeline passes | `[ci-check]` |
| All subtasks/blockers closed | `[subtask-check]` |

## Test Steps

### 1. {Test scenario name}
- **Label**: `[ai-verify]` / `[human-verify]` / `[human-assist]`
- **Env**: `local` / `dev` / `prod`
- **Precondition**: {what must be true before this step}
- **Action**: {what to do — API call, CLI command, function call, UI action}
- **Expected Result**: {what should happen}
- **Verification**: {how to confirm — response check, DB query, file check, log output}

### 2. {Next scenario}
...

## Negative / Edge Cases

### N1. {Error scenario}
- **Label**: `[ai-verify]`
- **Action**: {invalid input or error condition}
- **Expected Result**: {appropriate error response or handling}

## Post-Merge Checks

{List any checks that can only be verified after merge to main. Each gets a `[post-merge]` label.}

| Check | How to verify | Label |
|-------|---------------|-------|
| {prod health check} | `{command}` | `[post-merge]` |
| {DNS resolves} | `dig {hostname}` | `[post-merge]` |
| {Flux reconciles} | `kubectl get hr -n {ns}` | `[post-merge]` |

## Cleanup

{How to reverse any test data changes after testing is complete}
```

Present the test plan to the user for review before executing.

Use `AskUserQuestion` to ask:
- **Execute all tests** — Run through every step and report results
- **Execute specific tests** — Let the user choose which steps
- **Just save the plan** — Save without executing

If "Just save the plan", stop here.

---

## Phase 4: Test Data Setup

If tests require specific data to exist:

1. **Search for existing usable data first.** Check fixtures, seed files, factory files, or query existing data if a database is involved.

2. **If data must be created**, write a setup script appropriate for the tech stack:
   - SQL project: `.sql` file with INSERT/UPDATE statements
   - API project: `.sh` file with curl commands
   - Python: pytest fixtures or setup script
   - Node.js: seed script or test fixtures

   The script MUST include:
   - Header comment documenting what tables/files/resources are affected
   - The data operations
   - A cleanup section that reverses all changes
   - Whether changes are reversible and how

3. **Present the script to the user for review** before executing. Show exactly what will be modified, how many records, and how to undo.

4. **Only execute after explicit user approval.**

---

## Phase 5: Execute Tests

For each test step in the plan:

1. **State what you are testing** — print the step name and precondition.

2. **Perform the action:**
   - Use the project's native test runner when possible (`npm test`, `pytest`, `go test`, `cargo test`, etc.)
   - For API tests: use `curl` via Bash
   - For integration tests: run the appropriate command
   - For verification queries: use whatever tool the project provides

3. **Verify the result:**
   - Compare actual vs expected outcome
   - For API responses: check status code, response body structure, key field values
   - For data changes: verify the expected state
   - For side effects: check downstream effects

4. **Record the result** — update the test plan document:
   - **PASS**: result matches expected
   - **FAIL**: result does not match — include actual vs expected
   - **SKIP**: precondition not met or user chose to skip
   - **BLOCKED**: dependency not available

---

## Phase 6: Report Results

After all tests are executed, update the test plan's Status field and append:

```markdown
## Results

**Status**: {N} passed, {N} failed, {N} skipped, {N} blocked, {N} deferred (post-merge)
**Executed**: {date and time}

| Step | Name | Label | Env | Result | Notes |
|------|------|-------|-----|--------|-------|
| L1 | Lint | `[local-test]` | local | PASS | |
| L2 | Unit tests | `[local-test]` | local | PASS | |
| C1 | CI pipeline | `[ci-check]` | ci | PASS | |
| S1 | Subtasks closed | `[subtask-check]` | n/a | PASS | |
| 1 | {name} | `[ai-verify]` | dev | PASS | |
| 2 | {name} | `[ai-verify]` | dev | FAIL | Expected X, got Y |
| N1 | {name} | `[ai-verify]` | dev | PASS | |
| P1 | {name} | `[post-merge]` | prod | DEFERRED | Verify after merge |
```

If any tests failed, summarize failures and suggest next steps.

If test data was created, remind the user about the cleanup script.

---

## Rules

- **Never print secrets.** Connection strings, API keys, passwords, tokens — report only key names and whether they are set.
- **Document everything.** The test plan is the permanent record. It should be complete enough that someone else could re-run the tests.
- **Test data scripts require approval.** Never execute data setup without the user reviewing and approving.
- **Clearly label affected resources.** Every data modification must be documented.
- **Read-only by default.** Only write when the test explicitly requires it, and only after user approval.
- **One step at a time.** Report each step's result as you go so the user can see progress and intervene.
- **Detect, don't assume.** Discover the project's stack from its files rather than assuming any specific language or framework.
