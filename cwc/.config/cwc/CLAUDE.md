# CLAUDE.md

Guidance for Claude Code when working in `~/.config/cwc/`.

## What this is

Configuration for **cwc** (cwcwm), a Wayland compositor scripted in Lua. cwc loads `rc.lua` at startup.
The API is modeled on AwesomeWM: a global `cwc` object plus the `cuteful` and `gears` libraries.

## Files

- `rc.lua`: entry point. Applies `conf.lua`, runs `oneshot.lua` on first start, loads the key and mouse bindings and the battery monitor, configures screens, and defines client rules and signal handlers. Tags 10 to 12 are temporary tags for Gazebo, RViz, and Foxglove windows.
- `conf.lua`: the table passed to `config.init()` (cursor, keyboard, border, gaps).
- `keybind.lua`: keyboard bindings through `cwc.kbd.bind()`. `MODKEY` is `mod.LOGO`, or `mod.ALT` in a nested session. `MOD+W` enters a submap for moving floating windows.
- `mousebind.lua`: pointer bindings, swipe gestures, and a keyboard-as-mouse submap (`MOD+Z`).
- `oneshot.lua`: startup-only work: plugins, autostart programs, environment variables.
- `battery.lua`: low-battery warnings. Starts the overlay scripts in `scripts/`.
- `rofi/`: rofi themes and the scripts behind the `MOD+C` command menu.
- `scripts/`: waybar module scripts and the high-contrast toggle.
- `waybar/`: waybar config and styles. `style-active.css` is a local copy that the toggle rewrites.

## Patterns

- `cwc.connect_signal` for signals, `cwc.spawn_with_shell` to start programs.
- Enums come from `cuteful.enum`.
- Client rules use `crules.add_client_rule` with `where`, `set`, and `run`.
- `kbd.create_bindmap()` creates a modal key layer.
- High-contrast mode is on when `~/.cache/high-contrast-mode` exists. Every script reads that file. None keeps its own state.

## Style

- No code comments.
- User-facing text (notifications, tooltips, terminal banners) keeps the glitchcore tone: irreverent and a little chaotic.
- Palette, shared by rofi, waybar, swaylock, and kitty:
  - Background `rgba(2, 0, 8, 0.92)`
  - Primary `#00ffb4`
  - Urgent `#ff0050`
  - Dim `rgba(0, 255, 180, 0.22)`
  - Warning `#ff5500`
  - Font: Hack Nerd Font
  - Tag labels: katakana (ア イ ウ エ オ カ キ ク ケ) plus GZ, RV, FG

## Applying changes

`MOD+CTRL+R` reloads the compositor config.
Waybar is started once from `oneshot.lua`. Restart it by hand after changing its config.
