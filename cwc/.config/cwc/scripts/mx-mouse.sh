#!/usr/bin/env bash
set -u

export PATH="$HOME/.local/bin:$PATH"

ICON_ON='󰍽'
ICON_OFF='󰍾'
WAYBAR_SIGNAL=9
DPI_CACHE="$HOME/.cache/mx-dpi"
PRESETS=(400 600 800 1000 1200 1600 2000 2400 3200 4000 8000)
POWER_SUPPLY_DIR="${MX_POWER_SUPPLY_DIR:-/sys/class/power_supply}"

notify() { notify-send "Mouse" "$1"; }
refresh_waybar() { pkill -"RTMIN+$WAYBAR_SIGNAL" waybar 2>/dev/null || true; }

is_pointer() {
    local caps low has_input=1
    for caps in "$1"/device/input/input*/capabilities/rel; do
        [[ -r "$caps" ]] || continue
        has_input=0
        low=$(<"$caps")
        low=${low##* }
        [[ "$low" =~ ^[0-9a-fA-F]+$ ]] || continue
        (( (0x$low & 0x3) == 0x3 )) && return 0
    done
    (( has_input == 0 )) && return 1
    return 0
}

if [[ "${1:-}" == "status" ]]; then
    hint='Left click to set dpi, right click for details'
    for supply in "$POWER_SUPPLY_DIR"/hidpp_battery_*; do
        [[ -r "$supply/online" ]] || continue
        [[ "$(<"$supply/online")" == "1" ]] || continue
        is_pointer "$supply" || continue

        model=$(<"$supply/model_name")
        capacity=$(cat "$supply/capacity" 2>/dev/null || true)
        state=$(tr '[:upper:]' '[:lower:]' <"$supply/status")

        class=on
        case "$state" in charging|full) class=charging ;; esac
        if [[ "$capacity" =~ ^[0-9]+$ ]]; then
            text="$ICON_ON ${capacity}%"
            level="${capacity}%, $state"
            if [[ "$class" == on ]]; then
                (( capacity <= 10 )) && class=critical
                (( capacity > 10 && capacity <= 20 )) && class=warning
            fi
        else
            text="$ICON_ON"
            level="$(cat "$supply/capacity_level" 2>/dev/null || echo '?'), $state"
        fi
        dpi=''
        [[ -r "$DPI_CACHE" ]] && dpi=" · dpi $(<"$DPI_CACHE")"

        printf '{"text":"%s","class":"%s","tooltip":"%s: %s%s\\n%s"}\n' \
            "$text" "$class" "$model" "$level" "$dpi" "$hint"
        exit 0
    done
    printf '{"text":"%s","class":"off","tooltip":"Mouse: not connected\\n%s"}\n' \
        "$ICON_OFF" "$hint"
    exit 0
fi

DETAILS_PATTERN="$0 info-wait"

if [[ "${1:-}" == "info-wait" ]]; then
    mx info || true
    printf '\npress any key to close'
    read -rsn1
    exit 0
fi

if [[ "${1:-}" == "details" ]]; then
    pkill -f -- "$DETAILS_PATTERN" 2>/dev/null
    for _ in $(seq 40); do
        pgrep -f -- "$DETAILS_PATTERN" >/dev/null 2>&1 || break
        sleep 0.05
    done
    exec kitty --class float-term --title 'MOUSE' \
        -o remember_window_size=no \
        -o initial_window_width=80c \
        -o initial_window_height=8c \
        -e "$0" info-wait
fi

if [[ "${1:-}" == "pick" ]]; then
    if ! current=$(mx dpi 2>&1); then
        notify "$current"
        exit 1
    fi
    current=${current%% *}

    if [ -f "$HOME/.cache/high-contrast-mode" ]; then
        THEME="$HOME/.config/cwc/rofi/highcontrast.rasi"
    else
        THEME="$HOME/.config/cwc/rofi/glitchcore.rasi"
    fi

    menu=$(printf '%s\n' "${PRESETS[@]}" "$current" | sort -n | uniq |
        sed "s/^${current}\$/${current}  ← current/")

    pkill rofi 2>/dev/null
    sleep 0.05
    choice=$(rofi -dmenu -i -p "dpi" \
        -theme "$THEME" -normal-window -steal-focus \
        -theme-str 'window { width: 260px; } listview { lines: 12; }' \
        <<<"$menu") || exit 0
    choice=${choice%% *}
    [[ -n "$choice" ]] || exit 0
    if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
        notify "'$choice' is not a number"
        exit 1
    fi

    if result=$(mx dpi "$choice" 2>&1); then
        printf '%s\n' "$choice" >"$DPI_CACHE"
        notify "$result"
        refresh_waybar
    else
        notify "$result"
        exit 1
    fi
    exit 0
fi

echo "usage: $0 {status|pick|details}" >&2
exit 2
