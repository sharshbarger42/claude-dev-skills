# WSL Sandbox Windows Setup Script
# Sets up JetBrainsMono Nerd Font, Windows Terminal settings, and Ubuntu-Claude WSL distro.
# Adapted for the development-skills homelab environment (Gitea, no AWS/Jira).
#
# Prerequisites:
#   - Run PowerShell as Administrator
#   - Git for Windows installed
#   - development-skills repo cloned
#   - Windows Terminal installed
#   - WSL with Ubuntu distro installed (winget install Canonical.Ubuntu)
#
# Usage:
#   .\setup-windows.ps1            # Full setup with prompts
#   .\setup-windows.ps1 -Defaults  # Accept all defaults (no prompts)
#   .\setup-windows.ps1 -DryRun    # Show what would be done (no admin needed)

param(
    [switch]$DryRun,
    [switch]$Defaults
)

$BACKGROUND_URL = ""

if (-not $DryRun -and -not $Defaults) {
    Write-Host ""
    Write-Host "Background Image Setup" -ForegroundColor Cyan
    Write-Host "You can optionally set a background image for the terminal." -ForegroundColor Yellow
    Write-Host ""
    $response = Read-Host "Do you have a background image (URL or local path)? (y/N)"
    if ($response -eq "y" -or $response -eq "Y") {
        Write-Host ""
        Write-Host "Enter either:" -ForegroundColor Yellow
        Write-Host "  - A URL: https://example.com/image.jpg" -ForegroundColor Yellow
        Write-Host "  - A local path: C:\Users\...\Pictures\image.jpg" -ForegroundColor Yellow
        Write-Host ""
        $BACKGROUND_URL = Read-Host "Background image"
        Write-Host ""
    }
} elseif ($Defaults) {
    Write-Host "  [defaults] Skipping background image." -ForegroundColor Yellow
}

$ErrorActionPreference = "Stop"

# --- Helper: Build sudoers content from option selection ---
function Build-SudoersContent {
    param([string]$SudoChoice)
    $sudoOptions = $SudoChoice -split "," | ForEach-Object { $_.Trim() }
    $lines = @("# Controlled sudo for claude-user (sandbox mode)")
    if ($sudoOptions -contains "5" -or $sudoOptions -contains "1") {
        $lines += "claude-user ALL=(root) NOPASSWD: /usr/bin/apt-get install *"
        $lines += "claude-user ALL=(root) NOPASSWD: /usr/bin/apt install *"
    }
    if ($sudoOptions -contains "5" -or $sudoOptions -contains "2") {
        $lines += "claude-user ALL=(root) NOPASSWD: /usr/bin/apt-get update"
        $lines += "claude-user ALL=(root) NOPASSWD: /usr/bin/apt update"
    }
    if ($sudoOptions -contains "5" -or $sudoOptions -contains "3") {
        $lines += "claude-user ALL=(root) NOPASSWD: /usr/bin/systemctl *"
    }
    if ($sudoOptions -contains "5" -or $sudoOptions -contains "4") {
        $lines += "claude-user ALL=(root) NOPASSWD: /usr/bin/tee /etc/apt/sources.list.d/*"
        $lines += "claude-user ALL=(root) NOPASSWD: /usr/bin/tee /etc/apt/trusted.gpg.d/*"
        $lines += "claude-user ALL=(root) NOPASSWD: /usr/bin/add-apt-repository *"
        $lines += "claude-user ALL=(root) NOPASSWD: /usr/bin/apt-key *"
    }
    $lines += "claude-user ALL=(root) NOPASSWD: /usr/bin/chsh *"
    return $lines -join "`n"
}

# --- Helper: Prompt for sudo choice ---
function Get-SudoChoice {
    param([switch]$UseDefaults)
    if ($UseDefaults) {
        Write-Host "  [defaults] Sudo: 1,2,4" -ForegroundColor Yellow
        return "1,2,4"
    }
    Write-Host "  Select which sudo commands to allow (comma-separated):" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    1. apt-get install (install packages)"
    Write-Host "    2. apt-get update (update package lists)"
    Write-Host "    3. systemctl (manage services)"
    Write-Host "    4. tee /etc/apt/* (write apt config files)"
    Write-Host "    5. All of the above"
    Write-Host ""
    $choice = Read-Host "    Selection (default: 1,2,4)"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1,2,4" }
    return $choice
}

# --- Helper: Apply sudoers to distro ---
function Apply-Sudoers {
    param([string]$Content)
    $script = @"
#!/bin/bash
set -e
cat > /etc/sudoers.d/claude-user << 'SUDOERS'
$Content
SUDOERS
chmod 440 /etc/sudoers.d/claude-user
"@
    $script | Invoke-Wsl -d Ubuntu-Claude -u root -- bash -c "tr -d '\r' > /tmp/reconfig-sudo.sh"
    Invoke-Wsl -d Ubuntu-Claude -u root -- bash /tmp/reconfig-sudo.sh
}

if ($DryRun) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " DRY RUN MODE - No changes will be made" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

# Helper: run wsl.exe without stderr noise
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

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DevSkillsDir = (Resolve-Path "$ScriptDir\..\..").Path
$RoamingState = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\RoamingState"
$LocalState   = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
$SettingsDst  = "$LocalState\settings.json"

# --- 1. Install JetBrainsMono Nerd Font ---
if ($DryRun) {
    Write-Host "[Would check] JetBrainsMono Nerd Font installation" -ForegroundColor Yellow
} else {
    Write-Host "Checking JetBrainsMono Nerd Font..." -ForegroundColor Cyan
    $fontCheck = winget list --id DEVCOM.JetBrainsMonoNerdFont --exact 2>&1
    if ($fontCheck -like "*No installed package found*" -or $LASTEXITCODE -ne 0) {
        Write-Host "  Installing JetBrainsMono Nerd Font..." -ForegroundColor Cyan
        winget install --id DEVCOM.JetBrainsMonoNerdFont --silent --accept-package-agreements --accept-source-agreements | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Done." -ForegroundColor Green
        } else {
            Write-Warning "winget exited with code $LASTEXITCODE - font may not have installed correctly."
        }
    } else {
        Write-Host "  Already installed." -ForegroundColor Green
    }
}

# --- 2. Download images ---
if ($DryRun) {
    Write-Host "[Would create] $RoamingState" -ForegroundColor Yellow
    Write-Host "[Would check] claude-icon.ico" -ForegroundColor Yellow
    if (-not [string]::IsNullOrWhiteSpace($BACKGROUND_URL)) {
        Write-Host "[Would check] background.jpg" -ForegroundColor Yellow
    }
} else {
    New-Item -ItemType Directory -Force -Path $RoamingState | Out-Null

    if (-not (Test-Path "$RoamingState\claude-icon.ico")) {
        Write-Host "Downloading claude-icon.ico..." -ForegroundColor Cyan
        try {
            Invoke-WebRequest -Uri "https://claude.ai/favicon.ico" -OutFile "$RoamingState\claude-icon.ico"
            Write-Host "  Done." -ForegroundColor Green
        } catch {
            Write-Warning "Failed to download claude-icon.ico: $($_.Exception.Message)"
        }
    } else {
        Write-Host "Claude icon already exists - skipping." -ForegroundColor Green
    }

    if (-not [string]::IsNullOrWhiteSpace($BACKGROUND_URL)) {
        $cleanPath = $BACKGROUND_URL.Trim('"').Trim("'")
        if (Test-Path "$RoamingState\background.jpg") {
            Write-Host "Background image already exists - skipping." -ForegroundColor Green
        } elseif ($cleanPath -like "http*") {
            Write-Host "Downloading background image..." -ForegroundColor Cyan
            try {
                Invoke-WebRequest -Uri $cleanPath -OutFile "$RoamingState\background.jpg"
                Write-Host "  Done." -ForegroundColor Green
            } catch {
                Write-Warning "Failed to download background image: $($_.Exception.Message)"
            }
        } elseif (Test-Path $cleanPath) {
            Write-Host "Copying background image from local path..." -ForegroundColor Cyan
            try {
                Copy-Item $cleanPath "$RoamingState\background.jpg" -Force
                Write-Host "  Done." -ForegroundColor Green
            } catch {
                Write-Warning "Failed to copy background image: $($_.Exception.Message)"
            }
        } else {
            Write-Warning "Background image path/URL not valid: $cleanPath"
        }
    }
}

# --- 3. Shared Windows Directory ---
$SharedWinPath = ""
$SharedMountPoint = ""

if ($DryRun) {
    Write-Host ""
    Write-Host "[Would prompt] Shared Windows directory configuration" -ForegroundColor Yellow
} elseif ($Defaults) {
    Write-Host "  [defaults] Skipping shared directory." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "Shared Windows Directory" -ForegroundColor Cyan
    Write-Host "  Automount is disabled for sandbox isolation, but you can share" -ForegroundColor Yellow
    Write-Host "  a single Windows directory into WSL." -ForegroundColor Yellow
    Write-Host ""
    $shareResponse = Read-Host "  Share a Windows directory? (y/N)"
    if ($shareResponse -eq "y" -or $shareResponse -eq "Y") {
        Write-Host ""
        Write-Host "  Enter the Windows path to share." -ForegroundColor Yellow
        Write-Host "  Examples:" -ForegroundColor Yellow
        Write-Host "    C:\Users\$env:USERNAME\Documents\shared" -ForegroundColor Yellow
        Write-Host "    C:\Projects" -ForegroundColor Yellow
        Write-Host ""
        $SharedWinPath = Read-Host "  Windows path"

        if (-not [string]::IsNullOrWhiteSpace($SharedWinPath)) {
            $mountName = (Split-Path -Leaf $SharedWinPath).ToLower() -replace ' ', '-'
            $defaultMount = "/mnt/$mountName"
            Write-Host ""
            $customMount = Read-Host "  Mount point (default: $defaultMount)"
            if ([string]::IsNullOrWhiteSpace($customMount)) {
                $SharedMountPoint = $defaultMount
            } else {
                $SharedMountPoint = $customMount
            }
            Write-Host "  Will configure: $SharedWinPath -> $SharedMountPoint" -ForegroundColor Green
        } else {
            Write-Host "  [skip] No path provided." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [skip] No shared directory configured." -ForegroundColor Yellow
    }
}

# --- 4. Check for existing Ubuntu-Claude ---
if (-not $DryRun) {
    Write-Host "`nChecking for WSL Ubuntu-Claude..." -ForegroundColor Cyan
}

$ubuntuClaudeExists = $false
$ubuntuExists = $false

$savedErrorPref = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'

try {
    $null = wsl.exe -d Ubuntu-Claude -- bash -c "exit 0" 2>&1
    if ($LASTEXITCODE -eq 0) { $ubuntuClaudeExists = $true }

    $null = wsl.exe -d Ubuntu -- bash -c "exit 0" 2>&1
    if ($LASTEXITCODE -eq 0) { $ubuntuExists = $true }
} catch { }

$ErrorActionPreference = $savedErrorPref

# --- Update flags ---
$DoRepoSync = $true

# --- Existing distro: status check + update menu ---
if ($ubuntuClaudeExists) {
    Write-Host "`nUbuntu-Claude already exists. Checking configuration..." -ForegroundColor Cyan

    $checkScript = @'
echo "claude_user=$(id claude-user &>/dev/null && echo Y || echo N)"
echo "sudo_rules=$(test -f /etc/sudoers.d/claude-user && echo Y || echo N)"
echo "wsl_conf=$(grep -q 'default=claude-user' /etc/wsl.conf 2>/dev/null && echo Y || echo N)"
echo "dev_skills=$(test -d /home/claude-user/development-skills && echo Y || echo N)"
echo "shared_dir=$(grep -q 'drvfs' /etc/fstab 2>/dev/null && echo Y || echo N)"
echo "vscode=$(test -L /usr/local/bin/code && echo Y || echo N)"
echo "ro_mount=$(grep -q 'options=ro' /etc/wsl.conf 2>/dev/null && echo Y || echo N)"
'@
    $checkOutput = ($checkScript | Invoke-Wsl -d Ubuntu-Claude -u root -- bash | Out-String)

    $status = @{}
    foreach ($line in ($checkOutput -split "`n")) {
        if ($line.Trim() -match '^(\w+)=(\w)$') {
            $status[$matches[1]] = ($matches[2] -eq "Y")
        }
    }

    # Check Windows-side terminal profile
    $hasTerminalProfile = $false
    if (Test-Path $SettingsDst) {
        try {
            $termSettings = Get-Content $SettingsDst -Raw | ConvertFrom-Json
            $hasTerminalProfile = $null -ne ($termSettings.profiles.list | Where-Object {
                $_.name -eq "Ubuntu-Claude" -and $_.commandline -like "*Ubuntu-Claude*"
            })
        } catch {}
    }

    # Display status table
    $labels = [ordered]@{
        "claude_user" = "claude-user account"
        "wsl_conf"    = "wsl.conf"
        "sudo_rules"  = "sudo permissions"
        "dev_skills"  = "development-skills repo"
        "shared_dir"  = "shared directory"
        "ro_mount"    = "readonly Windows mount"
        "vscode"      = "VS Code (code .)"
    }
    Write-Host ""
    foreach ($entry in $labels.GetEnumerator()) {
        $label = "  {0,-23}" -f $entry.Value
        if ($status[$entry.Key]) {
            Write-Host "$label " -NoNewline; Write-Host "ok" -ForegroundColor Green
        } else {
            Write-Host "$label " -NoNewline; Write-Host "missing" -ForegroundColor Yellow
        }
    }
    $tpLabel = "  {0,-23}" -f "terminal profile"
    if ($hasTerminalProfile) {
        Write-Host "$tpLabel " -NoNewline; Write-Host "ok" -ForegroundColor Green
    } else {
        Write-Host "$tpLabel " -NoNewline; Write-Host "missing" -ForegroundColor Yellow
    }
    Write-Host ""

    $sudoMissing = -not $status["sudo_rules"]
    $vscodeMissing = -not $status["vscode"] -or -not $status["ro_mount"]
    $defaultNums = @("1")
    if ($sudoMissing) { $defaultNums += "2" }
    if ($vscodeMissing) { $defaultNums += "3" }
    $defaultStr = $defaultNums -join ","

    if ($Defaults) {
        Write-Host "  [defaults] Applying updates: $defaultStr" -ForegroundColor Yellow
        $DoRepoSync = $true
        $doVSCodeSetup = $vscodeMissing
    } elseif ($DryRun) {
        Write-Host "  [dry-run] Would offer update menu (defaults: $defaultStr)" -ForegroundColor Yellow
        $DoRepoSync = $true
    } else {
        Write-Host "  Available updates:" -ForegroundColor Cyan
        $d1 = if ($defaultNums -contains "1") { "*" } else { " " }
        $d2 = if ($defaultNums -contains "2") { "*" } else { " " }
        $d3 = if ($defaultNums -contains "3") { "*" } else { " " }
        Write-Host "   $d1 1. Sync development-skills repo"
        Write-Host "   $d2 2. Reconfigure sudo permissions"
        Write-Host "   $d3 3. Enable VS Code + readonly Windows mount"
        Write-Host "     4. All of the above"
        Write-Host ""
        Write-Host "  * = recommended  |  0 = skip all" -ForegroundColor DarkGray
        Write-Host ""
        $menuChoice = Read-Host "  Selection (default: $defaultStr)"
        if ([string]::IsNullOrWhiteSpace($menuChoice)) { $menuChoice = $defaultStr }

        $selected = @($menuChoice -split "," | ForEach-Object { $_.Trim() })
        $doAll = $selected -contains "4"

        if ($selected -contains "0") {
            $DoRepoSync = $false
            Write-Host "  Skipping all updates." -ForegroundColor Yellow
        } else {
            $DoRepoSync = $doAll -or $selected -contains "1"
            $doSudoReconfig = $doAll -or $selected -contains "2"
            $doVSCodeSetup = $doAll -or $selected -contains "3"
        }
    }

    # --- Reconfigure sudo if selected ---
    if ($doSudoReconfig -and -not $DryRun) {
        Write-Host "`nReconfiguring sudo permissions..." -ForegroundColor Cyan
        $sudoChoice = Get-SudoChoice -UseDefaults:$Defaults
        $sudoersContent = Build-SudoersContent $sudoChoice
        Apply-Sudoers $sudoersContent
        Write-Host "  Sudo permissions updated." -ForegroundColor Green
    } elseif ($doSudoReconfig -and $DryRun) {
        Write-Host "[Would reconfigure] sudo permissions" -ForegroundColor Yellow
    }

    # --- Enable VS Code + readonly mount if selected ---
    if ($doVSCodeSetup -and -not $DryRun) {
        Write-Host "`nEnabling VS Code + readonly Windows mount..." -ForegroundColor Cyan

        # Update wsl.conf automount to readonly
        $roMountScript = @'
#!/bin/bash
set -e
# Update automount section to enabled=true with ro,metadata
if grep -q '^\[automount\]' /etc/wsl.conf; then
    sed -i '/^\[automount\]/,/^\[/{
        s/^enabled=.*/enabled=true/
        /^options=/d
    }' /etc/wsl.conf
    if ! sed -n '/^\[automount\]/,/^\[/p' /etc/wsl.conf | grep -q '^enabled='; then
        sed -i '/^\[automount\]/a enabled=true' /etc/wsl.conf
    fi
    if ! sed -n '/^\[automount\]/,/^\[/p' /etc/wsl.conf | grep -q '^options='; then
        sed -i '/^\[automount\]/,/^\[/{/^mountFsTab/a options=ro,metadata
}' /etc/wsl.conf
    fi
else
    printf '\n[automount]\nenabled=true\nmountFsTab=true\noptions=ro,metadata\n' >> /etc/wsl.conf
fi
'@
        $roMountScript | Invoke-Wsl -d Ubuntu-Claude -u root -- bash -c "tr -d '\r' > /tmp/setup-ro-mount.sh"
        Invoke-Wsl -d Ubuntu-Claude -u root -- bash /tmp/setup-ro-mount.sh
        Write-Host "  Readonly automount configured." -ForegroundColor Green

        # Create VS Code symlink (need to restart WSL first for mount to be active)
        Write-Host "  Restarting WSL for mount to take effect..." -ForegroundColor Cyan
        wsl.exe --terminate Ubuntu-Claude
        Start-Sleep -Seconds 2

        $WinUser = $env:USERNAME.ToLower()
        $VSCodeUserPath = "C:\Users\$env:USERNAME\AppData\Local\Programs\Microsoft VS Code\bin\code"
        $VSCodeSysPath = "C:\Program Files\Microsoft VS Code\bin\code"
        if (Test-Path $VSCodeUserPath) {
            $vscodeMntPath = "/mnt/c/Users/$WinUser/AppData/Local/Programs/Microsoft VS Code/bin/code"
            Invoke-Wsl -d Ubuntu-Claude -u root -- bash -c "ln -sf '$vscodeMntPath' /usr/local/bin/code"
            Write-Host "  Linked: code -> $VSCodeUserPath" -ForegroundColor Green
        } elseif (Test-Path $VSCodeSysPath) {
            $vscodeMntPath = "/mnt/c/Program Files/Microsoft VS Code/bin/code"
            Invoke-Wsl -d Ubuntu-Claude -u root -- bash -c "ln -sf '$vscodeMntPath' /usr/local/bin/code"
            Write-Host "  Linked: code -> $VSCodeSysPath" -ForegroundColor Green
        } else {
            Write-Host "  [skip] VS Code not found on Windows" -ForegroundColor Yellow
            Write-Host "  Install VS Code and re-run setup to enable 'code .' support" -ForegroundColor Yellow
        }

        Write-Host "  Done. Run 'code .' from Ubuntu-Claude to open VS Code." -ForegroundColor Green
    } elseif ($doVSCodeSetup -and $DryRun) {
        Write-Host "[Would enable] VS Code + readonly Windows mount" -ForegroundColor Yellow
    }
}

# --- Fresh install: create distro ---
if (-not $ubuntuClaudeExists -and -not $DryRun) {
    if (-not $ubuntuExists) {
        Write-Error @"
Ubuntu WSL distro not found. Install it first:
  winget install Canonical.Ubuntu
Then re-run this script.
"@
        exit 1
    }

    $ExportDir   = "C:\wsl-exports"
    $InstanceDir = "C:\wsl-instances\ubuntu-claude"
    $ExportTar   = "$ExportDir\ubuntu-base.tar"

    New-Item -ItemType Directory -Force -Path $ExportDir   | Out-Null
    New-Item -ItemType Directory -Force -Path $InstanceDir | Out-Null

    Write-Host "Exporting Ubuntu -> $ExportTar (this may take a minute)..." -ForegroundColor Cyan
    wsl.exe --export Ubuntu $ExportTar

    Write-Host "Importing as Ubuntu-Claude..." -ForegroundColor Cyan
    wsl.exe --import Ubuntu-Claude $InstanceDir $ExportTar

    Write-Host "Cleaning up export tarball..." -ForegroundColor Cyan
    Remove-Item -Force $ExportTar -ErrorAction SilentlyContinue
    Write-Host "  Done." -ForegroundColor Green

    $WinUser = $env:USERNAME.ToLower()

    # --- Configure Ubuntu-Claude ---
    Write-Host "Configuring Ubuntu-Claude..." -ForegroundColor Cyan

    Write-Host ""
    Write-Host "Sudo permissions for claude-user:" -ForegroundColor Yellow
    $sudoChoice = Get-SudoChoice -UseDefaults:$Defaults
    $sudoersContent = Build-SudoersContent $sudoChoice

    # Build shared directory mount line (expand PowerShell vars now, not inside bash)
    $fstabLine = ""
    $mountDir = ""
    if (-not [string]::IsNullOrWhiteSpace($SharedWinPath) -and -not [string]::IsNullOrWhiteSpace($SharedMountPoint)) {
        $fstabLine = "$SharedWinPath $SharedMountPoint drvfs ro 0 0"
        $mountDir = $SharedMountPoint
    }

    $setupScript = @"
#!/bin/bash
set -e

# Create claude-user
useradd -m -s /bin/bash claude-user 2>/dev/null || true

# Write wsl.conf
cat > /etc/wsl.conf << 'WSLCONF'
[boot]
systemd=true

[user]
default=claude-user

[automount]
enabled=true
mountFsTab=true
options=ro,metadata

[interop]
appendWindowsPath=false
WSLCONF

# Configure controlled sudo
cat > /etc/sudoers.d/claude-user << 'SUDOERS'
$sudoersContent
SUDOERS
chmod 440 /etc/sudoers.d/claude-user

# Add shared directory mount if configured
if [[ -n "$fstabLine" ]]; then
    mkdir -p "$mountDir"
    echo "$fstabLine" >> /etc/fstab
fi

# Lock the Windows user account inside this distro
passwd -l $WinUser 2>/dev/null || true
"@
    $setupScript | Invoke-Wsl -d Ubuntu-Claude -u root -- bash -c "tr -d '\r' > /tmp/setup-distro.sh"
    Invoke-Wsl -d Ubuntu-Claude -u root -- bash /tmp/setup-distro.sh

    # --- Set up VS Code symlink ---
    Write-Host "Setting up VS Code integration..." -ForegroundColor Cyan
    $VSCodeUserPath = "C:\Users\$WinUser\AppData\Local\Programs\Microsoft VS Code\bin\code"
    $VSCodeSysPath = "C:\Program Files\Microsoft VS Code\bin\code"
    if (Test-Path $VSCodeUserPath) {
        $vscodeMntPath = "/mnt/c/Users/$WinUser/AppData/Local/Programs/Microsoft VS Code/bin/code"
        Invoke-Wsl -d Ubuntu-Claude -u root -- bash -c "ln -sf '$vscodeMntPath' /usr/local/bin/code"
        Write-Host "  Linked: code -> $VSCodeUserPath" -ForegroundColor Green
    } elseif (Test-Path $VSCodeSysPath) {
        $vscodeMntPath = "/mnt/c/Program Files/Microsoft VS Code/bin/code"
        Invoke-Wsl -d Ubuntu-Claude -u root -- bash -c "ln -sf '$vscodeMntPath' /usr/local/bin/code"
        Write-Host "  Linked: code -> $VSCodeSysPath" -ForegroundColor Green
    } else {
        Write-Host "  [skip] VS Code not found on Windows" -ForegroundColor Yellow
        Write-Host "  Install VS Code and re-run setup to enable 'code .' support" -ForegroundColor Yellow
    }

    Write-Host "Terminating Ubuntu-Claude so wsl.conf takes effect..." -ForegroundColor Cyan
    wsl.exe --terminate Ubuntu-Claude

    Write-Host "Ubuntu-Claude setup complete." -ForegroundColor Green
}

# --- 5. Copy development-skills repo into Ubuntu-Claude ---
if (-not $DryRun -and $DoRepoSync) {
    Write-Host "`nSyncing development-skills repo into Ubuntu-Claude..." -ForegroundColor Cyan

    $distroPath = "\\wsl$\Ubuntu-Claude\home\claude-user\development-skills"
    if (Test-Path $distroPath) {
        Remove-Item -Recurse -Force $distroPath -ErrorAction SilentlyContinue
    }
    Copy-Item -Recurse -Force $DevSkillsDir $distroPath -ErrorAction Stop
    Invoke-Wsl -d Ubuntu-Claude -u root -- bash -c "chown -R claude-user:claude-user /home/claude-user/development-skills && find /home/claude-user/development-skills \( -name '*.sh' -o -name '*.yaml' -o -name '*.yml' -o -name '*.md' \) -exec sed -i 's/\r$//' {} \; && find /home/claude-user/development-skills -name '*.sh' -exec chmod +x {} \;"

    Write-Host "  Done." -ForegroundColor Green
} elseif ($DryRun -and $DoRepoSync) {
    Write-Host ""
    Write-Host "[Would sync] ~/development-skills from Windows into Ubuntu-Claude" -ForegroundColor Yellow
}

# --- 6. Copy backup into distro if available ---
$BackupFile = "C:\wsl-exports\claude-backup.tar.gz"
if (Test-Path $BackupFile) {
    if ($DryRun) {
        Write-Host ""
        Write-Host "[Would copy] Previous backup into Ubuntu-Claude for restore" -ForegroundColor Yellow
    } else {
        Write-Host "`nFound previous backup at $BackupFile" -ForegroundColor Cyan
        $distroBackup = "\\wsl$\Ubuntu-Claude\home\claude-user\claude-backup.tar.gz"
        try {
            Copy-Item $BackupFile $distroBackup -Force
            Invoke-Wsl -d Ubuntu-Claude -u root -- bash -c "chown claude-user:claude-user /home/claude-user/claude-backup.tar.gz"
            Write-Host "  Copied into distro. setup-linux.sh will offer to restore." -ForegroundColor Green
        } catch {
            Write-Warning "Failed to copy backup into distro: $($_.Exception.Message)"
        }
    }
}

# --- 7. Configure shared directory mount (existing distros) ---
if (-not $DryRun -and $ubuntuClaudeExists -and -not [string]::IsNullOrWhiteSpace($SharedWinPath)) {
    Write-Host "`nConfiguring shared directory mount..." -ForegroundColor Cyan
    Write-Host "  $SharedWinPath -> $SharedMountPoint" -ForegroundColor Cyan

    $existingMount = Invoke-Wsl -d Ubuntu-Claude -u root -- bash -c "grep 'drvfs' /etc/fstab 2>/dev/null | grep -v '^#' || true"
    $existingMount = ($existingMount | Out-String).Trim()

    $applyMount = $true
    if (-not [string]::IsNullOrWhiteSpace($existingMount)) {
        Write-Host "  Existing mount found: $existingMount" -ForegroundColor Yellow
        if ($Defaults) {
            $applyMount = $false
            Write-Host "  [defaults] Keeping existing mount." -ForegroundColor Yellow
        } else {
            $reconfig = Read-Host "  Replace existing mount? (y/N)"
            if ($reconfig -ne "y" -and $reconfig -ne "Y") {
                $applyMount = $false
            }
        }
    }

    if ($applyMount) {
        $fstabEntry = "$SharedWinPath $SharedMountPoint drvfs ro 0 0"
        $mountScript = @"
#!/bin/bash
sed -i '/drvfs/d' /etc/fstab 2>/dev/null || true
echo "$fstabEntry" >> /etc/fstab
mkdir -p "$SharedMountPoint"
if grep -q '^\[automount\]' /etc/wsl.conf; then
    if ! grep -q 'mountFsTab' /etc/wsl.conf; then
        sed -i '/^\[automount\]/a mountFsTab=true' /etc/wsl.conf
    fi
else
    printf '\n[automount]\nmountFsTab=true\n' >> /etc/wsl.conf
fi
"@
        $mountScript | Invoke-Wsl -d Ubuntu-Claude -u root -- bash -c "tr -d '\r' > /tmp/setup-mount.sh"
        Invoke-Wsl -d Ubuntu-Claude -u root -- bash /tmp/setup-mount.sh
        Write-Host "  Mount configured. Will be active on next WSL restart." -ForegroundColor Green
    }
}

# --- 8. Add Ubuntu-Claude profile to Windows Terminal settings ---
if (-not $DryRun -and (Test-Path $SettingsDst)) {
    Write-Host "`nAdding Ubuntu-Claude profile to Windows Terminal..." -ForegroundColor Cyan
    try {
        $settings = Get-Content $SettingsDst -Raw | ConvertFrom-Json

        $customProfileExists = $settings.profiles.list | Where-Object {
            $_.name -eq "Ubuntu-Claude" -and $_.commandline -like "*Ubuntu-Claude*"
        }

        # Hide auto-generated WSL profiles for Ubuntu-Claude
        $hiddenCount = 0
        foreach ($profile in $settings.profiles.list) {
            if ($profile.name -eq "Ubuntu-Claude" -and $profile.source -eq "Microsoft.WSL" -and $profile.hidden -ne $true) {
                $profile.hidden = $true
                $hiddenCount++
            }
        }
        if ($hiddenCount -gt 0) {
            Write-Host "  Hidden $hiddenCount auto-generated WSL profile(s)" -ForegroundColor Cyan
        }

        $needsSave = $false

        if (-not $customProfileExists) {
            $newProfile = @{
                "guid" = "{9c42b463-6505-48d5-9c52-dc2df3e5b325}"
                "name" = "Ubuntu-Claude"
                "commandline" = "wsl.exe -d Ubuntu-Claude"
                "hidden" = $false
                "icon" = "ms-appdata:///roaming/claude-icon.ico"
                "tabTitle" = "Claude (Sandboxed)"
                "colorScheme" = "One Half Dark"
                "font" = @{
                    "face" = "JetBrainsMono Nerd Font"
                    "size" = 12
                }
                "cursorShape" = "bar"
                "cursorColor" = "#FFFFFF"
                "opacity" = 75
                "useAcrylic" = $true
                "suppressApplicationTitle" = $true
                "snapOnInput" = $true
            }

            if (Test-Path "$RoamingState\background.jpg") {
                $newProfile["backgroundImage"] = "ms-appdata:///roaming/background.jpg"
                $newProfile["backgroundImageOpacity"] = 0.5
            }

            $settings.profiles.list += $newProfile
            $needsSave = $true
            Write-Host "  Profile added successfully" -ForegroundColor Green
        } else {
            Write-Host "  Custom profile already exists - skipping" -ForegroundColor Yellow
        }

        if ($needsSave -or $hiddenCount -gt 0) {
            Copy-Item $SettingsDst "$SettingsDst.bak" -Force
            $settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsDst -Encoding UTF8
        }
    } catch {
        Write-Warning "Failed to update Windows Terminal settings: $($_.Exception.Message)"
    }
} elseif ($DryRun -and (Test-Path $SettingsDst)) {
    Write-Host ""
    Write-Host "[Would check] Windows Terminal profiles for Ubuntu-Claude" -ForegroundColor Yellow
}

# --- Done ---
if ($DryRun) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " Dry run complete" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "No changes were made." -ForegroundColor Green
    Write-Host ""
    Write-Host "To run the actual setup:" -ForegroundColor Yellow
    Write-Host "  .\setup-windows.ps1"
} else {
    Write-Host "`nSetup complete!" -ForegroundColor Green
    Write-Host "Restart Windows Terminal to pick up the new settings."
    Write-Host ""
    Write-Host "Next: open Ubuntu-Claude and run:" -ForegroundColor Yellow
    Write-Host "  ~/development-skills/setup/wsl-sandbox/setup-linux.sh"
    Write-Host ""
    Write-Host "Then open Claude Code and run:" -ForegroundColor Yellow
    Write-Host "  /start"
}
