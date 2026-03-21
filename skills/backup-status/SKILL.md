---
name: backup-status
description: Query restic backup snapshots and report backup health.
disable-model-invocation: true
---

# Backup Status

## Instructions

Check the status of all restic backup repositories.

### Step 1: Query snapshots
Run via SSH to proxmox-root (restic repos are on TrueNAS, mounted on Proxmox):

```bash
ssh proxmox-root "restic -r /mnt/Primary/Backups/photos snapshots --latest 3 --json" 2>/dev/null
ssh proxmox-root "restic -r /mnt/Primary/Backups/appdata snapshots --latest 3 --json" 2>/dev/null
ssh proxmox-root "restic -r /mnt/Primary/Backups/service-configs snapshots --latest 3 --json" 2>/dev/null
ssh proxmox-root "restic -r /mnt/Primary/Backups/proxmox-config snapshots --latest 3 --json" 2>/dev/null
```

Note: Restic will prompt for the repo password. Retrieve it from Bitwarden: `bw get password restic-repo`

### Step 2: Present results
For each repository, show:
- Last snapshot date and time
- Snapshot age (how many hours/days ago)
- Number of recent snapshots

Flag any repo where the last snapshot is older than 48 hours as a warning, or older than 7 days as critical.

### Step 3: Suggest actions
- If backups are stale, suggest running: `ssh proxmox-root "/path/to/backup.sh"`
- If a repo has no snapshots, flag it as critical
- Recommend running `restic check` if snapshots exist but seem inconsistent

Keep it concise. No fluff.
