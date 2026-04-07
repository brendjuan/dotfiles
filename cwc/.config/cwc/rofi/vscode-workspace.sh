#!/usr/bin/env bash
# pick a workspace dir and open vscode in it

if [ -f "$HOME/.cache/high-contrast-mode" ]; then
    THEME="$HOME/.config/cwc/rofi/highcontrast.rasi"
else
    THEME="$HOME/.config/cwc/rofi/glitchcore.rasi"
fi
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
WORKSPACE_DIR=$("$SCRIPT_DIR/find-workspace-dir.sh") || { notify-send "vscode-workspace" "No ~/Workspace(s) directory found"; exit 1; }

dirs=$(find "$WORKSPACE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
[[ -z "$dirs" ]] && notify-send "vscode-workspace" "No directories in $WORKSPACE_DIR" && exit 1

chosen=$(printf '%s\n' "$dirs" | rofi -dmenu -p "vscode" -theme "$THEME" -normal-window -steal-focus -i)
[[ -z "$chosen" ]] && exit 0

exec code "$WORKSPACE_DIR/$chosen"
