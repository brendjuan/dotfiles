#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_BASE="$DOTFILES_DIR/backups"
PACKAGES=(zsh bash git kitty mako swaylock cwc vscode k4 tmux)

if [ ! -d "$BACKUP_BASE" ] || [ -z "$(ls -A "$BACKUP_BASE" 2>/dev/null)" ]; then
    echo "No backups found in $BACKUP_BASE"
    exit 1
fi

# List available backups
echo "Available backups:"
echo ""
backups=()
i=1
for dir in "$BACKUP_BASE"/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    backups+=("$dir")
    echo "  $i) $name"
    i=$((i + 1))
done

if [ ${#backups[@]} -eq 0 ]; then
    echo "No backups found."
    exit 1
fi

echo ""
read -rp "Select a backup to restore [1-${#backups[@]}]: " choice

if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#backups[@]} ]; then
    echo "Invalid selection."
    exit 1
fi

BACKUP_DIR="${backups[$((choice - 1))]}"
echo ""
echo "Restoring from: $(basename "$BACKUP_DIR")"
echo ""

# Unstow packages first to remove symlinks
if command -v stow &>/dev/null; then
    for pkg in "${PACKAGES[@]}"; do
        if [ -d "$DOTFILES_DIR/$pkg" ]; then
            stow -d "$DOTFILES_DIR" -t "$HOME" -D "$pkg" 2>/dev/null || true
        fi
    done
fi

# Restore each backed-up file
restored=0
while IFS= read -r bak_file; do
    rel_path="${bak_file#"$BACKUP_DIR"/}"
    # Strip the .bak suffix
    target="$HOME/${rel_path%.bak}"
    target_dir=$(dirname "$target")

    mkdir -p "$target_dir"

    if [ -L "$target" ]; then
        rm "$target"
    fi

    if [ -d "$bak_file" ]; then
        cp -r "$bak_file" "$target"
    else
        cp "$bak_file" "$target"
    fi
    echo "  restored: ~/${rel_path%.bak}"
    restored=1
done < <(find "$BACKUP_DIR" -name "*.bak" -print)

if [ "$restored" -eq 1 ]; then
    echo ""
    echo "Done! Files restored from backup."
else
    echo "No .bak files found in that backup."
fi
