---
name: where-am-i
description: Status summary and top 5 recommended next actions based on active projects, weekly goals, and recent activity.
---

# Where Am I?

## Current State

### ACTIVE.md
!`cat /home/selina/gitea-repos/productivity/ACTIVE.md`

### WEEK.md
!`cat /home/selina/gitea-repos/productivity/WEEK.md`

### TODAY.md
!`cat /home/selina/gitea-repos/productivity/TODAY.md`

### FUTURE.md
!`cat /home/selina/gitea-repos/productivity/FUTURE.md`

### CHANGELOG.md (last 30 lines)
!`tail -30 /home/selina/gitea-repos/productivity/CHANGELOG.md`

### Recent git activity (last 7 days)
!`for repo in /home/selina/gitea-repos/*/; do name=$(basename "$repo"); commits=$(cd "$repo" 2>/dev/null && git log --oneline --since="7 days ago" 2>/dev/null | head -5); [ -n "$commits" ] && echo "=== $name ===" && echo "$commits"; cd - >/dev/null; done`

### Uncommitted work
!`for repo in /home/selina/gitea-repos/*/; do name=$(basename "$repo"); cd "$repo" 2>/dev/null && st=$(git status --porcelain 2>/dev/null) && [ -n "$st" ] && echo "=== $name ===" && echo "$st"; cd - >/dev/null; done`

## Instructions

### Step 1: Build the big picture

Scan all the data above and categorize every active project by momentum:
- **Hot** — worked on in the last 7 days, has clear next step
- **Warm** — has a defined next step but no recent activity
- **Stalled** — no activity, vague next step, or blocked
- **Paused** — explicitly marked paused or exploratory

### Step 2: Status summary

Give a concise overview (3-5 sentences max):
- How many projects are active, what's getting attention, what's been neglected
- Any deadlines, time-sensitive items, or blockers worth flagging
- Overall momentum — are things moving or scattered?

### Step 3: Top 5 recommended actions

Pick the 5 best things to do next. Rank using this priority framework:

1. **Time-sensitive** — deadlines, expiring items, things that get harder if delayed (e.g., taxes)
2. **Finish what's started** — half-done work creates drag. If something is 80% done, finish it.
3. **Unblock downstream work** — tasks that other projects depend on
4. **High-impact, low-effort** — quick wins that unlock progress or clear mental overhead
5. **Strategic investment** — bigger items that move important projects forward meaningfully

For each recommendation, include:
- The specific action (not vague — something you could start doing right now)
- Which project it belongs to
- Why it ranks here (one line)

### Step 4: Present it

Format:

**Status:** {3-5 sentence overview}

**Top 5 Next Actions:**
1. {action} — *{project}* — {why}
2. {action} — *{project}* — {why}
3. {action} — *{project}* — {why}
4. {action} — *{project}* — {why}
5. {action} — *{project}* — {why}

Then ask: "Want to dive into any of these?"

Keep it punchy. No filler.
