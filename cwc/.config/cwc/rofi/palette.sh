#!/usr/bin/env bash
# Pango markup colors for the rofi launchers, by high-contrast state. The rofi
# theme is not enough: rows carry their own colors, unreadable on the white one.

if [ -f "$HOME/.cache/high-contrast-mode" ]; then
    OK="#0000aa"
    WARN="#886600"
    ALERT="#aa0000"
    DIM="#444444"
else
    OK="#00ffb4"
    WARN="#ff5500"
    ALERT="#ff0050"
    DIM="#00ffb470"
fi
