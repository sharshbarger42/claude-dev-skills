# Agent Coordination

Register, query, and deregister active work across agents. Uses Gitea labels as the authoritative signal, Agent Mail for richer context, and Discord for user-facing notifications.

**Prerequisites:** Include these libs first:
- `!cat $HOME/.claude/development-skills/lib/agent-identity.md`
- `!cat $HOME/.claude/development-skills/lib/discord-notify.md`

## Multi-Agent Gate

Before using any Agent Mail or Discord features in this lib, check if multi-agent mode is enabled:

```bash
grep -q 'multi_agent: true' ~/.claude/env-config.yaml 2>/dev/null
```

If `multi_agent` is **not true**, skip all Agent Mail and Discord steps in this lib. Only Gitea label management (the authoritative signal) runs regardless of this flag.

## Register Active Work

Call this when an agent starts working on an issue or PR. Three actions, all best-effort:

### 1. Set Gitea label (authoritative)

Add the `status: in-progress` label to the issue (see `status-labels.md` for the swap procedure). This is the primary coordination signal — other agents check this label.

### 2. Send Agent Mail message

Post a structured message to the `active-work-{repo}` thread:

```
mcp__mcp-agent-mail__send_message
  thread: "active-work-{repo}"
  message: "[active-work] agent={AGENT_NAME} repo={OWNER}/{REPO} issue=#{INDEX} title={ISSUE_TITLE} started={ISO_TIMESTAMP}"
```

If Agent Mail is unavailable, skip silently.

### 3. Discord notification

Post a "Started Work" Discord notification using the blue embed template from `discord-notify.md`.

If Discord webhook is not configured, skip silently.

## Query Active Work

Call this to discover what other agents are currently working on. Returns a list of in-progress items with staleness information.

### 1. Check Gitea labels

Use `mcp__gitea__list_repo_issues` with `state: "open"` and filter for issues that have the `status: in-progress` label. These are the authoritative in-progress items.

### 2. Enrich from Agent Mail

For richer context (which agent, when started), search Agent Mail:

```
mcp__mcp-agent-mail__search_messages
  query: "[active-work]"
  thread: "active-work-{repo}"
```

Parse each `[active-work]` message to extract `agent`, `repo`, `issue`, and `started` timestamp.

Cross-reference with Gitea: an issue is actively in-progress only if BOTH the Gitea label is set AND an Agent Mail message exists with no matching `[completed]` message.

### 3. Staleness detection

For each active-work message, check if:
- A corresponding `[completed]` message exists in the same thread for the same issue — if so, the work is done (even if the label wasn't removed)
- The `started` timestamp is more than **2 hours ago** with no `[completed]` message — flag as **"possibly stale"**

Return the list of active items with:
- `issue_index`, `issue_title`, `agent_name`, `started_at`, `is_stale`

If Agent Mail is unavailable, fall back to Gitea labels only (no agent name or staleness info).

## Deregister Active Work

Call this when an agent finishes working on an issue or PR (after PR creation, merge, or abandonment).

### 1. Send Agent Mail completion message

```
mcp__mcp-agent-mail__send_message
  thread: "active-work-{repo}"
  message: "[completed] agent={AGENT_NAME} repo={OWNER}/{REPO} issue=#{INDEX} completed={ISO_TIMESTAMP}"
```

### 2. Discord notification

Post the appropriate Discord notification (PR Created, PR Merged, or Loop Complete) using the templates from `discord-notify.md`.

### 3. Gitea label (handled by caller)

The Gitea label transition (`in-progress` -> `in-review` or `done`) is handled by the calling skill's existing label management logic. Do not duplicate it here.

## Graceful Degradation

All three systems degrade independently:

| System | If unavailable | Impact |
|--------|---------------|--------|
| Gitea labels | Skill stops (Gitea is required) | Cannot proceed — this is fatal |
| Agent Mail | Skip registration/query | No agent names or staleness detection; rely on Gitea labels alone |
| Discord | Skip notifications | No user-facing activity log; work proceeds normally |

Never let Agent Mail or Discord failures block the skill's primary workflow.
