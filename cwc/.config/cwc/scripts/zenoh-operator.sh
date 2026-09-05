#!/usr/bin/env bash

set -uo pipefail

PATTERN='[z]enoh-bridge-ros2dds client'
LOGWIN_PATTERN='[z]enoh-operator.sh logs'
LOG_FILE="$HOME/.cache/zenoh-operator.log"
LOCK_FILE="$HOME/.cache/zenoh-operator.lock"

ICON_ON='󰌘'
ICON_OFF='󰌙'
WAYBAR_SIGNAL=8

export PATH="$HOME/.local/bin:$PATH"

notify() { notify-send "Zenoh operator" "$1"; }
bridge_pid() { pgrep -f -- "$PATTERN" | head -n 1; }
refresh_waybar() { pkill -"RTMIN+$WAYBAR_SIGNAL" waybar 2>/dev/null || true; }

if [[ "${1:-}" == "logs" ]]; then
    touch "$LOG_FILE"
    exec tail -n 500 -F "$LOG_FILE"
fi

if [[ "${1:-}" == "logwin" ]]; then
    pkill -f -- "$LOGWIN_PATTERN" 2>/dev/null
    for _ in $(seq 40); do
        pgrep -f -- "$LOGWIN_PATTERN" >/dev/null 2>&1 || break
        sleep 0.05
    done

    exec kitty --class float-term --title 'ZENOH OPERATOR' \
        -o remember_window_size=no \
        -o initial_window_width=110c \
        -o initial_window_height=42c \
        -e "$0" logs
fi

if [[ "${1:-}" == "status" ]]; then
    if [[ -n "$(bridge_pid)" ]]; then
        printf '{"text":"%s","class":"on","tooltip":"%s"}\n' \
            "$ICON_ON" "Zenoh operator: running\rLeft click to stop, right click for logs"
    else
        printf '{"text":"%s","class":"off","tooltip":"%s"}\n' \
            "$ICON_OFF" "Zenoh operator: stopped\rLeft click to start, right click for logs"
    fi
    exit 0
fi

exec 9>"$LOCK_FILE"
if ! flock -w 10 9; then
    notify "Another start or stop is still running"
    exit 1
fi

pid="$(bridge_pid)"
if [[ -n "$pid" ]]; then
    pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
    if [[ -n "$pgid" ]]; then
        kill -TERM -"$pgid" 2>/dev/null
    else
        kill -TERM "$pid" 2>/dev/null
    fi

    for _ in $(seq 50); do
        [[ -z "$(bridge_pid)" ]] && break
        sleep 0.1
    done

    if [[ -n "$(bridge_pid)" ]]; then
        [[ -n "$pgid" ]] && kill -KILL -"$pgid" 2>/dev/null
        pkill -KILL -f -- "$PATTERN" 2>/dev/null
    fi

    printf '\n=== %s: stopped ===\n' "$(date '+%F %T')" >>"$LOG_FILE"
    notify "Stopped"
    refresh_waybar
    exit 0
fi

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
WS_DIR="$("$SCRIPT_DIR/../rofi/find-workspace-dir.sh")" || {
    notify "No ~/Workspace(s) directory found"
    exit 1
}

TASK_DIR="$WS_DIR/deployment/deployment"
if [[ ! -d "$TASK_DIR" ]]; then
    notify "Not found: $TASK_DIR"
    exit 1
fi
cd "$TASK_DIR" || exit 1

if command -v mise >/dev/null 2>&1 && mise tasks info zenoh:operator >/dev/null 2>&1; then
    run_cmd=(mise run zenoh:operator "$@")
elif command -v task >/dev/null 2>&1; then
    run_cmd=(task zenoh:operator)
else
    notify "Neither mise nor task is installed"
    exit 1
fi

[[ -f "$LOG_FILE" ]] && mv -f "$LOG_FILE" "$LOG_FILE.1"
printf '=== %s: starting %s (cwd %s) ===\n' \
    "$(date '+%F %T')" "${run_cmd[*]}" "$TASK_DIR" >"$LOG_FILE"

setsid "${run_cmd[@]}" >>"$LOG_FILE" 2>&1 9>&- &
launcher=$!

started=""
for _ in $(seq 120); do
    if [[ -n "$(bridge_pid)" ]]; then
        started=1
        break
    fi
    kill -0 "$launcher" 2>/dev/null || break
    sleep 0.25
done

refresh_waybar

if [[ -n "$started" ]]; then
    notify "Started"
else
    notify "Failed to start. See $LOG_FILE"
    exit 1
fi
