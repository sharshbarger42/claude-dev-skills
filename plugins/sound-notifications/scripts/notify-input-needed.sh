#!/usr/bin/env bash
# Plays a system sound when Claude needs user input.
# Cross-platform: Termux/Android, Windows/WSL, macOS, Linux desktop.

# Termux/Android — check first since uname also returns "Linux"
if command -v termux-notification >/dev/null 2>&1; then
    termux-notification --title "Claude" --content "Input needed" --sound >/dev/null 2>&1 &
    exit 0
fi

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*|Windows_NT)
        powershell.exe -ExecutionPolicy Bypass -Command "[System.Media.SystemSounds]::Exclamation.Play()"
        ;;
    Darwin)
        afplay /System/Library/Sounds/Funk.aiff &
        ;;
    Linux)
        # WSL — route through PowerShell on Windows host
        if grep -qi microsoft /proc/version 2>/dev/null; then
            powershell.exe -ExecutionPolicy Bypass -Command "[System.Media.SystemSounds]::Exclamation.Play()" 2>/dev/null
        elif command -v paplay >/dev/null 2>&1; then
            paplay /usr/share/sounds/freedesktop/stereo/dialog-warning.oga 2>/dev/null &
        elif command -v aplay >/dev/null 2>&1; then
            aplay /usr/share/sounds/sound-icons/prompt 2>/dev/null &
        fi
        ;;
esac

exit 0
