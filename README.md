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
├── config/              # Per-environment settings (infrastructure, repos)
├── lib/                 # Shared libs included by skills (repo parsing, labels, coordination)
├── skills/              # Workflow skills (see table below)
├── planning-skills/     # Planning skills (analyze, plan, create issues)
├── plugins/             # Claude Code plugins (sound-notifications, productivity-hooks)
└── setup/               # WSL sandbox provisioning (setup-windows.ps1, setup-linux.sh)
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
| `/update-prs [repo] or [repo#N]` | Rebase stale PRs onto latest main and verify CI |
| `/triage-issues repo` | Prioritize open issues |
| `/investigate-bug <description or repo#issue>` | Reproduce, diagnose root cause, and file bug issues |
| `/start [repo]` | Full workspace orientation |
| `/start-quick [repo]` | Quick orientation |
| `/gwt repo#N [--with-data]` | Generate GIVEN/WHEN/THEN acceptance criteria from an issue |
| `/test repo#N` | Plan, document, and execute E2E tests for an issue |
| `/status` | Catch-up summary — active sessions, git activity, suggested next actions |
| `/clear` | Clear active session file when done with current work |
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

- `config/infrastructure.md` — IPs, domains, service URLs
- `lib/resolve-repo.md` — shared repo-parsing logic
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
