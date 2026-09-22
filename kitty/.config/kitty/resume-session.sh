#!/usr/bin/env bash
set -euo pipefail

SESSION_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/kitty/last-session.conf"

if [ ! -s "$SESSION_FILE" ]; then
    echo "No saved kitty session at $SESSION_FILE" >&2
    exit 1
fi

exec kitty --detach --session "$SESSION_FILE"
