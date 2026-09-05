#!/usr/bin/env bash

if [[ "$1" == "strip" ]]; then
    bare=$(printf '%s' "$2" | sed 's/<[^>]*>//g')
    printf '%s\n' "${bare%% - *}"
    exit 0
fi

WS_DIR="$1"
[[ -z "$WS_DIR" || ! -d "$WS_DIR" ]] && exit 1

while IFS= read -r name; do
    branch=$(git -C "$WS_DIR/$name" branch --show-current 2>/dev/null)
    if [[ -n "$branch" ]]; then
        printf '<b>%s</b> - <i><span foreground="#00ffb4">%s</span></i>\n' "$name" "$branch"
    elif git -C "$WS_DIR/$name" rev-parse --git-dir >/dev/null 2>&1; then
        printf '<b>%s</b> - <i><span foreground="#ff5500">(detached)</span></i>\n' "$name"
    else
        printf '<b>%s</b>\n' "$name"
    fi
done < <(find "$WS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
