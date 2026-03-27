# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Configuration for **cwc** (cwcwm), a Wayland compositor with Lua scripting. This lives at `~/.config/cwc/` and is loaded at compositor startup. cwc uses an AwesomeWM-inspired Lua API with libraries like `cuteful`, `gears`, and a global `cwc` object.

## Architecture

- **rc.lua** — Entry point. Loads config, runs oneshot on first start, sets up keybinds/mousebinds, configures screens/tags, and defines client rules and signal handlers.
- **conf.lua** — Returns a config table (cursor, keyboard, border, gaps settings) consumed by `config.init()`.
- **keybind.lua** — All keyboard bindings. Uses `cwc.kbd.bind()` and bindmap submaps. MODKEY is `mod.LOGO` (or `mod.ALT` when nested).
- **mousebind.lua** — Pointer bindings, swipe gestures, and a keyboard-as-mouse submap (`MOD+Z`).
- **oneshot.lua** — Startup-only commands: autostart apps (swaybg, waybar, playerctld, swayidle, copyq), env vars, dbus setup, plugin loading (cwcle, flayout, dwl-ipc).
- **rofi/glitchcore.rasi** — Rofi theme matching the glitchcore aesthetic.
- **waybar/** — Waybar config and styles using dwl/tags IPC protocol. Tag labels use katakana characters.

## Key Patterns

- The global `cwc` object is the compositor API — signals (`cwc.connect_signal`), spawning (`cwc.spawn_with_shell`), client/screen/pointer access.
- Enums come from `cuteful.enum` (layout modes, directions, modifiers, libinput constants).
- Tags/workspaces 1-9 with layout modes: MASTER (default), FLOATING (2,8,9), BSP (4,5,6).
- Client rules use `crules.add_client_rule` with `where`/`set`/`run` fields.
- Submaps (bindmaps) allow modal key layers — see `kbd.create_bindmap()` usage.

## Visual Theme

The vibe is **meme-y, sketchy glitchcore** — intentionally unhinged CRT-aesthetic energy. Code comments, waybar config, and CSS should match this tone (irreverent, self-aware, slightly chaotic). New UI elements must stay on-brand.

Consistent palette across rofi, waybar, and swaylock:
- Background: `rgba(2, 0, 8, ~0.92)` (near-black blue void)
- Primary: `#00ffb4` (teal/cyan)
- Accent/urgent: `#ff0050` (classification red)
- Dim/ghost: `rgba(0, 255, 180, 0.22)`
- Warning: `#ff5500` (amber)
- Font: Hack Nerd Font
- Katakana tag labels in waybar (ア イ ウ エ オ カ キ ク ケ)

## Applying Changes

Reload the compositor config with `MOD+CTRL+R` (calls `cwc.reload`). Waybar uses its own config path specified in oneshot.lua.
