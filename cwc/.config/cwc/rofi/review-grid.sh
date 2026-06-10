#!/usr/bin/env bash
# open a single-split kitty (two panes) in ~/Workspace/<name>, claude in each
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
WORKSPACE_DIR=$("$SCRIPT_DIR/find-workspace-dir.sh") || { notify-send "review-grid" "No ~/Workspace(s) directory found"; exit 1; }
NAME="${1:-1}"
DIR="$WORKSPACE_DIR/$NAME"

kitty --session - <<EOF
layout tall
cd $DIR
launch zsh -ic "claude; exec zsh -i"
launch zsh -ic "claude; exec zsh -i"
EOF
