#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$DOTFILES_DIR/config.env"
PACKAGES=(zsh bash git kitty mako swaylock cwc)

# Check for stow
if ! command -v stow &>/dev/null; then
    echo "GNU Stow is required but not installed."
    echo "Install it with: sudo apt install stow"
    exit 1
fi

# Load config
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Missing config.env — copy the example and fill it in:"
    echo "  cp config.env.example config.env"
    exit 1
fi
source "$CONFIG_FILE"

echo "Stowing dotfiles from $DOTFILES_DIR"

for pkg in "${PACKAGES[@]}"; do
    if [ -d "$DOTFILES_DIR/$pkg" ]; then
        echo "  -> $pkg"
        stow -d "$DOTFILES_DIR" -t "$HOME" --adopt "$pkg"
    else
        echo "  !! $pkg not found, skipping"
    fi
done

# After --adopt, stow pulls existing files into the repo.
# Reset any adopted changes to keep repo contents authoritative.
echo ""
echo "Restoring repo state (undoing any adopted diffs)..."
git -C "$DOTFILES_DIR" checkout -- .

# Replace placeholders after checkout so the symlinked files get real values
echo "Applying config..."
sed -i "s/{{GIT_NAME}}/$GIT_NAME/g; s/{{GIT_EMAIL}}/$GIT_EMAIL/g" "$DOTFILES_DIR/git/.gitconfig"

echo ""
echo "Done! All packages stowed."
