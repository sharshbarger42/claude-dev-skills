---
name: clear
description: Clear the active session file when you're done with current work and moving on to something new.
allowed-tools: Bash, Read, Glob
---

# Clear Session

Wipe the active session file for the current agent. Use this when you're done with a task and moving on to something new.

## Step 1: Find session files

Search for session files across repos:

```bash
find ~/gitea-repos -maxdepth 2 -name "SESSION-*.md" -type f 2>/dev/null
```

Also check the current directory.

## Step 2: Identify which file is ours

Derive the agent ID:

```bash
AGENT_ID="$(echo "${CLAUDE_SESSION_ID:-unknown}" | cut -c1-8)"
```

Look for `SESSION-${AGENT_ID}.md` in the results. This is our file.

If other session files exist (from other agents), note them but do NOT delete them.

## Step 3: Handle results

### If our session file exists

1. Read it and show a brief summary:
   ```
   Clearing session in {repo}:
   - **Skill:** {skill_name}
   - **Issue/PR:** #{index} — {title}
   - **Last step:** {step}
   ```
2. Delete it: `rm -f {path}`
3. Confirm: `Session cleared. Ready for new work.`

### If our session file does NOT exist but others do

Report:
```
No active session file found for this agent (ID: {agent_id}).

Other active sessions found:
- {repo}/SESSION-{other_id}.md — {brief summary from reading it}

These belong to other agents and were left untouched.
```

### If no session files exist anywhere

Report: `No active sessions found. Already clean.`

## Rules

- Only delete YOUR session file (matching your agent ID)
- Never delete another agent's session file
- Read-only for all other files
