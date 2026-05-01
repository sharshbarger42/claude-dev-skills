You are bootstrapping a new device for the super-werewolves homelab workflow. The
device is **assumed to have LAN access** to the homelab — either physical LAN, or
WireGuard already up. If it doesn't, Phase 0 will detect that and ask the human to run
the separate WireGuard bootstrap prompt before continuing.

Work through the phases below in order. After every phase, summarise what you did and
confirm the human is ready before moving on.

Homelab facts (current as of this prompt's last edit — verify before asserting):

- Gitea web UI: `http://git.home.superwerewolves.ninja` (LAN-only DNS via Pi-hole at
  `10.7.42.21`). Use this for browser links.
- Gitea SSH endpoint: `gitea.int.superwerewolves.ninja:2222`. Use this for clone URLs,
  SSH config, and `ssh -T` tests. (The `*.int` host targets the Gitea LXC's IP
  directly; the `*.home` host targets the web UI through NPM. Different paths — don't
  cross them.)
- Org: `super-werewolves` (most repos) and `selina` (a couple of personal repos).
- Default repo location: `~/gitea-repos/<repo>`.

## Phase 0 — Confirm LAN access

Before doing anything else, confirm this device can reach the homelab. Use whatever
tools are appropriate for this platform — don't assume a specific shell.

1. **Test LAN reachability.** Two checks:

   - Resolve `git.home.superwerewolves.ninja` via the platform's DNS-lookup tool
     (whichever is available: `getent`, `nslookup`, `dig`, `Resolve-DnsName`, etc.).
     Expected result: a `10.7.42.x` address.
   - Make an HTTP GET to `http://git.home.superwerewolves.ninja/` (use whatever HTTP
     client is available: `curl`, `wget`, `Invoke-WebRequest`, etc.). Expected status:
     `200` or `302`.

   If both pass → continue to Phase 1.

2. **If unreachable**, check whether WireGuard is configured but the tunnel is down
   before falling back to the WG bootstrap prompt. The exact check depends on the
   platform — Linux/WSL has a `wg0` interface and the `wg` CLI; macOS / Windows /
   Android use the WireGuard GUI app and the human needs to look at it. Ask the human
   if you can't determine WG status programmatically.

3. **Branch on the result:**

   | State | Action |
   |-------|--------|
   | WG installed, tunnel down | **First confirm `wg0` is actually the homelab tunnel** — the user might have a separate WG to a work VPN on the same interface. Check the configured peer endpoint matches `vpn.superwerewolves.ninja` (try `sudo wg show wg0 endpoints`, or `grep -E '^Endpoint' /etc/wireguard/wg0.conf` if config is readable). If it's a different VPN, stop and tell the human — don't bring up an unrelated tunnel and loop. If it's the right tunnel, use AskUserQuestion: "WireGuard is configured but the tunnel is down. Bring it up?" → options: "Yes — bring it up now", "I'll bring it up via the GUI app", "No — exit". After "yes", use the platform's command to start the tunnel (e.g. `wg-quick up wg0` on Linux/WSL), then re-run the Phase 0 reachability check. |
   | WG not installed | Tell the human: "This device has no LAN access and no WireGuard configured. Run the WireGuard bootstrap prompt (`wireguard-prompt.md` in this same `setup/` directory) first to get on the VPN, then come back and re-paste this prompt." Stop. |
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

2. **Ensure `~/.ssh` exists with the right perms, then generate a Gitea-specific SSH
   key** if one doesn't already exist. Also reconstruct the public key from the private
   if the `.pub` file is missing (e.g. accidentally deleted on a previous run):

   ```
   install -d -m 700 ~/.ssh
   [ -f ~/.ssh/id_ed25519_gitea ] || ssh-keygen -t ed25519 -C "<email>" -f ~/.ssh/id_ed25519_gitea -N ""
   ```

   ```
   if [ -f ~/.ssh/id_ed25519_gitea ] && [ ! -f ~/.ssh/id_ed25519_gitea.pub ]; then ssh-keygen -y -f ~/.ssh/id_ed25519_gitea > ~/.ssh/id_ed25519_gitea.pub && chmod 644 ~/.ssh/id_ed25519_gitea.pub; fi
   ```

3. **Configure `~/.ssh/config`** — append a stanza if not already present:

   ```
   Host gitea.int.superwerewolves.ninja
       HostName gitea.int.superwerewolves.ninja
       Port 2222
       User gitea
       IdentityFile ~/.ssh/id_ed25519_gitea
       IdentitiesOnly yes
       StrictHostKeyChecking accept-new
   ```

   Then `chmod 600 ~/.ssh/config`. Idempotent — if a `Host gitea.int.superwerewolves.ninja`
   block already exists, **read it and verify the `Port` line is `2222`**. If the existing
   block has a different port, stop and ask the human how to reconcile (the `ssh -T` test
   in step 5 will silently fall back to port 22 otherwise).

   `StrictHostKeyChecking accept-new` silently TOFUs the Gitea host key on first connect.
   The threat model on a homelab LAN is weak (an attacker on the LAN already has bigger
   reach), but for a paranoid run the human can verify by fetching the offered key
   (`ssh-keyscan -p 2222 -t ed25519 gitea.int.superwerewolves.ninja | ssh-keygen -lf -`)
   and comparing the fingerprint to `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`
   from the Gitea host.

4. **Stop and ask the human to add the SSH public key to Gitea:**

   ```
   Add this SSH key to Gitea at:

       http://git.home.superwerewolves.ninja/user/settings/keys

   Key (paste into the "Content" field):

       <contents of ~/.ssh/id_ed25519_gitea.pub>

   Reply "added" when done.
   ```

5. **Test SSH auth.** Pass `-p 2222` explicitly (don't rely on the SSH config block from
   step 3 to supply the port — if a stale stanza exists, ssh silently falls back to 22).
   Bump the timeout to 10s and retry once on failure, since Gitea sometimes has a brief
   cache delay right after a key is added in the web UI:

   ```
   ssh -T -p 2222 -o ConnectTimeout=10 -o NumberOfPasswordPrompts=0 gitea@gitea.int.superwerewolves.ninja || ( sleep 3 && ssh -T -p 2222 -o ConnectTimeout=10 -o NumberOfPasswordPrompts=0 gitea@gitea.int.superwerewolves.ninja )
   ```

   A successful auth returns a Gitea greeting on stderr ("Hi <user>! You've successfully
   authenticated...") with exit code 1 — that's expected. If both attempts fail, help
   the human verify the key was saved in Gitea, then retry.

6. **Clone `development-skills`:**

   ```
   mkdir -p ~/gitea-repos
   git clone ssh://gitea@gitea.int.superwerewolves.ninja:2222/super-werewolves/development-skills.git ~/gitea-repos/development-skills
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
   | No helper for this platform | Tell the human: "No setup script exists for `<platform>`. Authoring helper scripts for new platforms is tracked in `super-werewolves/development-skills#158` and belongs in a normal `/do-issue` loop, not in this bootstrap. For now, install the equivalents of `setup/wsl-sandbox/setup-linux.sh`'s outputs manually using the platform's package manager: `git`, Node.js (via the platform's preferred path), the Claude CLI (`npm install -g @anthropic-ai/claude-code`), `zsh`, `stow`, `qrencode`. Then continue to Phase 3." Stop offering to author the script here — it's out of scope. |

## Phase 3 — Hand off to /setup-env

The remaining configuration (Gitea MCP token, Discord webhook, productivity docs,
plugins, dev-type tools) is handled interactively by the `/setup-env` skill, which has
its own AskUserQuestion flow and shouldn't be driven from inside this prompt.

1. **Register the plugin marketplace, then verify it took:**

   ```
   claude plugin marketplace add ~/gitea-repos/development-skills
   ```

   ```
   claude plugin marketplace list
   ```

   The output should include an entry for the local `development-skills` checkout. If
   it doesn't, stop — there's likely a manifest issue at
   `~/gitea-repos/development-skills/.claude-plugin/marketplace.json`. Don't tell the
   human to re-launch into `/setup-env` until the marketplace registration is
   confirmed, or `/setup-env` will fail when it tries to install plugins.

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
