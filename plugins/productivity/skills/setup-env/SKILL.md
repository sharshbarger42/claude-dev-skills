---
name: setup-env
description: Set up the Claude Code environment for the development-skills workflow — configure Gitea, Discord, AGENTS.md, and verify prerequisites. Run after setup-linux.sh or on any new machine.
args: "[section] [repo]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion, mcp__gitea__list_my_repos
---

# Environment Setup

Interactive setup for a development-skills environment. Configures Gitea access, Discord notifications, generates AGENTS.md, and verifies all prerequisites.

## Targeted Mode

If `$ARGUMENTS` is provided, check if it targets a specific section and/or repo:

- **`/setup-env deploy`** — jump directly to deploy-config setup (Step 2h.3) for all repos
- **`/setup-env deploy food-automation`** — jump to deploy-config setup for a single repo only (add or update that repo's row in the table)
- **`/setup-env repos`** — jump to repos.md setup (Step 2h.1)
- **`/setup-env infrastructure`** — jump to infrastructure.md setup (Step 2h.2)
- **`/setup-env plugins`** — jump to plugin installation (Step 4c/4d)
- **No arguments** — run the full setup flow starting at Step 0

When running in targeted mode, skip re-run detection (Step 0) and all unrelated steps. Go directly to the targeted section, do the work, and report results.

## Step 0: Re-run Detection

Check if `~/.claude/env-config.yaml` exists with non-empty values (previous setup completed).

If it exists, read it and use AskUserQuestion with selectable options:

```
AskUserQuestion:
  question: "Previous setup detected. What would you like to do?"
  options: ["Re-apply (use existing config, set up missing pieces)", "Edit (modify specific settings, then re-apply)", "Fresh (start over from scratch)"]
```

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

Verify Gitea is reachable (follow redirects):

```bash
curl -sL -o /dev/null -w "%{http_code}" https://{gitea_host}/api/v1/settings/api 2>/dev/null
```

If not reachable, ask for the correct Gitea URL and save it.

### 2c. SSH Key

Check if SSH is already configured and working:

1. **Check if key exists:** Look for `~/.ssh/id_ed25519_gitea`
2. **If key exists**, test connectivity: `ssh -T -o ConnectTimeout=5 gitea@{gitea_host} 2>&1`
   - If test succeeds → SSH is good, move on
   - If test fails → warn user the key exists but auth is failing; suggest they check Gitea SSH keys settings
3. **If no key exists**, generate one and configure SSH:
   ```bash
   ssh-keygen -t ed25519 -C "{email}" -f ~/.ssh/id_ed25519_gitea -N ""
   ```
   Then create/update `~/.ssh/config`:
   ```
   Host {gitea_host}
       IdentityFile ~/.ssh/id_ed25519_gitea
       User gitea
       StrictHostKeyChecking accept-new
   ```
   Set `chmod 600 ~/.ssh/config`.

   **Set `ssh_key_generated=true`** — this flag tells Step 7 to display the public key and instructions.

Do NOT ask the user to add the key to Gitea during this step. Defer that to the summary in Step 7 so setup can continue uninterrupted.

### 2d. Gitea MCP

Many skills (`/do-issue`, `/review-pr`, `/fix-pr`, `/triage-issues`, `/test`, `/gwt`, etc.) require the Gitea MCP server to interact with issues, PRs, and repo contents. This step ensures it's configured.

**Check if already configured:**

```bash
grep -q '"gitea"' ~/.mcp.json 2>/dev/null || grep -q '"gitea"' ~/.claude.json 2>/dev/null
```

**If already configured**, report it and move on.

**If not configured**, the user needs a Gitea API token. Use AskUserQuestion:

```
AskUserQuestion:
  question: "Gitea MCP is required for most skills. Do you have a Gitea API token?"
  options: ["Yes, I have a token", "No, I need to create one", "Skip (skills that use Gitea won't work)"]
```

- **"Yes, I have a token"** — ask for the token value in a follow-up AskUserQuestion (free-text input is appropriate here since it's a secret).
- **"No, I need to create one"** — tell the user to create one at `{gitea_url}/user/settings/applications` (under "Manage Access Tokens"), then ask for it.
- **"Skip"** — warn that `/do-issue`, `/review-pr`, `/fix-pr`, `/triage-issues`, `/test`, and `/gwt` will not work, then move on.

**Once the token is provided:**

1. **Ensure `gitea-mcp` binary is installed.** Check if it's already on PATH:
   ```bash
   command -v gitea-mcp
   ```
   If not found, install it:
   ```bash
   go install gitea.com/gitea/gitea-mcp@latest
   ```
   If `go` is not installed, download the latest release binary from `https://gitea.com/gitea/gitea-mcp/releases` and place it in `/usr/local/bin`.

2. **Write or update `~/.mcp.json`:**

   If `~/.mcp.json` doesn't exist, create it:
   ```json
   {
     "gitea": {
       "command": "gitea-mcp",
       "args": ["-t", "stdio", "--host", "{gitea_url}", "--token", "{token}"]
     }
   }
   ```

   If `~/.mcp.json` already exists (with other MCP servers):
   1. Back up the file first: `cp ~/.mcp.json ~/.mcp.json.bak`
   2. Read the existing JSON, merge the `"gitea"` key into it. Do not overwrite other entries.
   3. Write the result to a temp file, validate it is parseable JSON (`jq . /tmp/mcp-merged.json`), then move it into place: `mv /tmp/mcp-merged.json ~/.mcp.json`
   4. If validation fails, restore from backup: `cp ~/.mcp.json.bak ~/.mcp.json`

3. Set `chmod 600 ~/.mcp.json` to protect the token.

4. **Enable `gitea` in the project config.** Claude Code requires MCP servers from `~/.mcp.json` to be explicitly enabled per project in `~/.claude.json`. Use the same backup-validate-move procedure from Step 2d: back up `~/.claude.json` first, then read it, find the `projects` entry matching your working directory, and add `"gitea"` to the `enabledMcpjsonServers` array if not already present. Validate the JSON before writing it back.

   Example — the relevant section should look like:
   ```json
   "enabledMcpjsonServers": ["gitea"]
   ```

   If the array already contains other entries, append `"gitea"` without removing them.

### 2e. Multi-Agent Mode

```
AskUserQuestion:
  question: "Enable multi-agent coordination? (Agent Mail, file reservations, Discord notifications between agents)"
  options: ["No — single agent only", "Yes — multi-agent"]
```

Save the choice as `multi_agent: true/false` in `~/.claude/env-config.yaml`.

If **multi-agent is enabled**, continue to Steps 2f (Discord) and 2g (Agent Mail).
If **single-agent**, skip both and go to Step 2h (Dev Types).

### 2f. Discord Webhook (only if multi_agent: true)

Use AskUserQuestion with options:

```
AskUserQuestion:
  question: "Configure Discord webhook for agent notifications?"
  options: ["Skip", "Enter webhook URL"]
```

If "Enter webhook URL" is selected, ask for the URL in a follow-up question.
If provided, save to `~/.config/development-skills/discord-webhook` with `chmod 600`.

### 2g. Agent Mail MCP (only if multi_agent: true)

Agent Mail enables inter-agent messaging, file reservations, and coordination. Uses the Rust implementation (`mcp_agent_mail_rust`) for reliability under concurrent workloads.

**Check if already configured:**

```bash
grep -q '"mcp-agent-mail"' ~/.mcp.json 2>/dev/null || grep -q '"mcp-agent-mail"' ~/.claude.json 2>/dev/null
```

**If already configured**, report it and move on.

**If not configured:**

1. **Check if `am` binary is installed:**
   ```bash
   command -v am
   ```

2. **If not installed**, install it:
   ```bash
   curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail_rust/main/install.sh" | bash
   ```
   This installs the `am` binary and sets up the server.

3. **Write or update `~/.mcp.json`:**

   Add the `mcp-agent-mail` entry:
   ```json
   {
     "mcp-agent-mail": {
       "command": "am",
       "args": ["mcp"]
     }
   }
   ```

   If `~/.mcp.json` already exists, use the same backup-validate-move procedure from Step 2d to merge the key safely. Do not overwrite other entries.

4. **Enable `mcp-agent-mail` in the project config.** Same as the Gitea MCP step — use the backup-validate-move procedure, then add `"mcp-agent-mail"` to the `enabledMcpjsonServers` array if not already present.

The Agent Mail server runs locally — no tokens or external auth needed for single-machine setups.

### 2h. Productivity Docs (optional)

The productivity-hooks plugin and skills rely on config documents at `~/.config/development-skills/`:

- **`repos.md`** — shorthand table mapping repo names to owner, local paths, and descriptions. Used by `resolve-repo.md` for all skill input parsing.
- **`infrastructure.md`** — IPs, domains, service URLs for the homelab environment. Used by `/investigate-bug`, `/qa-pr`, and injected on every prompt.
- **`deploy-config.md`** — deploy configuration table mapping repos to deploy workflows, dev URLs, chart names, and namespaces. Used by `/dev-deploy` and `/qa-pr`.

These live at `~/.config/development-skills/` (preferred) or fall back to the repo checkout.

```
AskUserQuestion:
  question: "Set up productivity docs? (repos.md project map and infrastructure.md reference — used by skills and injected on every prompt)"
  options: ["Yes, set them up", "Skip"]
```

**If yes:**

First, ensure the config directory exists:

```bash
mkdir -p ~/.config/development-skills/
```

**Re-apply mode:** If running in re-apply mode (Step 0), check if `repos.md` and `infrastructure.md` already exist and are non-empty at `~/.config/development-skills/`. If both exist, skip with a note: "Productivity docs already configured (repos.md + infrastructure.md)." and move on. Only re-prompt if one or both are missing.

#### repos.md

1. Check if `~/.config/development-skills/repos.md` already exists. If so, show it and ask if the user wants to keep or regenerate.

2. **Check if Gitea MCP is available** (was it configured in Step 2d?). If yes, auto-generate from Gitea. If no, fall back to manual entry.

3. **If Gitea MCP is available:** list all repos the user has access to via `mcp__gitea__list_my_repos`. Build a shorthand table:

   ```markdown
   # Project Map

   | Shorthand | Owner | Repo | Local path | Description |
   |-----------|-------|------|------------|-------------|
   | `homelab-setup` | `super-werewolves` | `homelab-setup` | `~/gitea-repos/homelab-setup` | Infrastructure as code |
   | `food-automation` | `super-werewolves` | `food-automation` | `~/gitea-repos/food-automation` | Grocy voice & photo assistant |
   | ... | ... | ... | ... | ... |
   ```

4. **If Gitea MCP is NOT available:** ask the user to provide repo names and owners manually via AskUserQuestion. Build the table from their input.

5. For each repo, infer the local path as `~/gitea-repos/{repo_name}`. If the directory exists, use the actual path. If not, use the default.

6. Present the generated table and ask the user to confirm or edit before saving.

7. Write to `~/.config/development-skills/repos.md` only. The canonical runtime location is `~/.config/development-skills/`.

#### infrastructure.md

1. Check if `~/.config/development-skills/infrastructure.md` already exists. If so, show a summary and ask if the user wants to keep or regenerate.

2. If generating or missing: check if a template exists at `~/development-skills/config/infrastructure.md`. If so, copy it to `~/.config/development-skills/infrastructure.md`.

3. If no template exists, create a minimal skeleton using values already collected in Step 2b:

   ```markdown
   # Infrastructure Reference

   ## Network

   | Name | Value |
   |------|-------|
   | Gitea Web URL | `{gitea_url}` |

   ## Services

   (Add your services here)
   ```

4. Tell the user they can edit `~/.config/development-skills/infrastructure.md` to add services, IPs, etc.

#### deploy-config.md

Deploy configuration maps repos to their deploy workflows, dev URLs, and Kubernetes resources. Used by `/dev-deploy` and `/qa-pr`.

1. Check if `~/.config/development-skills/deploy-config.md` already exists. If so, show it and ask if the user wants to keep, add a repo, or regenerate.

2. If generating fresh, create the file with header and any known repos. If Gitea MCP is available, list repos via `mcp__gitea__list_my_repos` and ask which ones have dev deploy workflows.

3. For each repo with a deploy workflow, ask the user for:
   - **Deploy workflow filename** (e.g., `deploy.yml`, `deploy.yaml`)
   - **Dev health URL** (e.g., `https://food-dev.apps.superwerewolves.ninja/api/health`)
   - **Dev base URL** (e.g., `https://food-dev.apps.superwerewolves.ninja`)
   - **Dev chart name** (e.g., `food-automation-dev`)
   - **Dev namespace** (e.g., `food-automation-dev`)
   - **Dev chart version pattern** (default: `0.1.0-dev.{run_number}`)

4. Write the deploy config table:

   ```markdown
   # Deploy Configuration

   | Repo | Deploy workflow | Dev health URL | Dev base URL | Dev chart name | Dev namespace | Dev chart version pattern |
   |------|----------------|----------------|--------------|----------------|---------------|--------------------------|
   | `multi-agent-coordinator` | `deploy.yml` | `https://agents.apps.superwerewolves.ninja/api/health` | `https://agents.apps.superwerewolves.ninja` | `multi-agent-coordinator-dev` | `multi-agent-coordinator-dev` | `0.1.0-dev.{run_number}` |
   | `food-automation` | `deploy.yaml` | `https://food-dev.apps.superwerewolves.ninja/api/health` | `https://food-dev.apps.superwerewolves.ninja` | `food-automation-dev` | `food-automation-dev` | `0.1.0-dev.{run_number}` |
   ```

5. Save to `~/.config/development-skills/deploy-config.md`.

**Targeted mode (`/setup-env deploy [repo]`):** If a specific repo is provided, read the existing `deploy-config.md`, ask for that repo's deploy details, and add or update only that repo's row. Do not prompt for other repos. If the file doesn't exist yet, create it with the header and the single repo row.

### 2i. Dev Types (optional)

Use AskUserQuestion with multi-select style options:

```
AskUserQuestion:
  question: "Which dev types do you want to set up? (select one, or skip)"
  options: ["Skip", "web-fullstack", "python", "go", "rust", "All of the above"]
```

If the user needs multiple (but not all), ask again after each selection until they say done, or use a follow-up question.

### 2j. Batch Confirmation

Present all collected values, then use AskUserQuestion:

```
AskUserQuestion:
  question: |
    Configuration:
    - Git: {name} <{email}>
    - Gitea: {url} (SSH: {ssh_status})
    - Gitea MCP: {configured/skipped}
    - Multi-agent: {enabled/disabled}
    - Agent Mail MCP: {configured/skipped/n/a}
    - Discord: {configured/not configured/n/a}
    - Productivity docs: {repos.md + infrastructure.md / skipped}
    - Dev types: {types or "none"}
  options: ["Confirm", "Edit a setting"]
```

If "Edit a setting" is selected, ask which setting to change.

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

- `SESSION-{agent_id}.md` files in each repo track active work context (auto-written by skills, cleared with `/clear-session`)
- Claude memory at ~/.claude/projects/ persists across sessions

## Skills Reference

| Skill | Purpose |
|-------|---------|
| `/start` | Full workspace orientation |
| `/do-the-thing [repo]` | Full dev loop (triage → implement → review → merge) |
| `/do-issue repo#N` | Implement a single issue |
| `/dev-deploy repo#N` | Deploy a PR or branch to dev |
| `/review-pr repo#N` | Code review a PR |
| `/gwt repo#N` | Generate acceptance criteria |
| `/test repo#N` | Plan and run E2E tests |
| `/status` | Catch-up summary |
| `/plan-the-thing` | Full planning pipeline |

## Config

- Repo shorthand: ~/.config/development-skills/config/repos.md
- Infrastructure: ~/.config/development-skills/config/infrastructure.md
```

### 4c. Migrate Old Symlink Installs

Before installing plugins, check for old symlink-based skill installations:

```bash
find ~/.claude/skills/ -maxdepth 1 -type l 2>/dev/null | head -5
```

If symlinks are found in `~/.claude/skills/`, ask the user:

```
AskUserQuestion:
  question: "Found old symlink-based skill installations in ~/.claude/skills/. Remove them? (Plugin-installed skills replace these)"
  options: ["Yes, clean up symlinks", "Keep both (may cause conflicts)"]
```

If "Yes, clean up symlinks":
```bash
find ~/.claude/skills/ -maxdepth 1 -type l -exec rm -f {} +
```

Report how many symlinks were removed. If no symlinks were found, skip silently.

### 4d. Install Plugins

Check if hook plugins and skill plugins are installed:

```bash
claude plugin list 2>/dev/null | grep -q "sound-notifications" || echo "Not installed: sound-notifications"
claude plugin list 2>/dev/null | grep -q "productivity-hooks" || echo "Not installed: productivity-hooks"
claude plugin list 2>/dev/null | grep -q "dev-workflow-hooks" || echo "Not installed: dev-workflow-hooks"
claude plugin list 2>/dev/null | grep -q "dev-workflow@" || echo "Not installed: dev-workflow (skill plugin)"
claude plugin list 2>/dev/null | grep -q "planning@" || echo "Not installed: planning (skill plugin)"
claude plugin list 2>/dev/null | grep -q "productivity@" || echo "Not installed: productivity (skill plugin)"
```

If any are not installed, offer to install them using AskUserQuestion:

```
AskUserQuestion:
  question: "Install plugins? (hook plugins = guardrails + Gitea context + sound, skill plugins = dev-workflow + planning + productivity skills)"
  options: ["Yes, install all", "Skip dev-workflow hooks (productivity + sound + skills only)", "Skip plugins"]
```

If yes:
```bash
claude plugin marketplace add ~/gitea-repos/development-skills 2>/dev/null || claude plugin marketplace add ~/development-skills 2>/dev/null
claude plugin install sound-notifications@super-werewolves-skills --scope user
claude plugin install productivity-hooks@super-werewolves-skills --scope user
claude plugin install dev-workflow-hooks@super-werewolves-skills --scope user
claude plugin install dev-workflow@super-werewolves-skills --scope user
claude plugin install planning@super-werewolves-skills --scope user
claude plugin install productivity@super-werewolves-skills --scope user
```

After plugin installation, sync shared libs to canonical path:

```bash
bash ~/gitea-repos/development-skills/scripts/sync-libs.sh
```

Report status of each plugin.

### 4e. Install Sound Dependencies (if sound-notifications installed)

The sound-notifications plugin needs audio utilities to produce sound. The requirements depend on the platform:

**WSL2 with WSLg:** Install `paplay` and freedesktop sound files. WSLg provides a PulseAudio server automatically.

```bash
# Check if WSLg PulseAudio is available
if [[ -S /mnt/wslg/PulseServer ]] || [[ -n "$PULSE_SERVER" ]]; then
    if ! command -v paplay &>/dev/null; then
        sudo apt-get install -y pulseaudio-utils sound-theme-freedesktop
    fi
fi
```

**WSL2 without WSLg (interop enabled):** No install needed — the plugin calls `powershell.exe` directly.

**Native Linux desktop:** Install PulseAudio utils if not present:

```bash
if ! command -v paplay &>/dev/null; then
    sudo apt-get install -y pulseaudio-utils sound-theme-freedesktop
fi
```

**macOS / Termux:** No install needed — uses built-in `afplay` / `termux-notification`.

After install, verify sound works:

```bash
paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null && echo "Sound works" || echo "Sound not working"
```

Report whether sound dependencies were installed and whether the test succeeded.

## Step 5: Verify Prerequisites

Run a comprehensive check and report results:

```
Prerequisites:
  Git identity:              {name} <{email}>
  Gitea reachable:           {yes/no}
  SSH key:                   {configured and working / generated (needs adding to Gitea) / missing}
  development-skills linked: {yes/no}
  Gitea MCP:                 {configured/not configured}
  Multi-agent:               {enabled/disabled}
  Agent Mail MCP:            {configured/not configured/n/a (single-agent)}
  Discord webhook:           {configured/not configured/n/a (single-agent)}
  Productivity docs:
    repos.md:                {configured/missing}
    infrastructure.md:       {configured/missing}
    deploy-config.md:        {configured/missing}

Plugins (hooks):
  sound-notifications:       {installed/not installed}
  productivity-hooks:        {installed/not installed}
  dev-workflow-hooks:        {installed/not installed}
  sound dependencies:        {paplay installed / not needed / missing}

Plugins (skills):
  dev-workflow:              {installed/not installed}
  planning:                  {installed/not installed}
  productivity:              {installed/not installed}

Tools:
  node:                      {version or missing}
  claude:                    {version or missing}
  {dev-type specific tools}
```

## Step 6: Save Config

Save the final configuration to `~/.claude/env-config.yaml`. Ensure these flags are included:

```yaml
multi_agent: true  # or false
ssh_key_generated: true  # or false — tracks whether a new SSH key was generated but may not yet be added to Gitea
```

Skills and libs read `multi_agent` to decide whether to use Agent Mail and agent coordination features. The `ssh_key_generated` flag persists across sessions so "Re-apply" can remind the user to add the key to Gitea.

## Step 7: Report Summary

```
## Environment Setup Complete

### Configured
- Git: {name} <{email}>
- Gitea: {url}
- SSH: {configured / newly generated}
- Gitea MCP: {configured / skipped}
- Multi-agent: {enabled / disabled}
- Agent Mail MCP: {configured / skipped / n/a}
- Discord: {configured / skipped / n/a}
- AGENTS.md: {created / already existed}
- Productivity docs: {repos.md + infrastructure.md configured / skipped}

### Installed
- {tools installed or skipped}

### Plugins
- {plugin status}
```

**If `ssh_key_generated` is true**, display the public key prominently so the user can add it to Gitea:

```
### SSH Key — Action Required

A new SSH key was generated. Add this public key to your Gitea account:

{gitea_url}/user/settings/keys

\`\`\`
{contents of ~/.ssh/id_ed25519_gitea.pub}
\`\`\`
```

Then continue with remaining next steps:

```
### Next Steps
- {if ssh_key_generated: "Add the SSH key above to Gitea, then test with: ssh -T -p 2222 gitea@{gitea_host}"}
- {if gitea_mcp skipped: "Create a Gitea API token at {gitea_url}/user/settings/applications and re-run /setup-env to configure Gitea MCP"}
- Run /start to begin your first session
```

## Rules

- **Always use AskUserQuestion with `options` for user prompts** — never ask free-text questions when a fixed set of choices is available. This gives users selectable options instead of requiring them to type responses.
- Never overwrite existing AGENTS.md or tracking files without asking
- Always check if tools are already installed before installing
- Report what was done vs skipped
- If any installation fails, report and continue — don't abort
- Never hardcode usernames, hosts, or credentials — use values from config
- Each sudo command must be a separate Bash call — never chain with &&
- Keep it lean — this is a homelab setup, not enterprise provisioning
