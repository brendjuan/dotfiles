#!/usr/bin/env bash
# open a float-term kitty in ~/Workspace/<name> and sic claude code on the
# convention-review skill in `learn` mode — mines the repo's conventions into
# the vault, one rule per note. meant to run in a watchable floating window so
# you can eyeball the carnage. glitchcore-adjacent.
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
WORKSPACE_DIR=$("$SCRIPT_DIR/find-workspace-dir.sh") || {
    notify-send "learn-conventions" "No ~/Workspace(s) directory found"; exit 1;
}
NAME="${1:-1}"
DIR="$WORKSPACE_DIR/$NAME"

exec kitty --class float-term \
    -o remember_window_size=no -o initial_window_width=110c -o initial_window_height=42c \
    -e zsh -ic "cd '$DIR' && claude '/convention-review learn'; exec zsh -i"
