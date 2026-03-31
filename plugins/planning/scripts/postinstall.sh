#!/usr/bin/env bash
set -euo pipefail
PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CANONICAL_DIR="$HOME/.config/development-skills"
mkdir -p "$CANONICAL_DIR/lib"
cp "$PLUGIN_DIR"/lib/*.md "$CANONICAL_DIR/lib/" 2>/dev/null || echo "Warning: no lib files found to sync"
echo "Synced libs to $CANONICAL_DIR/lib/"
