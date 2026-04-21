# development-skills

Portable Claude Code skills and plugins for dev workflow automation.

## Install

### Plugin system (recommended)

```bash
# Add the marketplace
claude plugin marketplace add ~/gitea-repos/development-skills

# Install plugins
claude plugin install sound-notifications@development-skills --scope user
claude plugin install productivity-hooks@development-skills --scope user
```

### Manual setup

```bash
git clone ssh://gitea@gitea.int.superwerewolves.ninja:2222/super-werewolves/development-skills.git ~/gitea-repos/development-skills
```

Then inside Claude Code:

1. Register the marketplace: `claude plugin marketplace add ~/gitea-repos/development-skills`
2. Run `/setup-env` to configure everything (Gitea MCP, SSH keys, plugins, skill symlinks, prerequisites)

`/setup-env` also supports targeted mode for configuring specific sections:

```
/setup-env deploy              # Configure deploy workflows for all repos
/setup-env deploy food-auto    # Add/update deploy config for one repo
/setup-env repos               # Regenerate repos.md
/setup-env infrastructure      # Regenerate infrastructure.md
/setup-env plugins             # Install/update plugins
```

## Structure

```
development-skills/
├── config/              # Committed defaults (infrastructure template)
├── lib/                 # Shared libs included by skills via !cat
├── plugins/
│   ├── dev-workflow/    # Dev workflow skills (do-issue, review-pr, fix-pr, etc.)
│   ├── planning/        # Planning skills (analyze-idea, plan-project, create-issues, etc.)
│   ├── productivity/    # Productivity skills (start, status, setup-env, etc.)
│   ├── dev-workflow-hooks/
│   ├── productivity-hooks/
│   └── sound-notifications/
├── skills/              # Redirect — skills moved to plugins/
├── planning-skills/     # Redirect — skills moved to plugins/planning/
└── setup/               # WSL sandbox provisioning (setup-windows.ps1, setup-linux.sh)
```

## Skills

Skills live in `plugins/dev-workflow/skills/`, `plugins/planning/skills/`, and `plugins/productivity/skills/`.

### Workflow (`plugins/dev-workflow/skills/`)

| Skill | Description |
|-------|-------------|
| `/do-the-thing [repo]` | Full dev loop — triage, implement, review, fix, merge |
| `/do-issue repo#N` | Implement a single issue end-to-end |
| `/dev-deploy repo#N` | Deploy a PR or branch to the dev environment |
| `/qa-pr repo#N` | Deploy to dev, run smoke tests, post QA results |
| `/review-pr repo#N` | 4-pass automated code review |
| `/fix-pr repo#N` | Address PR review comments |
| `/merge-prs [repo]` | Merge ready PRs with deploy monitoring |
| `/update-prs [repo\|repo#N]` | Rebase stale PRs onto latest main and verify CI |
| `/list-prs [repo]` | List open PRs with status |
| `/triage-issues repo` | Prioritize open issues |
| `/set-priority repo#N` | Mark an issue as current priority for triage |
| `/investigate-bug <desc\|repo#N>` | Reproduce, diagnose root cause, file bug issues |
| `/gwt repo#N [--with-data]` | Generate GIVEN/WHEN/THEN acceptance criteria |
| `/test repo#N` | Plan, document, and execute E2E tests |
| `/start [repo]` | Full workspace orientation |
| `/start-quick [repo]` | Quick orientation |
| `/status` | Catch-up summary — active sessions, git activity, next actions |
| `/clear-session` | Clear active session file when done with current work |
| `/setup-env [section] [repo]` | Interactive environment setup — Gitea, deploy config, plugins, tools |

### Planning & Verification (`plugins/planning/skills/`)

| Skill | Description |
|-------|-------------|
| `/plan-the-thing [idea]` | Full planning loop — analyze, plan, create issues |
| `/analyze-idea [idea]` | Critical analysis of a problem/solution idea |
| `/plan-project [plan-dir]` | Research and create detailed project plan |
| `/create-issues plan-dir [repo]` | Turn a plan into Gitea milestones and issues |
| `/hallucination-check path` | Verify plan claims against reality — catch false libs, wrong APIs, vague steps |
| `/verify-pr repo#N` | Verify PR implements issue requirements — catch missing features, inaccurate descriptions, pattern violations |

**Planning flow:** `/analyze-idea` → `/plan-project` → `/create-issues` (or `/plan-the-thing` for all three)

Plans are stored in `~/plans/{date}-{slug}/` with `analysis.md`, `plan.md`, and `issues-created.md`.

## Config

Runtime config lives at `~/.config/development-skills/` (per-machine, not committed):

| File | Purpose | Used by |
|------|---------|---------|
| `repos.md` | Shorthand table mapping repo names to owners and local paths | All skills via `resolve-repo.md` |
| `infrastructure.md` | IPs, domains, service URLs for the homelab | `/investigate-bug`, `/qa-pr`, productivity-hooks |
| `deploy-config.md` | Deploy workflows, dev URLs, chart names per repo | `/dev-deploy`, `/qa-pr` |
| `discord-webhook` | Discord webhook URL (chmod 600) | `/do-the-thing`, `/merge-prs` |

Committed defaults live in `config/` (infrastructure template) and `lib/` (shared parsing logic).

## Shared Libraries

Skills include shared logic via `!cat $HOME/.claude/development-skills/lib/{name}.md`:

| Library | Purpose |
|---------|---------|
| `resolve-repo.md` | Parse user input into owner/repo/index |
| `session-state.md` | Persistent session files across context compactions |
| `agent-identity.md` | Agent ID derivation and registration |
| `agent-coordination.md` | Multi-agent work registration and conflict detection |
| `discord-notify.md` | Discord webhook notifications |
| `status-labels.md` | Issue lifecycle label management |
| `pr-status-labels.md` | PR workflow label management |
| `review-checklists.md` | Code review checklist patterns |
| `planning-common.md` | Plan storage and information gathering |

## Gitea Workflow MCP Server

The `gitea-workflow-mcp` server provides PR label management, review posting,
and merge tools.  It runs as an HTTP service (port 8319) so all Claude sessions
share one instance.

```bash
# Start the server (requires GITEA_URL and GITEA_TOKEN in env)
gitea-workflow-mcp                     # HTTP on 127.0.0.1:8319 (default)
MCP_TRANSPORT=stdio gitea-workflow-mcp # stdio mode (single-session)
```

The server must be running before Claude sessions connect.  On flywheel it is
managed via systemd user service — see `homelab-setup` for the Ansible playbook.

Env vars: `MCP_TRANSPORT`, `MCP_HOST`, `MCP_PORT`, `GITEA_URL`, `GITEA_TOKEN`.

## Secrets

Secrets are never committed. They're read at runtime:

- **Gitea API token**: env var `GITEA_TOKEN` (for gitea-workflow-mcp) and `~/.mcp.json` (for gitea-mcp)
- **code-review-agent token**: `$HOME/.config/code-review-agent/token`
- **Discord webhook**: `~/.config/development-skills/discord-webhook`

## Plugins

| Plugin | Marketplace | Purpose |
|--------|-------------|---------|
| `sound-notifications` | `development-skills` | System sounds when Claude needs input or finishes a task. Cross-platform: WSL, macOS, Linux, Termux. |
| `productivity-hooks` | `development-skills` | Injects AGENTS.md rules + project context on every prompt, enforces rules in subagents, sends Discord notification on session stop. |

```bash
claude plugin marketplace add ~/gitea-repos/development-skills
claude plugin install sound-notifications@development-skills --scope user
claude plugin install productivity-hooks@development-skills --scope user
```

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
