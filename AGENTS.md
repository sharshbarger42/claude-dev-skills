# AGENTS.md — development-skills

Shared skills, hooks, and configuration for Claude Code across all projects.

## Rules for cross-project agents

- You may edit files here to update shared config, hooks, or skills.
- After editing plugin files, sync the cache: copy changes to `~/.claude/plugins/cache/super-werewolves-skills/productivity-hooks/<version>/`.
- Do not delete files without explicit user permission.
- Do not commit secrets or credentials.
- Test hook scripts after editing (`bash -n script.sh` at minimum).
