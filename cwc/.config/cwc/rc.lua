pcall(require, "luarocks.loader")

local gears = require("gears")
local enum = require("cuteful.enum")
local tag = require("cuteful.tag")
local impl = require("impl")
local config = require("config")
local crules = require("cuteful.rules")

local cwc = cwc

local conf = require("conf")

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

if cwc.is_startup() then
    gears.protected_call(require, "oneshot")
end

gears.protected_call(require, "keybind")
gears.protected_call(require, "mousebind")

gears.protected_call(require, "battery")

impl.use_core()

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

cwc.connect_signal("screen::new", function(screen)
    if screen.name == "eDP-1" then
        screen:set_mode(2560, 1600, 240)
        screen:set_scale(1.0)
        screen:set_transform(enum.output_transform.TRANSFORM_NORMAL)
        screen:set_adaptive_sync(true)
        screen:set_position(0, 600)
    end

    if screen.name == "DP-2" then
        screen:set_mode(2560, 1440, 100)
        screen:set_scale(1.0)
        screen:set_transform(enum.output_transform.TRANSFORM_NORMAL)
        screen:set_adaptive_sync(false)
        screen:set_position(2560, 600)
    end

    if screen.name == "DP-1" then
        screen:set_mode(2560, 1440, 100)
        screen:set_scale(1.0)
        screen:set_transform(enum.output_transform.TRANSFORM_90)
        screen:set_adaptive_sync(false)
        screen:set_position(5120, 0)
    end

    if screen.restored then return end

    for i = 1, 12 do
        tag.layout_mode(i, enum.layout_mode.MASTER, screen)
    end

end)

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

local function sim_tag_for(client)
    local aid = (client.appid or ""):lower()

    if aid:match("rviz") then
        return SIM_TAGS.rviz
    elseif aid:match("foxglove") then
        return SIM_TAGS.foxglove
    elseif aid:match("gz") or aid:match("gazebo") then
        return SIM_TAGS.gazebo
    end
end

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
    if client.unmanaged then return end

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

    if client.appid == "float-term" then
        client.floating = true
        client:center()
    end

    if client.floating then client:center() end

    local focused = cwc.client.focused()
    if focused and focused.fullscreen and client.parent ~= focused then
        client:lower()
        return
    end

    client:raise()
    client:focus()

end)

cwc.connect_signal("client::unmap", function(client)
    if client.unmanaged then return end

    local sim_tag = sim_tag_for(client)
    if sim_tag then
        local screen = client.screen
        local viewing_this = screen.active_workspace == sim_tag

        cwc.timer.delayed_call(function()
            shrink_sim_tags(screen, client)

            if viewing_this and screen.max_general_workspace < sim_tag then
                tag.history.restore(screen, 1)
                if screen.active_workspace > DEFAULT_MAX_WORKSPACE then
                    screen.active_workspace = DEFAULT_MAX_WORKSPACE
                end
            end
        end)
    end

    if client ~= cwc.client.focused() then return end

    local cont_stack = client.container.client_stack
    if #cont_stack > 1 then
        cont_stack[2]:focus()
    else
        local latest_focus_after = client.screen:get_focus_stack(true)[2]
        if latest_focus_after then latest_focus_after:focus() end
    end
end)

cwc.connect_signal("client::focus", function(client)
    client:raise()
end)

cwc.connect_signal("client::mouse_enter", function(c)
    local focused = cwc.client.focused()
    if focused and focused.floating then return end

    c:focus()
end)

cwc.connect_signal("container::insert", function(cont, client)
    cwc.container.reset_mark()

    client:focus()
end)

cwc.connect_signal("screen::mouse_enter", function(s)
    s:focus()
end)
