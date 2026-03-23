# Agent Identity

Derive a session-stable agent name and register presence via Agent Mail. Include this lib in any skill that participates in multi-agent coordination.

**Multi-agent gate:** Before running any steps in this lib, check if multi-agent mode is enabled:

```bash
grep -q '^multi_agent: true$' ~/.claude/env-config.yaml 2>/dev/null
```

If `multi_agent` is **not true**, skip this entire lib. Agent names and registration are only needed when multiple agents coordinate.

## Derive agent name

Generate a deterministic agent name from the Claude Code process PID:

```bash
AGENT_NAME="agent-${PPID}"
```

`$PPID` is the Claude Code process PID — stable across all bash invocations within the same session and unique per concurrent instance. Store `AGENT_NAME` as a variable for the rest of the session. Use it in all Agent Mail messages and Discord notifications.

## Register with Agent Mail

After deriving the agent name, announce presence by sending a message to the `agent-registry` thread:

```
mcp__mcp-agent-mail__send_message
  thread: "agent-registry"
  message: "[agent-online] ${AGENT_NAME} started at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

This is best-effort. If Agent Mail is unavailable (MCP tool not found or errors), log a note and continue — never block on registration failure.

## Usage

Skills that include this lib should:
1. Derive the agent name once at the start of the skill
2. Pass `AGENT_NAME` to `agent-coordination.md` functions
3. Include `AGENT_NAME` in Discord notifications
