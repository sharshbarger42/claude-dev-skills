---
name: setup-env
description: Set up the Claude Code environment for the development-skills workflow — configure Gitea, Discord, AGENTS.md, and verify prerequisites. Run after setup-linux.sh or on any new machine.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion
---

# Environment Setup

Interactive setup for a development-skills environment. Configures Gitea access, Discord notifications, generates AGENTS.md, and verifies all prerequisites.

## Step 0: Re-run Detection

Check if `~/.claude/env-config.yaml` exists with non-empty values (previous setup completed).

If it exists, read it and ask:

> Previous setup detected.
> - **Re-apply** — Re-run with existing config (only set up missing pieces)
> - **Edit** — Modify specific settings, then re-apply
> - **Fresh** — Start over from scratch

**Re-apply:** Load saved config, skip prompts, jump to Step 3.
**Edit:** Show current config, let user change specific items, then re-apply.
**Fresh:** Continue to Step 1.

## Step 1: Load Config

Check for config at `~/development-skills/setup/env-config.yaml` (template) or `~/gitea-repos/development-skills/setup/env-config.yaml`.

Read it to get defaults (Gitea URL, SSH, org).

## Step 2: Gather User Preferences

Collect values that are still blank. Ask related fields together to minimize prompts.

### 2a. Git Identity (if not already configured)

```
Git name and email?
```

Set via `git config --global` if not already set.

### 2b. Gitea Access

Verify Gitea is reachable:

```bash
curl -s -o /dev/null -w "%{http_code}" http://git.home.superwerewolves.ninja/api/v1/settings/api 2>/dev/null
```

If not reachable, ask for the correct Gitea URL and save it.

Check SSH key:
- If `~/.ssh/id_ed25519_gitea` exists, test it: `ssh -T -o ConnectTimeout=5 git@git.home.superwerewolves.ninja 2>&1`
- If no key exists, generate one and display the public key for the user to add to Gitea

### 2c. Discord Webhook (optional)

```
Discord webhook URL for notifications? (Enter to skip)
```

If provided, save to `~/.config/development-skills/discord-webhook` with `chmod 600`.

### 2d. Dev Types (optional)

```
Dev types (comma-separated, or Enter to skip): web-fullstack, python, go, rust
```

### 2e. Batch Confirmation

Present all collected values:

```
Configuration:
- Git: {name} <{email}>
- Gitea: {url} (SSH: {ssh_status})
- Discord: {configured/not configured}
- Dev types: {types or "none"}

Confirm (Enter) or specify corrections:
```

## Step 3: Install Dev Tools (if dev types selected)

Based on selected dev types, install tools. Check if already installed first.

**web-fullstack:**
```bash
# Node.js should already be present from setup-linux.sh
npm install -g typescript eslint prettier 2>/dev/null || true
```

**python:**
```bash
sudo apt-get install -y python3 python3-pip python3-venv 2>/dev/null || true
pip3 install --user ruff 2>/dev/null || true
```

**go:**
```bash
if ! command -v go &>/dev/null; then
    curl -sSL https://go.dev/dl/go1.22.0.linux-amd64.tar.gz | sudo tar -C /usr/local -xzf -
    echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bashrc
fi
```

**rust:**
```bash
if ! command -v rustc &>/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
```

Report what was installed vs skipped.

## Step 4: Set Up Workspace

### 4a. Create Repos Directory

```bash
mkdir -p ~/gitea-repos
```

### 4b. Generate ~/AGENTS.md

Create `~/AGENTS.md` if it doesn't exist. This is the workspace-level guide that `/start` and the productivity-hooks plugin read.

```markdown
# Workspace Agent Instructions

## Environment

- **Gitea:** {gitea_url}
- **Org:** {gitea_org}
- **Repos:** ~/gitea-repos/

## Safeguards

1. **No destructive actions without explicit approval.** This includes: force push, reset --hard, branch -D, deleting files outside the working repo.
2. **No push to main/master without approval.** Always work on feature branches.
3. **Never commit secrets, credentials, or .env files.**
4. **Confirm external writes.** Gitea issue/PR updates, Discord messages, and pushes all require confirmation.
5. **When working on issues, check status labels** to avoid conflicts with other agents.

## Tracking

- SESSION.md files in each repo track active work context
- Claude memory at ~/.claude/projects/ persists across sessions

## Skills Reference

| Skill | Purpose |
|-------|---------|
| `/start` | Full workspace orientation |
| `/do-the-thing [repo]` | Full dev loop (triage → implement → review → merge) |
| `/do-issue repo#N` | Implement a single issue |
| `/review-pr repo#N` | Code review a PR |
| `/gwt repo#N` | Generate acceptance criteria |
| `/test repo#N` | Plan and run E2E tests |
| `/status` | Catch-up summary |
| `/plan-the-thing` | Full planning pipeline |

## Config

- Repo shorthand: ~/.claude/development-skills/config/repos.md
- Infrastructure: ~/.claude/development-skills/config/infrastructure.md
```

### 4c. Install Plugins

Check if plugins are installed, and show install commands if not:

```bash
claude plugin list 2>/dev/null | grep -q "sound-notifications" || echo "Not installed: sound-notifications"
claude plugin list 2>/dev/null | grep -q "productivity-hooks" || echo "Not installed: productivity-hooks"
```

If not installed, offer to install them:

```
Install sound-notifications and productivity-hooks plugins? (Y/n)
```

If yes:
```bash
claude plugin marketplace add ~/gitea-repos/development-skills 2>/dev/null || claude plugin marketplace add ~/development-skills 2>/dev/null
claude plugin install sound-notifications@super-werewolves-skills --scope user
claude plugin install productivity-hooks@super-werewolves-skills --scope user
```

Report status of each plugin.

## Step 5: Verify Prerequisites

Run a comprehensive check and report results:

```
Prerequisites:
  Git identity:              {name} <{email}>
  Gitea reachable:           {yes/no}
  SSH key:                   {configured/missing}
  development-skills linked: {yes/no}
  Discord webhook:           {configured/not configured}
  Agent Mail MCP:            {configured/not configured}
  Gitea MCP:                 {configured/not configured}

Plugins:
  sound-notifications:       {installed/not installed}
  productivity-hooks:        {installed/not installed}

Tools:
  node:                      {version or missing}
  claude:                    {version or missing}
  {dev-type specific tools}
```

## Step 6: Save Config

Save the final configuration to `~/.claude/env-config.yaml`.

## Step 7: Report Summary

```
## Environment Setup Complete

### Configured
- Git: {name} <{email}>
- Gitea: {url}
- Discord: {status}
- AGENTS.md: {created / already existed}

### Installed
- {tools installed or skipped}

### Plugins
- {plugin status}

### Next Steps
- {any manual steps needed — e.g. "Add SSH key to Gitea", "Configure Gitea MCP"}
- Run /start to begin your first session
```

## Rules

- Never overwrite existing AGENTS.md or tracking files without asking
- Always check if tools are already installed before installing
- Report what was done vs skipped
- If any installation fails, report and continue — don't abort
- Never hardcode usernames, hosts, or credentials — use values from config
- Each sudo command must be a separate Bash call — never chain with &&
- Keep it lean — this is a homelab setup, not enterprise provisioning
