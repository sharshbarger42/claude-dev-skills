---
name: tailnet-check
description: Check that all services are reachable via their FQDN through NPM.
disable-model-invocation: true
---

# Tailnet Service Check

## Infrastructure Reference
!`cat $HOME/gitea-repos/development-skills/config/infrastructure.md`

## Instructions

Verify all homelab services are accessible via their public FQDN (*.home.superwerewolves.ninja) through NPM.

### Step 1: Run the check
- Execute `$HOME/gitea-repos/homelab-setup/check-tailnet.sh` via Bash
- This checks DNS resolution, NPM reachability, FQDN access for all 16 services, and SSL certificate validity
- Unlike `/service-check` (which tests direct LAN IPs via SSH to Proxmox), this tests the full client path: DNS → NPM → backend

### Step 2: Present results
- Summarize in a clean table:
  - DNS: wildcard resolving to NPM?
  - NPM gateway: admin UI reachable?
  - Per-service: HTTP code and pass/fail
  - SSL: certificate expiry status
- Highlight any failures prominently

### Step 3: Suggest actions
- DNS failure → check Pi-hole Local DNS records
- NPM unreachable → check CT 106 status: `ssh proxmox-root "ssh root@192.168.0.204 'pct status 106'"`
- Individual service failure → compare with `/service-check` to determine if the issue is the backend (direct IP fails) or the proxy (direct IP works but FQDN fails)
- SSL expiring → check NPM certificate renewal

Keep it concise. No fluff.
