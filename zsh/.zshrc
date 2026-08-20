# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="lambda"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
zstyle :omz:plugins:ssh-agent identities id_ed25519_personal id_ed25519

plugins=(git bazel bun colored-man-pages colorize command-not-found cp debian dirhistory docker docker-compose emoji golang history kitty mise nomad pip podman python rsync rust ssh ssh-agent sudo systemd task tmux ubuntu uv yum zsh-completion-sync)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# bun completions
[ -s "/home/bjax/.bun/_bun" ] && source "/home/bjax/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

export PATH="$HOME/.local/bin:$PATH"
. "$HOME/.cargo/env"

# Prepend hostname in blue to the prompt
PROMPT="%{$fg[blue]%}%m%{$reset_color%} $PROMPT"

# depot
if [ -d "$HOME/.depot/bin" ]; then
  export DEPOT_INSTALL_DIR="$HOME/.depot/bin"
  export PATH="$DEPOT_INSTALL_DIR:$PATH"
fi

# mise
if [ -x "$HOME/.local/bin/mise" ]; then
  eval "$("$HOME/.local/bin/mise" activate zsh)"
fi

# pnpm
if [ -d "$HOME/.local/share/pnpm" ]; then
  export PNPM_HOME="$HOME/.local/share/pnpm"
  case ":$PATH:" in
    *":$PNPM_HOME:"*) ;;
    *) export PATH="$PNPM_HOME:$PATH" ;;
  esac
fi

# Machine-specific values, generated by install.sh from config.env
[ -f "$HOME/.config/dotfiles/env.sh" ] && . "$HOME/.config/dotfiles/env.sh"
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

[ -f /opt/ros/jazzy/setup.zsh ] && source /opt/ros/jazzy/setup.zsh

alias emacs="emacs -nw"
export VISUAL="emacs -nw"
export EDITOR="$VISUAL"

# Obsidian vault location, plus a subfolder for Claude's internal memory
export OBSIDIAN_VAULT="$HOME/Documents/Base"
export CLAUDE_OBSIDIAN_VAULT="$OBSIDIAN_VAULT/Claude"

# Gazebo performance: force OpenGL on integrated Intel GPUs
if lspci 2>/dev/null | grep -qi 'VGA.*Intel' && ! lspci 2>/dev/null | grep -qi 'VGA.*NVIDIA\|VGA.*AMD.*Radeon'; then
  export LIBGL_ALWAYS_SOFTWARE=0
  export GZ_SIM_RENDER_ENGINE_GUI_API_BACKEND=opengl
fi

# Run a specific app on the discrete GPU (PRIME render offload).
#   Usage: prime-run gazebo   /   prime-run gz sim ...
# Scoped to the launched command on purpose: exporting these globally forces
# EGL/GL to the dGPU and breaks iGPU/Wayland rendering (e.g. a wlroots
# compositor can't render on the Intel iGPU, Xwayland glyphs go blank).
# Defining a function is harmless on any machine; it only acts when invoked.
if lspci 2>/dev/null | grep -qi 'VGA.*NVIDIA'; then
  prime-run() {
    __NV_PRIME_RENDER_OFFLOAD=1 \
    __GLX_VENDOR_LIBRARY_NAME=nvidia \
    __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json \
    "$@"
  }
elif lspci 2>/dev/null | grep -qi 'VGA.*AMD.*Radeon'; then
  prime-run() { DRI_PRIME=1 "$@"; }
else
  prime-run() { "$@"; }  # no discrete GPU: just run on the default GPU
fi

# pnpm
export PNPM_HOME="/home/bjax/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

export PATH="/home/bjax/.pixi/bin:$PATH"

# zerotier-one systemctl shortcut: `zero <cmd>` -> `sudo systemctl <cmd> zerotier-one.service`
zero() { sudo systemctl "$1" zerotier-one.service; }

# nomad systemctl shortcut: `nom <cmd>` -> `sudo systemctl <cmd> nomad.service`
nom() { sudo systemctl "$1" nomad.service; }

# `lsb`: ls with each subdir's git branch shown inline next to the folder, when
# the subdir is a git repo whose branch differs from the current directory's.
# Works with plain `lsb` and long format (`lsb -la`); preserves ls's own colors.
lsb() {
  local cur name b line clean longfmt=0 a onecol=-1 coloropt=
  [ -t 1 ] && coloropt=--color=always
  cur=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  for a in "$@"; do
    case $a in
      --) break ;;
      --format=long|--format=verbose) longfmt=1 ;;
      --*) ;;
      -*l*) longfmt=1 ;;
    esac
  done
  [ "$longfmt" -eq 1 ] && onecol=          # -l implies one entry per line already
  command ls $onecol $coloropt "$@" | while IFS= read -r line; do
    clean=$(printf '%s\n' "$line" | sed 's/\x1b\[[0-9;]*m//g')   # strip ANSI for matching
    case $clean in total\ *|"") printf '%s\n' "$line"; continue ;; esac
    if [ "$longfmt" -eq 1 ]; then
      name=$(printf '%s\n' "$clean" | awk '{for(i=9;i<=NF;i++)printf "%s%s",$i,(i<NF?" ":"")}')
    else
      name=$clean
    fi
    name=${name%% -> *}
    case $name in .|..) printf '%s\n' "$line"; continue ;; esac
    if [ -d "$name" ]; then
      b=$(git -C "$name" rev-parse --abbrev-ref HEAD 2>/dev/null)
      if [ -n "$b" ] && [ "$b" != "$cur" ]; then
        printf '%s \033[33m(%s)\033[0m\n' "$line" "$b"
        continue
      fi
    fi
    printf '%s\n' "$line"
  done
}
alias ls='lsb'
