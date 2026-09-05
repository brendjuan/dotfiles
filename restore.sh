#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_BASE="$DOTFILES_DIR/backups"
source "$DOTFILES_DIR/packages.sh"

if [ ! -d "$BACKUP_BASE" ] || [ -z "$(ls -A "$BACKUP_BASE" 2>/dev/null)" ]; then
    echo "No backups found in $BACKUP_BASE"
    exit 1
fi

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

if command -v stow &>/dev/null; then
    for pkg in "${PACKAGES[@]}"; do
        if [ -d "$DOTFILES_DIR/$pkg" ]; then
            stow -d "$DOTFILES_DIR" -t "$HOME" -D "$pkg" 2>/dev/null || true
        fi
    done
fi

restored=0
while IFS= read -r backed_file; do
    rel_path="${backed_file#"$BACKUP_DIR"/}"
    target="$HOME/$rel_path"
    target_dir=$(dirname "$target")

    mkdir -p "$target_dir"

    if [ -L "$target" ]; then
        rm "$target"
    fi

    if [ -d "$backed_file" ]; then
        cp -r "$backed_file" "$target"
    else
        cp "$backed_file" "$target"
    fi
    echo "  restored: ~/$rel_path"
    restored=1
done < <(find "$BACKUP_DIR" -type f -print)

if [ "$restored" -eq 1 ]; then
    echo ""
    echo "Done! Files restored from backup."
else
    echo "No files found in that backup."
fi
