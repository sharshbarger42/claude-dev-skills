#!/usr/bin/env bash
# Sync authoritative lib/ and config/ to the canonical runtime location.
# Run after cloning or updating the repo to ensure skills can find their includes.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CANONICAL_DIR="$HOME/.config/development-skills"

echo "Syncing libs from $REPO_DIR to $CANONICAL_DIR..."

# Sync lib/ files
mkdir -p "$CANONICAL_DIR/lib"
cp -u "$REPO_DIR"/lib/*.md "$CANONICAL_DIR/lib/" 2>/dev/null || true
echo "  lib/: $(ls "$CANONICAL_DIR/lib/" | wc -l) files"

# Sync config/ files (repos.md, infrastructure.md, deploy-config.md)
# Only copy if the canonical file doesn't exist — don't overwrite per-machine config
mkdir -p "$CANONICAL_DIR/config"
for f in "$REPO_DIR"/config/*.md; do
    basename="$(basename "$f")"
    if [[ ! -f "$CANONICAL_DIR/config/$basename" ]]; then
        cp "$f" "$CANONICAL_DIR/config/$basename"
        echo "  config/$basename: copied (new)"
    else
        echo "  config/$basename: exists (skipped — per-machine config)"
    fi
done

echo "Done. Canonical path: $CANONICAL_DIR"
