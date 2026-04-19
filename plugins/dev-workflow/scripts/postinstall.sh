#!/usr/bin/env bash
set -euo pipefail
PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CANONICAL_DIR="$HOME/.config/development-skills"
mkdir -p "$CANONICAL_DIR/lib"
cp "$PLUGIN_DIR"/lib/*.md "$CANONICAL_DIR/lib/" 2>/dev/null || echo "Warning: no lib files found to sync"
echo "Synced libs to $CANONICAL_DIR/lib/"

# Install the gitea-workflow-mcp binary if not already on PATH.
# The plugin's .mcp.json auto-registers the MCP server with Claude Code,
# but the binary itself must be installed separately since the plugin cache
# only contains the plugin directory, not the repo-root Python package.
if ! command -v gitea-workflow-mcp &>/dev/null; then
  REPO_ROOT="$HOME/gitea-repos/development-skills"
  if [ -d "$REPO_ROOT" ] && [ -f "$REPO_ROOT/pyproject.toml" ]; then
    echo "Installing gitea-workflow-mcp..."
    uv tool install --editable "$REPO_ROOT" 2>/dev/null \
      || pip install -e "$REPO_ROOT" 2>/dev/null \
      || echo "Warning: could not install gitea-workflow-mcp. Run 'uv tool install --editable ~/gitea-repos/development-skills' manually."
  else
    echo "Warning: gitea-workflow-mcp not found and $REPO_ROOT does not exist. Clone development-skills and re-run plugin install."
  fi
else
  echo "gitea-workflow-mcp already installed."
fi

# Ensure GITEA_URL and GITEA_TOKEN are in the user's shell profile.
# The .mcp.json uses ${VAR} template references that read from the
# launching shell environment at MCP startup time.
case "${SHELL:-/bin/bash}" in
  */zsh) SHELL_RC="$HOME/.zshrc" ;;
  *)     SHELL_RC="$HOME/.bashrc" ;;
esac

if [ -f "$SHELL_RC" ]; then
  if ! grep -q "^export GITEA_URL=" "$SHELL_RC" 2>/dev/null; then
    # Try to discover the URL from the running gitea-mcp process
    GITEA_URL_VAL=""
    if pgrep -f "gitea-mcp" &>/dev/null; then
      GITEA_URL_VAL=$(cat /proc/"$(pgrep -f 'gitea-mcp -t stdio' | head -1)"/environ 2>/dev/null | tr '\0' '\n' | grep "^GITEA_HOST=" | cut -d= -f2-)
    fi
    if [ -n "$GITEA_URL_VAL" ]; then
      echo "export GITEA_URL=\"$GITEA_URL_VAL\"" >> "$SHELL_RC"
      echo "Added GITEA_URL=$GITEA_URL_VAL to $SHELL_RC"
    else
      echo "Warning: GITEA_URL not set in $SHELL_RC and could not auto-detect. Set it manually."
    fi
  fi
  if ! grep -q "^export GITEA_TOKEN=" "$SHELL_RC" 2>/dev/null; then
    GITEA_TOKEN_VAL=""
    if pgrep -f "gitea-mcp" &>/dev/null; then
      GITEA_TOKEN_VAL=$(cat /proc/"$(pgrep -f 'gitea-mcp -t stdio' | head -1)"/environ 2>/dev/null | tr '\0' '\n' | grep "^GITEA_ACCESS_TOKEN=" | cut -d= -f2-)
    fi
    if [ -n "$GITEA_TOKEN_VAL" ]; then
      echo "export GITEA_TOKEN=\"$GITEA_TOKEN_VAL\"" >> "$SHELL_RC"
      echo "Added GITEA_TOKEN to $SHELL_RC"
    else
      echo "Warning: GITEA_TOKEN not set in $SHELL_RC and could not auto-detect. Set it manually."
    fi
  fi
fi
