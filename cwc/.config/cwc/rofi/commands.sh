#!/usr/bin/env bash
# custom command menu — rofi but make it useful
# add entries as "label|command" lines

if [ -f "$HOME/.cache/high-contrast-mode" ]; then
    THEME="$HOME/.config/cwc/rofi/highcontrast.rasi"
else
    THEME="$HOME/.config/cwc/rofi/glitchcore.rasi"
fi
ROFI_OPTS=(-theme "$THEME" -normal-window -steal-focus -i)
ROFI_MARKUP_OPTS=("${ROFI_OPTS[@]}" -markup-rows)

declare -A commands=(
    ["󰤥 Network (nmtui)"]="kitty --class float-term -e nmtui"
    ["󱒈 Workspace Grid"]="__workspace_grid"
    ["󰨞 VSCode Workspace"]="~/.config/cwc/rofi/vscode-workspace.sh"
    ["󰌁 High Contrast Toggle"]="~/.config/cwc/scripts/high-contrast.sh"
)

chosen=$(printf '%s\n' "${!commands[@]}" | rofi -dmenu -p "cmd" "${ROFI_OPTS[@]}")

[[ -z "$chosen" ]] && exit 0

cmd="${commands[$chosen]}"

if [[ "$cmd" == "__workspace_grid" ]]; then
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    WS_DIR=$("$SCRIPT_DIR/find-workspace-dir.sh") || { notify-send "workspace-grid" "No ~/Workspace(s) directory found"; exit 1; }
    dirs=$("$SCRIPT_DIR/list-workspaces.sh" "$WS_DIR")
    [[ -z "$dirs" ]] && notify-send "workspace-grid" "No directories in $WS_DIR" && exit 1
    chosen=$(printf '%s\n' "$dirs" | rofi -dmenu -p "workspace" "${ROFI_MARKUP_OPTS[@]}")
    [[ -z "$chosen" ]] && exit 0
    exec ~/.config/cwc/rofi/workspace-grid.sh "$("$SCRIPT_DIR/list-workspaces.sh" strip "$chosen")"
fi

exec $cmd
