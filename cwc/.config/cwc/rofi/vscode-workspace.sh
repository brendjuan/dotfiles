#!/usr/bin/env bash
# pick a workspace dir and open vscode in it

if [ -f "$HOME/.cache/high-contrast-mode" ]; then
    THEME="$HOME/.config/cwc/rofi/highcontrast.rasi"
else
    THEME="$HOME/.config/cwc/rofi/glitchcore.rasi"
fi
WORKSPACE_DIR="$HOME/Workspace"

[[ ! -d "$WORKSPACE_DIR" ]] && notify-send "vscode-workspace" "~/Workspace does not exist" && exit 1

dirs=$(find "$WORKSPACE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
[[ -z "$dirs" ]] && notify-send "vscode-workspace" "No directories in ~/Workspace" && exit 1

chosen=$(printf '%s\n' "$dirs" | rofi -dmenu -p "vscode" -theme "$THEME" -normal-window -steal-focus -i)
[[ -z "$chosen" ]] && exit 0

exec code "$WORKSPACE_DIR/$chosen"
