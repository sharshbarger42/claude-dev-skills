# development-skills

Portable Claude Code skills plugin for dev workflow automation.

## Install

### Plugin system (recommended)

```bash
# Add the marketplace
/plugin marketplace add https://gitea.int.superwerewolves.ninja/super-werewolves/development-skills.git

# Install the plugin
/plugin install development-skills@super-werewolves-skills
```

Skills are invoked as `/development-skills:do-issue`, `/development-skills:review-pr`, etc.

### Manual setup

```bash
git clone ssh://gitea@git.baryonyx-walleye.ts.net:2222/super-werewolves/development-skills.git ~/gitea-repos/development-skills
```

Then inside Claude Code:

1. Register the skills marketplace: `/plugin marketplace add ~/gitea-repos/development-skills`
2. Run `/setup-env` to configure everything (Gitea MCP, SSH keys, plugins, skill symlinks, prerequisites)

## Structure

```
development-skills/
├── .claude-plugin/
│   └── plugin.json         # Plugin metadata (name, version, description)
├── marketplace.json        # Marketplace catalog for plugin discovery
├── install.sh              # Deprecated — points to /setup-env
├── config/
│   ├── repos.md            # Centralized repo shorthand table
│   └── infrastructure.md   # IPs, domains, service URLs
├── lib/
│   ├── resolve-repo.md     # Shared repo-parsing instructions
│   ├── agent-identity.md   # Agent name derivation + registration
│   ├── agent-coordination.md  # Multi-agent work tracking
│   ├── discord-notify.md   # Discord webhook templates
│   ├── status-labels.md    # Status label lifecycle
│   ├── review-checklists.md   # Code review checklists
│   └── planning-common.md  # Shared planning logic (plan storage, repo creation)
├── skills/                 # Workflow skills
│   ├── do-issue/           # Implement a Gitea issue end-to-end
│   ├── do-the-thing/       # Full dev loop (triage → implement → review → merge)
│   ├── review-pr/          # Automated PR code review
│   ├── fix-pr/             # Address PR review comments
│   ├── merge-prs/          # Merge ready PRs with deploy monitoring
│   ├── qa-pr/              # Quality assurance on PR
│   ├── triage-issues/      # Prioritize repo issues
│   ├── gwt/                # GIVEN/WHEN/THEN acceptance criteria from issues
│   ├── test/               # E2E test planning and execution
│   ├── status/             # Session catch-up and status summary
│   ├── start/              # Full workspace orientation
│   └── start-quick/        # Quick orientation
├── planning-skills/        # Planning skills
│   ├── analyze-idea/        # Critical analysis of a problem/solution
│   ├── plan-project/        # Detailed technical project plan
│   ├── create-issues/       # Turn a plan into Gitea milestones + issues
│   └── plan-the-thing/      # Full planning loop (analyze → plan → issues)
├── plugins/                # Claude Code plugins
│   ├── sound-notifications/ # System sounds on input needed / task done
│   └── productivity-hooks/  # AGENTS.md injection, context hooks, Discord on stop
└── setup/                  # WSL sandbox provisioning
    ├── wsl-sandbox/         # setup-windows.ps1, setup-linux.sh, teardown
    ├── env-config.yaml      # Environment configuration template
    └── dotfiles-defaults/   # Fallback shell/tmux configs
```

## Skills

### Workflow

| Skill | Description |
|-------|-------------|
| `/do-the-thing [repo]` | Full dev loop — triage → implement → review → fix → merge |
| `/do-issue repo#N` | Implement a single issue end-to-end |
| `/review-pr repo#N` | 4-pass automated code review |
| `/fix-pr repo#N` | Address PR review comments |
| `/merge-prs [repo]` | Merge ready PRs with deploy monitoring |
| `/triage-issues repo` | Prioritize open issues |
| `/start [repo]` | Full workspace orientation |
| `/start-quick [repo]` | Quick orientation |
| `/gwt repo#N [--with-data]` | Generate GIVEN/WHEN/THEN acceptance criteria from an issue |
| `/test repo#N` | Plan, document, and execute E2E tests for an issue |
| `/status` | Catch-up summary — active sessions, git activity, suggested next actions |
| `/setup-env` | Interactive environment setup — Gitea, Discord, AGENTS.md, plugins, tools |

### Planning

| Skill | Description |
|-------|-------------|
| `/plan-the-thing [idea]` | Full planning loop — analyze → plan → create issues |
| `/analyze-idea [idea]` | Critical analysis of a problem/solution idea |
| `/plan-project [plan-dir]` | Research and create detailed project plan |
| `/create-issues plan-dir [repo]` | Turn a plan into Gitea milestones and issues |

**Planning flow:** `/analyze-idea` → `/plan-project` → `/create-issues` (or use `/plan-the-thing` to run all three)

Plans are stored in `~/plans/{date}-{slug}/` with `analysis.md`, `plan.md`, and `issues-created.md`.

## Config

- `config/repos.md` — repo shorthand table (used by all skills)
- `config/infrastructure.md` — IPs, domains, service URLs
- `lib/resolve-repo.md` — shared repo-parsing logic with `!cat` include of repos.md
- `lib/planning-common.md` — plan storage, repo creation, information gathering patterns

### Per-VM customization

Config files are committed with defaults for the primary environment. On a different VM, edit `config/repos.md` and `config/infrastructure.md` with that VM's values.

## Secrets

Secrets are never committed. They're read at runtime:
- **code-review-agent token**: `$HOME/.config/code-review-agent/token`
- **MCP server tokens**: `~/.mcp.json` and `~/.claude.json`
- **API keys**: MCP server env vars

## Plugins

Register the marketplace, then install plugins:

```bash
claude plugin marketplace add ~/gitea-repos/development-skills
claude plugin install sound-notifications@super-werewolves-skills --scope user
claude plugin install productivity-hooks@super-werewolves-skills --scope user
```

| Plugin | Purpose |
|--------|---------|
| `sound-notifications` | System sounds on Notification (needs input) and Stop (task done). Cross-platform: Termux/Android, WSL, macOS, Linux. |
| `productivity-hooks` | Injects AGENTS.md rules + project context on every prompt, enforces rules in subagents, sends Discord notification on session stop. |

## WSL Sandbox Setup

For Windows/WSL environments, provision an isolated Ubuntu-Claude distro:

```powershell
# From PowerShell (Admin):
.\setup\wsl-sandbox\setup-windows.ps1          # Create distro + terminal profile
.\setup\wsl-sandbox\setup-windows.ps1 -DryRun  # Preview changes
.\setup\wsl-sandbox\setup-windows.ps1 -Defaults # No prompts

# Inside Ubuntu-Claude:
~/development-skills/setup/wsl-sandbox/setup-linux.sh  # Install tools + skills

# Teardown:
.\setup\wsl-sandbox\teardown-windows.ps1        # Remove distro + cleanup
```

Features: controlled sudo, automount disabled, Gitea SSH key generation, dotfiles stow, backup/restore across teardown cycles.
