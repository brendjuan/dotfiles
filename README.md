# dotfiles

Linux desktop configuration managed with [GNU Stow](https://www.gnu.org/software/stow/).
Every top-level directory is a Stow package. Stow links the files inside it into `$HOME`.
The terminal and editor packages also install on macOS. See [macOS](#macos).

![Tiling layout with VS Code, neofetch, and btop](screenshots/tiling.png)

<p align="center">
  <img src="screenshots/desktop.png" width="49%" alt="Desktop" />
  <img src="screenshots/lockscreen.png" width="49%" alt="Lock screen" />
</p>

## Install

```bash
git clone <repo-url> ~/Personal/dotfiles
cd ~/Personal/dotfiles
cp config.env.example config.env
"$EDITOR" config.env
./install.sh
```

`install.sh` does this, in order:

1. Seeds the local files that git does not track: on Linux the lock screen and wallpaper images, on macOS `kitty/current-theme.conf` from `dark.conf`.
2. Copies every file it would replace to `backups/<timestamp>/`.
3. Links each package listed in `packages.sh` into `$HOME`. The list depends on the operating system. Stow creates real directories and links single files, so programs that write into `~/.claude` or `~/.config/Code` never write into this repo.
4. Fills the `{{PLACEHOLDER}}` values in the git config from `config.env`.
5. Linux only: writes `~/.config/dotfiles/env.sh`. The shells source it to set `CYCLONEDDS_URI` from the ROS workspace.
6. Linux only: asks whether to install the legacy Awesome WM package.

`restore.sh` unlinks the packages and copies a backup back into `$HOME`.

To link or unlink a single package:

```bash
stow -t ~ kitty
stow -D -t ~ kitty
```

### Install on macOS

`brew bundle` installs what the macOS packages need: stow, git, git-lfs, gh, tmux, uv, emacs, kitty, and VS Code.
Oh My Zsh has no Homebrew formula, so its own installer runs first.

```bash
brew bundle
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
cp config.env.example config.env
"$EDITOR" config.env
./install.sh
```

`install.sh` detects macOS with `uname` and stows the packages in `MACOS_PACKAGES`.
`ROS_WORKSPACE` is not used, so the example value can stay.
The [macOS](#macos) section lists which packages are included and why.

## config.env

This file is not tracked.

| Variable | Used by | Meaning |
|---|---|---|
| `WORK_GIT_NAME`, `WORK_GIT_EMAIL` | `~/.gitconfig` | Default git identity |
| `PERSONAL_GIT_NAME`, `PERSONAL_GIT_EMAIL` | `~/.gitconfig-personal` | Git identity for repositories under `~/Personal/` |
| `ROS_WORKSPACE` | `~/.config/dotfiles/env.sh` | ROS workspace whose nix dev shell provides the CycloneDDS config. Linux only. |

## Packages

| Package | What it holds |
|---|---|
| `zsh`, `bash` | Shell setup. depot, mise, and pnpm are enabled only when they are installed. |
| `git` | Git config with git-lfs and a second identity for `~/Personal/` |
| `kitty` | Terminal. `current-theme.conf` is a local file. On Linux the high-contrast toggle writes it, on macOS `install.sh` seeds it from `dark.conf`. |
| `tmux` | Terminal features for tmux inside kitty |
| `mako` | Notification daemon |
| `swaylock` | Screen locker. `scripts/gen_lockscreen.py` draws the background image. |
| `cwc` | The cwc Wayland compositor: Lua config, waybar, rofi menus, helper scripts. See [cwc](#cwc). |
| `vscode` | VS Code user settings |
| `vscode-macos` | The same VS Code settings, linked at `~/Library/Application Support/Code/User/`, where VS Code reads them on macOS. |
| `k4` | `k4 [dir]` opens kitty with four windows in a 2x2 grid |
| `mx` | `mx` reads the battery and sets the DPI of a Logitech mouse. See [mx](#mx). |
| `claude-diff` | `claude-diff` shows a git diff with a file tree and expandable context, in a kitty split next to Claude Code. See [claude-diff](#claude-diff). |
| `claude` | Claude Code skills. No credentials or state. |
| `apps` | Desktop entries for AppImage apps so rofi can start them. See [apps](#apps). |
| `awesome` | Legacy X11 window manager config. See [awesome](#awesome). |

`scripts/` holds tools that are not stowed:

- `gen_lockscreen.py` and `glitch-wallpaper.sh` generate the lock screen and wallpaper images. They need Pillow and ImageMagick.
- `gps-fix.py` and `heading_cli.py` are ROS 2 terminal tools that show the vehicle's GPS fix and heading.
- `share-internet.sh` turns this machine into a NAT gateway for another network. Run it with `--help`.

## macOS

`MACOS_PACKAGES` in `packages.sh` holds the packages that work on a Mac.
A package is included when macOS has a program that reads the same config file.
The other packages are Linux desktop parts with no such program.

| Package | On macOS |
|---|---|
| `zsh` | zsh is the default shell, and Oh My Zsh runs on it. The `debian`, `ubuntu`, `yum`, and `systemd` plugins are replaced by `brew` and `macos`. |
| `git` | Same program. `brew bundle` installs git-lfs and gh. |
| `kitty` | kitty.app from Homebrew. It reads `~/.config/kitty/kitty.conf` on macOS too, and the cask links `kitty` and `kitten` into the PATH. |
| `tmux` | Same program |
| `vscode-macos` | VS Code reads `~/Library/Application Support/Code/User/settings.json`. This package links the shared settings file at that path. |
| `claude` | Same program, same `~/.claude` directory |
| `k4`, `claude-diff` | They only need kitty, uv, and gh. |

The zsh config runs on both systems. Its Linux-only parts, such as `lspci`, `systemctl`, and ROS, are guarded or do nothing when the program is missing.

## cwc

Key bindings live in `cwc/.config/cwc/keybind.lua`. `MOD+H` lists them in rofi.
`MOD+CTRL+R` reloads the compositor config. `MOD+C` opens a menu of custom commands.

### High-contrast mode

`MOD+F6`, the waybar button, and the `MOD+C` menu all run `scripts/high-contrast.sh`.
The mode is on while `~/.cache/high-contrast-mode` exists.
The script switches kitty, mako, waybar, rofi, VS Code, btop, the wallpaper, and the system color scheme.
It does not edit files tracked in this repo, except the VS Code settings.

### Waybar modules that need setup

- `custom/mouse` needs the `mx` package and one run of `mx setup`.
- `custom/claude-usage` reads the Claude Code token from `~/.claude/.credentials.json`.
- `custom/ccm-battery` and `custom/zenoh` talk to a vehicle on the local network. `custom/zenoh` runs the `zenoh:operator` task from the deployment repository under `~/Workspace/`.
- `custom/package` shows FedEx tracking. It is defined but not in the bar by default. To use it, add it to `modules-right` in `waybar/config.jsonc`, copy `packages.json.example` to `~/.config/cwc/packages.json`, and fill in the FedEx API credentials. Get them at developer.fedex.com: create a project, enable the Track API, and copy the production key and secret. A package entry may have a `url` field that replaces the page opened on click. The chip is hidden while the package list is empty.

## mx

`mx` talks HID++ to a Logitech mouse through its `/dev/hidraw` node.
It works over Bluetooth or a USB cable, but not through a Unifying or Bolt receiver. It needs only Python 3.

| Command | Effect |
|---|---|
| `mx setup` | Installs a udev rule so the other commands work without sudo. Run once. |
| `mx battery` | Charge level and charging state |
| `mx dpi` | Current DPI and the allowed values |
| `mx dpi 1600` | Set the DPI |
| `mx info` | Device, HID++ version, battery, and DPI |
| `mx devices` | List Logitech devices. `*` marks the one in use. |

When several Logitech devices are connected, `mx` picks the one that looks most like a mouse.
To choose by hand, pass `--device` with part of the device name or a `/dev/hidraw` node, or set `MX_DEVICE`.

## claude-diff

`claude-diff` is a terminal diff viewer in the style of GitHub's "Files changed" tab.
A file tree with line counts sits above the diff of the selected file, and the unchanged lines between hunks are folded until you expand them.
It reloads every two seconds while files or branches change. It needs `uv`, which installs the Textual library on the first run.

| Command | Effect |
|---|---|
| `claude-diff` | Working tree against the point where the branch split from the default branch |
| `claude-diff main` | Working tree against `main` |
| `claude-diff feat/a feat/b` | What `feat/b` adds on top of `feat/a`, like a pull request |
| `claude-diff feat/a..feat/b` | Plain two-point diff |
| `claude-diff --pr 42` | A GitHub pull request, by number or URL, fetched through `gh`. `--pr` alone takes the pull request of the current branch. |
| `claude-diff --pr --local` | The local branch of the pull request against its base branch on origin. When the branch is checked out, uncommitted changes are included. |
| `claude-diff --worktree NAME ...` | Run against another worktree of the repository, by directory name, branch, or path. Its uncommitted changes are included. |
| `claude-diff --pane ...` | Open the viewer in a kitty split to the right of the current window, 45 percent wide |
| `claude-diff --toggle ...` | Open the split, or close it when it is already open |
| `claude-diff --close` | Close the split for this repository |
| `claude-diff --layout side ...` | Put the file tree beside the diff instead of above it. `hidden` starts without it. |

Keys: `j` and `k` or the arrow keys move between files. `Enter` moves focus to the diff. `t` moves the file tree: top, hidden, side. `e` expands every fold of the file, `w` shows the whole file, `c` cycles the context size between 3, 10, and 25 lines, `r` reloads, `q` quits.
When the diff has focus, the arrow keys or `h` and `l` scroll it, also sideways for long lines.
Click a file in the tree or an arrow in a fold line. The mouse wheel scrolls.

The kitty package binds `ctrl+shift+d` to open the split for the directory of the current window, or close it when it is open.
Zsh completes the revisions with branches, tags, and `HEAD`, also after `..` and `...`, `--pr` with the open pull requests, and `--worktree` with the worktrees. The completion file lives in `~/.local/share/zsh/site-functions`, which `.zshrc` adds to `fpath`.
From a Claude Code session, ask Claude to run `claude-diff --pane feat/a feat/b`. The split opens next to that session.

## apps

The desktop entries start `~/Applications/FinOps.AppImage` and `~/Applications/GHOST.AppImage`.
Both are symlinks to the real, versioned files, which are not in the repo. On a new machine:

```bash
mkdir -p ~/Applications
mv ~/Downloads/FinOps-*.AppImage ~/Downloads/GHOST_*.AppImage ~/Applications/
chmod +x ~/Applications/*.AppImage
ln -sfn FinOps-2.6.1.AppImage ~/Applications/FinOps.AppImage
ln -sfn GHOST_11.2.0_amd64.AppImage ~/Applications/GHOST.AppImage
```

Use the file names you downloaded in the `ln` commands.
To update an app, replace the AppImage and point the symlink at the new file.
Icons are optional. The entries look for `~/.local/share/icons/finops.png` and `ghost.png`.

## awesome

Legacy X11 setup, kept as a fallback. `install.sh` asks before installing it.
It clones [awesome-copycats](https://github.com/lcpz/awesome-copycats) into `~/.config/awesome` and links this repo's `rc.lua` and `theme.lua` on top.
Skip it on new machines.
