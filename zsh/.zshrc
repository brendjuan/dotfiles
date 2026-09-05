export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="lambda"

zstyle :omz:plugins:ssh-agent identities id_ed25519_personal id_ed25519

plugins=(git bazel bun colored-man-pages colorize command-not-found cp debian dirhistory docker docker-compose emoji golang history kitty mise nomad pip podman python rsync rust ssh ssh-agent sudo systemd task tmux ubuntu uv yum)

source $ZSH/oh-my-zsh.sh

[ -s "/home/bjax/.bun/_bun" ] && source "/home/bjax/.bun/_bun"

export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

export PATH="$HOME/.local/bin:$PATH"
. "$HOME/.cargo/env"

PROMPT="%{$fg[blue]%}%m%{$reset_color%} $PROMPT"

if [ -d "$HOME/.depot/bin" ]; then
  export DEPOT_INSTALL_DIR="$HOME/.depot/bin"
  export PATH="$DEPOT_INSTALL_DIR:$PATH"
fi

if [ -x "$HOME/.local/bin/mise" ]; then
  eval "$("$HOME/.local/bin/mise" activate zsh)"
fi

if [ -d "$HOME/.local/share/pnpm" ]; then
  export PNPM_HOME="$HOME/.local/share/pnpm"
  case ":$PATH:" in
    *":$PNPM_HOME:"*) ;;
    *) export PATH="$PNPM_HOME:$PATH" ;;
  esac
fi

[ -f "$HOME/.config/dotfiles/env.sh" ] && source "$HOME/.config/dotfiles/env.sh"
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

[ -f /opt/ros/jazzy/setup.zsh ] && source /opt/ros/jazzy/setup.zsh

alias emacs="emacs -nw"
export VISUAL="emacs -nw"
export EDITOR="$VISUAL"

export OBSIDIAN_VAULT="$HOME/Documents/Base"
export CLAUDE_OBSIDIAN_VAULT="$OBSIDIAN_VAULT/Claude"

if lspci 2>/dev/null | grep -qi 'VGA.*Intel' && ! lspci 2>/dev/null | grep -qi 'VGA.*NVIDIA\|VGA.*AMD.*Radeon'; then
  export LIBGL_ALWAYS_SOFTWARE=0
  export GZ_SIM_RENDER_ENGINE_GUI_API_BACKEND=opengl
fi

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
  prime-run() { "$@"; }
fi

export PNPM_HOME="/home/bjax/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

export PATH="/home/bjax/.pixi/bin:$PATH"

zero() { sudo systemctl "$1" zerotier-one.service; }

nom() { sudo systemctl "$1" nomad.service; }

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
  [ "$longfmt" -eq 1 ] && onecol=
  command ls $onecol $coloropt "$@" | while IFS= read -r line; do
    clean=$(printf '%s\n' "$line" | sed 's/\x1b\[[0-9;]*m//g')
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

if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"

  ROS_PYTHONPATH="$PYTHONPATH"
  _keep_ros_pythonpath() {
    [[ -n $ROS_PYTHONPATH ]] || return 0
    case ":$PYTHONPATH:" in
      *":${ROS_PYTHONPATH%%:*}:"*) ;;
      *) export PYTHONPATH="$ROS_PYTHONPATH${PYTHONPATH:+:$PYTHONPATH}" ;;
    esac
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _keep_ros_pythonpath
fi
