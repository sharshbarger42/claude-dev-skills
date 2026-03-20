#!/usr/bin/env bash
# Plays a "task complete" sound when Claude finishes responding.
# Cross-platform: Termux/Android, Windows/WSL, macOS, Linux desktop.

# Termux/Android — check first since uname also returns "Linux"
if command -v termux-toast >/dev/null 2>&1; then
    termux-toast "Task complete" 2>/dev/null
    if command -v termux-notification >/dev/null 2>&1; then
        termux-notification --title "Claude" --content "Task complete" --sound >/dev/null 2>&1 &
    fi
    exit 0
fi

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*|Windows_NT)
        powershell.exe -ExecutionPolicy Bypass -Command "[console]::Beep(600,150); [console]::Beep(900,200)"
        ;;
    Darwin)
        afplay /System/Library/Sounds/Glass.aiff &
        ;;
    Linux)
        # WSL — route through PowerShell on Windows host
        if grep -qi microsoft /proc/version 2>/dev/null; then
            powershell.exe -ExecutionPolicy Bypass -Command "[console]::Beep(600,150); [console]::Beep(900,200)" 2>/dev/null
        elif command -v paplay >/dev/null 2>&1; then
            paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null &
        elif command -v beep >/dev/null 2>&1; then
            beep -f 600 -l 150 && beep -f 900 -l 200
        fi
        ;;
esac

exit 0
