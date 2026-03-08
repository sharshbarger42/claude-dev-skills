# Infrastructure Reference

IPs, domains, and service URLs for the homelab environment.

## Network

| Name | Value |
|------|-------|
| Domain | `*.home.superwerewolves.ninja` |
| Gitea Web URL | `http://git.home.superwerewolves.ninja` |
| Gitea API URL | `http://git.home.superwerewolves.ninja/api/v1` |
| Gitea SSH | `ssh://gitea@192.168.0.174:2222` |
| Pi-hole DNS IP | `192.168.0.225` |
| NPM (Nginx Proxy Manager) IP | `192.168.0.140` |

## Proxmox Cluster

| Node | IP |
|------|-----|
| PVE1 | `192.168.0.147` |
| PVE2 | `192.168.0.204` |
| PVE3 | `192.168.0.205` |

## Services

| Service | IP:Port | LXC/VM ID | Node |
|---------|---------|-----------|------|
| JellyFin | `192.168.0.160:8096` | LXC 104 | pve1 |
| Pi-hole | `192.168.0.225` | LXC 105 | pve1 |
| NPM | `192.168.0.140` | LXC 106 | pve2 |
| ErsatzTV | `192.168.0.161:8409` | LXC 107 | pve1 |
| Grocy | `192.168.0.172` | — | — |
| Tandoor | `192.168.0.207:8002` | — | — |
| TrueNAS | `192.168.0.169` | — | — |
| Home Assistant | — | — | — |
| Immich | — | — | — |
| AudioBookShelf | — | — | — |
| Paperless NGX | — | — | — |
| Uptime Kuma | — | — | — |
| WireGuard | — | — | — |
| Authentik (SSO) | — | — | — |
| Flywheel | — | — | — |

## Notifications

| Name | Value |
|------|-------|
| Discord webhook file | `~/.config/development-skills/discord-webhook` |
| Agent Mail thread prefix | `active-work-{repo}` |
| Agent registry thread | `agent-registry` |

The Discord webhook file should contain a single line with the Discord webhook URL. Create it with `chmod 600`. If the file does not exist, Discord notifications are silently skipped.

## DNS Check Domains

These subdomains should all resolve to the NPM IP (`192.168.0.140`) via Pi-hole:

- `jellyfin.home.superwerewolves.ninja`
- `tandoor.home.superwerewolves.ninja`
- `grocy.home.superwerewolves.ninja`
- `immich.home.superwerewolves.ninja`
- `pihole.home.superwerewolves.ninja`
- `git.home.superwerewolves.ninja`
- `uptime.home.superwerewolves.ninja`
