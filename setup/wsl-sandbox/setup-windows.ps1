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
$RoamingStateCheck = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\RoamingState"

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

# --- Detect existing distros (needed before prompts) ---
$ubuntuClaudeExists = $false
$ubuntuExists = $false

$savedErrorPref = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'

try {
    $distroList = (wsl.exe --list --all 2>$null) -replace "`0", ""
    foreach ($line in ($distroList -split "`n")) {
        $name = $line.Trim() -replace ' \(Default\)$', ''
        if ($name -eq "Ubuntu-Claude") { $ubuntuClaudeExists = $true }
        if ($name -eq "Ubuntu") { $ubuntuExists = $true }
    }
} catch { }

$ErrorActionPreference = $savedErrorPref

# --- Helper: read a value from env-config.yaml inside the distro ---
function Get-DistroConfig {
    param([string]$Key)
    if (-not $ubuntuClaudeExists) { return "" }
    $readScript = @'
#!/bin/bash
key="$1"
cfg="$HOME/.claude/env-config.yaml"
[ ! -f "$cfg" ] && exit 0
if [[ "$key" == *.* ]]; then
    section="${key%%.*}"; field="${key#*.}"
    sed -n "/^${section}:/,/^[^ ]/p" "$cfg" | grep "^ *${field}:" | head -1 | sed 's/^[^:]*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d '\r' | sed 's/^ *//;s/ *$//'
else
    grep "^${key}:" "$cfg" | head -1 | sed 's/^[^:]*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d '\r' | sed 's/^ *//;s/ *$//'
fi
'@
    $readScript | Invoke-Wsl -d Ubuntu-Claude -u claude-user -- bash -c "tr -d '\r' > /tmp/read-config.sh"
    $result = Invoke-Wsl -d Ubuntu-Claude -u claude-user -- bash /tmp/read-config.sh $Key
    return ($result | Out-String).Trim()
}

# --- Helper: save a value to env-config.yaml inside the distro ---
function Set-DistroConfig {
    param([string]$Key, [string]$Value)
    if (-not $ubuntuClaudeExists) { return }
    $writeScript = @'
#!/bin/bash
key="$1"; value="$2"
cfg="$HOME/.claude/env-config.yaml"
mkdir -p "$(dirname "$cfg")"
safe_value=$(printf '%s' "$value" | sed 's/[|&\\/]/\\&/g')
if [[ "$key" != *.* ]]; then
    if [ -f "$cfg" ] && grep -q "^${key}:" "$cfg"; then
        sed -i "s|^${key}:.*|${key}: \"${safe_value}\"|" "$cfg"
    else
        echo "${key}: \"${value}\"" >> "$cfg"
    fi
else
    section="${key%%.*}"; field="${key#*.}"
    if [ ! -f "$cfg" ]; then
        printf '%s:\n  %s: "%s"\n' "$section" "$field" "$value" > "$cfg"
        exit 0
    fi
    if grep -q "^${section}:" "$cfg"; then
        if sed -n "/^${section}:/,/^[^ ]/p" "$cfg" | grep -q "^ *${field}:"; then
            sed -i "/^${section}:/,/^[^ ]/{s|^ *${field}:.*|  ${field}: \"${safe_value}\"|}" "$cfg"
        else
            sed -i "/^${section}:/a\  ${field}: \"${safe_value}\"" "$cfg"
        fi
    else
        printf '\n%s:\n  %s: "%s"\n' "$section" "$field" "$value" >> "$cfg"
    fi
fi
'@
    $writeScript | Invoke-Wsl -d Ubuntu-Claude -u claude-user -- bash -c "tr -d '\r' > /tmp/write-config.sh"
    Invoke-Wsl -d Ubuntu-Claude -u claude-user -- bash /tmp/write-config.sh $Key $Value
}

if ($DryRun) {
    if ($ubuntuClaudeExists) {
        Write-Host "[Detected] Ubuntu-Claude distro exists" -ForegroundColor Green
    } else {
        Write-Host "[Detected] Ubuntu-Claude distro not found - would create fresh" -ForegroundColor Yellow
        if ($ubuntuExists) {
            Write-Host "[Detected] Ubuntu base distro available" -ForegroundColor Green
        } else {
            Write-Host "[Detected] Ubuntu base distro NOT found - setup would fail" -ForegroundColor Red
        }
    }
    Write-Host ""
}

# --- Background image prompt (state-aware) ---
if (-not $DryRun -and -not $Defaults) {
    if (Test-Path "$RoamingStateCheck\background.jpg") {
        Write-Host ""
        Write-Host "Background Image" -ForegroundColor Cyan
        Write-Host "  Already configured." -ForegroundColor Green
    } else {
        # Check if a URL was saved from a previous run
        $savedBgUrl = Get-DistroConfig "terminal.background_url"
        if (-not [string]::IsNullOrWhiteSpace($savedBgUrl)) {
            Write-Host ""
            Write-Host "Background Image" -ForegroundColor Cyan
            Write-Host "  Reusing saved URL: $savedBgUrl" -ForegroundColor Green
            $BACKGROUND_URL = $savedBgUrl
        } else {
            Write-Host ""
            Write-Host "Background Image Setup" -ForegroundColor Cyan
            Write-Host "  You can set a background image for the terminal." -ForegroundColor Yellow
            Write-Host "  Enter a URL or local path (leave blank to skip):" -ForegroundColor Yellow
            Write-Host ""
            $bgInput = Read-Host "  Background image"
            if (-not [string]::IsNullOrWhiteSpace($bgInput)) {
                $BACKGROUND_URL = $bgInput
            }
        }
    }
} elseif ($DryRun) {
    if (Test-Path "$RoamingStateCheck\background.jpg") {
        Write-Host "[Already configured] Background image" -ForegroundColor Green
    } else {
        $savedBgUrl = Get-DistroConfig "terminal.background_url"
        if (-not [string]::IsNullOrWhiteSpace($savedBgUrl)) {
            Write-Host "[Would reuse] Saved background URL: $savedBgUrl" -ForegroundColor Green
        } else {
            Write-Host "[Would prompt] Background image URL or path" -ForegroundColor Yellow
        }
    }
} elseif ($Defaults) {
    # In Defaults mode, reuse saved URL if available
    $savedBgUrl = Get-DistroConfig "terminal.background_url"
    if (-not [string]::IsNullOrWhiteSpace($savedBgUrl)) {
        $BACKGROUND_URL = $savedBgUrl
        Write-Host "  [defaults] Reusing saved background: $savedBgUrl" -ForegroundColor Yellow
    } else {
        Write-Host "  [defaults] Skipping background image." -ForegroundColor Yellow
    }
}

# --- Color theme selection (state-aware) ---
$ThemeChoices = [ordered]@{
    "1" = "One Half Dark"
    "2" = "Catppuccin Mocha"
    "3" = "Catppuccin Macchiato"
    "4" = "Catppuccin Frappe"
    "5" = "Catppuccin Latte"
}

$SelectedTheme = "One Half Dark"

if (-not $DryRun -and -not $Defaults) {
    $savedTheme = Get-DistroConfig "terminal.color_scheme"
    if (-not [string]::IsNullOrWhiteSpace($savedTheme)) {
        Write-Host ""
        Write-Host "Color Theme" -ForegroundColor Cyan
        Write-Host "  Already configured: $savedTheme" -ForegroundColor Green
        $SelectedTheme = $savedTheme
    } else {
        Write-Host ""
        Write-Host "Color Theme" -ForegroundColor Cyan
        foreach ($entry in $ThemeChoices.GetEnumerator()) {
            Write-Host "    $($entry.Key). $($entry.Value)"
        }
        Write-Host ""
        $themeChoice = Read-Host "  Selection (default: 1)"
        if ([string]::IsNullOrWhiteSpace($themeChoice)) { $themeChoice = "1" }
        if ($ThemeChoices.Contains($themeChoice)) {
            $SelectedTheme = $ThemeChoices[$themeChoice]
        }
        Write-Host "  Selected: $SelectedTheme" -ForegroundColor Green
    }
} elseif ($DryRun) {
    $savedTheme = Get-DistroConfig "terminal.color_scheme"
    if (-not [string]::IsNullOrWhiteSpace($savedTheme)) {
        Write-Host "[Already configured] Color theme: $savedTheme" -ForegroundColor Green
    } else {
        Write-Host "[Would prompt] Color theme selection" -ForegroundColor Yellow
    }
} elseif ($Defaults) {
    $savedTheme = Get-DistroConfig "terminal.color_scheme"
    if (-not [string]::IsNullOrWhiteSpace($savedTheme)) {
        $SelectedTheme = $savedTheme
        Write-Host "  [defaults] Reusing saved theme: $savedTheme" -ForegroundColor Yellow
    } else {
        Write-Host "  [defaults] Using One Half Dark." -ForegroundColor Yellow
    }
}

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
                Set-DistroConfig "terminal.background_url" $cleanPath
            } catch {
                Write-Warning "Failed to download background image: $($_.Exception.Message)"
            }
        } elseif (Test-Path $cleanPath) {
            Write-Host "Copying background image from local path..." -ForegroundColor Cyan
            try {
                Copy-Item $cleanPath "$RoamingState\background.jpg" -Force
                Write-Host "  Done." -ForegroundColor Green
                Set-DistroConfig "terminal.background_url" $cleanPath
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
    if ($ubuntuClaudeExists) {
        $existingShareDry = (Invoke-Wsl -d Ubuntu-Claude -u root -- bash -c "grep 'drvfs' /etc/fstab 2>/dev/null | grep -v '^#' || true" | Out-String).Trim()
        if (-not [string]::IsNullOrWhiteSpace($existingShareDry)) {
            Write-Host "[Already configured] Shared directory: $existingShareDry" -ForegroundColor Green
        } else {
            Write-Host "[Would prompt] Shared Windows directory configuration" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[Would prompt] Shared Windows directory (after distro creation)" -ForegroundColor Yellow
    }
} elseif ($Defaults) {
    Write-Host "  [defaults] Skipping shared directory." -ForegroundColor Yellow
} else {
    # Check if a shared directory is already configured (existing distro)
    $existingShare = ""
    if ($ubuntuClaudeExists) {
        $existingShare = (Invoke-Wsl -d Ubuntu-Claude -u root -- bash -c "grep 'drvfs' /etc/fstab 2>/dev/null | grep -v '^#' || true" | Out-String).Trim()
    }

    Write-Host ""
    Write-Host "Shared Windows Directory" -ForegroundColor Cyan
    if (-not [string]::IsNullOrWhiteSpace($existingShare)) {
        Write-Host "  Already configured: $existingShare" -ForegroundColor Green
        $shareResponse = "n"
    } else {
        Write-Host "  Automount is disabled for sandbox isolation, but you can share" -ForegroundColor Yellow
        Write-Host "  a single Windows directory into WSL." -ForegroundColor Yellow
        Write-Host ""
        $shareResponse = Read-Host "  Share a Windows directory? (y/N)"
    }

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
        if (-not [string]::IsNullOrWhiteSpace($existingShare)) {
            Write-Host "  [keep] Keeping existing shared directory." -ForegroundColor Green
        } else {
            Write-Host "  [skip] No shared directory configured." -ForegroundColor Yellow
        }
    }
}

# --- 4. Update flags ---
$DoRepoSync = $true

# --- Existing distro: status check + update menu ---
if ($ubuntuClaudeExists) {
    Write-Host "`nUbuntu-Claude already exists. Checking configuration..." -ForegroundColor Cyan

    $checkScript = @'
echo "claude_user=$(id claude-user &>/dev/null && echo Y || echo N)"
echo "sudo_rules=$(grep -q 'apt' /etc/sudoers.d/claude-user 2>/dev/null && echo Y || echo N)"
echo "wsl_conf=$(grep -q 'default.*=.*claude-user' /etc/wsl.conf 2>/dev/null && echo Y || echo N)"
echo "dev_skills=$(test -d /home/claude-user/development-skills && echo Y || echo N)"
echo "shared_dir=$(grep -q 'drvfs' /etc/fstab 2>/dev/null && echo Y || echo N)"
echo "vscode=$(test -L /usr/local/bin/code && echo Y || echo N)"
echo "ro_mount=$(grep -q 'options.*=.*ro' /etc/wsl.conf 2>/dev/null && echo Y || echo N)"
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
        $doSudoReconfig = $sudoMissing
        $doVSCodeSetup = $vscodeMissing
    } elseif ($DryRun) {
        Write-Host "  [dry-run] Would offer update menu (defaults: $defaultStr)" -ForegroundColor Yellow
        $DoRepoSync = $true
        $doSudoReconfig = $sudoMissing
        $doVSCodeSetup = $vscodeMissing
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
# Idempotent automount config — use python3 to safely rewrite the INI section
python3 -c "
import configparser, os
conf = configparser.ConfigParser()
conf.read('/etc/wsl.conf')
if not conf.has_section('automount'):
    conf.add_section('automount')
conf.set('automount', 'enabled', 'true')
conf.set('automount', 'mountFsTab', 'true')
conf.set('automount', 'options', 'ro,metadata')
with open('/etc/wsl.conf', 'w') as f:
    conf.write(f)
"
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
if (-not $ubuntuClaudeExists -and $DryRun) {
    Write-Host ""
    if (-not $ubuntuExists) {
        Write-Host "[Would FAIL] Ubuntu base distro not found" -ForegroundColor Red
        Write-Host "  Install first: winget install Canonical.Ubuntu" -ForegroundColor Yellow
    } else {
        Write-Host "[Would create] Ubuntu-Claude distro from Ubuntu base" -ForegroundColor Yellow
        Write-Host "  Export Ubuntu -> C:\wsl-exports\ubuntu-base.tar" -ForegroundColor Yellow
        Write-Host "  Import as Ubuntu-Claude -> C:\wsl-instances\ubuntu-claude" -ForegroundColor Yellow
        Write-Host "[Would configure] claude-user account, wsl.conf, sudoers" -ForegroundColor Yellow
        Write-Host "[Would prompt] Sudo permission selection" -ForegroundColor Yellow
        Write-Host "[Would configure] VS Code symlink + readonly Windows mount" -ForegroundColor Yellow
    }
}

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

# Add shared directory mount if configured (idempotent — skip if already present)
if [[ -n "$fstabLine" ]]; then
    mkdir -p "$mountDir"
    if ! grep -qF "$mountDir" /etc/fstab 2>/dev/null; then
        echo "$fstabLine" >> /etc/fstab
    fi
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
set -e
# Remove any existing drvfs mounts and add the new one
sed -i '/drvfs/d' /etc/fstab 2>/dev/null || true
echo "$fstabEntry" >> /etc/fstab
mkdir -p "$SharedMountPoint"
# Ensure automount section has mountFsTab=true (idempotent via python3)
python3 -c "
import configparser
conf = configparser.ConfigParser()
conf.read('/etc/wsl.conf')
if not conf.has_section('automount'):
    conf.add_section('automount')
conf.set('automount', 'mountFsTab', 'true')
if not conf.has_option('automount', 'options'):
    conf.set('automount', 'options', 'ro,metadata')
with open('/etc/wsl.conf', 'w') as f:
    conf.write(f)
"
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

        # --- Install Catppuccin color scheme if selected ---
        if ($SelectedTheme -like "Catppuccin*") {
            $catppuccinSchemes = @{
                "Catppuccin Mocha" = @{
                    "name" = "Catppuccin Mocha"; "cursorColor" = "#F5E0DC"; "selectionBackground" = "#585B70"
                    "background" = "#1E1E2E"; "foreground" = "#CDD6F4"
                    "black" = "#45475A"; "red" = "#F38BA8"; "green" = "#A6E3A1"; "yellow" = "#F9E2AF"
                    "blue" = "#89B4FA"; "purple" = "#F5C2E7"; "cyan" = "#94E2D5"; "white" = "#BAC2DE"
                    "brightBlack" = "#585B70"; "brightRed" = "#F38BA8"; "brightGreen" = "#A6E3A1"; "brightYellow" = "#F9E2AF"
                    "brightBlue" = "#89B4FA"; "brightPurple" = "#F5C2E7"; "brightCyan" = "#94E2D5"; "brightWhite" = "#A6ADC8"
                }
                "Catppuccin Macchiato" = @{
                    "name" = "Catppuccin Macchiato"; "cursorColor" = "#F4DBD6"; "selectionBackground" = "#5B6078"
                    "background" = "#24273A"; "foreground" = "#CAD3F5"
                    "black" = "#494D64"; "red" = "#ED8796"; "green" = "#A6DA95"; "yellow" = "#EED49F"
                    "blue" = "#8AADF4"; "purple" = "#F5BDE6"; "cyan" = "#8BD5CA"; "white" = "#B8C0E0"
                    "brightBlack" = "#5B6078"; "brightRed" = "#ED8796"; "brightGreen" = "#A6DA95"; "brightYellow" = "#EED49F"
                    "brightBlue" = "#8AADF4"; "brightPurple" = "#F5BDE6"; "brightCyan" = "#8BD5CA"; "brightWhite" = "#A5ADCB"
                }
                "Catppuccin Frappe" = @{
                    "name" = "Catppuccin Frappe"; "cursorColor" = "#F2D5CF"; "selectionBackground" = "#626880"
                    "background" = "#303446"; "foreground" = "#C6D0F5"
                    "black" = "#51576D"; "red" = "#E78284"; "green" = "#A6D189"; "yellow" = "#E5C890"
                    "blue" = "#8CAAEE"; "purple" = "#F4B8E4"; "cyan" = "#81C8BE"; "white" = "#B5BFE2"
                    "brightBlack" = "#626880"; "brightRed" = "#E78284"; "brightGreen" = "#A6D189"; "brightYellow" = "#E5C890"
                    "brightBlue" = "#8CAAEE"; "brightPurple" = "#F4B8E4"; "brightCyan" = "#81C8BE"; "brightWhite" = "#A5ADCE"
                }
                "Catppuccin Latte" = @{
                    "name" = "Catppuccin Latte"; "cursorColor" = "#DC8A78"; "selectionBackground" = "#ACB0BE"
                    "background" = "#EFF1F5"; "foreground" = "#4C4F69"
                    "black" = "#5C5F77"; "red" = "#D20F39"; "green" = "#40A02B"; "yellow" = "#DF8E1D"
                    "blue" = "#1E66F5"; "purple" = "#EA76CB"; "cyan" = "#179299"; "white" = "#ACB0BE"
                    "brightBlack" = "#ACB0BE"; "brightRed" = "#D20F39"; "brightGreen" = "#40A02B"; "brightYellow" = "#DF8E1D"
                    "brightBlue" = "#1E66F5"; "brightPurple" = "#EA76CB"; "brightCyan" = "#179299"; "brightWhite" = "#BCC0CC"
                }
            }

            $scheme = $catppuccinSchemes[$SelectedTheme]
            if ($scheme) {
                # Ensure schemes array exists
                if (-not $settings.schemes) {
                    $settings | Add-Member -NotePropertyName "schemes" -NotePropertyValue @() -Force
                }
                # Add or update the scheme
                $existingScheme = $settings.schemes | Where-Object { $_.name -eq $SelectedTheme }
                if (-not $existingScheme) {
                    $schemeObj = New-Object PSObject -Property $scheme
                    $settings.schemes += $schemeObj
                    Write-Host "  Installed $SelectedTheme color scheme" -ForegroundColor Cyan
                }
            }
        }

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
                "startingDirectory" = "//wsl$/Ubuntu-Claude/home/claude-user"
                "hidden" = $false
                "icon" = "ms-appdata:///roaming/claude-icon.ico"
                "tabTitle" = "Claude (Sandboxed)"
                "colorScheme" = $SelectedTheme
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
            # Update existing profile with any missing fields
            $existingProfile = $settings.profiles.list | Where-Object {
                $_.name -eq "Ubuntu-Claude" -and $_.commandline -like "*Ubuntu-Claude*" -and -not $_.source
            } | Select-Object -First 1

            if ($existingProfile) {
                $updated = @()
                if (-not $existingProfile.startingDirectory) {
                    $existingProfile | Add-Member -NotePropertyName "startingDirectory" -NotePropertyValue "//wsl$/Ubuntu-Claude/home/claude-user" -Force
                    $updated += "startingDirectory"
                }
                if (-not $existingProfile.backgroundImage -and (Test-Path "$RoamingState\background.jpg")) {
                    $existingProfile | Add-Member -NotePropertyName "backgroundImage" -NotePropertyValue "ms-appdata:///roaming/background.jpg" -Force
                    $existingProfile | Add-Member -NotePropertyName "backgroundImageOpacity" -NotePropertyValue 0.5 -Force
                    $updated += "backgroundImage"
                }
                if ($existingProfile.colorScheme -ne $SelectedTheme) {
                    $existingProfile | Add-Member -NotePropertyName "colorScheme" -NotePropertyValue $SelectedTheme -Force
                    $updated += "colorScheme"
                }
                if ($updated.Count -gt 0) {
                    $needsSave = $true
                    Write-Host "  Updated profile: $($updated -join ', ')" -ForegroundColor Cyan
                } else {
                    Write-Host "  Custom profile already exists - up to date" -ForegroundColor Green
                }
            }
        }

        if ($needsSave -or $hiddenCount -gt 0) {
            Copy-Item $SettingsDst "$SettingsDst.bak" -Force
            $settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsDst -Encoding UTF8
        }

        # Save theme choice to distro config
        Set-DistroConfig "terminal.color_scheme" $SelectedTheme
    } catch {
        Write-Warning "Failed to update Windows Terminal settings: $($_.Exception.Message)"
    }
} elseif ($DryRun -and (Test-Path $SettingsDst)) {
    Write-Host ""
    Write-Host "[Would check] Windows Terminal profiles and color scheme for Ubuntu-Claude" -ForegroundColor Yellow
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
    Write-Host "  /setup-env"
}
