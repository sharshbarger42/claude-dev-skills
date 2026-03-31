# Discord Notifications

Post key events to a Discord channel via webhook. Silent no-op if the webhook is not configured.

## Setup

The webhook URL is stored at:
```
~/.config/development-skills/discord-webhook
```

The file should contain a single line: the Discord webhook URL. Create it with `chmod 600`.

## Check availability

Before sending any notification, check if the webhook file exists:

```bash
DISCORD_WEBHOOK="$(cat ~/.config/development-skills/discord-webhook 2>/dev/null || true)"
```

If `DISCORD_WEBHOOK` is empty, skip all Discord notifications silently. Never error on missing webhook.

## Event templates

All notifications use Discord embeds via `curl`. Always use a heredoc for the JSON body to handle special characters in titles and descriptions safely.

### Started Work (blue embed, color 3447003)

Post when an agent begins working on an issue or PR.

```bash
curl -s -X POST "$DISCORD_WEBHOOK" \
  -H "Content-Type: application/json" \
  -d "$(cat <<EOF
{
  "embeds": [{
    "title": "Started: ${ISSUE_TITLE}",
    "description": "**Agent:** ${AGENT_NAME}\n**Repo:** ${OWNER}/${REPO}\n**Issue:** #${INDEX}",
    "color": 3447003,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }]
}
EOF
)"
```

### PR Created (purple embed, color 10181046)

Post when an agent creates a pull request.

```bash
curl -s -X POST "$DISCORD_WEBHOOK" \
  -H "Content-Type: application/json" \
  -d "$(cat <<EOF
{
  "embeds": [{
    "title": "PR Created: ${PR_TITLE}",
    "description": "**Agent:** ${AGENT_NAME}\n**Repo:** ${OWNER}/${REPO}\n**PR:** #${PR_INDEX}\n**Branch:** ${BRANCH}",
    "color": 10181046,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }]
}
EOF
)"
```

### PR Merged (green embed, color 3066993)

Post when a PR is merged.

```bash
curl -s -X POST "$DISCORD_WEBHOOK" \
  -H "Content-Type: application/json" \
  -d "$(cat <<EOF
{
  "embeds": [{
    "title": "Merged: ${PR_TITLE}",
    "description": "**Agent:** ${AGENT_NAME}\n**Repo:** ${OWNER}/${REPO}\n**PR:** #${PR_INDEX}\n**Style:** ${MERGE_STYLE}",
    "color": 3066993,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }]
}
EOF
)"
```

### Loop Complete (gold embed, color 15844367)

Post when a full `/do-the-thing` cycle finishes.

```bash
curl -s -X POST "$DISCORD_WEBHOOK" \
  -H "Content-Type: application/json" \
  -d "$(cat <<EOF
{
  "embeds": [{
    "title": "Loop Complete: ${REPO}",
    "description": "**Agent:** ${AGENT_NAME}\n**Issue:** #${ISSUE_INDEX} ${ISSUE_TITLE}\n**PR:** #${PR_INDEX}\n**Status:** ${FINAL_STATUS}",
    "color": 15844367,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }]
}
EOF
)"
```

## Important notes

- Always use heredoc (`<<EOF`) for the JSON body — never interpolate user-provided strings directly into JSON without it
- All curl calls use `-s` (silent) to avoid progress output
- If curl fails, ignore the error and continue — Discord is advisory, never blocking
- Escape double quotes in `ISSUE_TITLE` and `PR_TITLE` before interpolation: `SAFE_TITLE="${TITLE//\"/\\\"}"`
