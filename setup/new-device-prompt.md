--- BEGIN PROMPT ---

You are bootstrapping a new device for the super-werewolves homelab workflow. The
device is **assumed to have LAN access** to the homelab — either physical LAN, or
WireGuard already up. If it doesn't, this prompt will detect that in Phase 0 and
redirect the human to `setup/wireguard-prompt.md` first.

Work through the phases below in order. After every phase, summarise what you did and
confirm the human is ready before moving on.

Homelab facts (current as of this prompt's last edit — verify before asserting):

- Gitea web: `http://git.home.superwerewolves.ninja` (LAN-only DNS via Pi-hole at `10.7.42.21`).
- Gitea SSH: `ssh://gitea@git.home.superwerewolves.ninja:2222`.
- Org: `super-werewolves` (most repos) and `selina` (a couple of personal repos).
- Default repo location: `~/gitea-repos/<repo>`.

## Phase 0 — Confirm LAN access

Before doing anything else, confirm this device can reach the homelab.

1. **Test LAN reachability.** Try DNS resolution and HTTP in one shot:

   ```
   getent hosts git.home.superwerewolves.ninja || nslookup git.home.superwerewolves.ninja
   curl -sS --connect-timeout 3 --max-time 5 -o /dev/null -w "%{http_code}\n" http://git.home.superwerewolves.ninja
   ```

   `getent` / `nslookup` should resolve to a `10.7.42.x` address, and `curl` should
   return `200` or `302`. If both pass → continue to Phase 1.

2. **If unreachable**, check for an existing-but-down WireGuard tunnel before sending
   the human to the WG prompt:

   - Linux/WSL: `command -v wg && sudo wg show 2>/dev/null` and `ip link show wg0 2>/dev/null`
   - macOS / Windows / Android: ask the human to check the WireGuard app's status panel.

3. **Branch on the result:**

   | State | Action |
   |-------|--------|
   | WG installed, tunnel down | Use AskUserQuestion: "WireGuard is installed but the tunnel is down. Bring it up?" → options: "Yes — `sudo wg-quick up wg0`", "I'll bring it up via the GUI app", "No — exit". After "yes", bring it up and re-run the Phase 0 reachability check. |
   | WG not installed | Tell the human: "This device has no LAN access and no WireGuard configured. Paste `setup/wireguard-prompt.md` to set that up first, then come back and re-paste this prompt." Stop. |
   | LAN reachable after retry | Continue to Phase 1. |
   | Still unreachable after WG up | Stop and help the human diagnose — don't push forward into a flow that will fail. |

## Phase 1 — Repo access (Gitea SSH)

The device can now reach Gitea. Set up SSH-based auth and clone `development-skills`.

1. **Read or set git identity.**

   ```
   git config --global user.name
   git config --global user.email
   ```

   If either is empty, ask the human and set them, plus useful defaults:

   ```
   git config --global user.name "<name>"
   git config --global user.email "<email>"
   git config --global init.defaultBranch main
   git config --global push.autoSetupRemote true
   ```

2. **Generate a Gitea-specific SSH key** if one doesn't already exist:

   ```
   test -f ~/.ssh/id_ed25519_gitea || ssh-keygen -t ed25519 -C "<email>" -f ~/.ssh/id_ed25519_gitea -N ""
   ```

3. **Configure `~/.ssh/config`** — append a stanza if not already present:

   ```
   Host git.home.superwerewolves.ninja
       HostName git.home.superwerewolves.ninja
       Port 2222
       User gitea
       IdentityFile ~/.ssh/id_ed25519_gitea
       IdentitiesOnly yes
       StrictHostKeyChecking accept-new
   ```

   Then `chmod 600 ~/.ssh/config`. Idempotent — if a `Host git.home.superwerewolves.ninja`
   block already exists, leave it alone.

4. **Stop and ask the human to add the SSH public key to Gitea:**

   ```
   Add this SSH key to Gitea at:

       http://git.home.superwerewolves.ninja/user/settings/keys

   Key (paste into the "Content" field):

       <contents of ~/.ssh/id_ed25519_gitea.pub>

   Reply "added" when done.
   ```

5. **Test SSH auth:**

   ```
   ssh -T -o ConnectTimeout=5 git@git.home.superwerewolves.ninja
   ```

   A successful auth returns a Gitea greeting on stderr ("Hi <user>! You've successfully
   authenticated...") with exit code 1 — that's expected. If auth fails, help the human
   verify the key was saved in Gitea, then retry.

6. **Clone `development-skills`:**

   ```
   mkdir -p ~/gitea-repos
   git clone ssh://gitea@git.home.superwerewolves.ninja:2222/super-werewolves/development-skills.git ~/gitea-repos/development-skills
   ```

## Phase 2 — Platform setup

Now that the repo is cloned, figure out what installer/helper this device needs.

1. **Identify the platform:**

   - `uname -s` → `Linux`, `Darwin`, or other.
   - If Linux: `cat /etc/os-release`. WSL detection via `grep -qi microsoft /proc/version`
     or `$WSL_DISTRO_NAME`.
   - If Darwin: `sw_vers`.
   - If `$PREFIX` matches `*com.termux*` → Termux on Android.
   - Windows-native PowerShell: `$env:OS == "Windows_NT"`.

2. **Look up the matching helper script** under `~/gitea-repos/development-skills/setup/`:

   - WSL2 / Ubuntu / Debian → `setup/wsl-sandbox/setup-linux.sh` (existing) installs core
     packages, Node, Claude CLI, Oh My Zsh, and dotfiles.
   - Other platforms (macOS, Windows-native, Termux, non-Debian Linux) → no per-platform
     helper exists yet (tracked in the homelab-setup standardize-scripts issue). For now,
     do step 3.

3. **Branch on what's available:**

   | State | Action |
   |-------|--------|
   | Helper exists for this platform | Use AskUserQuestion: "Run `<script path>` to install platform basics? It installs core packages, Node, Claude CLI, etc." → "Yes, run it now", "Show me what it does first", "Skip — already set up". |
   | No helper for this platform | Use AskUserQuestion: "No setup script exists for <platform>. Options:" → "Author one in setup/platform-helpers/setup-<platform>.<ext> and run it", "Author one but I'll review before running", "Skip — I'll handle platform basics manually". |

4. **If authoring a new helper script**, write it under
   `~/gitea-repos/development-skills/setup/platform-helpers/setup-<platform>.<ext>` on
   a worktree branch:

   ```
   git -C ~/gitea-repos/development-skills fetch origin
   git -C ~/gitea-repos/development-skills worktree add -b setup/<platform>-helper ~/gitea-repos/development-skills/.claude-worktrees/<platform>-helper origin/main
   ```

   The helper should mirror `setup/wsl-sandbox/setup-linux.sh` in shape — install the
   platform's package manager equivalents of: `git`, `node` (via nvm or platform native),
   `@anthropic-ai/claude-code` (npm global), `zsh`, `stow`, `qrencode`, `wireguard-tools`.
   It should **not** duplicate `/setup-env`'s job — defer Gitea MCP / Discord /
   productivity-docs / plugins to that skill.

   After authoring, commit on the worktree branch and tell the human to push + open a
   PR. Then run the script.

## Phase 3 — Hand off to /setup-env

The remaining configuration (Gitea MCP token, Discord webhook, productivity docs,
plugins, dev-type tools) is handled interactively by the `/setup-env` skill, which has
its own AskUserQuestion flow and shouldn't be driven from inside this prompt.

1. **Register the plugin marketplace:**

   ```
   claude plugin marketplace add ~/gitea-repos/development-skills
   ```

2. **Tell the human to exit this Claude session and run:**

   ```
   cd ~/gitea-repos/development-skills
   claude
   ```

   Then inside the new session: `/setup-env`.

3. **Final summary** to print:

   - Platform: `<detected platform>`
   - LAN access: yes (verified Phase 0)
   - Gitea SSH: working, key at `~/.ssh/id_ed25519_gitea`
   - `development-skills` cloned to `~/gitea-repos/development-skills`
   - Platform helper: `<ran|skipped|authored on branch X>`
   - Plugin marketplace registered
   - Next step: `cd ~/gitea-repos/development-skills && claude`, then `/setup-env`

## Rules

- Never display, copy, or transmit private keys (SSH or otherwise).
- Stop and wait at each "ask the human" point. Do not assume they did it.
- One sudo command per `Bash` call — never chain with `&&`.
- Verify dynamic facts (peer assignments, server pubkey, helper-script paths) by reading
  the current state of the repo or making API calls. Do not assert from this prompt's
  text alone — anything in here may be stale.
- If a step fails, stop and diagnose rather than skipping forward. The phases depend on
  each other.

--- END PROMPT ---
