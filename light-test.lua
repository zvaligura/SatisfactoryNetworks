-- light-test.lua
-- Simple test that blinks an indicator module on a Large Control Panel

local PANEL_CLASS = classes.LargeControlPanel

-- Change these if your indicator is in a different slot
local MODULE_X = 0
local MODULE_Y = 0
local MODULE_PANEL_INDEX = 0   -- Large Control Panel uses 0 as the panel index

local function log(msg)
    print("[light-test] " .. msg)
end

local function getPanel()
    local ids = component.findComponent(PANEL_CLASS)
    if not ids or #ids == 0 then
        log("No LargeControlPanel found on the network")
        return nil
    end

    if #ids > 1 then
        log("Multiple panels found, using the first one")
    end

    return component.proxy(ids[1])
end

local function getIndicator(panel)
    local m = panel:getModule(MODULE_X, MODULE_Y, MODULE_PANEL_INDEX)
    if not m then
        log("No module at " .. MODULE_X .. ", " .. MODULE_Y .. ", " .. MODULE_PANEL_INDEX)
        return nil
    end

    if not m.setColor then
        log("Module at that slot has no setColor function")
        return nil
    end

    return m
end

local function setOff(ind)
    ind:setColor(0, 0, 0, 0)
end

local function setOn(ind)
    -- Green, bright
    ind:setColor(0, 1, 0, 10)
end

local function blink(ind, times)
    times = times or 5

    -- If the event module is missing, just turn it on once
    if not event or not event.pull then
        log("event.pull not available, turning indicator on solid instead")
        setOn(ind)
        return
    end

    for i = 1, times do
        setOn(ind)
        -- This assumes event.pull supports a timeout.
        -- If your version does not, change event.pull(0.5) to plain event.pull().
        event.pull(0.5)
        setOff(ind)
        event.pull(0.5)
    end
end

local function main()
    log("light-test starting")

    local panel = getPanel()
    if not panel then
        computer.beep(0.2)
        return
    end

    local ind = getIndicator(panel)
    if not ind then
        computer.beep(0.4)
        return
    end

    computer.beep(1.0)
    log("Blinking indicator")
    blink(ind, 6)

    setOn(ind)
    log("Done, indicator left on")
end

main()
