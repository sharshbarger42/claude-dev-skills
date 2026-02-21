# development-skills

Portable Claude Code skills plugin. Single source of truth for all development, productivity, and infrastructure skills.

## Install

```bash
git clone ssh://gitea@192.168.0.174:2222/selina/development-skills.git ~/gitea-repos/development-skills
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
    ├── do-issue/           # Dev workflow: implement a Gitea issue
    ├── review-pr/          # Dev workflow: automated PR code review
    ├── fix-pr/             # Dev workflow: address PR review comments
    ├── triage-issues/      # Dev workflow: prioritize repo issues
    ├── morning/            # Daily morning briefing
    ├── catch-up/           # Session catch-up
    ├── check-in/           # Mid-session status check
    ├── weekly-review/      # Weekly productivity review
    ├── meal-plan/          # Meal planning with Tandoor + Grocy
    ├── grocery-list/       # Shopping list generation
    ├── service-check/      # Homelab service health check
    ├── infra-report/       # VM/LXC resource usage report
    ├── backup-status/      # Restic backup health
    ├── dns-check/          # Pi-hole DNS verification
    ├── tailnet-check/      # FQDN reachability via NPM
    ├── media-report/       # JellyFin + ErsatzTV stats
    ├── start/              # Full workspace orientation
    └── start-quick/        # Quick workspace orientation
```

## Config

- `config/repos.md` — repo shorthand table (used by do-issue, fix-pr, review-pr, triage-issues)
- `config/infrastructure.md` — IPs, domains, service URLs (used by dns-check, service-check, etc.)
- `lib/resolve-repo.md` — shared repo-parsing logic with `!cat` include of repos.md

### Per-VM customization

Config files are committed with defaults for the primary environment. On a different VM, edit `config/repos.md` and `config/infrastructure.md` with that VM's values.

## Secrets

Secrets are never committed. They're read at runtime:
- **code-review-agent token**: `$HOME/.config/code-review-agent/token`
- **MCP server tokens**: `~/.mcp.json` and `~/.claude.json`
- **API keys**: MCP server env vars
