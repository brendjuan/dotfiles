-- script which better run once on startup

local cwc = cwc

-- load builtin cwc C plugin
local plugins_folder = cwc.is_nested() and "./build/plugins" or cwc.get_datadir() .. "/plugins"
cwc.plugin.load(plugins_folder .. "/cwcle.so")
cwc.plugin.load(plugins_folder .. "/flayout.so")
cwc.plugin.load(plugins_folder .. "/dwl-ipc.so")

-- autostart app
cwc.spawn_with_shell("swaybg --output '*' --image ~/.config/cwc/wallpaper.png --mode fill --color '#020008'")
-- seed active waybar style if it doesn't exist (first boot or stow refresh)
cwc.spawn_with_shell("[ -f ~/.config/cwc/waybar/style-active.css ] || cp ~/.config/cwc/waybar/style.css ~/.config/cwc/waybar/style-active.css")
cwc.spawn_with_shell("waybar -c ~/.config/cwc/waybar/config.jsonc -s ~/.config/cwc/waybar/style-active.css")
cwc.spawn_with_shell("playerctld daemon")
cwc.spawn_with_shell("mako")

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

