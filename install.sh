#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
mkdir -p "$SKILLS_DIR"

echo "=== Installing skills ==="
for skill_dir in "$REPO_DIR/skills"/*/; do
  name=$(basename "$skill_dir")
  target="$SKILLS_DIR/$name"
  if [[ -L "$target" ]]; then
    echo "  $name: already linked"
  elif [[ -d "$target" ]]; then
    echo "  $name: EXISTS (not symlink) — skipping"
  else
    ln -sf "$skill_dir" "$target"
    echo "  $name: linked"
  fi
done

echo ""
echo "=== Prerequisites ==="
[[ -f "$HOME/.config/code-review-agent/token" ]] && echo "  review-agent token: OK" || echo "  review-agent token: MISSING"
for srv in gitea tandoor obsidian grocy google kroger ersatztv; do
  if grep -q "\"$srv\"" "$HOME/.mcp.json" 2>/dev/null; then
    echo "  MCP $srv: OK"
  elif grep -q "\"$srv\"" "$HOME/.claude.json" 2>/dev/null; then
    echo "  MCP $srv: OK (.claude.json)"
  else
    echo "  MCP $srv: not configured"
  fi
done
