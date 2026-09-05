local cwc = cwc

local plugins_folder = cwc.is_nested() and "./build/plugins" or cwc.get_datadir() .. "/plugins"
cwc.plugin.load(plugins_folder .. "/cwcle.so")
cwc.plugin.load(plugins_folder .. "/flayout.so")
cwc.plugin.load(plugins_folder .. "/dwl-ipc.so")

cwc.spawn_with_shell([[
if [ -f ~/.cache/high-contrast-mode ] && [ -f ~/.config/cwc/wallpaper-inverted.png ]; then
    swaybg --output '*' --image ~/.config/cwc/wallpaper-inverted.png --mode fill --color '#ffffff'
else
    swaybg --output '*' --image ~/.config/cwc/wallpaper.png --mode fill --color '#020008'
fi]])
cwc.spawn_with_shell([[
if [ -f ~/.cache/high-contrast-mode ]; then
    cp ~/.config/kitty/highcontrast.conf ~/.config/kitty/current-theme.conf
else
    cp ~/.config/kitty/dark.conf ~/.config/kitty/current-theme.conf
fi]])
cwc.spawn_with_shell("[ -f ~/.config/cwc/waybar/style-active.css ] || cp ~/.config/cwc/waybar/style.css ~/.config/cwc/waybar/style-active.css")
cwc.spawn_with_shell("waybar -c ~/.config/cwc/waybar/config.jsonc -s ~/.config/cwc/waybar/style-active.css")
cwc.spawn_with_shell("playerctld daemon")
cwc.spawn_with_shell("mako")
cwc.spawn_with_shell("[ -f ~/.cache/high-contrast-mode ] && (sleep 0.5; makoctl mode -s highcontrast) || true")

cwc.spawn_with_shell("~/.config/cwc/scripts/device-notify.py")

cwc.timer.new(3, function()
    cwc.spawn { "copyq" }
end, { one_shot = true })

cwc.setenv("HYPRCURSOR_THEME", "Bibata-Modern-Classic")

cwc.spawn_with_shell(
    "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")

cwc.spawn_with_shell('swayidle -w before-sleep "swaylock -f"')

cwc.spawn_with_shell("/usr/lib/x86_64-linux-gnu/libexec/polkit-kde-authentication-agent-1")

cwc.spawn_with_shell(
    'for i in $(seq 1 20); do DISPLAY=:1 xhost +si:localuser:root 2>/dev/null && break; sleep 0.5; done')
