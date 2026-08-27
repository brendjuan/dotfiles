#!/usr/bin/env bash
# Start or stop the local zenoh bridge ("operator") from the MOD+C command menu.
#
# This script never implements a bridge itself. It only calls the task that the
# deployment repository already defines in <workspace>/deployment/deployment:
#   - mise.toml     -> mise run zenoh:operator
#   - Taskfile.yml  -> task zenoh:operator      (fallback when mise is missing)
#
# Source of truth for "is it running": the bridge process itself. There is no
# state file, so the toggle stays correct even if the bridge was started or
# stopped from a terminal.
#
# Usage:
#   zenoh-operator.sh [host]   toggle: stop if running, otherwise start
#   zenoh-operator.sh logwin   open the log in a terminal window (only one)
#   zenoh-operator.sh logs     follow the log file in the current terminal
#   zenoh-operator.sh status   print waybar JSON for the bar module
#
# The bridge runs detached and writes to $LOG_FILE, so no terminal window has to
# stay open. Both the MOD+C menu entry and the waybar right click call "logwin",
# so the terminal flags live here only and cannot drift apart.
#
# "status" is read only. It only looks for the local bridge process. It never
# publishes to ROS or zenoh and never queries the vehicle, so polling it from
# waybar cannot put anything on the wire.

set -uo pipefail

# The process name is longer than the 15 character kernel limit, so pgrep -x
# cannot match it. Match the full command line instead. The [z] makes the
# pattern not match the command line of a process that contains the pattern
# itself, for example this script started with the pattern as an argument.
PATTERN='[z]enoh-bridge-ros2dds client'
# Matches the terminal that "logwin" starts, because the log command appears in
# that terminal's own command line. Used to close an old window before opening a
# new one, so only one log window can exist. The [z] guard applies here too: a
# process asked to open a window runs "logwin", which this does not match.
LOGWIN_PATTERN='[z]enoh-operator.sh logs'
LOG_FILE="$HOME/.cache/zenoh-operator.log"
LOCK_FILE="$HOME/.cache/zenoh-operator.lock"

# waybar module glyphs: lan-connect / lan-disconnect.
ICON_ON='󰌘'
ICON_OFF='󰌙'
# Real time signal that tells the waybar module to refresh. Must match the
# "signal" value of custom/zenoh in waybar/config.jsonc.
WAYBAR_SIGNAL=8

# mise installs to ~/.local/bin, which is not always on PATH for a process
# spawned by the compositor.
export PATH="$HOME/.local/bin:$PATH"

notify() { notify-send "Zenoh operator" "$1"; }
bridge_pid() { pgrep -f -- "$PATTERN" | head -n 1; }
# Update the bar right away instead of waiting for its poll interval.
refresh_waybar() { pkill -"RTMIN+$WAYBAR_SIGNAL" waybar 2>/dev/null || true; }

# ── logs ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "logs" ]]; then
    touch "$LOG_FILE"
    # -F keeps following after the file is replaced on the next start.
    exec tail -n 500 -F "$LOG_FILE"
fi

# ── log window ────────────────────────────────────────────────────────
# Opens one log window. Any window opened earlier is closed first, so pressing
# the menu entry or the bar button again replaces the window instead of stacking
# another copy on top of it. Runs before the lock: reading the log must never
# wait behind a start or stop.
if [[ "${1:-}" == "logwin" ]]; then
    pkill -f -- "$LOGWIN_PATTERN" 2>/dev/null
    # Wait for the old window to go away, so the new one is the only match.
    for _ in $(seq 40); do
        pgrep -f -- "$LOGWIN_PATTERN" >/dev/null 2>&1 || break
        sleep 0.05
    done

    # This kitty build wants --class, not --app-id.
    exec kitty --class float-term --title 'ZENOH OPERATOR' \
        -o remember_window_size=no \
        -o initial_window_width=110c \
        -o initial_window_height=42c \
        -e "$0" logs
fi

# ── status ────────────────────────────────────────────────────────────
# Runs before the lock on purpose. waybar polls this often, and it must never
# wait behind a start or stop.
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

# Serialize overlapping triggers so a double press cannot start two bridges.
# The lock uses an explicit file descriptor so it can be closed again when the
# bridge is started. A child that inherits the descriptor keeps holding the
# lock, which would block every later toggle until the bridge exits.
exec 9>"$LOCK_FILE"
if ! flock -w 10 9; then
    notify "Another start or stop is still running"
    exit 1
fi

# ── stop ──────────────────────────────────────────────────────────────
pid="$(bridge_pid)"
if [[ -n "$pid" ]]; then
    # Kill the whole process group so the mise and nix wrappers exit too.
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

# ── start ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
WS_DIR="$("$SCRIPT_DIR/../rofi/find-workspace-dir.sh")" || {
    notify "No ~/Workspace(s) directory found"
    exit 1
}

# The task lives in the deployment repository's own deployment/ config root.
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

# The bridge logs every route it creates, so one start can write several MB.
# Keep only the previous run, and start each run with an empty file.
[[ -f "$LOG_FILE" ]] && mv -f "$LOG_FILE" "$LOG_FILE.1"
printf '=== %s: starting %s (cwd %s) ===\n' \
    "$(date '+%F %T')" "${run_cmd[*]}" "$TASK_DIR" >"$LOG_FILE"

# 9>&- keeps the lock out of the bridge, so a later toggle can take it.
setsid "${run_cmd[@]}" >>"$LOG_FILE" 2>&1 9>&- &
launcher=$!

# mise enters a nix shell first, so the bridge takes a few seconds to appear.
started=""
for _ in $(seq 120); do
    if [[ -n "$(bridge_pid)" ]]; then
        started=1
        break
    fi
    # Stop waiting if the launcher already failed.
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
