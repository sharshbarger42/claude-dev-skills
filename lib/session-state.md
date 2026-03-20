# Session State

Persist conversational context across crashes and context compactions. Include this lib in any long-running skill so the user can resume naturally if interrupted.

## How it works

A `SESSION-{agent_id}.md` file is written to the **target repo root** (where the work is happening). It captures what skill is running, what we're working on, key decisions, and the current approach. Multiple agents can each have their own session file in the same repo.

The file is **overwritten** on each update — it represents current state, not a log.

## Derive session file path

```bash
AGENT_ID="$(echo "${CLAUDE_SESSION_ID:-unknown}" | cut -c1-8)"
SESSION_FILE="${REPO_LOCAL_PATH}/SESSION-${AGENT_ID}.md"
```

**Important:** Always use `unknown` as the fallback when `CLAUDE_SESSION_ID` is unset. Never use random values — the same ID must be derived on every invocation so writes and reads target the same file. All files that derive an agent ID (this lib, `/clear`, `/start`) must use this exact same fallback.

Where `REPO_LOCAL_PATH` is the local checkout path of the repo being worked on (from the shorthand table in `config/repos.md`). If the repo is not in the shorthand table, use the current working directory (`pwd`). Never leave `REPO_LOCAL_PATH` empty — validate it before writing.

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

Session files must NEVER be committed. Before the **first Session Write** in a skill run, check the gitignore:

1. Check if `.gitignore` exists in `REPO_LOCAL_PATH`
2. If it exists, check if it already contains `SESSION-*.md` — if yes, skip
3. If not present, warn the user: `"Note: SESSION-*.md is not in {repo}/.gitignore. Consider adding it to prevent accidental commits."`

Do NOT modify `.gitignore` automatically — it creates unstaged changes that interfere with dirty-tree checks in other skills. The development-skills repo already has `SESSION-*.md` in its `.gitignore`. For other repos, the user should add it manually or it should be part of the repo's initial setup.

## Parent-child skill handling

`do-the-thing` invokes `do-issue`, `fix-pr`, and `merge-prs` as child skills. To avoid the child overwriting the parent's session state:

1. At Session Read time, check if the session file already exists
2. If it exists and its `Skill:` header is **different** from the current skill (e.g., file says `do-the-thing` but current skill is `do-issue`), this is a **parent-managed session**
3. In parent-managed mode: skip all Session Write, Session Read presentation, and Session Clear — let the parent handle the file
4. If the file doesn't exist, or the `Skill:` header matches the current skill, proceed normally

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
