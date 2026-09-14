DOTFILES_OS="$(uname -s)"

LINUX_PACKAGES=(zsh bash git kitty mako swaylock cwc vscode k4 tmux claude apps mx claude-diff)
MACOS_PACKAGES=(zsh git kitty vscode-macos k4 tmux claude claude-diff)

if [ "$DOTFILES_OS" = "Darwin" ]; then
    PACKAGES=("${MACOS_PACKAGES[@]}")
else
    PACKAGES=("${LINUX_PACKAGES[@]}")
fi
