-- script which better run once on startup

local cwc = cwc

-- load builtin cwc C plugin
local plugins_folder = cwc.is_nested() and "./build/plugins" or cwc.get_datadir() .. "/plugins"
cwc.plugin.load(plugins_folder .. "/cwcle.so")
cwc.plugin.load(plugins_folder .. "/flayout.so")
cwc.plugin.load(plugins_folder .. "/dwl-ipc.so")

-- autostart app
-- reconcile persisted high-contrast state on boot: the state file survives a
-- reboot but runtime state (wallpaper, mako mode, kitty theme) does not, so
-- seed each to match ~/.cache/high-contrast-mode instead of hardcoding dark.
cwc.spawn_with_shell([[
if [ -f ~/.cache/high-contrast-mode ] && [ -f ~/.config/cwc/wallpaper-inverted.png ]; then
    swaybg --output '*' --image ~/.config/cwc/wallpaper-inverted.png --mode fill --color '#ffffff'
else
    swaybg --output '*' --image ~/.config/cwc/wallpaper.png --mode fill --color '#020008'
fi]])
-- seed kitty's included theme file to match state (dark unless sunlight mode is on)
cwc.spawn_with_shell([[
if [ -f ~/.cache/high-contrast-mode ]; then
    cp ~/.config/kitty/highcontrast.conf ~/.config/kitty/current-theme.conf
else
    cp ~/.config/kitty/dark.conf ~/.config/kitty/current-theme.conf
fi]])
-- seed active waybar style if it doesn't exist (first boot or stow refresh)
cwc.spawn_with_shell("[ -f ~/.config/cwc/waybar/style-active.css ] || cp ~/.config/cwc/waybar/style.css ~/.config/cwc/waybar/style-active.css")
cwc.spawn_with_shell("waybar -c ~/.config/cwc/waybar/config.jsonc -s ~/.config/cwc/waybar/style-active.css")
cwc.spawn_with_shell("playerctld daemon")
cwc.spawn_with_shell("mako")
-- mako modes are runtime-only (don't survive a mako restart), so re-apply the
-- high-contrast mode once mako's socket is up if the state file says we're ON.
cwc.spawn_with_shell("[ -f ~/.cache/high-contrast-mode ] && (sleep 0.5; makoctl mode -s highcontrast) || true")

-- for app that use tray better to wait for the bar to load
cwc.timer.new(3, function()
    cwc.spawn { "copyq" }
end, { one_shot = true })

-- env var
cwc.setenv("HYPRCURSOR_THEME", "Bibata-Modern-Classic")

-- xdg-desktop-portal-wlr
cwc.spawn_with_shell(
    "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")

-- swayidle: lock screen before sleep (lid close)
cwc.spawn_with_shell('swayidle -w before-sleep "swaylock -f"')

