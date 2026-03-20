# WSL Sandbox Teardown Script
# Removes the Ubuntu-Claude distro and cleans up associated files.
#
# Prerequisites:
#   - Run PowerShell as Administrator (not required for -DryRun)
#
# Usage:
#   .\teardown-windows.ps1                # interactive
#   .\teardown-windows.ps1 -Force         # no prompts
#   .\teardown-windows.ps1 -DryRun        # show what would be removed
#
# What this removes:
#   - Ubuntu-Claude WSL distro
#   - C:\wsl-instances\ubuntu-claude (distro disk image)
#   - Windows Terminal RoamingState images
#   - Ubuntu-Claude profiles from Windows Terminal settings.json
#
# What this preserves (optional backup):
#   - ~/.claude/projects/ (Claude Code auto-memory)
#   - ~/.claude/env-config.yaml (setup config)
#   Backup saved to C:\wsl-exports\claude-backup.tar.gz
#
# What this does NOT remove:
#   - Base Ubuntu WSL distro
#   - Windows Terminal settings.json
#   - development-skills repo on Windows
#   - Installed fonts

param(
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Invoke-Wsl {
    $savedPref = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $pipeData = @($input)
        if ($pipeData.Count -gt 0) {
            $pipeData | wsl.exe @args 2>$null
        } else {
            wsl.exe @args 2>$null
        }
    }
    finally { $ErrorActionPreference = $savedPref }
}

$RoamingState = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\RoamingState"

if ($DryRun) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " DRY RUN MODE - No changes will be made" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Confirm-Step {
    param([string]$Message)
    if ($DryRun) { return $false }
    if ($Force) { return $true }
    $response = Read-Host "$Message (y/N)"
    return ($response -eq "y" -or $response -eq "Y")
}

# --- 1. Check if distro exists ---
$ubuntuClaudeExists = $false
$distroList = (wsl.exe --list --all 2>$null) -join " " -replace "`0", ""
$ubuntuClaudeExists = $distroList -like "*Ubuntu-Claude*"

# --- 2. Backup user data ---
$BackupDir = "C:\wsl-exports"
$BackupFile = "$BackupDir\claude-backup.tar.gz"

if ($ubuntuClaudeExists) {
    if ($DryRun) {
        Write-Host "[Would offer] Backup Claude memory and config before teardown" -ForegroundColor Yellow
        Write-Host "  Backup location: $BackupFile" -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "Backup User Data" -ForegroundColor Cyan
        Write-Host "  The following data will be lost when the distro is removed:" -ForegroundColor Yellow
        Write-Host "    - ~/.claude/projects/ (Claude Code auto-memory)" -ForegroundColor Yellow
        Write-Host "    - ~/.claude/env-config.yaml (setup config)" -ForegroundColor Yellow
        Write-Host "    - ~/gitea-repos/*/SESSION.md (active sessions)" -ForegroundColor Yellow
        Write-Host ""
        if (Confirm-Step "Back up this data to $BackupFile ?") {
            Write-Host "Creating backup..." -ForegroundColor Cyan
            New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

            $backupScript = @'
#!/bin/bash
cd /home/claude-user
files=""
for p in .claude/projects .claude/env-config.yaml; do
    [ -e "$p" ] && files="$files $p"
done
# Also grab SESSION.md files from repos
for s in gitea-repos/*/SESSION.md; do
    [ -f "$s" ] && files="$files $s"
done
if [ -z "$files" ]; then
    echo "NOTHING_TO_BACKUP"
    exit 0
fi
rm -f /tmp/claude-backup.tar.gz
tar czf /tmp/claude-backup.tar.gz $files 2>/dev/null
if [ -f /tmp/claude-backup.tar.gz ]; then
    echo "SIZE: $(du -h /tmp/claude-backup.tar.gz | cut -f1)"
else
    echo "TAR_FAILED"
fi
'@
            $backupScript | Invoke-Wsl -d Ubuntu-Claude -u root -- bash -c "tr -d '\r' > /tmp/do-backup.sh"
            $tarResult = Invoke-Wsl -d Ubuntu-Claude -u claude-user -- bash /tmp/do-backup.sh
            $tarResult = ($tarResult | Out-String).Trim()

            if ($tarResult -match "NOTHING_TO_BACKUP") {
                Write-Host "  No user data found to back up -- skipping." -ForegroundColor Yellow
            } elseif ($tarResult -match "TAR_FAILED") {
                Write-Warning "Backup tar creation failed inside distro."
            } else {
                Write-Host "  $tarResult" -ForegroundColor Cyan
                $copied = $false
                try {
                    cmd.exe /c "wsl.exe -d Ubuntu-Claude -u claude-user -- cat /tmp/claude-backup.tar.gz > `"$BackupFile`"" 2>$null
                    $copied = (Test-Path $BackupFile) -and (Get-Item $BackupFile).Length -gt 0
                } catch { }

                if (-not $copied) {
                    try {
                        $distroTmpPath = "\\wsl`$\Ubuntu-Claude\tmp\claude-backup.tar.gz"
                        Copy-Item $distroTmpPath $BackupFile -Force -ErrorAction Stop
                        $copied = $true
                    } catch { }
                }

                if ($copied) {
                    Write-Host "  Saved to $BackupFile" -ForegroundColor Green
                } else {
                    Write-Warning "Failed to copy backup out of distro."
                }
            }
        } else {
            Write-Host "  Skipping backup." -ForegroundColor Yellow
        }
    }
}

# --- 3. Unregister distro ---
if ($DryRun) {
    if ($ubuntuClaudeExists) {
        Write-Host "[Would unregister] Ubuntu-Claude WSL distro" -ForegroundColor Yellow
    } else {
        Write-Host "[Would check] Ubuntu-Claude distro not found - would skip" -ForegroundColor Yellow
    }
} elseif ($ubuntuClaudeExists) {
    Write-Host ""
    if (Confirm-Step "Unregister Ubuntu-Claude WSL distro? This destroys all data inside it.") {
        Write-Host "Unregistering Ubuntu-Claude..." -ForegroundColor Cyan
        wsl.exe --unregister Ubuntu-Claude
        Write-Host "  Done." -ForegroundColor Green
    }
}

# --- 4. Shutdown WSL ---
if (-not $DryRun) {
    if ($Force) {
        Write-Host ""
        Write-Host "Shutting down WSL to release file locks..." -ForegroundColor Cyan
        wsl.exe --shutdown
        Start-Sleep -Seconds 5
    } else {
        Write-Host ""
        Write-Host "To remove Ubuntu-Claude files, WSL must be shut down." -ForegroundColor Yellow
        Write-Host "This will stop all running WSL distros." -ForegroundColor Yellow
        Write-Host ""
        if (Confirm-Step "Shutdown WSL now?") {
            Write-Host "Shutting down WSL..." -ForegroundColor Cyan
            wsl.exe --shutdown
            Start-Sleep -Seconds 5
            Write-Host "  Done." -ForegroundColor Green
        } else {
            Write-Warning "Cannot remove locked files without shutting down WSL."
            Write-Warning "Please run 'wsl --shutdown' manually and try again."
            exit 1
        }
    }
}

# --- 5. Remove instance directory ---
$InstanceDir = "C:\wsl-instances\ubuntu-claude"
if (Test-Path $InstanceDir) {
    if ($DryRun) {
        Write-Host "[Would remove] $InstanceDir" -ForegroundColor Yellow
    } elseif (Confirm-Step "Remove instance directory ($InstanceDir)?") {
        Write-Host "Removing $InstanceDir..." -ForegroundColor Cyan

        $maxRetries = 3
        $retryDelay = 3
        $success = $false

        for ($i = 1; $i -le $maxRetries; $i++) {
            try {
                Remove-Item -Recurse -Force $InstanceDir -ErrorAction Stop
                $success = $true
                Write-Host "  Done." -ForegroundColor Green
                break
            } catch {
                if ($i -lt $maxRetries) {
                    Write-Host "  File locked, waiting $retryDelay seconds (attempt $i/$maxRetries)..." -ForegroundColor Yellow
                    Start-Sleep -Seconds $retryDelay
                    $retryDelay += 2
                } else {
                    Write-Host ""
                    Write-Host "Failed to remove $InstanceDir after $maxRetries attempts" -ForegroundColor Red
                    Write-Host "The directory will need to be manually deleted after a reboot." -ForegroundColor Yellow
                    Write-Host "Continuing with teardown of other items..." -ForegroundColor Cyan
                }
            }
        }
    }
} else {
    Write-Host "Instance directory not found - skipping." -ForegroundColor Yellow
}

# --- 6. Remove terminal images ---
$IconFile = "$RoamingState\claude-icon.ico"
$BgFile   = "$RoamingState\background.jpg"
$hasImages = (Test-Path $IconFile) -or (Test-Path $BgFile)

$LocalState   = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
$SettingsPath = "$LocalState\settings.json"

# Check if other profiles reference these images
$otherProfileUsesIcon = $false
$otherProfileUsesBg = $false
if (Test-Path $SettingsPath) {
    try {
        $settingsCheck = Get-Content $SettingsPath -Raw | ConvertFrom-Json
        $otherProfiles = @($settingsCheck.profiles.list | Where-Object {
            $_.name -ne "Ubuntu-Claude" -and $_.commandline -notlike "*Ubuntu-Claude*"
        })
        foreach ($prof in $otherProfiles) {
            $profJson = $prof | ConvertTo-Json -Depth 5
            if ($profJson -match "claude-icon") { $otherProfileUsesIcon = $true }
            if ($profJson -match "background")  { $otherProfileUsesBg = $true }
        }
    } catch { }
}

if ($hasImages) {
    if ($DryRun) {
        if ((Test-Path $IconFile) -and -not $otherProfileUsesIcon) { Write-Host "[Would remove] $IconFile" -ForegroundColor Yellow }
        if ((Test-Path $IconFile) -and $otherProfileUsesIcon)      { Write-Host "[Would keep] $IconFile (used by another profile)" -ForegroundColor Yellow }
        if ((Test-Path $BgFile) -and -not $otherProfileUsesBg)     { Write-Host "[Would remove] $BgFile" -ForegroundColor Yellow }
        if ((Test-Path $BgFile) -and $otherProfileUsesBg)          { Write-Host "[Would keep] $BgFile (used by another profile)" -ForegroundColor Yellow }
    } elseif (Confirm-Step "Remove Windows Terminal images?") {
        if ((Test-Path $IconFile) -and -not $otherProfileUsesIcon) { Remove-Item -Force $IconFile; Write-Host "  Removed claude-icon.ico" -ForegroundColor Cyan }
        if ((Test-Path $IconFile) -and $otherProfileUsesIcon)      { Write-Host "  Kept claude-icon.ico (used by another profile)" -ForegroundColor Yellow }
        if ((Test-Path $BgFile) -and -not $otherProfileUsesBg)     { Remove-Item -Force $BgFile;   Write-Host "  Removed background.jpg" -ForegroundColor Cyan }
        if ((Test-Path $BgFile) -and $otherProfileUsesBg)          { Write-Host "  Kept background.jpg (used by another profile)" -ForegroundColor Yellow }
    }
}

# --- 7. Remove Ubuntu-Claude profiles from Windows Terminal settings ---
if (Test-Path $SettingsPath) {
    if ($DryRun) {
        Write-Host "[Would check] Windows Terminal settings for Ubuntu-Claude profiles" -ForegroundColor Yellow
    } elseif (Confirm-Step "Remove Ubuntu-Claude profiles from Windows Terminal settings?") {
        try {
            Write-Host "Cleaning Windows Terminal settings..." -ForegroundColor Cyan

            $settingsContent = Get-Content $SettingsPath -Raw
            $settings = $settingsContent | ConvertFrom-Json

            $beforeCount = $settings.profiles.list.Count
            $settings.profiles.list = @($settings.profiles.list | Where-Object {
                -not ($_.name -eq "Ubuntu-Claude" -or $_.commandline -like "*Ubuntu-Claude*")
            })
            $afterCount = $settings.profiles.list.Count
            $removed = $beforeCount - $afterCount

            if ($removed -gt 0) {
                Copy-Item $SettingsPath "$SettingsPath.bak" -Force
                $settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsPath -Encoding UTF8
                Write-Host "  Removed $removed Ubuntu-Claude profile(s)" -ForegroundColor Cyan
                Write-Host "  Backup saved to settings.json.bak" -ForegroundColor Cyan
            } else {
                Write-Host "  No Ubuntu-Claude profiles found - skipping." -ForegroundColor Yellow
            }
        } catch {
            Write-Warning "Failed to update Windows Terminal settings: $($_.Exception.Message)"
        }
    }
}

# --- Summary ---
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host " Dry run complete" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "No changes were made." -ForegroundColor Green
    Write-Host ""
    Write-Host "To actually remove these items, run without -DryRun:" -ForegroundColor Yellow
    Write-Host "  .\teardown-windows.ps1"
} else {
    Write-Host " Teardown complete" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    $needsCleanup = @()
    if (Test-Path "C:\wsl-instances\ubuntu-claude") {
        $needsCleanup += "C:\wsl-instances\ubuntu-claude"
    }

    if ($needsCleanup.Count -gt 0) {
        Write-Host "Some items could not be removed automatically:" -ForegroundColor Yellow
        $needsCleanup | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        Write-Host ""
        Write-Host "Delete manually after a reboot or longer wait." -ForegroundColor Yellow
        Write-Host ""
    } else {
        Write-Host "All items removed successfully." -ForegroundColor Green
        Write-Host ""
    }

    if (Test-Path "$BackupDir\claude-backup.tar.gz") {
        Write-Host "Backup saved at: $BackupDir\claude-backup.tar.gz" -ForegroundColor Green
        Write-Host "  setup-linux.sh will offer to restore it on next setup." -ForegroundColor Cyan
        Write-Host ""
    }

    Write-Host "To set up again, run:" -ForegroundColor Cyan
    Write-Host "  .\setup-windows.ps1"
}
Write-Host ""
