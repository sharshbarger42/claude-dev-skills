#!/usr/bin/env bash
# PreToolUse hook: Directory boundary enforcement.
# Blocks Edit/Write to files outside the launch directory unless
# the target directory tree contains an AGENTS.md.
#
# Exit codes:
#   0 = allow (no output or informational message)
#   2 = block (stderr message shown to user)

# Safety: if jq is missing, allow with warning
if ! command -v jq &>/dev/null; then
    echo "boundary-guard: jq not found, allowing by default" >&2
    exit 0
fi

# Read tool input JSON from stdin
INPUT="$(cat)"

# Extract file_path from JSON (Edit and Write both use file_path)
FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')"

# If no file_path found, this tool call doesn't write to a file — allow
if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# Expand ~ to $HOME
FILE_PATH="${FILE_PATH/#\~/$HOME}"

# Normalize path: collapse .. and redundant slashes without resolving symlinks
if command -v python3 &>/dev/null; then
    FILE_PATH="$(python3 -c "import os.path, sys; print(os.path.normpath(sys.argv[1]))" "$FILE_PATH")"
else
    # Fallback: use realpath --no-symlinks if available, else use path as-is
    if command -v realpath &>/dev/null; then
        FILE_PATH="$(realpath --no-symlinks "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")"
    fi
fi

LAUNCH_DIR="$(pwd)"

# --- Allow rules (order matters) ---

# 1. Within launch directory
if [[ "$FILE_PATH" == "$LAUNCH_DIR"/* || "$FILE_PATH" == "$LAUNCH_DIR" ]]; then
    exit 0
fi

# 2. Under /tmp/
if [[ "$FILE_PATH" == /tmp/* || "$FILE_PATH" == /tmp ]]; then
    exit 0
fi

# 3. Under ~/.claude/
CLAUDE_DIR="$HOME/.claude"
if [[ "$FILE_PATH" == "$CLAUDE_DIR"/* || "$FILE_PATH" == "$CLAUDE_DIR" ]]; then
    exit 0
fi

# 4. Under ~/.config/development-skills/
LOCAL_CONFIG="$HOME/.config/development-skills"
if [[ "$FILE_PATH" == "$LOCAL_CONFIG"/* || "$FILE_PATH" == "$LOCAL_CONFIG" ]]; then
    exit 0
fi

# 5. Target directory tree has AGENTS.md — walk up from file's directory
check_dir="$(dirname "$FILE_PATH")"
found_agents=""
while [[ "$check_dir" != "/" ]]; do
    if [[ -f "$check_dir/AGENTS.md" ]]; then
        found_agents="$check_dir/AGENTS.md"
        break
    fi
    check_dir="$(dirname "$check_dir")"
done

if [[ -n "$found_agents" ]]; then
    echo "boundary-guard: Cross-project write allowed. Follow rules in $found_agents" >&2
    exit 0
fi

# 6. None of the above — block
echo "boundary-guard: BLOCKED — $FILE_PATH is outside your launch directory ($LAUNCH_DIR) and the target has no AGENTS.md. Stay in your project or ensure the target directory has an AGENTS.md." >&2
exit 2
