---
name: media-report
description: Report JellyFin and ErsatzTV stats and health.
disable-model-invocation: true
---

# Media Report

## Infrastructure Reference
!`cat $HOME/gitea-repos/development-skills/config/infrastructure.md`

## Instructions

Check the health and stats of media services. Use IPs and LXC IDs from the infrastructure reference above.

### Step 1: JellyFin health
```bash
curl -s http://<JELLYFIN_IP>/health
curl -s http://<JELLYFIN_IP>/System/Info/Public
```

Extract: server name, version, startup status.

### Step 2: JellyFin library stats
```bash
curl -s http://<JELLYFIN_IP>/Items/Counts -H "X-Emby-Token: <key>"
```

If no API key is available, note that library stats require authentication and skip.

### Step 3: ErsatzTV health
```bash
curl -s http://<ERSATZTV_IP>/health 2>/dev/null || curl -s -o /dev/null -w "%{http_code}" http://<ERSATZTV_IP>
```

Check if ErsatzTV is responding.

### Step 4: Container status
```bash
ssh proxmox "pvesh get /nodes/<JELLYFIN_NODE>/lxc/<JELLYFIN_LXCID>/status/current --output-format json" 2>/dev/null
ssh proxmox "pvesh get /nodes/<ERSATZTV_NODE>/lxc/<ERSATZTV_LXCID>/status/current --output-format json" 2>/dev/null
```

Extract CPU/memory usage for JellyFin and ErsatzTV containers.

### Step 5: Present results
- Service health: up/down for each
- JellyFin: version, library counts (if available)
- ErsatzTV: status
- Resource usage for both containers
- Flag any issues

Keep it concise. No fluff.
