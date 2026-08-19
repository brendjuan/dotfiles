-- cwc default config

-- If LuaRocks is installed, make sure that packages installed through it are
-- found (e.g. lgi). If LuaRocks is not installed, do nothing.
pcall(require, "luarocks.loader")

local gears = require("gears")
local enum = require("cuteful.enum")
local tag = require("cuteful.tag")
local impl = require("impl")
local config = require("config")
local crules = require("cuteful.rules")

-- make it local so the `undefined global` lsp error stop yapping on every cwc access
local cwc = cwc

-- config.init should go first before anything else
local conf = require("conf")

-- high contrast mode: override border colors when state file exists
local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

if file_exists(os.getenv("HOME") .. "/.cache/high-contrast-mode") then
    conf.border_color_focus  = gears.color("#000000")
    conf.border_color_normal = gears.color("#666666")
    conf.border_color_raised = gears.color("#000000")
    conf.border_width        = 3
    conf.useless_gaps        = 0
end

config.init(conf)

-- execute oneshot.lua once, cwc.is_startup() mark that the configuration is loaded for the first time
if cwc.is_startup() then
    gears.protected_call(require, "oneshot")
end

-- execute keybind script
gears.protected_call(require, "keybind")
gears.protected_call(require, "mousebind")

-- battery watchdog: urgent mako at <10%, pulsing red edges at <5%
gears.protected_call(require, "battery")

-- use core implementation
impl.use_core()

-- input device config
cwc.connect_signal("input::new", function(dev)
    dev.sensitivity   = -0.75
    dev.accel_profile = enum.libinput.ACCEL_PROFILE_FLAT

    if dev.name:lower():match("touchpad") then
        dev.sensitivity    = 0.7
        dev.natural_scroll = true
        dev.tap            = true
        dev.tap_drag       = true
        dev.dwt            = true
    end
end)

------------------------------- SCREEN SETUP ------------------------------------
-- Layout (from wlr-randr):
--   [ eDP-1 laptop ][ DP-2 landscape ][ DP-1 portrait ]
--         2560x1600      2560x1440        1440x2560 (rotated 90°)
-- Matches on screen.name: the two H27T27 externals have identical EDIDs (same
-- make/model, no serial), so description can't distinguish landscape vs
-- portrait — port name is the only stable discriminator. If you re-cable
-- DP-1/DP-2, swap the port checks below.
-- Positions MUST be non-negative (Cudiph/cwcwm#49).
cwc.connect_signal("screen::new", function(screen)
    -- Laptop internal panel: BOE NE180QDM-NZ2, max 2560x1600 @ 240Hz
    if screen.name == "eDP-1" then
        screen:set_mode(2560, 1600, 240)
        screen:set_scale(1.0)
        screen:set_transform(enum.output_transform.TRANSFORM_NORMAL)
        screen:set_adaptive_sync(true)
        screen:set_position(0, 600)
    end

    -- Primary external (landscape): SKG H27T27, max 2560x1440 @ 60Hz
    if screen.name == "DP-2" then
        screen:set_mode(2560, 1440, 100) -- actually ~99.965 Hz; cwc ±2 Hz fuzzy matches
        screen:set_scale(1.0)
        screen:set_transform(enum.output_transform.TRANSFORM_NORMAL)
        screen:set_adaptive_sync(false)
        screen:set_position(2560, 600)
        -- screen.allow_tearing = true
    end

    -- Secondary external (portrait, rotated 90°): SKG H27T27, max 2560x1440 @ 60Hz
    -- Rotated → effective logical size 1440x2560.
    if screen.name == "DP-1" then
        screen:set_mode(2560, 1440, 100) -- actually ~99.965 Hz; cwc ±2 Hz fuzzy matches
        screen:set_scale(1.0)
        screen:set_transform(enum.output_transform.TRANSFORM_90)
        screen:set_adaptive_sync(false)
        screen:set_position(5120, 0)
    end

    -- don't apply if restored since it will reset whats manually changed
    if screen.restored then return end

    -- set all tags (including sim tags 10-12) to master/stack mode by default
    for i = 1, 12 do
        tag.layout_mode(i, enum.layout_mode.MASTER, screen)
    end

end)

-- cwc.connect_signal("screen::destroy", function(screen)
--     --- here screen.clients is equivalent as screen:get_clients()
--     local cmd = string.format(
--         'notify-send "Screen removed" "Screen %s [%s] with %s clients attached"', screen.name,
--         screen.description or "-", #screen.clients)
--     cwc.spawn_with_shell(cmd)
-- end)

--------------------------- ROS SIMULATION TAGS ----------------------------
-- Ephemeral tags for Gazebo, RViz and Foxglove. Gazebo/RViz come from
-- `task gazebo:sim:rviz`; Foxglove is launched on its own.
-- Tags appear when sim windows map and vanish when all sim windows close.

local DEFAULT_MAX_WORKSPACE = 9

local SIM_TAGS = {
    gazebo   = 10,
    rviz     = 11,
    foxglove = 12,
}

local SIM_TAG_LABELS = {
    [10] = "GZ",
    [11] = "RV",
    [12] = "FG",
}

--- Return the sim tag index for a client, or nil if not a sim window.
local function sim_tag_for(client)
    local aid = (client.appid or ""):lower()

    -- check rviz first; its title contains the .rviz config path which
    -- often includes "gazebo" (e.g. ghostfin_gazebo/config/ghostfin.rviz)
    if aid:match("rviz") then
        return SIM_TAGS.rviz
    elseif aid:match("foxglove") then
        return SIM_TAGS.foxglove
    elseif aid:match("gz") or aid:match("gazebo") then
        return SIM_TAGS.gazebo
    end
end

--- Shrink max_general_workspace to hide empty sim tags.
local function shrink_sim_tags(screen, unmapping_client)
    local max_needed = DEFAULT_MAX_WORKSPACE
    for _, tidx in pairs(SIM_TAGS) do
        for _, c in ipairs(screen:get_clients(false)) do
            if c ~= unmapping_client and c.workspace == tidx then
                max_needed = math.max(max_needed, tidx)
                break
            end
        end
    end
    screen.max_general_workspace = max_needed
end

------------------------ CLIENT BEHAVIOR -----------------------------
crules.add_client_rule {
    where = { appid = "pcmanfm" },
    set = { floating = true },
    run = function(client)
        client:center()
    end,
}

crules.add_client_rule {
    where = { appid = "rofi" },
    set = { floating = true },
    run = function(client)
        client:center()
    end,
}

cwc.connect_signal("client::map", function(client)
    -- unmanaged client is a popup/tooltip client in xwayland so lets skip it.
    if client.unmanaged then return end

    -- ROS sim windows → ephemeral tags. Park them on the sim tag without
    -- yanking the user's view away — surface them via MOD+0 when wanted.
    local sim_tag = sim_tag_for(client)
    if sim_tag then
        local screen = client.screen
        if screen.max_general_workspace < sim_tag then
            screen.max_general_workspace = sim_tag
        end
        local t = screen:get_tag(sim_tag)
        t.label = SIM_TAG_LABELS[sim_tag] or tostring(sim_tag)
        t.layout_mode = enum.layout_mode.MASTER
        client:move_to_tag(sim_tag)
        return
    end

    -- float-term: force float for custom command kitty windows
    if client.appid == "float-term" then
        client.floating = true
        client:center()
    end

    -- center the client from the screen workarea if its floating or in floating layout.
    if client.floating then client:center() end

    -- don't pass focus when the focused client is fullscreen but allow if the parent is the focused
    -- one. Useful when gaming where an app may restart itself and steal focus.
    local focused = cwc.client.focused()
    if focused and focused.fullscreen and client.parent ~= focused then
        client:lower()
        return
    end

    client:raise()
    client:focus()

    --[[ you could use the rules approach above or do it imperative way like so.
    -- Both approach is equivalent.

    -- It'll move any firefox app to the workspace 2 and maximize it also we moving to tag 2.
    if client.appid == "firefox" then
        client:move_to_tag(2)
        client.screen.active_workspace = 2
    end

    if client.appid:match("pcmanfm") then
        client.floating = true
        client:center()
    end
    --]]
end)

cwc.connect_signal("client::unmap", function(client)
    if client.unmanaged then return end

    -- clean up ephemeral sim tags when a sim window closes
    -- defer shrink so dwl-ipc broadcasts the empty tag state before
    -- max_general_workspace is reduced (otherwise waybar never sees the update)
    local sim_tag = sim_tag_for(client)
    if sim_tag then
        local screen = client.screen
        local viewing_this = screen.active_workspace == sim_tag

        cwc.timer.delayed_call(function()
            shrink_sim_tags(screen, client)

            -- if we were viewing the now-empty tag, jump to the closest regular tag
            if viewing_this and screen.max_general_workspace < sim_tag then
                tag.history.restore(screen, 1)
                if screen.active_workspace > DEFAULT_MAX_WORKSPACE then
                    screen.active_workspace = DEFAULT_MAX_WORKSPACE
                end
            end
        end)
    end

    -- exit when the unmapped client is not the focused client.
    if client ~= cwc.client.focused() then return end

    -- if the client container has more than one client then we focus just below the unmapped
    -- client
    local cont_stack = client.container.client_stack
    if #cont_stack > 1 then
        cont_stack[2]:focus()
    else
        -- get the focus stack (first item is the newest) and we shift focus to the second newest
        -- since first one is about to be unmapped from the screen.
        local latest_focus_after = client.screen:get_focus_stack(true)[2]
        if latest_focus_after then latest_focus_after:focus() end
    end
end)

cwc.connect_signal("client::focus", function(client)
    -- by default when a client got focus it's not raised so we raise it.
    -- should've been hardcoded to the compositor since that's the intuitive behavior
    -- but it's nice to have option I guess.
    client:raise()
end)

-- sloppic focus only in tiled client
cwc.connect_signal("client::mouse_enter", function(c)
    local focused = cwc.client.focused()
    if focused and focused.floating then return end

    c:focus()
end)

cwc.connect_signal("container::insert", function(cont, client)
    -- reset mark after first insertion in case forgot to toggle off mark
    cwc.container.reset_mark()

    -- focus to the newly inserted client
    client:focus()
end)

cwc.connect_signal("screen::mouse_enter", function(s)
    s:focus()
end)
