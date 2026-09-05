#!/usr/bin/env bash

if [ -f "$HOME/.cache/high-contrast-mode" ]; then
    THEME="$HOME/.config/cwc/rofi/highcontrast.rasi"
else
    THEME="$HOME/.config/cwc/rofi/glitchcore.rasi"
fi
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
WORKSPACE_DIR=$("$SCRIPT_DIR/find-workspace-dir.sh") || { notify-send "vscode-workspace" "No ~/Workspace(s) directory found"; exit 1; }

dirs=$("$SCRIPT_DIR/list-workspaces.sh" "$WORKSPACE_DIR")
[[ -z "$dirs" ]] && notify-send "vscode-workspace" "No directories in $WORKSPACE_DIR" && exit 1

chosen=$(printf '%s\n' "$dirs" | rofi -dmenu -p "vscode" -markup-rows -theme "$THEME" -normal-window -steal-focus -i)
[[ -z "$chosen" ]] && exit 0

exec code "$WORKSPACE_DIR/$("$SCRIPT_DIR/list-workspaces.sh" strip "$chosen")"
