---
name: media-report
description: Report JellyFin and ErsatzTV stats and health.
disable-model-invocation: true
---

# Media Report

## Instructions

Check the health and stats of media services.

### Step 1: JellyFin health
```bash
curl -s http://192.168.0.160:8096/health
curl -s http://192.168.0.160:8096/System/Info/Public
```

Extract: server name, version, startup status.

### Step 2: JellyFin library stats
```bash
curl -s http://192.168.0.160:8096/Items/Counts -H "X-Emby-Token: <key>"
```

If no API key is available, note that library stats require authentication and skip.

### Step 3: ErsatzTV health
```bash
curl -s http://192.168.0.161:8409/health 2>/dev/null || curl -s -o /dev/null -w "%{http_code}" http://192.168.0.161:8409
```

Check if ErsatzTV is responding.

### Step 4: Container status
```bash
ssh proxmox "pvesh get /nodes/pve1/lxc/104/status/current --output-format json" 2>/dev/null
ssh proxmox "pvesh get /nodes/pve1/lxc/107/status/current --output-format json" 2>/dev/null
```

Extract CPU/memory usage for JellyFin (LXC 104) and ErsatzTV (LXC 107).

### Step 5: Present results
- Service health: up/down for each
- JellyFin: version, library counts (if available)
- ErsatzTV: status
- Resource usage for both containers
- Flag any issues

Keep it concise. No fluff.
