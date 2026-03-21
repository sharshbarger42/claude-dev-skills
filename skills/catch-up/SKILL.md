---
name: catch-up
description: Session catch-up briefing. Reviews pending work, active projects, and standalone TODO files to get a new session up to speed.
disable-model-invocation: true
---

# Session Catch-Up

## Current Files

### ACTIVE.md
!`cat /home/selina/gitea-repos/productivity/ACTIVE.md`

### WEEK.md
!`cat /home/selina/gitea-repos/productivity/WEEK.md`

### TODAY.md
!`cat /home/selina/gitea-repos/productivity/TODAY.md`

### CHANGELOG.md (last 20 lines)
!`tail -20 /home/selina/gitea-repos/productivity/CHANGELOG.md`

### Standalone TODO files
!`find /home/selina -maxdepth 1 -name '*TODO*' -o -name '*todo*' | head -10`

!`for f in /home/selina/*TODO*; do [ -f "$f" ] && echo "=== $f ===" && cat "$f" && echo; done 2>/dev/null`

## Instructions

### Step 1: Scan for pending work
- Read ACTIVE.md for all projects with status "In Progress"
- Read WEEK.md for unchecked goals
- Read any standalone TODO files found in the home directory (like RECIPE_REVIEW_TODO.md)
- Check TODAY.md for any carried-over tasks

### Step 2: Check recent activity
- Read CHANGELOG.md to understand what was done recently
- Note what was completed in the last session so you don't repeat it

### Step 3: Present the briefing
Give a concise summary:
1. **Active projects** — list each with its current next step
2. **This week's open goals** — unchecked items from WEEK.md
3. **Pending TODOs** — any standalone TODO files with their key items
4. **Recent work** — last 2-3 changelog entries for context
5. **Suggested focus** — what seems most important to work on next

### Step 4: Ask what to work on
After presenting the briefing, ask the user what they'd like to focus on this session.

Keep it brief and actionable. No fluff.
