#!/usr/bin/env bash
# Runs before Claude processes each user prompt.
# Injects development workflow context: Gitea coordination, project map, infrastructure.
set -uo pipefail

SKILLS_DIR="$HOME/.claude/development-skills"
LOCAL_CONFIG="$HOME/.config/development-skills"

# Read user prompt from stdin JSON (hook receives JSON with "prompt" field)
USER_PROMPT=""
stdin_data="$(cat)"
if [[ -n "$stdin_data" ]] && command -v jq &>/dev/null; then
    USER_PROMPT=$(printf '%s' "$stdin_data" | jq -r '.prompt // empty' 2>/dev/null)
fi

cat << 'RULES'
<development-skills-context>
REMINDERS (from dev-workflow-hooks plugin):

1. Gitea coordination: When working on issues or PRs, check for status labels
   (status: in-progress, status: blocked, etc.) to avoid conflicts with other agents.

RULES

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
if [[ -n "$USER_PROMPT" ]] && printf '%s\n' "$USER_PROMPT" | grep -qiE '/actions/runs/|action.?run|workflow.?run|job.?log|ci.?(fail|pass|status|check)|actions.?(fail|broke|error)'; then
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
