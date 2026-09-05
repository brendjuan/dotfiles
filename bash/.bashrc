case $- in
    *i*) ;;
      *) return;;
esac

HISTCONTROL=ignoreboth

shopt -s histappend

HISTSIZE=1000
HISTFILESIZE=2000

shopt -s checkwinsize

[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
        color_prompt=yes
    else
        color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -s)" > /dev/null
    ssh-add ~/.ssh/id_ed25519_personal ~/.ssh/id_ed25519 2> /dev/null
fi

export PATH="$HOME/.local/bin:$PATH"
. "$HOME/.cargo/env"

if [ -d "$HOME/.depot/bin" ]; then
  export DEPOT_INSTALL_DIR="$HOME/.depot/bin"
  export PATH="$DEPOT_INSTALL_DIR:$PATH"
fi

if [ -x "$HOME/.local/bin/mise" ]; then
  eval "$("$HOME/.local/bin/mise" activate bash)"
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

[ -f /opt/ros/jazzy/setup.bash ] && source /opt/ros/jazzy/setup.bash

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
