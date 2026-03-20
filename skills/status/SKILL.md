---
name: status
description: Summarize what's been going on based on SESSION.md files, git activity, and Claude memory. Use when the user says "what am I doing", "where was I", "what's my status", "catch me up", or "what have I been working on".
allowed-tools: Read, Glob, Grep, Bash
---

# What Am I Doing?

Piece together the user's current state from SESSION.md files, git history, Gitea activity, and Claude memory, then suggest what to do next.

---

## Step 1: Find SESSION.md Files

Search for session files across repos:

```bash
find ~/gitea-repos -maxdepth 2 -name "SESSION-*.md" -type f 2>/dev/null
find ~/repos -maxdepth 2 -name "SESSION-*.md" -type f 2>/dev/null
```

Also check for a SESSION.md (legacy) or SESSION-*.md in the current directory.

For each session file found:
1. Read it — it contains active task context (issue, goal, plan, work done)
2. Note which repo it's in
3. Check the git status and recent activity:
   ```bash
   git -C <repo_path> log --oneline -5 --since="midnight"
   git -C <repo_path> status --short
   git -C <repo_path> branch --show-current
   ```

---

## Step 2: Check Recent Git Activity

For repos under `~/gitea-repos/` that do NOT have a session file but have today's commits:

```bash
for repo in ~/gitea-repos/*/; do
    today_commits=$(git -C "$repo" log --oneline --since="midnight" 2>/dev/null | head -5)
    if [[ -n "$today_commits" ]]; then
        echo "=== $(basename "$repo") ==="
        echo "$today_commits"
    fi
done
```

This catches work in repos where the session file was already cleared.

---

## Step 3: Check Claude Memory

Read any memory files that exist:

```bash
find ~/.claude/projects -name "MEMORY.md" -type f 2>/dev/null | head -5
```

For each MEMORY.md found, read it to see what recent context was saved. This may contain notes about in-progress work, decisions made, or things to follow up on.

Also check for an AGENTS.md at home level (`~/AGENTS.md`) which may have workspace-level context.

---

## Step 4: Build the Picture

Synthesize everything into a clear status report:

```
## Status — [today's date]

### Active Sessions
[For each session file found:]
- **[repo]** — [issue/goal from SESSION.md]
  - Branch: [current branch]
  - Status: [uncommitted changes / clean / N commits today]
  - Last commit: [most recent commit message]

### Today's Git Activity
[Repos with today's commits but no active session:]
- **[repo]** — [N] commits today, last: "[message]"

### Recent Memory Notes
[From Claude memory files, if relevant:]
- [key context or decisions noted]

[If nothing found anywhere: "No tracked activity found. Start with `/start` or `/do-the-thing` to pick up work."]
```

---

## Step 5: Suggest Follow-Up Actions

Based on the picture, suggest 3-5 concrete next actions. Prioritize by:

1. **Resume interrupted work** — if there's a session file with uncommitted changes, suggest resuming that task first
2. **Commit and push** — if a repo has uncommitted changes from today's work, suggest committing
3. **Open PRs needing attention** — if Gitea MCP is available, check for open PRs by the user that need review or have comments
4. **Pick next task** — if no active session, suggest running `/do-the-thing` or `/do-issue` to pick up work
5. **Triage** — if there are unassigned issues, suggest running `/triage-issues`

Present as a numbered list:

```
### Suggested Next Actions

1. **Resume work in [repo]** — you have uncommitted changes on branch `feat/...`
2. **Commit and push [repo]** — clean working tree but unpushed commits
3. **Check PR #[N] in [repo]** — has new review comments
4. **Run `/do-the-thing [repo]`** — no active session, pick your next task
```

---

## Rules

- **Read-only.** This skill only reads files and git state. It never modifies files, commits, pushes, or posts to external services.
- **Don't print secrets.** If any files contain credentials, do not include them in output.
- **Be concise.** The user wants a quick catch-up, not a novel. Use bullet points and short descriptions.
- **Handle missing data gracefully.** If no session files exist and no git activity today, say so and suggest starting fresh.
- **Respect time boundaries.** Only report on today's activity unless a session file has older context that's still relevant (check file modification time).
