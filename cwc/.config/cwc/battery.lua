-- battery.lua — laptop low-battery nagger
--
-- polls /sys/class/power_supply/BAT0 on a slow cadence. escalates:
--   • below WARN_PCT (10%)  → urgent mako notification
--                           + subtle static scanlines overlay
--   • below CRIT_PCT  (5%)  → critical mako (sticky)
--                           + denser scanlines with VCR tracking bar scroll
--                           + pulsing red edge flash overlay
--
-- overlays are idempotent — we pkill by name before spawning a fresh one
-- so reload/flap doesn't leave duplicates.

local cwc = cwc

local M = {}

local BAT = "/sys/class/power_supply/BAT0"
local POLL_SECONDS = 30
local WARN_PCT = 10
local CRIT_PCT = 5

local HOME = os.getenv("HOME")
local SCANLINES_SCRIPT = HOME .. "/.config/cwc/scripts/scanlines.py"
local SCANLINES_MATCH = "scanlines.py"
local FLASH_SCRIPT = HOME .. "/.config/cwc/scripts/battery-edge-flash.py"
local FLASH_MATCH = "battery-edge-flash.py"

-- scanline tiers — alpha/scroll tuned per severity
local SCAN_WARN = "--alpha 0.22 --step 3"
local SCAN_CRIT = "--alpha 0.55 --step 2 --scroll 42 --hum-bar --glitch-roll"

-- "ok" | "charging" | "warn" | "crit"
local last_state = "ok"

local function read_first_line(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local line = f:read("*l")
    f:close()
    return line
end

local function read_battery()
    local cap = tonumber(read_first_line(BAT .. "/capacity"))
    local status = read_first_line(BAT .. "/status") or ""
    return cap, status
end

local function shq(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function notify(summary, body, urgency, timeout_ms)
    local cmd = string.format(
        "notify-send -u %s -t %d -a battery-monitor -i battery-caution %s %s",
        urgency, timeout_ms, shq(summary), shq(body))
    cwc.spawn_with_shell(cmd)
end

-- kill any existing overlay of a given script by name, optionally respawn
local function respawn(match, script, args)
    if args then
        cwc.spawn_with_shell(string.format(
            "pkill -f %s; %s %s >/dev/null 2>&1 &",
            shq(match), shq(script), args))
    else
        cwc.spawn_with_shell(string.format("pkill -f %s", shq(match)))
    end
end

local function set_scanlines(tier)
    if tier == "warn" then
        respawn(SCANLINES_MATCH, SCANLINES_SCRIPT, SCAN_WARN)
    elseif tier == "crit" then
        respawn(SCANLINES_MATCH, SCANLINES_SCRIPT, SCAN_CRIT)
    else
        respawn(SCANLINES_MATCH, nil, nil) -- kill only
    end
end

local function set_flash(on)
    if on then
        respawn(FLASH_MATCH, FLASH_SCRIPT, "")
    else
        respawn(FLASH_MATCH, nil, nil)
    end
end

local function poll()
    local pct, status = read_battery()
    if not pct then return end

    local discharging = status == "Discharging"

    -- plugged in or full → tear everything down
    if not discharging then
        if last_state ~= "charging" and last_state ~= "ok" then
            set_scanlines("off")
            set_flash(false)
        end
        last_state = "charging"
        return
    end

    if pct <= CRIT_PCT then
        if last_state ~= "crit" then
            set_scanlines("crit")
            set_flash(true)
            notify("CRITICAL //: " .. pct .. "%",
                "wallpaper bleeding — plug in NOW or eat the shutdown",
                "critical", 0)
            last_state = "crit"
        end
    elseif pct <= WARN_PCT then
        if last_state ~= "warn" then
            set_scanlines("warn")
            set_flash(false)
            notify("LOW BATTERY //: " .. pct .. "%",
                "the void is hungry. plug in before i go dark.",
                "critical", 15000)
            last_state = "warn"
        end
    else
        if last_state == "warn" or last_state == "crit" then
            set_scanlines("off")
            set_flash(false)
        end
        last_state = "ok"
    end
end

-- initial poll so a session starting already-low gets flagged immediately
poll()

cwc.timer.new(POLL_SECONDS, poll)

return M
