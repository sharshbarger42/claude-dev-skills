---
name: morning
description: Daily morning briefing. Reviews yesterday, sets up today, tracks routine streaks.
disable-model-invocation: true
---

# Morning Briefing

## Current Files

### TODAY.md
!`cat $HOME/gitea-repos/productivity/TODAY.md`

### WEEK.md
!`cat $HOME/gitea-repos/productivity/WEEK.md`

### DAILY_ROUTINE.md
!`cat $HOME/gitea-repos/productivity/DAILY_ROUTINE.md`

### WEEKLY_ROUTINE.md
!`cat $HOME/gitea-repos/productivity/WEEKLY_ROUTINE.md`

### ROUTINES.md
!`cat $HOME/gitea-repos/productivity/ROUTINES.md`

### CHANGELOG.md
!`cat $HOME/gitea-repos/productivity/CHANGELOG.md`

## Instructions

### Step 1: Review yesterday and ask for input
- Read TODAY.md and summarize what was checked off (daily routine + priorities)
- If multiple days have passed since the last TODAY.md date, note all unlogged days
- Present the summary to the user and ask (using AskUserQuestion or conversationally):
  - Did you complete anything else that isn't checked off?
  - Anything to note for those days? (e.g. "sick day", "traveled", etc.)
- **STOP here and wait for the user's response before continuing to Step 2**

### Step 2: Log yesterday's routine
- Using the user's input from Step 1, append rows to ROUTINES.md for any unlogged days
- Mark checkmarks or misses based on TODAY.md checkboxes + whatever the user reported

### Step 3: Refresh TODAY.md
- If TODAY.md has the wrong date, refresh it for today
- Pull daily routine items from DAILY_ROUTINE.md as unchecked checkboxes under ### Daily
- Carry over any uncompleted non-routine tasks from yesterday if still relevant
- Keep the format defined in AGENTS.md

### Step 4: Check Google Calendar
- Use the Google MCP server to check today's calendar events
- List any events with their times
- If no events, note "No calendar events today"

### Step 5: Morning summary
Give a concise briefing:
1. Today's date and day of the week
2. Yesterday's routine recap (what got done, current streaks)
3. Uncompleted weekly goals from WEEK.md
4. Suggested focus for the day
5. Any meals planned for today (check WEEK.md meal plan)
6. Today's calendar events (from Step 3)

Keep it brief. No fluff.
