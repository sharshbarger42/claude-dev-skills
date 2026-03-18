# development-skills

Portable Claude Code skills plugin for dev workflow automation.

## Install

```bash
git clone ssh://gitea@192.168.0.174:2222/super-werewolves/development-skills.git ~/gitea-repos/development-skills
cd ~/gitea-repos/development-skills
./install.sh
```

### Selective install

```bash
./install.sh all        # Install everything (default)
./install.sh workflow   # Workflow skills only (do-issue, review-pr, etc.)
./install.sh planning   # Planning skills only (analyze-idea, plan-project, etc.)
```

This symlinks each skill directory into `~/.claude/skills/`. A `git pull` instantly updates all skills — no re-install needed.

## Structure

```
development-skills/
├── install.sh              # Symlink installer + prerequisite checker
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
│   ├── triage-issues/      # Prioritize repo issues
│   ├── start/              # Full workspace orientation
│   └── start-quick/        # Quick orientation
└── planning-skills/        # Planning skills
    ├── analyze-idea/        # Critical analysis of a problem/solution
    ├── plan-project/        # Detailed technical project plan
    ├── create-issues/       # Turn a plan into Gitea milestones + issues
    └── plan-the-thing/      # Full planning loop (analyze → plan → issues)
```

## Skills

### Workflow (`./install.sh workflow`)

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

### Planning (`./install.sh planning`)

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
