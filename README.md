# dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Packages

| Package    | What it configures              |
|------------|---------------------------------|
| `zsh`      | `.zshrc`, `.zshenv` (Oh My Zsh) |
| `bash`     | `.bashrc`                       |
| `git`      | `.gitconfig`, `.config/git/`    |
| `kitty`    | Kitty terminal                  |
| `mako`     | Mako notification daemon        |
| `swaylock` | Swaylock screen locker          |
| `cwc`      | CWC window compositor           |

## Install

```bash
git clone <repo-url> ~/Personal/dotfiles
cd ~/Personal/dotfiles
cp config.env.example config.env   # fill in your name/email
./install.sh
```

## Config

`config.env` holds values that get substituted into templates (e.g. git identity).
Copy the example and edit it before running install:

```bash
cp config.env.example config.env
```

See `config.env.example` for available options.

## Stow individual packages

```bash
stow -t ~ kitty    # symlink just kitty
stow -D -t ~ kitty # unlink kitty
```
