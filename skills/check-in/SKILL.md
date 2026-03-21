---
name: check-in
description: Mid-session status check. Summarizes what's been done today, checks progress against goals, and suggests what to tackle next.
disable-model-invocation: true
---

# Check-In

## Current State

### TODAY.md
!`cat /home/selina/gitea-repos/productivity/TODAY.md`

### WEEK.md
!`cat /home/selina/gitea-repos/productivity/WEEK.md`

### Today's git activity
!`for repo in /home/selina/gitea-repos/*/; do name=$(basename "$repo"); commits=$(cd "$repo" 2>/dev/null && git log --oneline --since="midnight" 2>/dev/null); [ -n "$commits" ] && echo "=== $name ===" && echo "$commits"; cd - >/dev/null; done`

### Uncommitted work
!`for repo in /home/selina/gitea-repos/*/; do name=$(basename "$repo"); cd "$repo" 2>/dev/null && st=$(git status --porcelain 2>/dev/null) && [ -n "$st" ] && echo "=== $name ===" && echo "$st"; cd - >/dev/null; done`

## Instructions

### Step 1: What got done

Review today's git commits across all repos. Summarize the work completed — group by theme, not by repo.

### Step 2: Where things stand

- Check TODAY.md tasks — what's checked off vs still open
- Check WEEK.md goals — overall progress for the week
- Note any uncommitted or unpushed work

### Step 3: Suggest next items

Pick 2-3 concrete next steps using this priority order:

1. **Finish in-progress work** — half-done tasks create drag. If something was started today, suggest completing it first.
2. **Unblock others** — if a task is blocking downstream work (e.g., a service needed by a skill), prioritize it.
3. **Time-sensitive items** — deadlines, appointments, expiring ingredients, calendar events approaching.
4. **High-impact items** — things that unlock the most future capability or save the most recurring effort.
5. **Quick wins** — if the user seems low-energy or between big tasks, suggest something completable in <15 minutes.

When suggesting, reference the specific WEEK.md goal or TODO item. Don't invent work that isn't tracked.

### Step 4: Present the check-in

Format:
1. **Done today** — bulleted list of completed work
2. **In progress** — anything started but not finished (uncommitted changes, open tasks)
3. **Suggested next** — 2-3 items with brief rationale

Keep it tight. This is a status check, not a planning session.
