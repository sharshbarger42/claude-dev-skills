---
name: start
description: "Full workspace orientation with memory and rule acknowledgment. Optionally takes a repo name to also read that repo's AGENTS.md."
args: "[repo]"
disable-model-invocation: true
---

# Start

## Instructions

### Step 1: Read the workspace guide

Read `~/AGENTS.md` — this is the source of truth for:
- Directory layout (which repos exist and where)
- MCP servers and their purpose
- SSH access patterns
- Security rules and constraints

If `~/AGENTS.md` does not exist, fall back to `AGENTS.md` in the current working directory.

If the ARGUMENTS specify a repo name, also read that repo's
`AGENTS.md` (e.g. `~/gitea-repos/<repo>/AGENTS.md`).

### Step 2: Read memory

Read `~/.claude/projects/-home-selina/memory/MEMORY.md` — this
contains lessons from previous sessions, gotchas, and the
post-compaction checklist.

### Step 3: Register rules and acknowledge

In your response, explicitly list:

1. **Files read** — which files you read in steps 1-2 (and the repo
AGENTS.md if applicable)
2. **Rules registered** — list each rule by number/name with a
one-line summary:
   - Rule 1: No deletions without explicit permission
   - Rule 2: Read `docs/security.md` before infrastructure work;
dangerous commands need approval
   - Rule 3: No Claude/AI references in commits, code, or PRs
   - Rule 4: No direct pushes to main; all work via PRs
(`feature/{ticket}-short-description`)
   - Security Posture: Never extract or expose credentials
3. **Post-compaction plan** — state: "If context gets compacted
mid-session, I will re-read AGENTS.md and MEMORY.md, confirm the
rules still apply, and tell you I remember them before continuing
work."

Then ask what the user wants to work on.
