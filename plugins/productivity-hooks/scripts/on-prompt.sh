#!/usr/bin/env bash
# Runs before Claude processes each user prompt.
# Injects general productivity guardrails: AGENTS.md compliance, secrets, git safety.

AGENTS_FILES=()

# Find AGENTS.md in current directory and parents (up to home)
dir="$(pwd)"
while [[ "$dir" != "/" && "$dir" != "$HOME" ]]; do
    if [[ -f "$dir/AGENTS.md" ]]; then
        AGENTS_FILES+=("$dir/AGENTS.md")
    fi
    dir="$(dirname "$dir")"
done
# Also check home-level AGENTS.md
if [[ -f "$HOME/AGENTS.md" ]]; then
    AGENTS_FILES+=("$HOME/AGENTS.md")
fi

# Deduplicate
mapfile -t AGENTS_FILES < <(printf '%s\n' "${AGENTS_FILES[@]}" | sort -u)

cat << 'RULES'
<productivity-context>
REMINDERS (from productivity-hooks plugin):

1. AGENTS.md compliance: If an AGENTS.md file exists in the current repo or ~/, follow its rules.
   - No destructive actions without explicit approval
   - No push to main/master without approval
   - Never commit secrets, credentials, or .env files

2. Secrets: Never print connection strings, API keys, passwords, or tokens in your output.

3. Git branching — MANDATORY:
   - ALWAYS fetch and branch from the latest remote default branch (usually origin/main).
     Run `git fetch origin` then `git checkout -b <branch> origin/main`. NEVER branch from
     whatever branch happens to be checked out — it may be stale or unrelated.
   - NEVER assume the local main/master is up to date. Always use `origin/main` after fetching.
   - If you need to work on an existing branch, fetch first: `git fetch origin && git checkout <branch> && git pull`.

4. Worktrees — MANDATORY:
   - ALWAYS use a git worktree for new work (Agent tool with `isolation: "worktree"`, or
     `git worktree add`). This keeps the user's working directory clean and avoids conflicts
     with in-progress work on other branches.
   - The ONLY exception is if the user explicitly tells you to work in the current directory.
   - When using the Agent tool for implementation work, set `isolation: "worktree"`.
   - After worktree work is done, push the branch — do not leave changes stranded in a worktree.
RULES

# List active AGENTS.md files
if [[ ${#AGENTS_FILES[@]} -gt 0 ]]; then
    echo ""
    echo "Active AGENTS.md files:"
    for f in "${AGENTS_FILES[@]}"; do
        echo "  - $f"
    done
fi

echo "</productivity-context>"

exit 0
