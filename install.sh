#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$DOTFILES_DIR/config.env"
PACKAGES=(zsh bash git kitty mako swaylock cwc k4 tmux)

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

# If no custom lockscreen, link the example
LOCKSCREEN="$DOTFILES_DIR/swaylock/.config/swaylock/img/lockscreen.png"
if [ ! -f "$LOCKSCREEN" ]; then
    echo "No lockscreen.png found, linking example..."
    ln -s lockscreen.png.example "$LOCKSCREEN"
fi

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
sed -i "s/{{WORK_GIT_NAME}}/$WORK_GIT_NAME/g; s/{{WORK_GIT_EMAIL}}/$WORK_GIT_EMAIL/g" "$DOTFILES_DIR/git/.gitconfig"
sed -i "s/{{PERSONAL_GIT_NAME}}/$PERSONAL_GIT_NAME/g; s/{{PERSONAL_GIT_EMAIL}}/$PERSONAL_GIT_EMAIL/g" "$DOTFILES_DIR/git/.gitconfig-personal"
sed -i "s|{{CYCLONEDDS_URI}}|$CYCLONEDDS_URI|g" "$DOTFILES_DIR/zsh/.zshrc"
sed -i "s|{{CYCLONEDDS_URI}}|$CYCLONEDDS_URI|g" "$DOTFILES_DIR/bash/.bashrc"

# Optional: Awesome WM
read -rp "Set up Awesome WM config? [y/N] " awesome_answer
if [[ "${awesome_answer,,}" == "y" ]]; then
    AWESOME_DIR="$HOME/.config/awesome"

    if [ ! -d "$AWESOME_DIR/.git" ]; then
        echo "Cloning awesome-copycats..."
        git clone --recurse-submodules https://github.com/lcpz/awesome-copycats "$AWESOME_DIR"
    else
        echo "awesome-copycats already cloned, skipping."
    fi

    # Stow our customizations on top of the cloned repo
    echo "  -> awesome (overlay)"
    stow -d "$DOTFILES_DIR" -t "$HOME" --adopt awesome
    git -C "$DOTFILES_DIR" checkout -- awesome

    # If no custom wallpaper, fall back to the backup
    AWESOME_WALL="$AWESOME_DIR/themes/powerarrow-dark/wall.jpg"
    if [ ! -f "$AWESOME_WALL" ] || [ -L "$AWESOME_WALL" ]; then
        echo "No wall.jpg found, linking backup..."
        ln -sf wall.jpg.bak "$AWESOME_WALL"
    fi

    # Silence stow-managed files in the cloned repo's git status
    git -C "$AWESOME_DIR" update-index --assume-unchanged rc.lua 2>/dev/null || true
    git -C "$AWESOME_DIR" update-index --assume-unchanged themes/powerarrow-dark/theme.lua 2>/dev/null || true
fi

echo ""
echo "Done! All packages stowed."
