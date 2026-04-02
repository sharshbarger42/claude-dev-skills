# AGENTS.md — development-skills

Shared skills, hooks, and configuration for Claude Code across all projects.

## Rules for cross-project agents

- You may edit files here to update shared config, hooks, or skills.
- Do not delete files without explicit user permission.
- Do not commit secrets or credentials.
- Test hook scripts after editing (`bash -n script.sh` at minimum).

## Repository structure

```
plugins/
  {plugin-name}/
    .claude-plugin/
      plugin.json          # name, version, description, author
    hooks/
      hooks.json           # hook definitions (optional)
    scripts/
      postinstall.sh       # runs on plugin install/update
      on-prompt-*.sh       # pre-prompt hooks
    lib/                   # shared markdown libs included by skills
      *.md
    skills/
      {skill-name}/
        SKILL.md           # single-file skill definition
.claude-plugin/
  marketplace.json         # top-level registry of all plugins
```

## Adding a new skill

1. Create `plugins/{plugin-name}/skills/{skill-name}/SKILL.md`.
2. Use YAML frontmatter: `name`, `description` (required), `allowed-tools` (optional).
3. Write sequential steps. Include shared libs via `!\`cat ${CLAUDE_PLUGIN_ROOT}/lib/{lib}.md\``.
4. **Bump the plugin version** in `plugins/{plugin-name}/.claude-plugin/plugin.json` — this is required for `claude plugins update` to detect the change.
5. Commit, push, and create a PR.

## Adding a new plugin

1. Create the directory structure under `plugins/{plugin-name}/`.
2. Add `.claude-plugin/plugin.json` with `name`, `version`, `description`, `author`.
3. Add a `hooks/hooks.json` if the plugin needs hooks (optional).
4. Add a `scripts/postinstall.sh` if the plugin needs to sync files on install (optional).
5. Register the plugin in `.claude-plugin/marketplace.json` — add an entry to the `plugins` array with `name`, `description`, `category`, and `source` (relative path like `./plugins/{plugin-name}`).
6. Commit, push, and create a PR.

## Installing and updating plugins

The plugin cache lives at `~/.claude/plugins/cache/development-skills/{plugin-name}/{version}/`. It is a static snapshot — it does **not** follow the repo's current branch.

- **Install:** `claude plugins install {plugin-name}@development-skills`
- **Update:** `claude plugins update {plugin-name}@development-skills` — only works if the version in `plugin.json` was bumped.
- **Force refresh (same version):** `claude plugins uninstall {plugin-name}@development-skills && claude plugins install {plugin-name}@development-skills`
- **Test a branch before merging:** Check out the branch in `~/gitea-repos/development-skills/`, then reinstall the plugin. The cache is built from whatever is on disk.

## Shared libs

Skills include reusable markdown via `!\`cat ${CLAUDE_PLUGIN_ROOT}/lib/{name}.md\``. Key libs:

| Lib | Purpose |
|-----|---------|
| `resolve-repo.md` | Parse issue/PR references (shorthand, owner/repo#N, URL) |
| `commit-push.md` | Commit formatting, testing, and push rules |
| `quality-gate.md` | Lint, format, type-check, test before committing |
| `pr-status-labels.md` | PR label swap procedures |
| `deploy-aware-label.md` | Check if repo has dev/prod deploy config |
| `fetch-agents-md.md` | Read a repo's AGENTS.md for coding standards |
| `review-checklists.md` | Four-pass code review checklists |
| `agent-identity.md` | Derive agent name for multi-agent coordination |
| `agent-coordination.md` | Register active work, query conflicts |
| `session-state.md` | Read/write session persistence across skills |
| `discord-notify.md` | Send Discord notifications |
| `check-ci.md` | Poll CI status |

The `postinstall.sh` script syncs lib files to `~/.config/development-skills/lib/` for cross-repo access.
