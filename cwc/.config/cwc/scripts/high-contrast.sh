#!/usr/bin/env bash
# Toggle high-contrast "sunlight" mode across the desktop.
# Entry points: MOD+F6 (keybind.lua), the waybar button (config.jsonc), and the
# MOD+C command menu (rofi/commands.sh) — all funnel through this one script.
#
# Source of truth: the state file ~/.cache/high-contrast-mode. Its EXISTENCE ==
# ON. That contract is also read by rc.lua (border colors), rofi/commands.sh,
# rofi/vscode-workspace.sh, rofi/palette.sh, scripts/cheatsheet.sh,
# scripts/lock.sh, the battery overlays, and the MOD+R launcher.
#
# Design notes:
#  - Never mutates stow-tracked source files. kitty uses a gitignored
#    current-theme.conf; mako uses native runtime modes; waybar uses a runtime
#    style-active.css copy. Only vscode settings.json is edited in place (it must
#    be, to retheme the editor) and that is done symlink-preserving + atomically.
#  - Idempotent + serialized (flock), so overlapping triggers can't corrupt state.

STATE_FILE="$HOME/.cache/high-contrast-mode"
LOCK_FILE="$HOME/.cache/high-contrast-mode.lock"
LOG_FILE="$HOME/.cache/high-contrast-mode.log"
VSCODE_STASH="$HOME/.cache/high-contrast-vscode-theme"
CWC_DIR="$HOME/.config/cwc"
KITTY_DIR="$HOME/.config/kitty"
VSCODE_SETTINGS="$HOME/.config/Code/User/settings.json"
WALLPAPER="$CWC_DIR/wallpaper.png"
WALLPAPER_INVERTED="$CWC_DIR/wallpaper-inverted.png"

# Glitchcore default opacity (matches kitty.conf). High contrast forces opaque.
KITTY_OPACITY_DEFAULT="0.75"
KITTY_OPACITY_HIGHCONTRAST="1.0"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >>"$LOG_FILE"; }

# ── kitty ─────────────────────────────────────────────────────────────
# $1 = source theme (.conf: colors + background_opacity); $2 = live opacity.
# Two mechanisms, BOTH required (do not drop either):
#   - current-theme.conf feeds NEW kitty processes via `include` at startup.
#   - `kitty @ set-colors` retheme EXISTING windows (and new tabs within them).
apply_kitty_colors() {
    local theme="$1" opacity="$2" tmp sock pid found=0

    # New windows: write the included file atomically (temp + rename) so a kitty
    # launching mid-write never parses a half-written palette. current-theme.conf
    # is a real local file (gitignored, not a symlink) — safe to overwrite.
    if tmp="$(mktemp "$KITTY_DIR/.current-theme.XXXXXX" 2>/dev/null)"; then
        if cat "$theme" >"$tmp" 2>>"$LOG_FILE"; then
            mv -f "$tmp" "$KITTY_DIR/current-theme.conf"
        else
            log "failed writing current-theme.conf from $theme"; rm -f "$tmp"
        fi
    else
        log "mktemp for current-theme.conf failed"
    fi

    # Live windows: listen_on mints one socket per pid. Skip sockets whose kitty
    # process is gone (a crashed kitty leaves a stale socket behind).
    for sock in /tmp/kitty-*; do
        [ -S "$sock" ] || continue
        pid="${sock##*/kitty-}"
        case "$pid" in
            ''|*[!0-9]*) ;;                                   # not pid-shaped; try anyway
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

# ── gtk apps ──────────────────────────────────────────────────────────
# GTK/libadwaita apps follow the desktop color-scheme. GTK3 apps may ignore it.
apply_gtk_color_scheme() {  # $1 = prefer-dark | prefer-light
    command -v gsettings >/dev/null 2>&1 || { log "gsettings not found; skipping gtk color-scheme"; return; }
    gsettings set org.gnome.desktop.interface color-scheme "$1" >>"$LOG_FILE" 2>&1 \
        || log "gsettings color-scheme $1 failed"
}

# ── vscode ────────────────────────────────────────────────────────────
# Edit settings.json in place, preserving the stow symlink (write to its target,
# atomic rename on the same filesystem) and VS Code's 4-space formatting so the
# tracked file round-trips cleanly when the toggle is OFF.
_vscode_apply() {  # $1 = jq filter; rest = extra jq args (e.g. --argjson v ...)
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

# ── wallpaper ──────────────────────────────────────────────────────────
ensure_inverted_wallpaper() {
    command -v convert >/dev/null 2>&1 || { log "convert (ImageMagick) not found; cannot invert wallpaper"; return; }
    [ -f "$WALLPAPER" ] || { log "base wallpaper missing: $WALLPAPER"; return; }
    # (re)generate when missing or when the base wallpaper is newer than the cache
    if [ ! -f "$WALLPAPER_INVERTED" ] || [ "$WALLPAPER" -nt "$WALLPAPER_INVERTED" ]; then
        convert "$WALLPAPER" -negate "$WALLPAPER_INVERTED" >>"$LOG_FILE" 2>&1 || log "convert -negate failed"
    fi
}
set_wallpaper() {  # $1 = image, $2 = fallback fill color
    local image="$1" color="$2" i
    [ -f "$image" ] || { log "wallpaper missing, skipping swaybg: $image"; return; }
    killall swaybg 2>/dev/null
    # wait for the old surface to go away to avoid a wallpaper-less flash
    for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -x swaybg >/dev/null || break; sleep 0.02; done
    # 9>&- is critical: swaybg is a long-lived daemon and would otherwise inherit
    # the flock fd (9) and hold the lock forever, deadlocking every future toggle.
    swaybg --output '*' --image "$image" --mode fill --color "$color" >/dev/null 2>&1 9>&- &
    disown
}

# ── enable / disable ────────────────────────────────────────────────────
enable_high_contrast() {
    # vscode: stash the current theme (once) so disable can restore it. The stash
    # lives in ~/.cache, decoupled from the gate file, so a jq hiccup can never
    # leave a bogus "ON" gate. Only captured on a real OFF->ON transition.
    if vscode_ok; then
        [ -f "$VSCODE_STASH" ] || jq -c '."workbench.colorTheme" // null' "$VSCODE_SETTINGS" >"$VSCODE_STASH"
        vscode_set_hc
    elif [ -f "$VSCODE_SETTINGS" ]; then
        log "vscode settings.json not plain JSON (or jq missing); skipping vscode theme"
    fi

    : >"$STATE_FILE"                       # gate ON (after the stash exists)

    cp "$CWC_DIR/waybar/style-highcontrast.css" "$CWC_DIR/waybar/style-active.css"
    killall -SIGUSR2 waybar 2>/dev/null

    apply_kitty_colors "$KITTY_DIR/highcontrast.conf" "$KITTY_OPACITY_HIGHCONTRAST"
    apply_gtk_color_scheme prefer-light

    makoctl mode -a highcontrast >>"$LOG_FILE" 2>&1 || log "makoctl mode -a failed"

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
    rm -f "$VSCODE_STASH" "$STATE_FILE"    # gate OFF

    cp "$CWC_DIR/waybar/style.css" "$CWC_DIR/waybar/style-active.css"
    killall -SIGUSR2 waybar 2>/dev/null

    apply_kitty_colors "$KITTY_DIR/dark.conf" "$KITTY_OPACITY_DEFAULT"
    apply_gtk_color_scheme prefer-dark

    makoctl mode -r highcontrast >>"$LOG_FILE" 2>&1 || log "makoctl mode -r failed"

    set_wallpaper "$WALLPAPER" '#020008'

    notify-send "High Contrast" "OFF — glitchcore restored" -u low
}

# ── dispatch ────────────────────────────────────────────────────────────
# Serialize: three fire-and-forget entry points can otherwise race into a
# double-enable/disable. flock -n drops the overlapping invocation (the in-flight
# toggle wins; it finishes in well under a second).
exec 9>"$LOCK_FILE"
flock -n 9 || { log "another instance holds the lock; skipping"; exit 0; }

# keep the log bounded
if [ -f "$LOG_FILE" ] && [ "$(wc -l <"$LOG_FILE" 2>/dev/null || echo 0)" -gt 500 ]; then
    tail -n 200 "$LOG_FILE" >"$LOG_FILE.tmp" 2>/dev/null && mv -f "$LOG_FILE.tmp" "$LOG_FILE"
fi

log "invoked (caller=${PPID}, state=$([ -f "$STATE_FILE" ] && echo ON || echo OFF))"
if [ -f "$STATE_FILE" ]; then
    disable_high_contrast
else
    enable_high_contrast
fi

# borders: rc.lua re-reads the state file at config-load time, so reload cwc HERE
# (covers F6, waybar, and rofi uniformly — not just the F6 keybind). Done last,
# after the state file is finalized. Guarded so a non-cwc invocation can't fail.
if command -v cwctl >/dev/null 2>&1; then
    cwctl reload >>"$LOG_FILE" 2>&1 || log "cwctl reload failed"
else
    log "cwctl not found; window borders not refreshed"
fi
log "done"
