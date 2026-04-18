#!/usr/bin/env bash
set -euo pipefail
PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CANONICAL_DIR="$HOME/.config/development-skills"
mkdir -p "$CANONICAL_DIR/lib"
cp "$PLUGIN_DIR"/lib/*.md "$CANONICAL_DIR/lib/" 2>/dev/null || echo "Warning: no lib files found to sync"
# Sync issue-formats subdirectory (used by create-issues, update-issue, create-subtasks)
if [ -d "$PLUGIN_DIR/lib/issue-formats" ]; then
    mkdir -p "$CANONICAL_DIR/lib/issue-formats"
    cp "$PLUGIN_DIR"/lib/issue-formats/*.md "$CANONICAL_DIR/lib/issue-formats/" 2>/dev/null || echo "Warning: no issue-formats files found to sync"
fi
echo "Synced libs to $CANONICAL_DIR/lib/"
