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

### Step 2b: Check for active sessions

Search for session files across repos:

```bash
find ~/gitea-repos -maxdepth 2 -name "SESSION-*.md" -type f 2>/dev/null
```

If session files are found:

1. Read each one
2. Derive your own agent ID: `AGENT_ID="$(echo "${CLAUDE_SESSION_ID:-unknown}" | cut -c1-8)"`
3. If **multiple session files** exist, present a summary of each and ask which one is yours:
   ```
   Found active sessions:

   1. **{repo}/SESSION-{id1}.md** — {skill}: #{index} {title} (step: {step}, updated: {timestamp})
   2. **{repo}/SESSION-{id2}.md** — {skill}: #{index} {title} (step: {step}, updated: {timestamp})
   ```
   Use `AskUserQuestion` with each session as an option plus a "None — starting fresh" option.
4. If **one session file** exists, present it and ask if the user wants to resume:
   ```
   Found a previous session:
   - **Skill:** {skill}
   - **Repo:** {repo}
   - **Issue/PR:** #{index} — {title}
   - **Last step:** {step}
   - **Updated:** {timestamp}

   {summary from "What we're doing" section}
   ```
   Use `AskUserQuestion`: **Resume this work** or **Start fresh** (clears the session file).
5. If **no session files** found, skip silently.

If the user picks a session, include its full content in your context so you can reference decisions and progress throughout the conversation.

If the user says "start fresh", delete the session file(s) that were presented.

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
