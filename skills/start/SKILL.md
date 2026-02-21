---
name: start
description: Workspace orientation. Discover repos, skills, MCP servers, and service health. Run this at the start of a session to understand what's available.
disable-model-invocation: true
---

# Workspace Orientation

## Instructions

### Step 1: Read the workspace guide

Read `~/AGENTS.md` — this is the source of truth for:
- Directory layout (which repos exist and where)
- MCP servers and their purpose
- SSH access patterns
- Security rules and constraints

Do NOT summarize the whole file — just internalize it.

### Step 2: Discover available skills

List all skills with a one-line description:
!`for d in $HOME/.claude/skills/*/; do name=$(basename "$d"); desc=$(grep '^description:' "$d/SKILL.md" 2>/dev/null | sed 's/description: //'); echo "/$name — $desc"; done`

### Step 3: Check repo states

Quick git status of active repos — are there uncommitted changes or unpushed commits?
!`for repo in $HOME/gitea-repos/*/; do name=$(basename "$repo"); cd "$repo" 2>/dev/null && st=$(git status --porcelain 2>/dev/null | head -3) && ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "?") && echo "$name: ${st:-clean} (${ahead} ahead)" && cd ->/dev/null; done`

### Step 4: Check service health

!`systemctl --user is-active recipe-readiness.timer 2>/dev/null && echo "recipe-readiness timer: active" || echo "recipe-readiness timer: NOT running"`
!`python3 -c "import json; from datetime import datetime, timezone; d=json.load(open('$HOME/.local/share/recipe-readiness/readiness.json')); age=int((datetime.now(timezone.utc)-datetime.strptime(d['generated_at'],'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)).total_seconds()/60); print(f'readiness.json: {len(d[\"recipes\"])} recipes, {age}min old')" 2>/dev/null || echo "readiness.json: not available"`

### Step 5: Present orientation

Give a concise summary:
1. **Repos** — list each with status (clean/dirty/ahead)
2. **Skills** — list available slash commands
3. **MCP servers** — which are configured (from AGENTS.md)
4. **Services** — recipe-readiness timer health
5. **Anything needing attention** — dirty repos, stale data, services down

If any repos are dirty (uncommitted changes, untracked files, or unpushed commits), ask the user if they'd like to clean them up before moving on — e.g. commit and push, stash, or discard. List the dirty repos and what's pending in each.

Then ask what the user wants to work on.

Keep it brief. This is orientation, not a task briefing — use `/catch-up` or `/morning` for that.
