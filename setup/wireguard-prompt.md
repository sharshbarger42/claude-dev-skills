You are bootstrapping WireGuard on a new device so it can reach the super-werewolves
homelab LAN. After this prompt finishes successfully, the human will paste the separate
`new-device-prompt.md` to continue Gitea + Claude setup.

Tunnel facts (current as of this prompt's last edit — verify before asserting):

- Server: WireGuard runs natively on OPNsense at `10.7.42.1`.
- Tunnel subnet: `10.7.99.0/24`. Personal-device peer pool is `10.7.99.10` – `10.7.99.99`.
- Public endpoint: `vpn.superwerewolves.ninja:51820` (Cloudflare DDNS → home WAN).
- LAN DNS: `10.7.42.21` (Pi-hole). All clients use this.
- Default tunnel scope: split tunnel — only LAN + tunnel subnets route through. Internet
  stays on the device's own connection. Full-tunnel (exit gateway) on OPNsense personal
  peers is a separate piece of work — check
  `super-werewolves/homelab-setup` open issues for "full-tunnel" before asserting it does
  or doesn't exist.

The human will need separate access to the OPNsense web UI (`https://10.7.42.1`) to add
the peer. If they're remote, they need someone on-LAN to do it for them, or they need to
add it from another device that's already on the VPN.

## Step 1 — Detect platform

Identify what you're running on before doing anything else.

- `uname -s` → `Linux`, `Darwin`, or other.
- If Linux: `cat /etc/os-release`. Check for WSL via `grep -qi microsoft /proc/version`
  or `$WSL_DISTRO_NAME`.
- If Darwin: `sw_vers`.
- If `$PREFIX` matches `*com.termux*` → Termux on Android.
- On Windows-native PowerShell, `$env:OS` is `Windows_NT`.

Branch on the result:

| Platform | Path |
|----------|------|
| Debian/Ubuntu Linux, or WSL2 | Continue to Step 2 — CLI flow. |
| macOS | Skip to Step 6 — GUI fallback. |
| Windows native | Skip to Step 6 — GUI fallback. |
| Termux on Android (rooted) | Continue to Step 2 — CLI flow. |
| Termux on Android (unrooted) | Skip to Step 6 — Android GUI fallback. |
| Anything else | Tell the human their platform isn't covered, dump the config values from Step 4 for them to plug into a hand-rolled setup, and stop. |

## Step 2 — Install tooling (CLI flow)

Use the platform's package manager. Each platform should end up with `wg`, `wg-quick`,
and a working `resolvconf` (or equivalent).

| Platform | Commands |
|----------|----------|
| Debian / Ubuntu / WSL2 | First `sudo apt-get update`, then in a separate `Bash` call: `sudo apt-get install -y wireguard wireguard-tools resolvconf qrencode`. The "one sudo per Bash call" rule (line 244) applies here — never chain with `&&`. |
| Termux (rooted) | `pkg install wireguard-tools` (root required for `wg-quick up`) |

For WSL2, also confirm the kernel has WireGuard support: `modinfo wireguard` should
succeed. Recent WSL2 kernels (5.10+) ship it built-in; older ones need
`WSL --update`.

## Step 3 — Generate a client keypair

Use restrictive perms. The keypair lives entirely inside root's process — `umask 077`
must be set inside the same `sudo` invocation that creates the file, otherwise root's
umask (often `0022`) wins and the private key ends up `0644`.

```
sudo install -d -m 700 /etc/wireguard
sudo bash -c 'umask 077 && cd /etc/wireguard && wg genkey | tee client_private.key | wg pubkey > client_public.key'
sudo chmod 600 /etc/wireguard/client_private.key
sudo chmod 644 /etc/wireguard/client_public.key
```

Show the human only the **public** key:

```
sudo cat /etc/wireguard/client_public.key
```

**Critical rule: only ever read from `*_public.key`.** Never `cat`, `echo`, `$(...)`,
or otherwise pipe `client_private.key` through the calling shell. When the private key
needs to land in a file, do the read-and-merge inside a single `sudo bash -c '...'` so
the value never crosses into the parent shell's process memory or argv (where `set -x`,
shell history, or harness command-echo could log it).

## Step 4 — Collect peer values (default-then-confirm)

Compute defaults first, then present them all at once and ask if any need to be changed.

Defaults to compute / hardcode:

| Value | Default | How to compute |
|-------|---------|----------------|
| Peer name | `$(hostname)` | Read from `hostname` command. Used in the OPNsense peer description. |
| Peer tunnel IP | *(needs human input)* | Tell the human to check
  `https://10.7.42.1 → VPN → WireGuard → Peers` for the next free IP in `10.7.99.10–99`,
  or to read from `homelab-setup/docs/network-configuration.md` § WireGuard → Clients.
  No reliable way to auto-pick from this side of the tunnel. |
| Server pubkey | *(needs human input)* | Tell the human to copy it from
  `https://10.7.42.1 → VPN → WireGuard → Instances → <server> → "Public Key"`. Do not
  hardcode a value — it has rotated before. |
| Endpoint | `vpn.superwerewolves.ninja:51820` | DDNS hostname. |
| AllowedIPs | `10.7.42.0/24, 10.7.99.0/24` | Split tunnel. Full-tunnel deferred to
  homelab-setup issue tracker (see top of prompt). |
| MTU | `1420` | Standard for WireGuard over typical residential WAN. |
| DNS | `10.7.42.21` | Pi-hole. |

Use AskUserQuestion with the question "Defaults — peer name `<hostname>`, endpoint
`vpn.superwerewolves.ninja:51820`, AllowedIPs split-tunnel (`10.7.42.0/24, 10.7.99.0/24`),
DNS `10.7.42.21`, MTU `1420`. Override anything?" and options "Use defaults (still need
tunnel IP + server pubkey from OPNsense)" and "Override one or more defaults".

Then ask for the unavoidable inputs (tunnel IP, server pubkey) and any overrides. Show
the final values back to the human and ask them to confirm before writing the config.

## Step 5 — Write the config

Construct the config inside a single `sudo bash -c '...'` so the private key is read
and substituted entirely within root's shell. The outer single-quotes prevent the
parent shell from expanding `$(cat ...)` — the substitution happens in the inner
shell, not the calling one. **Do not** fall back to `sudo tee <<EOF` with `$(sudo cat
client_private.key)` in the heredoc body — that routes the key through the parent
shell where `set -x`, history, or harness command-echo can log it.

```
sudo bash -c 'cat > /etc/wireguard/wg0.conf << CONFEOF
[Interface]
PrivateKey = $(cat /etc/wireguard/client_private.key)
Address = <peer_tunnel_ip>/32
MTU = <mtu>
DNS = <dns>

[Peer]
PublicKey = <server_pubkey>
AllowedIPs = <allowed_ips>
Endpoint = <endpoint>
PersistentKeepalive = 25
CONFEOF
chmod 600 /etc/wireguard/wg0.conf'
```

After writing, **do not `cat /etc/wireguard/wg0.conf`** — it contains the private key.
Safe diagnostics that don't expose the key: `sudo wg show wg0`, `ip addr show wg0`,
and (to inspect non-secret fields) `sudo grep -v '^PrivateKey' /etc/wireguard/wg0.conf`.

## Step 6 — GUI fallback (macOS / Windows / unrooted Android)

Skip the CLI install. Instead:

1. Tell the human which app to install:
   - macOS → WireGuard from the App Store
   - Windows → https://www.wireguard.com/install/
   - Android (unrooted) → Google Play "WireGuard" by WireGuard Development Team
2. Generate a `.conf` file in the user's home directory (no privileged location needed
   for GUI apps). Use the same template as Step 5. Same rule: do not echo the private
   key.
3. Tell the human to import the `.conf` into the GUI and toggle the tunnel on after
   Step 7.
4. Continue to Step 7.

## Step 7 — Add the peer in OPNsense

Print this block to the human, with the public key and tunnel IP filled in:

```
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

Then update super-werewolves/homelab-setup docs/network-configuration.md
§ WireGuard → Clients so the registry stays in sync.

Reply "added" when done.
```

Wait for the human to confirm. Do not bring the tunnel up before they do — the
handshake will fail and waste diagnostic time.

> **Future:** if `super-werewolves/homelab-setup` adds an `opnsense-wg-peer.yml`
> Ansible play (or a Gitea workflow that wraps it), this manual step can be replaced
> with a single automated invocation. Check the homelab-setup issue tracker for
> "opnsense WireGuard peer" before falling back to the manual flow.

## Step 8 — Bring the tunnel up

CLI platforms — bring the tunnel up first, then enable the unit only if systemd is
actually running (older WSL distros and Termux don't have systemd, and `systemctl
enable` will fail noisily on those):

```
sudo wg-quick up wg0
```

```
[ -d /run/systemd/system ] && sudo systemctl enable wg-quick@wg0 || echo "systemd not running — bring up the tunnel manually after reboot, or enable systemd in /etc/wsl.conf and reboot the distro."
```

WSL caveats: if `wg-quick up` fails with a `resolvconf` error, install `openresolv`
(`sudo apt-get install -y openresolv`) and retry. If DNS still misbehaves after the
tunnel is up, set `[network] generateResolvConf = false` in `/etc/wsl.conf` and write
`/etc/resolv.conf` manually pointing to `10.7.42.21`.

GUI platforms: tell the human to toggle the tunnel on in the WireGuard app, then come
back.

## Step 9 — Verify

Run four checks. Use the right tool for the platform detected in Step 1 — don't assume
the commands below run as-is on every shell.

| Check | What to verify | Linux / WSL / Termux | macOS | Windows-native |
|-------|----------------|----------------------|-------|----------------|
| Tunnel handshake | Recent handshake, non-zero rx/tx | `sudo wg show wg0` | `sudo wg show wg0` | WireGuard GUI status panel |
| LAN ping | Reachable | `ping -c 3 10.7.42.21` | `ping -c 3 10.7.42.21` | `Test-Connection 10.7.42.21` |
| DNS resolution | Resolves to a `10.7.42.x` address | `getent hosts git.home.superwerewolves.ninja` (or `nslookup git.home.superwerewolves.ninja`) | `dscacheutil -q host -a name git.home.superwerewolves.ninja` (or `dig git.home.superwerewolves.ninja`) | `Resolve-DnsName git.home.superwerewolves.ninja` |
| HTTP reachability | Status `200` or `302` | `curl -sS -o /dev/null -w "%{http_code}\n" http://git.home.superwerewolves.ninja` | `curl -sS -o /dev/null -w "%{http_code}\n" http://git.home.superwerewolves.ninja` | `Invoke-WebRequest -Uri http://git.home.superwerewolves.ninja -UseBasicParsing \| Select-Object -ExpandProperty StatusCode` |

If any fail, common causes — work through them in order:

1. Server pubkey wrong → re-copy from OPNsense Instances panel.
2. Peer not "Applied" yet → human forgot to click Apply at the top of the WG pages.
3. WAN firewall rule for UDP 51820 missing → check OPNsense `Firewall → Rules → WAN`.
4. Endpoint blocked by client-side network → try from a hotspot to confirm.
5. `AllowedIPs` mismatch → re-check the value in the config matches what was decided in
   Step 4.

## Step 10 — Final summary

Print:

```
WireGuard tunnel: up
  Platform:       <linux|wsl|macos|windows|termux>
  Peer name:      <peer_name>
  Tunnel IP:      <peer_tunnel_ip>
  Endpoint:       <endpoint>
  AllowedIPs:     <allowed_ips>

LAN reachable: yes (verified ping + DNS + HTTP).

Next step for the human:
  Paste the new-device bootstrap prompt (the `new-device-prompt.md` file alongside this
  one in development-skills/setup/) to continue with Gitea SSH + /setup-env.
```

## Rules

- Never display, copy, or transmit private keys (WireGuard or anything else).
- Never `cat /etc/wireguard/wg0.conf` after writing — it contains the private key.
- Stop and wait at the OPNsense peer-add step. Do not assume the human did it.
- One sudo command per `Bash` call — never chain with `&&`.
- If a step fails, stop and diagnose. Do not skip ahead.
