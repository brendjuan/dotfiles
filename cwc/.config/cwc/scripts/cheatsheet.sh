#!/usr/bin/env bash
# auto-generated keybind cheatsheet — content built by keybind.lua, dumped to /tmp

CHEAT_FILE="/tmp/cwc-cheatsheet.txt"
[[ ! -s "$CHEAT_FILE" ]] && exit 0

if [ -f "$HOME/.cache/high-contrast-mode" ]; then
    THEME="$HOME/.config/cwc/rofi/highcontrast.rasi"
else
    THEME="$HOME/.config/cwc/rofi/glitchcore.rasi"
fi

pkill rofi 2>/dev/null
sleep 0.05
rofi -dmenu -markup-rows -i -p "keybind" -no-custom \
    -theme "$THEME" -normal-window -steal-focus \
    -theme-str 'window { width: 1140px; } listview { columns: 3; lines: 24; }' \
    < "$CHEAT_FILE" > /dev/null
