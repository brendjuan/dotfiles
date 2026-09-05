# dotfiles

Linux desktop configuration managed with [GNU Stow](https://www.gnu.org/software/stow/).
Every top-level directory is a Stow package. Stow links the files inside it into `$HOME`.

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

1. Copies every file it would replace to `backups/<timestamp>/`.
2. Links each package listed in `packages.sh` into `$HOME`.
3. Fills the `{{PLACEHOLDER}}` values in the git config from `config.env`.
4. Writes `~/.config/dotfiles/env.sh`. The shells source it to set `CYCLONEDDS_URI` from the ROS workspace.
5. Asks whether to install the legacy Awesome WM package.

`restore.sh` unlinks the packages and copies a backup back into `$HOME`.

To link or unlink a single package:

```bash
stow -t ~ kitty
stow -D -t ~ kitty
```

## config.env

This file is not tracked.

| Variable | Used by | Meaning |
|---|---|---|
| `WORK_GIT_NAME`, `WORK_GIT_EMAIL` | `~/.gitconfig` | Default git identity |
| `PERSONAL_GIT_NAME`, `PERSONAL_GIT_EMAIL` | `~/.gitconfig-personal` | Git identity for repositories under `~/Personal/` |
| `ROS_WORKSPACE` | `~/.config/dotfiles/env.sh` | ROS workspace whose nix dev shell provides the CycloneDDS config |

## Packages

| Package | What it holds |
|---|---|
| `zsh`, `bash` | Shell setup. depot, mise, and pnpm are enabled only when they are installed. |
| `git` | Git config with git-lfs and a second identity for `~/Personal/` |
| `kitty` | Terminal. `current-theme.conf` is a local file that the high-contrast toggle rewrites. |
| `tmux` | Terminal features for tmux inside kitty |
| `mako` | Notification daemon |
| `swaylock` | Screen locker. `scripts/gen_lockscreen.py` draws the background image. |
| `cwc` | The cwc Wayland compositor: Lua config, waybar, rofi menus, helper scripts. See [cwc](#cwc). |
| `vscode` | VS Code user settings |
| `k4` | `k4 [dir]` opens kitty with four windows in a 2x2 grid |
| `mx` | `mx` reads the battery and sets the DPI of a Logitech mouse. See [mx](#mx). |
| `claude` | Claude Code skills. No credentials or state. |
| `apps` | Desktop entries for AppImage apps so rofi can start them. See [apps](#apps). |
| `awesome` | Legacy X11 window manager config. See [awesome](#awesome). |

`scripts/` holds tools that are not stowed:

- `gen_lockscreen.py` and `glitch-wallpaper.sh` generate the lock screen and wallpaper images. They need Pillow and ImageMagick.
- `gps-fix.py` and `heading_cli.py` are ROS 2 terminal tools that show the vehicle's GPS fix and heading.
- `share-internet.sh` turns this machine into a NAT gateway for another network. Run it with `--help`.

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
