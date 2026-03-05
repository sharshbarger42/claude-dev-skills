---
name: start-quick
description: "Quick workspace orientation. Reads AGENTS.md and acknowledges readiness. Optionally takes a repo name to also read that repo's key docs."
args: "[repo]"
disable-model-invocation: true
---

# Quick Start

## Instructions

### Step 1: Read the workspace guide

Read `~/AGENTS.md` — this is the source of truth for:
- Directory layout (which repos exist and where)
- MCP servers and their purpose
- SSH access patterns
- Security rules and constraints

If `~/AGENTS.md` does not exist, fall back to `AGENTS.md` in the current working directory.

Do NOT summarize the whole file — just internalize it.

### Step 2: Repo orientation (if repo argument provided)

If a repo name was provided as `$ARGUMENTS`, orient yourself on that repo:

1. **Resolve the repo path** using the shorthand table in `~/gitea-repos/development-skills/config/repos.md`. If the name matches a known shorthand, use that local path. Otherwise try `~/gitea-repos/<repo>/`.

2. **Read the repo's AGENTS.md** (at `<repo-path>/AGENTS.md`). This has repo-specific rules, architecture, and conventions. Internalize it — don't summarize it back.

3. **Read key status files** if they exist — check for and read any of these:
   - `ACTIVE.md` — current work in progress
   - `TODAY.md` — daily tasks
   - `WEEK.md` — weekly tasks
   - `CHANGELOG.md` — recent changes
   - `README.md` — project overview (if no AGENTS.md found)

4. **Check git status** — run `git status` and `git log --oneline -5` in the repo to see current branch, uncommitted changes, and recent commits.

Skip this step entirely if no repo argument was provided.

### Step 3: Acknowledge

Briefly confirm you've read AGENTS.md and are ready. If a repo was specified, also confirm you've oriented on that repo with a one-line summary of its current state. Then ask what the user wants to work on.
