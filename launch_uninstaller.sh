#!/bin/bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SCRIPT="${DIR}/uninstall_backend.sh"
for term in kitty foot konsole gnome-terminal alacritty wezterm xterm; do
    if command -v "$term" >/dev/null 2>&1; then
        if [ "$term" = "gnome-terminal" ]; then
            exec gnome-terminal -- "$SCRIPT"
        elif [ "$term" = "konsole" ]; then
            exec konsole -e "$SCRIPT"
        else
            exec "$term" -e "$SCRIPT"
        fi
    fi
done
echo "No terminal emulator found"
exit 1
