#!/usr/bin/env bash
# open a 2x2 kitty grid in ~/Workspace/<name>
NAME="${1:-1}"
DIR="$HOME/Workspace/$NAME"
mkdir -p "$DIR/deployment"

kitty --session - <<EOF
layout grid
cd $DIR
launch
launch --cwd $DIR/deployment bash -c "task ping -- --scan; exec bash"
launch
launch
EOF
