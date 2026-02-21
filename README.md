# development-skills

Portable Claude Code skills plugin for dev workflow automation.

## Install

```bash
git clone ssh://gitea@192.168.0.174:2222/super-werewolves/development-skills.git ~/gitea-repos/development-skills
cd ~/gitea-repos/development-skills
./install.sh
```

This symlinks each `skills/{name}/` into `~/.claude/skills/{name}/`. A `git pull` instantly updates all skills — no re-install needed.

## Structure

```
development-skills/
├── install.sh              # Symlink installer + prerequisite checker
├── config/
│   ├── repos.md            # Centralized repo shorthand table
│   └── infrastructure.md   # IPs, domains, service URLs
├── lib/
│   └── resolve-repo.md     # Shared repo-parsing instructions
└── skills/
    ├── do-issue/           # Implement a Gitea issue end-to-end
    ├── review-pr/          # Automated PR code review
    ├── fix-pr/             # Address PR review comments
    └── triage-issues/      # Prioritize repo issues
```

## Config

- `config/repos.md` — repo shorthand table (used by all 4 skills)
- `config/infrastructure.md` — IPs, domains, service URLs (used by review-pr for Gitea API)
- `lib/resolve-repo.md` — shared repo-parsing logic with `!cat` include of repos.md

### Per-VM customization

Config files are committed with defaults for the primary environment. On a different VM, edit `config/repos.md` and `config/infrastructure.md` with that VM's values.

## Secrets

Secrets are never committed. They're read at runtime:
- **code-review-agent token**: `$HOME/.config/code-review-agent/token`
- **MCP server tokens**: `~/.mcp.json` and `~/.claude.json`
- **API keys**: MCP server env vars
