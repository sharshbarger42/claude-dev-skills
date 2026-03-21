---
name: infra-report
description: Report on VM/LXC resource usage, disk space, and pending updates.
disable-model-invocation: true
---

# Infrastructure Report

## Instructions

Gather resource usage data from the Proxmox cluster.

### Step 1: Cluster resources
Run via SSH:
```bash
ssh proxmox "pvesh get /cluster/resources --type vm --output-format json"
```

Parse the JSON and extract for each VM/container:
- Name, VMID, type (VM/LXC), node, status
- CPU usage (%), memory usage (used/max), disk usage (used/max)

### Step 2: Node resources
```bash
ssh proxmox "pvesh get /cluster/resources --type node --output-format json"
```

Extract per node:
- CPU usage, memory usage, local disk usage
- Uptime

### Step 3: Storage status
```bash
ssh proxmox "pvesh get /cluster/resources --type storage --output-format json"
```

Show each storage pool: total, used, available, % full. Flag any storage over 80% usage.

### Step 4: Present results
- Show a table of all VMs/containers with resource usage
- Show node summary with CPU/RAM/disk
- Show storage pools
- Highlight anything concerning:
  - CPU > 80% sustained
  - Memory > 85%
  - Disk/storage > 80%
  - Any stopped VMs/containers that should be running

Keep it concise. Use tables for readability.
