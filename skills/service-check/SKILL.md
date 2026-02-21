---
name: service-check
description: Probe all homelab services and report health status.
disable-model-invocation: true
---

# Service Health Check

## Infrastructure Reference
!`cat $HOME/gitea-repos/development-skills/config/infrastructure.md`

## Instructions

Run the service health check script and present the results.

### Step 1: Run the check
- Execute `$HOME/gitea-repos/homelab-setup/check-services.sh` via Bash
- This connects to Proxmox via SSH and checks cluster health, VM/container status, HTTP endpoints, and NPM proxy routing

### Step 2: Present results
- Summarize in a clean table:
  - Cluster status (quorate or not)
  - VMs/containers: which are running vs stopped
  - Services: which responded OK vs failed (with HTTP codes)
  - NPM proxy routing status
- Highlight any failures or warnings prominently
- If SSH to proxmox fails, note that the connection is down and suggest checking Tailscale

### Step 3: Suggest actions
- For any failed services, suggest a restart command: `ssh proxmox "sudo pct restart <VMID>"`
- For failed HTTP checks on running containers, suggest checking the service logs

Keep it concise. No fluff.
