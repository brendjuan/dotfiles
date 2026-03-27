#!/usr/bin/env bash
# toggle high contrast mode across the desktop
# entry points: MOD+F6, waybar button, MOD+C command menu

STATE_FILE="$HOME/.cache/high-contrast-mode"
CWC_DIR="$HOME/.config/cwc"
KITTY_DIR="$HOME/.config/kitty"
MAKO_DIR="$HOME/.config/mako"
VSCODE_SETTINGS="$HOME/.config/Code/User/settings.json"
WALLPAPER="$CWC_DIR/wallpaper.png"
WALLPAPER_INVERTED="$CWC_DIR/wallpaper-inverted.png"

enable_high_contrast() {
    touch "$STATE_FILE"

    # waybar: swap to high contrast css and reload
    cp "$CWC_DIR/waybar/style-highcontrast.css" "$CWC_DIR/waybar/style-active.css"
    killall -SIGUSR2 waybar 2>/dev/null

    # kitty: push high contrast colors to all running instances
    for sock in /tmp/kitty-*; do
        [ -S "$sock" ] && kitty @ --to "unix:$sock" set-colors --all "$KITTY_DIR/highcontrast.conf" 2>/dev/null
    done

    # mako: swap config and reload
    cp "$MAKO_DIR/config" "$MAKO_DIR/config.bak"
    cp "$MAKO_DIR/config-highcontrast" "$MAKO_DIR/config"
    makoctl reload 2>/dev/null

    # rofi: handled by commands.sh reading state file for theme selection

    # vscode: switch to high contrast light theme
    if [ -f "$VSCODE_SETTINGS" ]; then
        tmp=$(mktemp)
        jq '."workbench.colorTheme" = "Default High Contrast Light"' "$VSCODE_SETTINGS" > "$tmp" && mv "$tmp" "$VSCODE_SETTINGS"
    fi

    # wallpaper: use cached inverted wallpaper, generate if missing
    if [ -f "$WALLPAPER" ]; then
        [ -f "$WALLPAPER_INVERTED" ] || convert "$WALLPAPER" -negate "$WALLPAPER_INVERTED"
        killall swaybg 2>/dev/null
        swaybg --output '*' --image "$WALLPAPER_INVERTED" --mode fill --color '#ffffff' &
        disown
    fi

    # cwc borders: reload config so rc.lua picks up the state file
    # cwc.reload is triggered by the keybind itself or we signal it
    # use cwc IPC if available, otherwise the keybind handles it
    notify-send "High Contrast" "ON — sunlight mode" -u low
}

disable_high_contrast() {
    rm -f "$STATE_FILE"

    # waybar: restore glitchcore css and reload
    cp "$CWC_DIR/waybar/style.css" "$CWC_DIR/waybar/style-active.css"
    killall -SIGUSR2 waybar 2>/dev/null

    # kitty: restore default (just reset to config defaults)
    for sock in /tmp/kitty-*; do
        [ -S "$sock" ] && kitty @ --to "unix:$sock" set-colors --all --reset 2>/dev/null
    done

    # mako: restore original config
    if [ -f "$MAKO_DIR/config.bak" ]; then
        mv "$MAKO_DIR/config.bak" "$MAKO_DIR/config"
    fi
    makoctl reload 2>/dev/null

    # vscode: restore previous theme (remove the override)
    if [ -f "$VSCODE_SETTINGS" ]; then
        tmp=$(mktemp)
        jq 'del(."workbench.colorTheme")' "$VSCODE_SETTINGS" > "$tmp" && mv "$tmp" "$VSCODE_SETTINGS"
    fi

    # wallpaper: restore original and restart swaybg
    killall swaybg 2>/dev/null
    swaybg --output '*' --image "$WALLPAPER" --mode fill --color '#0a000a' &
    disown

    notify-send "High Contrast" "OFF — glitchcore restored" -u low
}

if [ -f "$STATE_FILE" ]; then
    disable_high_contrast
else
    enable_high_contrast
fi
