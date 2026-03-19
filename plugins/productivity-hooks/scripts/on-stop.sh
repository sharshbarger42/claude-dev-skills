#!/usr/bin/env bash
# Runs after Claude finishes responding (async).
# Sends a Discord notification that the session has stopped.

DISCORD_WEBHOOK="$(cat ~/.config/development-skills/discord-webhook 2>/dev/null || true)"

# Only notify if webhook is configured
if [[ -z "$DISCORD_WEBHOOK" ]]; then
    exit 0
fi

AGENT_NAME="${CLAUDE_SESSION_ID:-unknown}"
REPO_NAME="$(basename "$(pwd)" 2>/dev/null || echo "unknown")"

curl -s -X POST "$DISCORD_WEBHOOK" \
  -H "Content-Type: application/json" \
  -d "$(cat <<EOF
{
  "embeds": [{
    "title": "Session Stopped",
    "description": "**Agent:** ${AGENT_NAME}\n**Directory:** ${REPO_NAME}\n**Action:** Waiting for input or task complete",
    "color": 9807270,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }]
}
EOF
)" >/dev/null 2>&1

exit 0
