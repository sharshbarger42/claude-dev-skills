#!/usr/bin/env bash
# Runs before Claude processes each user prompt.
# Stdout is injected as context into the conversation.

SKILLS_DIR="$HOME/.claude/development-skills"
LOCAL_CONFIG="$HOME/.config/development-skills"
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
<development-skills-context>
REMINDERS (from productivity-hooks plugin):

1. AGENTS.md compliance: If an AGENTS.md file exists in the current repo or ~/, follow its rules.
   - No destructive actions without explicit approval
   - No push to main/master without approval
   - Never commit secrets, credentials, or .env files

2. Gitea coordination: When working on issues or PRs, check for status labels
   (status: in-progress, status: blocked, etc.) to avoid conflicts with other agents.

3. Secrets: Never print connection strings, API keys, passwords, or tokens in your output.
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

echo "</development-skills-context>"

exit 0
