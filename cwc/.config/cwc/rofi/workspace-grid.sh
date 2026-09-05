#!/usr/bin/env bash
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
WORKSPACE_DIR=$("$SCRIPT_DIR/find-workspace-dir.sh") || { notify-send "workspace-grid" "No ~/Workspace(s) directory found"; exit 1; }
NAME="${1:-1}"
DIR="$WORKSPACE_DIR/$NAME"
mkdir -p "$DIR/deployment"

kitty --session - <<EOF
layout grid
cd $DIR
launch
launch --cwd $DIR/deployment zsh -ic "task ping -- --scan; exec zsh -i"
launch
launch
EOF
