# Session State

Persist conversational context across crashes and context compactions. Include this lib in any long-running skill so the user can resume naturally if interrupted.

## How it works

A `SESSION-{agent_id}.md` file is written to the **target repo root** (where the work is happening). It captures what skill is running, what we're working on, key decisions, and the current approach. Multiple agents can each have their own session file in the same repo.

The file is **overwritten** on each update — it represents current state, not a log.

## Derive session file path

```bash
AGENT_ID="$(echo "${CLAUDE_SESSION_ID:-$(head -c 4 /dev/urandom | xxd -p)}" | cut -c1-8)"
SESSION_FILE="${REPO_LOCAL_PATH}/SESSION-${AGENT_ID}.md"
```

Where `REPO_LOCAL_PATH` is the local checkout path of the repo being worked on (from the shorthand table in `config/repos.md`).

## Session Write

Call this at skill start and after each major milestone (step transitions, user decisions, approach confirmations). Overwrite the entire file each time.

**Write the file** using the Write tool with this format:

```markdown
# Active Session

**Skill:** {skill_name} (e.g., do-issue, fix-pr, merge-prs)
**Repo:** {owner}/{repo}
**Issue/PR:** #{index} — {title}
**Branch:** {branch_name}
**Step:** {current_step} — {step_description}
**Updated:** {ISO timestamp}

## What we're doing

{2-3 sentence summary of the current task and approach}

## Key decisions

- {decision 1 — e.g., "User chose to deprecate install.sh instead of fixing it"}
- {decision 2 — e.g., "Using squash merge for this PR"}
- {decision 3}

## Context

{Any important context that would be lost on compaction — user preferences expressed during this session, approach details, things the user said like "do it the same way as last time" with what "last time" means}

## Progress

- [x] {completed step}
- [x] {completed step}
- [ ] {current step} <-- current
- [ ] {remaining step}
- [ ] {remaining step}
```

**Important:**
- Keep it concise — this is a recovery aid, not documentation
- Focus on capturing **why** decisions were made, not just what
- Include user quotes when they express preferences (e.g., "user said: always use rebase for single-commit PRs")
- Update the progress checklist as steps complete

## Session Read

Call this at skill start (before Step 1 work begins) to check for an existing session file.

1. Check if `SESSION-{AGENT_ID}.md` exists in the repo root
2. If it exists, read it and present the context to the user:
   ```
   Found a previous session file in {repo}:
   - **Skill:** {skill_name}
   - **Issue/PR:** #{index} — {title}
   - **Last step:** {step} — {description}
   - **Updated:** {timestamp}

   {summary from "What we're doing" section}
   ```
3. This is informational — the skill should use this context to inform its work but still follow its normal flow

## Session Clear

Call this when the user invokes `/clear`, or when a skill completes its full flow successfully (final report posted).

Delete the session file:
```bash
rm -f "${SESSION_FILE}"
```

## Git safety

Session files must NEVER be committed. The `session_write` procedure must ensure the target repo's `.gitignore` includes `SESSION-*.md`:

1. Check if `.gitignore` exists in the repo root
2. If it exists, check if it already contains `SESSION-*.md`
3. If not, append `SESSION-*.md` to the `.gitignore` (do NOT commit this change — leave it as an unstaged modification, or if `.gitignore` is already tracked, add the line and note it for the user)
4. If `.gitignore` doesn't exist, create it with just `SESSION-*.md`

This is a one-time safety net per repo. Once the gitignore entry exists, skip this check.

## Which skills should include this

Add `!cat $HOME/.claude/development-skills/lib/session-state.md` to:
- `do-issue` — long-running, multi-step implementation
- `do-the-thing` — the longest skill, orchestrates multiple sub-skills
- `fix-pr` — multi-step PR fixes
- `merge-prs` — polling and deployment monitoring

These skills should:
1. Call **Session Read** at the very start to check for prior context
2. Call **Session Write** after each major step transition
3. Call **Session Clear** at the end of a successful run
