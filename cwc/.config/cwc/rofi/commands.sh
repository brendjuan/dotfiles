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
    ["󰓦 Fetch All Workspaces"]="kitty --class float-term -o remember_window_size=no -o initial_window_width=110c -o initial_window_height=42c -e $HOME/.config/cwc/rofi/fetch-workspaces.sh"
    ["󰘬 Return Workspaces to Main"]="kitty --class float-term -o remember_window_size=no -o initial_window_width=110c -o initial_window_height=42c -e $HOME/.config/cwc/rofi/switch-main-workspaces.sh"
    ["󱒈 Workspace Grid"]="__workspace_grid"
    ["󰐊 Review Grid"]="__review_grid"
    ["󰂺 Learn Conventions"]="__learn_conventions"
    ["󰈈 Browse Reviews"]="~/.config/cwc/rofi/review-browser.sh"
    ["󰨞 VSCode Workspace"]="~/.config/cwc/rofi/vscode-workspace.sh"
    ["󰌁 High Contrast Toggle"]="~/.config/cwc/scripts/high-contrast.sh"
)

chosen=$(printf '%s\n' "${!commands[@]}" | rofi -dmenu -p "cmd" "${ROFI_OPTS[@]}")

[[ -z "$chosen" ]] && exit 0

cmd="${commands[$chosen]}"

# commands that need a workspace picked first, then exec a script with the name
if [[ "$cmd" == "__workspace_grid" || "$cmd" == "__review_grid" || "$cmd" == "__learn_conventions" ]]; then
    case "$cmd" in
        __review_grid)       target="review-grid.sh" ;;
        __learn_conventions) target="learn-conventions.sh" ;;
        *)                   target="workspace-grid.sh" ;;
    esac
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    WS_DIR=$("$SCRIPT_DIR/find-workspace-dir.sh") || { notify-send "$target" "No ~/Workspace(s) directory found"; exit 1; }
    dirs=$("$SCRIPT_DIR/list-workspaces.sh" "$WS_DIR")
    [[ -z "$dirs" ]] && notify-send "$target" "No directories in $WS_DIR" && exit 1
    chosen=$(printf '%s\n' "$dirs" | rofi -dmenu -p "workspace" "${ROFI_MARKUP_OPTS[@]}")
    [[ -z "$chosen" ]] && exit 0
    exec ~/.config/cwc/rofi/"$target" "$("$SCRIPT_DIR/list-workspaces.sh" strip "$chosen")"
fi

exec $cmd
