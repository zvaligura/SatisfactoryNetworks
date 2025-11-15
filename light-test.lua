-- light-test.lua
-- Blink a single indicator-like module on a Large Control Panel

-- Slot of the indicator module on the panel.
-- For a Large Control Panel, panel index is usually 0.
local MODULE_X           = 0
local MODULE_Y           = 0
local MODULE_PANEL_INDEX = 0

local function log(msg)
    print("[light-test] " .. msg)
end

log("light-test starting")

-- Get first LargeControlPanel on the network
local panels = component.proxy(component.findComponent(classes.LargeControlPanel))
if not panels or #panels == 0 then
    log("No LargeControlPanel found on the network")
    computer.beep(0.3)
    return
end

local panel = panels[1]
log("Using panel: " .. tostring(panel))

-- Use Modular Control Panel API: getModule(x, y, panelIndex)
local indicator = panel:getModule(MODULE_X, MODULE_Y, MODULE_PANEL_INDEX)
if not indicator then
    log("No module at " .. MODULE_X .. ", " .. MODULE_Y .. ", " .. MODULE_PANEL_INDEX)
    computer.beep(0.3)
    return
end

if not indicator.setColor then
    log("Module at that slot has no setColor; is it an Indicator or Button?")
    computer.beep(0.3)
    return
end

log("Found indicator-like module at slot")

local function setOn()
    -- bright green
    indicator:setColor(0, 1, 0, 5)
end

local function setOff()
    indicator:setColor(0, 0, 0, 0)
end

local function blink_forever(interval)
    interval = interval or 0.5

    while true do
        setOn()
        event.pull(interval)
        setOff()
        event.pull(interval)
    end
end

log("Starting infinite blink")
blink_forever(0.3)
