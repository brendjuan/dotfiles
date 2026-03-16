#!/usr/bin/env bash
# custom command menu — rofi but make it useful
# add entries as "label|command" lines

THEME="$HOME/.config/cwc/rofi/glitchcore.rasi"
ROFI_OPTS=(-theme "$THEME" -normal-window -steal-focus -i)

declare -A commands=(
    ["󰤥 Network (nmtui)"]="kitty --class float-term -e nmtui"
    ["󱒈 Workspace Grid"]="__workspace_grid"
    ["󰨞 VSCode Workspace"]="~/.config/cwc/rofi/vscode-workspace.sh"
)

chosen=$(printf '%s\n' "${!commands[@]}" | rofi -dmenu -p "cmd" "${ROFI_OPTS[@]}")

[[ -z "$chosen" ]] && exit 0

cmd="${commands[$chosen]}"

if [[ "$cmd" == "__workspace_grid" ]]; then
    dirs=$(find "$HOME/Workspace" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
    [[ -z "$dirs" ]] && notify-send "workspace-grid" "No directories in ~/Workspace" && exit 1
    chosen_dir=$(printf '%s\n' "$dirs" | rofi -dmenu -p "workspace" "${ROFI_OPTS[@]}")
    [[ -z "$chosen_dir" ]] && exit 0
    exec ~/.config/cwc/rofi/workspace-grid.sh "$chosen_dir"
fi

exec $cmd
