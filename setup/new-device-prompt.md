# New Device Bootstrap Prompt

Paste the section below (between the `--- BEGIN PROMPT ---` and `--- END PROMPT ---`
markers) into a fresh `claude` session on a new device. Claude will walk through four
phases:

0. **Platform detect** — figure out what OS/shell this is. If Linux or WSL, continue
   inline. Otherwise, offer to author a tailored setup script for this OS in
   `setup/setup-<os>.sh` (or `.ps1`), commit it, and adapt the rest of the flow
   accordingly.
1. **WireGuard** — install tools, generate a keypair, write the client config, wait for
   the human to add the peer on OPNsense, bring the tunnel up, verify LAN reachability.
2. **Gitea repo access** — generate an SSH key, wait for the human to add it to Gitea,
   clone `development-skills` to `~/gitea-repos/`.
3. **Hand off** — register the plugin marketplace and tell the human to run
   `/setup-env` to finish configuration.

## Prerequisites

- Claude Code installed (`npm install -g @anthropic-ai/claude-code`).
- A user account with admin/sudo rights (for installing packages and writing WG config).
- The endpoint `vpn.superwerewolves.ninja:51820` reachable from this device's network.
- You (the human) need access to the OPNsense web UI at `https://10.7.42.1` to add the
  peer. If you're off-LAN setting this device up, do it from another device that's
  already on the VPN.

## Pick the peer assignment before starting

Have these values ready — Claude will ask for them one at a time:

| Value | Where to get it | Notes |
|-------|-----------------|-------|
| Peer name | You decide | e.g. `selina-newlaptop`. Used as the description in the OPNsense peer entry and as a comment in any docs you update. |
| Peer tunnel IP | Pick from the unused range | `10.7.99.10–99`. Check `homelab-setup/docs/network-configuration.md` § WireGuard for current allocations. |
| Server pubkey | OPNsense → `VPN → WireGuard → Instances` | The WG instance's public key. Copy it from the UI rather than this doc — it has rotated before. |
| Endpoint | DDNS hostname | `vpn.superwerewolves.ninja:51820` (Cloudflare DDNS → home WAN IP). |

> **Note:** This prompt targets OPNsense-native WireGuard (the new path). The legacy
> friend VPN on LXC 108 (`10.10.10.0/24`) is documented in `homelab-setup/docs/vpn-setup.md`
> and is being retired. Don't use this prompt to add friends — those still go on LXC 108
> until #53 / OPNsense friend-tier work lands.

---

--- BEGIN PROMPT ---

You are bootstrapping a brand-new device for the super-werewolves homelab workflow.
Work through the phases below in order. Do not skip ahead. After every phase, summarise
what you did and confirm the human is ready before moving on.

## Phase 0 — Platform detection

Detect what OS, shell, and package manager this device has before doing anything else.

1. **Identify the platform.** In rough order of detection:
   - `uname -s` → `Linux`, `Darwin`, or other
   - If Linux: `cat /etc/os-release`, and check for WSL via
     `grep -qi microsoft /proc/version` or `$WSL_DISTRO_NAME`
   - If Darwin: `sw_vers` for macOS version
   - If `$PREFIX` matches `*com.termux*` → Termux on Android
   - On Windows-native (when run from PowerShell wrappers), `$env:OS` will be
     `Windows_NT`

2. **Decide what to do** based on the result:

   | Platform | Action |
   |----------|--------|
   | Linux (Debian/Ubuntu derivative) | Continue inline at Phase 1. |
   | WSL2 (any distro) | Continue inline at Phase 1. WSL-specific notes are called out where they apply. |
   | macOS | Stop the inline flow. Go to step 3 (offer to author a setup script). |
   | Windows native (PowerShell) | Stop the inline flow. Go to step 3. |
   | Termux (Android) | Stop the inline flow. Go to step 3. |
   | Linux non-Debian (Arch, Fedora, Alpine, etc.) | Stop the inline flow. Go to step 3 — the inline flow assumes `apt-get`. |
   | Anything else | Stop, explain that the inline flow is Linux/WSL/Debian-only, and offer step 3. |

3. **Offer to author a tailored setup script.** Use AskUserQuestion:

   ```
   AskUserQuestion:
     question: "This device is <platform>. The inline flow assumes Debian/Ubuntu Linux. Would you like me to write a tailored setup script for <platform> instead? It'll be saved to development-skills/setup/setup-<platform>.{sh|ps1} and run instead of the inline Phase 1."
     options:
       - "Yes — write the script, commit it, then run it"
       - "Yes — write the script, but I'll review and run it manually"
       - "No — I'll set up WireGuard manually outside this prompt; skip to Phase 2"
       - "No — abort entirely"
   ```

4. **If "write the script"**, the script must:
   - Use the platform's native package manager (Homebrew on macOS, `pkg` on Termux,
     `pacman`/`dnf`/`apk` on non-Debian Linux, `winget` or chocolatey on Windows-native).
   - Install: `wireguard-tools` (or platform equivalent), `git`, `openssh`, `qrencode`
     (optional), and Node.js if Claude CLI is missing.
   - Generate a WireGuard keypair under the platform's standard config location:
     - Linux/WSL: `/etc/wireguard/`
     - macOS: `/usr/local/etc/wireguard/` (Intel) or `/opt/homebrew/etc/wireguard/`
       (Apple Silicon)
     - Windows: `%ProgramData%\WireGuard\Configurations\` (use the WG GUI for tunnel
       management — the script just generates the config file)
     - Termux: `$PREFIX/etc/wireguard/`
   - Print the **public key only** with copy-paste-ready instructions (never private).
   - Pause for the human to add the peer in OPNsense (same as Phase 1 step 6 below).
   - Bring the tunnel up using the platform-native command:
     - Linux/WSL: `wg-quick up wg0`
     - macOS: `wg-quick up wg0` (Homebrew installs it) **or** instruct to import into
       the WireGuard.app
     - Windows: instruct to import the `.conf` into the WireGuard GUI (no CLI tunnel
       management on Windows-native)
     - Termux: `wg-quick up wg0` after `pkg install wireguard-tools` (note: requires
       root on Android, which is uncommon — fall back to using the WireGuard Android
       app if not rooted)
   - Verify LAN reachability with `ping 10.7.42.21` and a curl against
     `http://git.home.superwerewolves.ninja`.

   Before writing the script, find the development-skills repo on this device. Try in
   order: `~/gitea-repos/development-skills`, `~/development-skills`, the path from
   `claude plugin marketplace list` if it shows the marketplace registered, or
   `pwd` if the human says they ran the prompt from the repo. If none of these exist
   yet (because we haven't cloned the repo yet — that's Phase 2), write the script to
   `~/setup-<platform>.<ext>` instead and tell the human to move it into the repo
   later when they have access.

   When writing into the repo, use a worktree branched from `origin/main`:
   `git -C <repo> fetch origin && git -C <repo> worktree add -b new-device/<platform>-setup <path> origin/main`.
   After committing, surface the branch + remind the human to push and open a PR.

5. **If "set up manually then skip to Phase 2"**, skip the rest of Phase 1 entirely. The
   human is on their own for WG; just wait for them to confirm "tunnel up, can ping
   `10.7.42.21`" before proceeding.

6. **If "abort"**, stop and exit.

For all remaining phases below, treat "this device" as Linux or WSL. The platform
script (if written in step 4) handles the equivalent steps for other platforms.

## Phase 1 — WireGuard client (Linux / WSL)

The home Gitea is LAN-only (`git.home.superwerewolves.ninja` resolves via Pi-hole at
`10.7.42.21`), so this device must be on the WireGuard tunnel before it can clone any
repo. WireGuard runs natively on OPNsense at `10.7.42.1`; the public endpoint is
`vpn.superwerewolves.ninja:51820` and the tunnel subnet is `10.7.99.0/24`.

1. **Install WireGuard tooling** (and `qrencode` for optional QR code rendering):
   ```bash
   sudo apt-get update
   sudo apt-get install -y wireguard wireguard-tools resolvconf qrencode
   ```
   On WSL2, also confirm the kernel has WireGuard support: `modinfo wireguard` should
   succeed. Recent WSL2 kernels (5.10+) ship it built-in.

2. **Generate a client keypair** with restrictive perms:
   ```bash
   sudo mkdir -p /etc/wireguard
   sudo chmod 700 /etc/wireguard
   ( umask 077 && wg genkey | sudo tee /etc/wireguard/client_private.key | wg pubkey | sudo tee /etc/wireguard/client_public.key > /dev/null )
   ```
   Show the human only the **public** key (`sudo cat /etc/wireguard/client_public.key`).
   The private key must never be displayed, copied, or transmitted.

3. **Ask the human** (use AskUserQuestion where it fits, free-text where it doesn't):
   - Peer name (e.g. `selina-newlaptop`)
   - Peer tunnel IP — must be in `10.7.99.10–99` range and unused. Tell them to check
     `homelab-setup/docs/network-configuration.md` § WireGuard for current allocations
     (or the OPNsense UI: `VPN → WireGuard → Peers`).
   - Server public key — instruct them to copy it from OPNsense:
     `VPN → WireGuard → Instances → <wg server> → "Public Key"`. Don't accept a
     hardcoded value; the key has rotated before.
   - Endpoint host (default `vpn.superwerewolves.ninja:51820`).

4. **Write `/etc/wireguard/wg0.conf`.** Read the private key from
   `/etc/wireguard/client_private.key` and inline it — do not echo it to the terminal.
   Use this template, substituting the human's answers:

   ```ini
   [Interface]
   PrivateKey = <contents of /etc/wireguard/client_private.key>
   Address = <peer_tunnel_ip>/32
   MTU = 1420
   DNS = 10.7.42.21

   [Peer]
   PublicKey = <server_pubkey>
   AllowedIPs = 10.7.42.0/24, 10.7.99.0/24
   Endpoint = vpn.superwerewolves.ninja:51820
   PersistentKeepalive = 25
   ```

   This is a **split tunnel** — only LAN and tunnel subnets route through the VPN.
   Internet stays on the device's own connection. If the human explicitly wants
   full-tunnel for this device, replace `AllowedIPs` with `0.0.0.0/0` — but ask before
   doing so, and warn that there is currently no exit gateway configured for personal
   peers on OPNsense (the CH-exit path lives on legacy LXC 108).

   Write the file via a heredoc piped through `sudo tee /etc/wireguard/wg0.conf > /dev/null`,
   then `sudo chmod 600 /etc/wireguard/wg0.conf`. After writing, do **not** `cat` the
   file back — it contains the private key.

5. **Stop and ask the human to add the peer in OPNsense.** Show them this block, with
   the public key and tunnel IP filled in:

   ```text
   The new device's WireGuard public key is:

       <client_public_key>

   In the OPNsense web UI (https://10.7.42.1):

     1. VPN → WireGuard → Peers → "+" (Add)
     2. Name: <peer_name>
     3. Public key: <client_public_key>
     4. Allowed IPs: <peer_tunnel_ip>/32
     5. Save
     6. VPN → WireGuard → Instances → edit the server instance
        → add this new peer to the "Peers" list → Save
     7. Apply (button at top of the WireGuard pages)

   Then update homelab-setup/docs/network-configuration.md § WireGuard → Clients
   so the registry stays in sync.

   Reply "added" when done.
   ```

   Wait for confirmation. Do not bring the tunnel up until the human confirms.

   > **Future:** if the homelab gains an `opnsense-wg-peer.yml` Ansible play (or a
   > Gitea workflow that wraps it), this manual step can be replaced with a single
   > automated invocation. As of this prompt, no such automation exists.

6. **Bring the tunnel up:**
   ```bash
   sudo wg-quick up wg0
   sudo systemctl enable wg-quick@wg0
   ```
   If `wg-quick up` fails with a `resolvconf` error on WSL, install `openresolv`
   (`sudo apt-get install -y openresolv`) and retry. If DNS resolution still misbehaves
   on WSL after the tunnel is up, advise the human to set
   `[network] generateResolvConf = false` in `/etc/wsl.conf` and write `/etc/resolv.conf`
   manually pointing to `10.7.42.21`.

7. **Verify LAN reachability:**
   ```bash
   sudo wg show wg0
   ping -c 3 10.7.42.21
   getent hosts git.home.superwerewolves.ninja
   curl -sS --max-time 5 -o /dev/null -w "%{http_code}\n" http://git.home.superwerewolves.ninja
   ```
   `wg show` should show a recent handshake and non-zero rx/tx. The ping should
   succeed. The `getent` lookup should resolve (Pi-hole is reachable). The `curl`
   should return `200` or `302`. If any of these fail, stop and help the human
   diagnose before moving on — common causes: wrong server pubkey, peer not yet
   "Applied" in OPNsense UI, or WAN firewall rule for UDP 51820 missing.

## Phase 2 — Gitea repo access

Now the device can reach Gitea over the tunnel. Set up SSH-based access and clone
`development-skills`.

1. **Generate an SSH key** for Gitea (separate from any existing key on this device):
   ```bash
   ssh-keygen -t ed25519 -C "<git_email>" -f ~/.ssh/id_ed25519_gitea -N ""
   ```
   Ask the human for `<git_email>` if not already set in `git config --global user.email`.

2. **Configure `~/.ssh/config`** — append (don't overwrite) a stanza for the Gitea host.
   The Gitea SSH endpoint is on port 2222. The host alias should match the URL the
   user clones with:

   ```
   Host git.home.superwerewolves.ninja
       HostName git.home.superwerewolves.ninja
       Port 2222
       User gitea
       IdentityFile ~/.ssh/id_ed25519_gitea
       IdentitiesOnly yes
       StrictHostKeyChecking accept-new
   ```

   Then `chmod 600 ~/.ssh/config`. Idempotent: if a `Host git.home.superwerewolves.ninja`
   block already exists, leave it alone and tell the human.

3. **Surface the SSH public key** and stop:

   ```text
   Add this SSH key to Gitea at:

       http://git.home.superwerewolves.ninja/user/settings/keys

   Key (paste into the "Content" field):

       <contents of ~/.ssh/id_ed25519_gitea.pub>

   Reply "added" when done.
   ```

4. **Test SSH auth:**
   ```bash
   ssh -T -o ConnectTimeout=5 git@git.home.superwerewolves.ninja
   ```
   A successful auth returns a Gitea greeting on stderr ("Hi <user>! You've successfully
   authenticated...") with exit code 1 — that's expected. If auth fails, help the
   human verify the key is registered in Gitea, then retry.

5. **Clone `development-skills`:**
   ```bash
   mkdir -p ~/gitea-repos
   git clone ssh://gitea@git.home.superwerewolves.ninja:2222/super-werewolves/development-skills.git ~/gitea-repos/development-skills
   ```

6. **Set git identity** if not already set:
   ```bash
   git config --global user.name "<name>"
   git config --global user.email "<email>"
   git config --global init.defaultBranch main
   git config --global push.autoSetupRemote true
   ```

## Phase 3 — Hand off to /setup-env

The remaining configuration (Gitea MCP, Discord, productivity docs, plugins, dev tools)
is handled interactively by the `/setup-env` skill, which has its own AskUserQuestion
flow and shouldn't be driven from inside this prompt.

1. **Register the plugin marketplace:**
   ```bash
   claude plugin marketplace add ~/gitea-repos/development-skills
   ```

2. **Tell the human to exit this Claude session and run:**
   ```bash
   cd ~/gitea-repos/development-skills
   claude
   ```
   Then inside the new session: `/setup-env`.

3. **Final summary** to print:
   - Platform: Linux/WSL (or whatever Phase 0 detected)
   - WireGuard tunnel: up, peer IP `<peer_tunnel_ip>`
   - Gitea SSH: working, key at `~/.ssh/id_ed25519_gitea`
   - `development-skills` cloned to `~/gitea-repos/development-skills`
   - Plugin marketplace registered
   - Next step for the human: `cd ~/gitea-repos/development-skills && claude`, then `/setup-env`

## Rules for this whole flow

- **Never display, copy, or transmit private keys** — WireGuard private key, SSH private
  key, or any token. Only ever show public counterparts.
- **Never `cat` `/etc/wireguard/wg0.conf`** after writing — it contains the private key.
- **Stop and wait at each "ask the human" point.** Do not assume they did it.
- **One sudo command per `Bash` call** — never chain with `&&`.
- **If a step fails, stop and diagnose** rather than skipping forward. The phases depend
  on each other: no tunnel means no Gitea; no Gitea means no repo; no repo means no
  `/setup-env`.

--- END PROMPT ---
