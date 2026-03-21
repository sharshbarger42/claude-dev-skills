---
name: dns-check
description: Verify Pi-hole DNS records and local domain resolution.
disable-model-invocation: true
---

# DNS Check

## Instructions

Verify that Pi-hole DNS is working and local domains resolve correctly.

### Step 1: Check Pi-hole status
```bash
ssh proxmox "sudo pct exec 105 -- pihole status"
```

### Step 2: Verify local DNS resolution
Test that `*.home.superwerewolves.ninja` resolves to the NPM reverse proxy (192.168.0.140):

```bash
dig +short jellyfin.home.superwerewolves.ninja @192.168.0.225
dig +short tandoor.home.superwerewolves.ninja @192.168.0.225
dig +short grocy.home.superwerewolves.ninja @192.168.0.225
dig +short immich.home.superwerewolves.ninja @192.168.0.225
dig +short pihole.home.superwerewolves.ninja @192.168.0.225
dig +short git.home.superwerewolves.ninja @192.168.0.225
dig +short uptime.home.superwerewolves.ninja @192.168.0.225
```

All should resolve to `192.168.0.140` (NPM).

### Step 3: Check dnsmasq config
```bash
ssh proxmox "sudo pct exec 105 -- cat /etc/dnsmasq.d/02-local-wildcard-dns.conf"
```

Should contain: `address=/home.superwerewolves.ninja/192.168.0.140`

### Step 4: Present results
- Pi-hole status (running/stopped, blocking enabled/disabled)
- DNS resolution table: domain → resolved IP → expected IP → pass/fail
- Any mismatches flagged prominently
- If `dig` isn't available locally, use `ssh proxmox "sudo pct exec 105 -- nslookup <domain> 127.0.0.1"` as fallback

Keep it concise. No fluff.
