#!/usr/bin/env bash
# list workspace dirs as Pango-marked-up "<name> - <branch>" lines, sorted by name
# also exposes a `strip` mode that recovers the bare dir name from a selection
#
# usage:
#   list-workspaces.sh <workspace-dir>           — print markup list
#   list-workspaces.sh strip "<marked-up line>"  — print bare dir name
#
# callers must pass `-markup-rows` to rofi when displaying the list

if [[ "$1" == "strip" ]]; then
    # drop pango tags, then trim the " - <branch>" suffix
    bare=$(printf '%s' "$2" | sed 's/<[^>]*>//g')
    printf '%s\n' "${bare%% - *}"
    exit 0
fi

# row colors follow high-contrast state; neon is unreadable on the white theme
source "$(dirname "${BASH_SOURCE[0]}")/palette.sh"

WS_DIR="$1"
[[ -z "$WS_DIR" || ! -d "$WS_DIR" ]] && exit 1

while IFS= read -r name; do
    branch=$(git -C "$WS_DIR/$name" branch --show-current 2>/dev/null)
    if [[ -n "$branch" ]]; then
        printf '<b>%s</b> - <i><span foreground="%s">%s</span></i>\n' "$name" "$OK" "$branch"
    elif git -C "$WS_DIR/$name" rev-parse --git-dir >/dev/null 2>&1; then
        printf '<b>%s</b> - <i><span foreground="%s">(detached)</span></i>\n' "$name" "$WARN"
    else
        printf '<b>%s</b>\n' "$name"
    fi
done < <(find "$WS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
