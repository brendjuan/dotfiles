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

# Glitchcore default opacity (matches kitty.conf). High contrast forces opaque.
KITTY_OPACITY_DEFAULT="0.75"
KITTY_OPACITY_HIGHCONTRAST="1.0"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG_FILE"; }

apply_kitty_colors() {
    # $1: path to colors.conf, or empty string for --reset
    # $2: opacity to apply
    local colors_conf="$1"
    local opacity="$2"
    local found=0
    for sock in /tmp/kitty-*; do
        [ -S "$sock" ] || continue
        found=1
        if [ -n "$colors_conf" ]; then
            kitty @ --to "unix:$sock" set-colors --all --configured "$colors_conf" >>"$LOG_FILE" 2>&1 \
                || log "set-colors failed on $sock"
        else
            kitty @ --to "unix:$sock" set-colors --all --reset >>"$LOG_FILE" 2>&1 \
                || log "set-colors --reset failed on $sock"
        fi
        kitty @ --to "unix:$sock" set-background-opacity "$opacity" >>"$LOG_FILE" 2>&1 \
            || log "set-background-opacity failed on $sock"
    done
    [ "$found" = 0 ] && log "no kitty sockets found at /tmp/kitty-*"
}

enable_high_contrast() {
    # vscode: stash previous theme value (JSON: a quoted string, or `null` if unset)
    # into the state file so disable_high_contrast can restore it. Written before
    # touch so the file's existence still gates the toggle.
    if [ -f "$VSCODE_SETTINGS" ]; then
        jq -c '."workbench.colorTheme" // null' "$VSCODE_SETTINGS" > "$STATE_FILE"
    else
        : > "$STATE_FILE"
    fi

    # waybar: swap to high contrast css and reload
    cp "$CWC_DIR/waybar/style-highcontrast.css" "$CWC_DIR/waybar/style-active.css"
    killall -SIGUSR2 waybar 2>/dev/null

    # kitty: push high contrast colors to all running instances. --configured so
    # new windows also pick up the theme; opacity is a separate setting from colors.
    apply_kitty_colors "$KITTY_DIR/highcontrast.conf" "$KITTY_OPACITY_HIGHCONTRAST"

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
    # vscode: restore previous theme stashed by enable_high_contrast.
    # If the stash is a string, set the key back to it; if it's null/empty/garbage,
    # fall back to deleting the key so VS Code uses its default.
    if [ -f "$VSCODE_SETTINGS" ]; then
        prev=$(cat "$STATE_FILE" 2>/dev/null)
        tmp=$(mktemp)
        if [ -n "$prev" ] && echo "$prev" | jq -e 'type == "string"' >/dev/null 2>&1; then
            jq --argjson v "$prev" '."workbench.colorTheme" = $v' "$VSCODE_SETTINGS" > "$tmp" && mv "$tmp" "$VSCODE_SETTINGS"
        else
            jq 'del(."workbench.colorTheme")' "$VSCODE_SETTINGS" > "$tmp" && mv "$tmp" "$VSCODE_SETTINGS"
        fi
    fi

    rm -f "$STATE_FILE"

    # waybar: restore glitchcore css and reload
    cp "$CWC_DIR/waybar/style.css" "$CWC_DIR/waybar/style-active.css"
    killall -SIGUSR2 waybar 2>/dev/null

    # kitty: reset palette to startup defaults and put opacity back where kitty.conf has it
    apply_kitty_colors "" "$KITTY_OPACITY_DEFAULT"

    # mako: restore original config
    if [ -f "$MAKO_DIR/config.bak" ]; then
        mv "$MAKO_DIR/config.bak" "$MAKO_DIR/config"
    fi
    makoctl reload 2>/dev/null

    # wallpaper: restore original and restart swaybg
    killall swaybg 2>/dev/null
    swaybg --output '*' --image "$WALLPAPER" --mode fill --color '#020008' &
    disown

    notify-send "High Contrast" "OFF — glitchcore restored" -u low
}

log "invoked (caller=${PPID}, state_file_exists=$([ -f "$STATE_FILE" ] && echo yes || echo no))"
if [ -f "$STATE_FILE" ]; then
    disable_high_contrast
else
    enable_high_contrast
fi
log "done"
