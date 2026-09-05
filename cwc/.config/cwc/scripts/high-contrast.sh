#!/usr/bin/env bash

STATE_FILE="$HOME/.cache/high-contrast-mode"
LOCK_FILE="$HOME/.cache/high-contrast-mode.lock"
LOG_FILE="$HOME/.cache/high-contrast-mode.log"
VSCODE_STASH="$HOME/.cache/high-contrast-vscode-theme"
BTOP_STASH="$HOME/.cache/high-contrast-btop-theme"
BTOP_CONF="$HOME/.config/btop/btop.conf"
CWC_DIR="$HOME/.config/cwc"
KITTY_DIR="$HOME/.config/kitty"
VSCODE_SETTINGS="$HOME/.config/Code/User/settings.json"
WALLPAPER="$CWC_DIR/wallpaper.png"
WALLPAPER_INVERTED="$CWC_DIR/wallpaper-inverted.png"

KITTY_OPACITY_DEFAULT="0.75"
KITTY_OPACITY_HIGHCONTRAST="1.0"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >>"$LOG_FILE"; }

apply_kitty_colors() {
    local theme="$1" opacity="$2" tmp sock pid found=0

    if tmp="$(mktemp "$KITTY_DIR/.current-theme.XXXXXX" 2>/dev/null)"; then
        if cat "$theme" >"$tmp" 2>>"$LOG_FILE"; then
            mv -f "$tmp" "$KITTY_DIR/current-theme.conf"
        else
            log "failed writing current-theme.conf from $theme"; rm -f "$tmp"
        fi
    else
        log "mktemp for current-theme.conf failed"
    fi

    for sock in /tmp/kitty-*; do
        [ -S "$sock" ] || continue
        pid="${sock##*/kitty-}"
        case "$pid" in
            ''|*[!0-9]*) ;;
            *) kill -0 "$pid" 2>/dev/null || { log "skip dead socket $sock"; continue; } ;;
        esac
        found=1
        kitty @ --to "unix:$sock" set-colors --all --configured "$theme" >>"$LOG_FILE" 2>&1 \
            || log "set-colors failed on $sock"
        kitty @ --to "unix:$sock" set-background-opacity "$opacity" >>"$LOG_FILE" 2>&1 \
            || log "set-background-opacity failed on $sock (a window started before dynamic_background_opacity was added needs a kitty restart to toggle opacity live)"
    done
    [ "$found" = 0 ] && log "no live kitty sockets"
}

_vscode_apply() {
    local filter="$1"; shift
    local real tmp
    real="$(readlink -f "$VSCODE_SETTINGS" 2>/dev/null)"; [ -n "$real" ] || real="$VSCODE_SETTINGS"
    tmp="$(mktemp "$(dirname "$real")/.hc-settings.XXXXXX" 2>/dev/null)" || { log "vscode mktemp failed"; return 1; }
    if jq --indent 4 "$@" "$filter" "$real" >"$tmp" 2>>"$LOG_FILE"; then
        mv -f "$tmp" "$real"
    else
        log "vscode jq edit failed: $filter"; rm -f "$tmp"; return 1
    fi
}
vscode_ok()      { [ -f "$VSCODE_SETTINGS" ] && command -v jq >/dev/null 2>&1 && jq empty "$VSCODE_SETTINGS" >/dev/null 2>&1; }
vscode_set_hc()  { _vscode_apply '."workbench.colorTheme" = "Default High Contrast Light"'; }
vscode_restore() { _vscode_apply '."workbench.colorTheme" = $v' --argjson v "$1"; }
vscode_del()     { _vscode_apply 'del(."workbench.colorTheme")'; }

btop_ok()        { [ -f "$BTOP_CONF" ] && grep -q '^color_theme = ' "$BTOP_CONF"; }
btop_set_theme() {
    sed -i "s|^color_theme = .*|color_theme = \"$1\"|" "$BTOP_CONF" 2>>"$LOG_FILE" \
        || log "btop sed edit failed"
}

set_color_scheme() {
    command -v gsettings >/dev/null 2>&1 || { log "gsettings not found; color-scheme unchanged"; return; }
    gsettings set org.gnome.desktop.interface color-scheme "$1" >>"$LOG_FILE" 2>&1 \
        || log "gsettings color-scheme $1 failed"
}

ensure_inverted_wallpaper() {
    command -v convert >/dev/null 2>&1 || { log "convert (ImageMagick) not found; cannot invert wallpaper"; return; }
    [ -f "$WALLPAPER" ] || { log "base wallpaper missing: $WALLPAPER"; return; }
    if [ ! -f "$WALLPAPER_INVERTED" ] || [ "$WALLPAPER" -nt "$WALLPAPER_INVERTED" ]; then
        convert "$WALLPAPER" -negate "$WALLPAPER_INVERTED" >>"$LOG_FILE" 2>&1 || log "convert -negate failed"
    fi
}
set_wallpaper() {
    local image="$1" color="$2" i
    [ -f "$image" ] || { log "wallpaper missing, skipping swaybg: $image"; return; }
    killall swaybg 2>/dev/null
    for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -x swaybg >/dev/null || break; sleep 0.02; done
    swaybg --output '*' --image "$image" --mode fill --color "$color" >/dev/null 2>&1 9>&- &
    disown
}

enable_high_contrast() {
    if vscode_ok; then
        [ -f "$VSCODE_STASH" ] || jq -c '."workbench.colorTheme" // null' "$VSCODE_SETTINGS" >"$VSCODE_STASH"
        vscode_set_hc
    elif [ -f "$VSCODE_SETTINGS" ]; then
        log "vscode settings.json not plain JSON (or jq missing); skipping vscode theme"
    fi

    if btop_ok; then
        [ -f "$BTOP_STASH" ] || sed -n 's/^color_theme = "\(.*\)"$/\1/p' "$BTOP_CONF" >"$BTOP_STASH"
        btop_set_theme "whiteout"
    else
        log "btop.conf missing or has no color_theme line; skipping btop"
    fi

    : >"$STATE_FILE"

    cp "$CWC_DIR/waybar/style-highcontrast.css" "$CWC_DIR/waybar/style-active.css"
    killall -SIGUSR2 waybar 2>/dev/null

    apply_kitty_colors "$KITTY_DIR/highcontrast.conf" "$KITTY_OPACITY_HIGHCONTRAST"

    makoctl mode -a highcontrast >>"$LOG_FILE" 2>&1 || log "makoctl mode -a failed"

    set_color_scheme prefer-light

    ensure_inverted_wallpaper
    set_wallpaper "$WALLPAPER_INVERTED" '#ffffff'

    notify-send "High Contrast" "ON — sunlight mode" -u low
}

disable_high_contrast() {
    if vscode_ok; then
        prev=""; [ -f "$VSCODE_STASH" ] && prev="$(cat "$VSCODE_STASH")"
        if [ -n "$prev" ] && printf '%s' "$prev" | jq -e 'type == "string"' >/dev/null 2>&1; then
            vscode_restore "$prev"
        else
            vscode_del
        fi
    fi

    if btop_ok; then
        prev=""; [ -f "$BTOP_STASH" ] && prev="$(cat "$BTOP_STASH")"
        btop_set_theme "${prev:-Default}"
    fi

    rm -f "$VSCODE_STASH" "$BTOP_STASH" "$STATE_FILE"

    cp "$CWC_DIR/waybar/style.css" "$CWC_DIR/waybar/style-active.css"
    killall -SIGUSR2 waybar 2>/dev/null

    apply_kitty_colors "$KITTY_DIR/dark.conf" "$KITTY_OPACITY_DEFAULT"

    makoctl mode -r highcontrast >>"$LOG_FILE" 2>&1 || log "makoctl mode -r failed"

    set_color_scheme prefer-dark

    set_wallpaper "$WALLPAPER" '#020008'

    notify-send "High Contrast" "OFF — glitchcore restored" -u low
}

exec 9>"$LOCK_FILE"
flock -n 9 || { log "another instance holds the lock; skipping"; exit 0; }

if [ -f "$LOG_FILE" ] && [ "$(wc -l <"$LOG_FILE" 2>/dev/null || echo 0)" -gt 500 ]; then
    tail -n 200 "$LOG_FILE" >"$LOG_FILE.tmp" 2>/dev/null && mv -f "$LOG_FILE.tmp" "$LOG_FILE"
fi

log "invoked (caller=${PPID}, state=$([ -f "$STATE_FILE" ] && echo ON || echo OFF))"
if [ -f "$STATE_FILE" ]; then
    disable_high_contrast
else
    enable_high_contrast
fi

if command -v cwctl >/dev/null 2>&1; then
    cwctl reload >>"$LOG_FILE" 2>&1 || log "cwctl reload failed"
else
    log "cwctl not found; window borders not refreshed"
fi
log "done"
