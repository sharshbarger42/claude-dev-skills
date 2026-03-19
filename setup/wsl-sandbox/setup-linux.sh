#!/usr/bin/env bash
# WSL sandbox Linux setup script
# Installs core tools, configures git, sets up dotfiles, installs development-skills.
# Adapted for homelab/Gitea environment (no GitHub/AWS/Jira).
#
# Usage:
#   ~/development-skills/setup/wsl-sandbox/setup-linux.sh
#
# Prerequisites:
#   - Running as claude-user in Ubuntu-Claude distro
#   - development-skills repo present at ~/development-skills (copied by setup-windows.ps1)
#   - sudo configured for apt install/update (done by setup-windows.ps1)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_SKILLS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOTFILES_DEFAULTS="$DEV_SKILLS_DIR/setup/dotfiles-defaults"

echo ""
echo "=========================================="
echo " Development Skills Sandbox - Linux Setup"
echo "=========================================="
echo ""

# --- Helpers ---
command_exists() { command -v "$1" &>/dev/null; }
install_if_missing() {
    local cmd="$1" pkg="${2:-$1}"
    if command_exists "$cmd"; then
        echo "  [skip] $cmd already installed"
    else
        echo "  [install] $cmd..."
        sudo apt-get install -y "$pkg" > /dev/null 2>&1
    fi
}

# Read a value from env-config.yaml
ENV_CONFIG="${HOME}/.claude/env-config.yaml"
if [[ ! -f "$ENV_CONFIG" ]]; then
    ENV_CONFIG="${DEV_SKILLS_DIR}/setup/env-config.yaml"
fi
config_get() {
    local key="$1"
    if [[ ! -f "$ENV_CONFIG" ]]; then
        echo ""
        return
    fi
    if [[ "$key" == *.* ]]; then
        local section="${key%%.*}"
        local field="${key#*.}"
        sed -n "/^${section}:/,/^[^ ]/p" "$ENV_CONFIG" \
            | { grep "^  ${field}:" || true; } \
            | head -1 \
            | sed 's/^[^:]*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' \
            | tr -d '\r' \
            | sed 's/^ *//;s/ *$//'
    else
        { grep "^${key}:" "$ENV_CONFIG" || true; } \
            | head -1 \
            | sed 's/^[^:]*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' \
            | tr -d '\r' \
            | sed 's/^ *//;s/ *$//'
    fi
}

config_save() {
    local key="$1" value="$2"
    local safe_value
    safe_value=$(printf '%s' "$value" | sed 's/[|&\\/]/\\&/g')
    local target="${HOME}/.claude/env-config.yaml"
    mkdir -p "$(dirname "$target")"
    if [[ "$key" != *.* ]]; then
        if [[ -f "$target" ]] && grep -q "^${key}:" "$target"; then
            sed -i "s|^${key}:.*|${key}: \"${safe_value}\"|" "$target"
        else
            echo "${key}: \"${value}\"" >> "$target"
        fi
    else
        local section="${key%%.*}"
        local field="${key#*.}"
        if [[ ! -f "$target" ]]; then
            printf "%s:\n  %s: \"%s\"\n" "$section" "$field" "$value" > "$target"
            return
        fi
        if grep -q "^${section}:" "$target"; then
            if sed -n "/^${section}:/,/^[^ ]/p" "$target" | grep -q "^  ${field}:"; then
                sed -i "/^${section}:/,/^[^ ]/{s|^  ${field}:.*|  ${field}: \"${safe_value}\"|}" "$target"
            else
                sed -i "/^${section}:/a\\  ${field}: \"${safe_value}\"" "$target"
            fi
        else
            printf "\n%s:\n  %s: \"%s\"\n" "$section" "$field" "$value" >> "$target"
        fi
    fi
}

# --- Restore backup (before anything reads config) ---
BACKUP_FILE="$HOME/claude-backup.tar.gz"
if [[ -f "$BACKUP_FILE" ]]; then
    echo "--- Restore Previous Data ---"
    echo "  Found backup from a previous teardown."
    echo "  This contains:"
    echo "    - ~/.claude/projects/ (Claude Code auto-memory)"
    echo "    - ~/.claude/env-config.yaml (setup config)"
    echo "    - ~/gitea-repos/ session files"
    echo ""
    read -rp "  Restore this data? (Y/n): " RESTORE_CHOICE
    if [[ "${RESTORE_CHOICE,,}" != "n" ]]; then
        echo "  Restoring..."
        tar xzf "$BACKUP_FILE" -C "$HOME" 2>/dev/null
        echo "  Done. Previous data restored."
        rm -f "$BACKUP_FILE"
        if [[ -f "${HOME}/.claude/env-config.yaml" ]]; then
            ENV_CONFIG="${HOME}/.claude/env-config.yaml"
        fi
    else
        echo "  [skip] Backup not restored."
        echo "  The backup is still at $BACKUP_FILE if you change your mind."
    fi
    echo ""
fi

# --- 1. Core system packages ---
echo "--- Installing core packages ---"
sudo apt-get update > /dev/null 2>&1
install_if_missing git git
install_if_missing jq jq
install_if_missing curl curl
install_if_missing wget wget
install_if_missing unzip unzip
install_if_missing stow stow
install_if_missing zsh zsh

# Tmux is optional
TMUX_ENABLED=$(config_get "enhancements.tmux")
if [[ "$TMUX_ENABLED" == "true" ]]; then
    install_if_missing tmux tmux
fi

# --- 2. Node.js (required for Claude Code CLI) ---
echo ""
echo "--- Node.js ---"
if command_exists node; then
    echo "  [skip] node already installed ($(node --version))"
else
    echo "  [install] node via nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash > /dev/null 2>&1
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    nvm install --lts > /dev/null 2>&1
fi

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# --- 3. Claude Code CLI ---
echo ""
echo "--- Claude Code CLI ---"
if command_exists claude; then
    echo "  [skip] claude already installed"
else
    echo "  [install] claude code cli..."
    npm install -g @anthropic-ai/claude-code > /dev/null 2>&1
fi

# --- 4. Git Identity ---
echo ""
echo "--- Git Identity ---"
CURRENT_NAME=$(git config --global user.name 2>/dev/null || true)
CURRENT_EMAIL=$(git config --global user.email 2>/dev/null || true)

if [[ -n "$CURRENT_NAME" && -n "$CURRENT_EMAIL" ]]; then
    echo "  [skip] already configured: $CURRENT_NAME <$CURRENT_EMAIL>"
else
    CONFIG_NAME=$(config_get "git.name")
    CONFIG_EMAIL=$(config_get "git.email")

    GIT_NAME="${CONFIG_NAME:-}"
    GIT_EMAIL="${CONFIG_EMAIL:-}"
    read -rp "  Git name${GIT_NAME:+ [$GIT_NAME]}: " INPUT_NAME
    read -rp "  Git email${GIT_EMAIL:+ [$GIT_EMAIL]}: " INPUT_EMAIL
    GIT_NAME="${INPUT_NAME:-$GIT_NAME}"
    GIT_EMAIL="${INPUT_EMAIL:-$GIT_EMAIL}"

    echo "  Setting: $GIT_NAME <$GIT_EMAIL>"
    git config --global user.name "$GIT_NAME"
    git config --global user.email "$GIT_EMAIL"
    git config --global init.defaultBranch main
    git config --global push.autoSetupRemote true

    config_save "git.name" "$GIT_NAME"
    config_save "git.email" "$GIT_EMAIL"
fi

# --- 5. Oh My Zsh ---
echo ""
echo "--- Oh My Zsh ---"
if [[ -d "$HOME/.oh-my-zsh" ]]; then
    echo "  [skip] already installed"
else
    echo "  [install] oh-my-zsh..."
    RUNZSH=no CHSH=no sh -c \
        "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" > /dev/null 2>&1
fi

CURRENT_SHELL=$(getent passwd "$(whoami)" | cut -d: -f7)
if [[ "$CURRENT_SHELL" != */zsh ]]; then
    echo "  Setting zsh as default shell..."
    sudo /usr/bin/chsh -s /bin/zsh "$(whoami)" 2>/dev/null || chsh -s /bin/zsh 2>/dev/null || true
fi

# --- 6. Dotfiles ---
echo ""
echo "--- Dotfiles ---"

CONFIG_DOTFILES_URL=$(config_get "dotfiles.url")
DOTFILES_DIR="$HOME/repos/dotfiles"
mkdir -p "$HOME/repos"

if [[ -d "$DOTFILES_DIR" ]]; then
    DOTFILES_ORIGIN=$(cd "$DOTFILES_DIR" && git remote get-url origin 2>/dev/null || echo "unknown")
    echo "  Dotfiles already present from: $DOTFILES_ORIGIN"
    DOTFILES_READY=true
elif [[ -n "$CONFIG_DOTFILES_URL" ]]; then
    echo "  [config] Cloning dotfiles from $CONFIG_DOTFILES_URL"
    git clone "$CONFIG_DOTFILES_URL" "$DOTFILES_DIR" 2>&1 | sed 's/^/  /'
    DOTFILES_READY=true
    config_save "dotfiles.url" "$CONFIG_DOTFILES_URL"
else
    echo "  Dotfiles configure your shell, terminal, and editor."
    echo ""
    read -rp "  Do you have a dotfiles repo? (y/N): " HAS_DOTFILES
    if [[ "${HAS_DOTFILES,,}" == "y" ]]; then
        read -rp "  Dotfiles repo URL: " DOTFILES_URL
        git clone "$DOTFILES_URL" "$DOTFILES_DIR" 2>&1 | sed 's/^/  /'
        DOTFILES_READY=true
        config_save "dotfiles.url" "$DOTFILES_URL"
    else
        DOTFILES_READY=false
    fi
fi

if [[ "$DOTFILES_READY" == "true" && -d "$DOTFILES_DIR" ]]; then
    CONFIG_PACKAGES=$(config_get "dotfiles.packages")
    if [[ -n "$CONFIG_PACKAGES" ]]; then
        STOW_PACKAGES=$(echo "$CONFIG_PACKAGES" | tr -d '[]' | tr ',' ' ' | xargs)
    else
        STOW_PACKAGES=$(ls -d "$DOTFILES_DIR"/*/ 2>/dev/null | xargs -I{} basename {} | tr '\n' ' ')
    fi

    echo "  Stowing packages: $STOW_PACKAGES"
    cd "$DOTFILES_DIR"
    for pkg in $STOW_PACKAGES; do
        if [[ -d "$pkg" ]]; then
            stow -n "$pkg" 2>&1 | { grep "existing target" || true; } | sed 's/.*: //' | while read -r conflict; do
                rm -f "$HOME/$conflict" 2>/dev/null || true
            done
            stow "$pkg" 2>/dev/null && echo "    [stow] $pkg" || echo "    [warn] $pkg failed to stow"
        else
            echo "    [skip] $pkg (not found)"
        fi
    done
    cd "$HOME"
else
    echo "  Applying default dotfiles from development-skills..."
    cp "$DOTFILES_DEFAULTS/zsh/.zshrc" "$HOME/.zshrc" 2>/dev/null || true
    cp "$DOTFILES_DEFAULTS/tmux/.tmux.conf" "$HOME/.tmux.conf" 2>/dev/null || true
    echo "  Default dotfiles applied."
fi

# --- 7. Install development-skills ---
echo ""
echo "--- Installing development-skills ---"
if [[ -f "$DEV_SKILLS_DIR/install.sh" ]]; then
    bash "$DEV_SKILLS_DIR/install.sh"
else
    echo "  [error] install.sh not found at $DEV_SKILLS_DIR"
    echo "  Skills not installed. Run install.sh manually after fixing."
    exit 1
fi

# --- 8. Set up PATH and repos directory ---
echo ""
echo "--- PATH and directory setup ---"
mkdir -p "$HOME/bin" "$HOME/gitea-repos"
BASHRC="$HOME/.bashrc"

if ! grep -q 'HOME/bin' "$BASHRC" 2>/dev/null; then
    echo 'export PATH="$HOME/bin:$HOME/.local/bin:$PATH"' >> "$BASHRC"
fi
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"

if ! grep -q 'NVM_DIR' "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" << 'NVMRC'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
NVMRC
fi

# --- 9. Zsh plugins ---
echo ""
echo "--- Zsh Plugins ---"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
for plugin_repo in \
    "zsh-users/zsh-autosuggestions" \
    "zsh-users/zsh-syntax-highlighting"; do
    plugin_name="${plugin_repo##*/}"
    plugin_dir="$ZSH_CUSTOM/plugins/$plugin_name"
    if [[ -d "$plugin_dir" ]]; then
        echo "  [skip] $plugin_name already installed"
    else
        echo "  [install] $plugin_name..."
        git clone "https://github.com/$plugin_repo.git" "$plugin_dir" --depth 1 > /dev/null 2>&1
    fi
done

# fzf binary (the OMZ fzf plugin needs the binary)
if command_exists fzf; then
    echo "  [skip] fzf already installed"
else
    echo "  [install] fzf..."
    sudo apt-get install -y fzf > /dev/null 2>&1
fi

# --- Done ---
echo ""
echo "=========================================="
echo " Linux setup complete!"
echo "=========================================="
echo ""
echo "Installed:"
CORE_PKGS="git, jq, curl, wget, unzip, stow, zsh"
command_exists tmux && CORE_PKGS="$CORE_PKGS, tmux"
echo "  - Core packages ($CORE_PKGS)"
echo "  - Node.js (via nvm)"
echo "  - Claude Code CLI"
echo "  - Oh My Zsh"
echo "  - development-skills"
echo ""
echo "Configured:"
GIT_CONFIGURED_NAME=$(git config --global user.name 2>/dev/null || true)
GIT_CONFIGURED_EMAIL=$(git config --global user.email 2>/dev/null || true)
CONFIGURED_SHELL=$(getent passwd "$(whoami)" | cut -d: -f7)
echo "  - Git: $GIT_CONFIGURED_NAME <$GIT_CONFIGURED_EMAIL>"
echo "  - Shell: $CONFIGURED_SHELL"
if [[ -d "$DOTFILES_DIR" ]]; then
    DOTFILES_ORIGIN=$(cd "$DOTFILES_DIR" && git remote get-url origin 2>/dev/null || echo "local")
    echo "  - Dotfiles: $DOTFILES_ORIGIN"
fi
echo "  - PATH: ~/bin, nvm"
echo "  - Repos dir: ~/gitea-repos/"
echo ""
echo "Next:"
echo "  Open a new terminal (or run: exec zsh) then run: claude"
echo ""
echo "Then run /start inside Claude Code."
echo ""
