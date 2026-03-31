#!/usr/bin/env bash
# Runs when a subagent starts.
# Stdout is injected into the subagent's context so it inherits project rules.

SKILLS_DIR="$HOME/.config/development-skills"

# Find AGENTS.md — prefer current directory, then home
AGENTS_FILE=""
if [[ -f "$(pwd)/AGENTS.md" ]]; then
    AGENTS_FILE="$(pwd)/AGENTS.md"
elif [[ -f "$HOME/AGENTS.md" ]]; then
    AGENTS_FILE="$HOME/AGENTS.md"
else
    exit 0
fi

AGENTS_CONTENT=$(cat "$AGENTS_FILE")

cat << 'HEADER'
<subagent-rules>
You are a subagent. The following project rules from AGENTS.md apply to your work:

HEADER

echo "$AGENTS_CONTENT"

cat << 'FOOTER'

Key rules to follow:
- No destructive actions without explicit approval from the parent agent or user
- Never commit secrets, credentials, or .env files
- Never print connection strings, API keys, passwords, or tokens
- When working on Gitea issues, check status labels before starting to avoid conflicts
- If you need to modify data, generate a script for review — do not execute directly
</subagent-rules>
FOOTER

# Inject coordination context if agent-coordination lib exists
if [[ -f "$SKILLS_DIR/lib/agent-coordination.md" ]]; then
    echo ""
    echo "<subagent-coordination>"
    echo "Multi-agent coordination rules are at: $SKILLS_DIR/lib/agent-coordination.md"
    echo "Check Gitea labels and Agent Mail before starting work on any issue."
    echo "</subagent-coordination>"
fi

exit 0
