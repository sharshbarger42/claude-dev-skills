---
name: dns-check
description: Verify Pi-hole DNS records and local domain resolution.
disable-model-invocation: true
---

# DNS Check

## Infrastructure Reference
!`cat $HOME/gitea-repos/development-skills/config/infrastructure.md`

## Instructions

Verify that Pi-hole DNS is working and local domains resolve correctly. Use the IPs and domains from the infrastructure reference above.

### Step 1: Check Pi-hole status
```bash
ssh proxmox "sudo pct exec 105 -- pihole status"
```

### Step 2: Verify local DNS resolution
Test that `*.home.superwerewolves.ninja` resolves to the NPM reverse proxy IP (from the infrastructure table):

```bash
dig +short jellyfin.home.superwerewolves.ninja @<PI_HOLE_DNS_IP>
dig +short tandoor.home.superwerewolves.ninja @<PI_HOLE_DNS_IP>
dig +short grocy.home.superwerewolves.ninja @<PI_HOLE_DNS_IP>
dig +short immich.home.superwerewolves.ninja @<PI_HOLE_DNS_IP>
dig +short pihole.home.superwerewolves.ninja @<PI_HOLE_DNS_IP>
dig +short git.home.superwerewolves.ninja @<PI_HOLE_DNS_IP>
dig +short uptime.home.superwerewolves.ninja @<PI_HOLE_DNS_IP>
```

All should resolve to the NPM IP from the infrastructure table.

### Step 3: Check dnsmasq config
```bash
ssh proxmox "sudo pct exec 105 -- cat /etc/dnsmasq.d/02-local-wildcard-dns.conf"
```

Should contain: `address=/home.superwerewolves.ninja/<NPM_IP>`

### Step 4: Present results
- Pi-hole status (running/stopped, blocking enabled/disabled)
- DNS resolution table: domain → resolved IP → expected IP → pass/fail
- Any mismatches flagged prominently
- If `dig` isn't available locally, use `ssh proxmox "sudo pct exec 105 -- nslookup <domain> 127.0.0.1"` as fallback

Keep it concise. No fluff.
