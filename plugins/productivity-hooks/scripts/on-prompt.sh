#!/usr/bin/env bash
# Runs before Claude processes each user prompt.
# Stdout is injected as context into the conversation.

SKILLS_DIR="$HOME/.claude/development-skills"
LOCAL_CONFIG="$HOME/.config/development-skills"
AGENTS_FILES=()

# Read user prompt from stdin JSON (hook receives JSON with "prompt" field)
USER_PROMPT=""
if read -r -t 0.1 stdin_data; then
    USER_PROMPT=$(echo "$stdin_data" | jq -r '.prompt // empty' 2>/dev/null)
fi

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
<development-skills-context>
REMINDERS (from productivity-hooks plugin):

1. AGENTS.md compliance: If an AGENTS.md file exists in the current repo or ~/, follow its rules.
   - No destructive actions without explicit approval
   - No push to main/master without approval
   - Never commit secrets, credentials, or .env files

2. Gitea coordination: When working on issues or PRs, check for status labels
   (status: in-progress, status: blocked, etc.) to avoid conflicts with other agents.

3. Secrets: Never print connection strings, API keys, passwords, or tokens in your output.

4. Git branching — MANDATORY:
   - ALWAYS fetch and branch from the latest remote default branch (usually origin/main).
     Run `git fetch origin` then `git checkout -b <branch> origin/main`. NEVER branch from
     whatever branch happens to be checked out — it may be stale or unrelated.
   - NEVER assume the local main/master is up to date. Always use `origin/main` after fetching.
   - If you need to work on an existing branch, fetch first: `git fetch origin && git checkout <branch> && git pull`.

5. Worktrees — MANDATORY:
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

# Inline project map (local config first, fall back to repo)
repos_file=""
if [[ -f "$LOCAL_CONFIG/repos.md" ]]; then
    repos_file="$LOCAL_CONFIG/repos.md"
elif [[ -f "$SKILLS_DIR/config/repos.md" ]]; then
    repos_file="$SKILLS_DIR/config/repos.md"
fi

if [[ -n "$repos_file" ]]; then
    echo ""
    echo "<project-map>"
    cat "$repos_file"
    echo "</project-map>"
fi

# Inline infrastructure reference (local config first, fall back to repo)
infra_file=""
if [[ -f "$LOCAL_CONFIG/infrastructure.md" ]]; then
    infra_file="$LOCAL_CONFIG/infrastructure.md"
elif [[ -f "$SKILLS_DIR/config/infrastructure.md" ]]; then
    infra_file="$SKILLS_DIR/config/infrastructure.md"
fi

if [[ -n "$infra_file" ]]; then
    echo ""
    echo "<infrastructure-reference>"
    cat "$infra_file"
    echo "</infrastructure-reference>"
fi

# Inline MCP-specific guides from lib/ — only when the prompt is relevant
# Gitea MCP guide: injected when the user's prompt mentions actions URLs or action runs
if [[ -n "$USER_PROMPT" ]] && echo "$USER_PROMPT" | grep -qiE '/actions/runs/|action.?run|workflow.?run|job.?log|ci.?(fail|pass|status|check)|actions.?(fail|broke|error)'; then
    gitea_guide=""
    if [[ -f "$SKILLS_DIR/lib/gitea-mcp-guide.md" ]]; then
        gitea_guide="$SKILLS_DIR/lib/gitea-mcp-guide.md"
    elif [[ -f "$(dirname "$(dirname "$(dirname "$0")")")/../lib/gitea-mcp-guide.md" ]]; then
        gitea_guide="$(dirname "$(dirname "$(dirname "$0")")")/../lib/gitea-mcp-guide.md"
    fi

    if [[ -n "$gitea_guide" ]]; then
        echo ""
        echo "<gitea-mcp-guide>"
        cat "$gitea_guide"
        echo "</gitea-mcp-guide>"
    fi
fi

echo "</development-skills-context>"

exit 0
