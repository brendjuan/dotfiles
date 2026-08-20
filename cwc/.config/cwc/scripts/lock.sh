#!/usr/bin/env bash
# Lock the screen with the config that matches high-contrast state. swaylock has
# no runtime mode mechanism, so the two themes are two files and this picks one.

CONFIG="$HOME/.config/swaylock/config"
if [ -f "$HOME/.cache/high-contrast-mode" ] && [ -f "$HOME/.config/swaylock/config-highcontrast" ]; then
    CONFIG="$HOME/.config/swaylock/config-highcontrast"
fi

# fall back to swaylock's own default if the file is missing, so a broken
# symlink can never leave the screen unlocked
if [ -f "$CONFIG" ]; then
    exec swaylock -C "$CONFIG" "$@"
else
    exec swaylock "$@"
fi
