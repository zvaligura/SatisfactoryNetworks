----------------------------------------------------------------
-- control-panel.lua
-- Template for modular control panels (Large Vertical Control Panel).
-- Three example panels:
--   Right Lower 1
--   Right Lower 2
--   Right Lower 3
--
-- Each panel section has:
--   Button
--   Lever
--   Potentiometer
--   Text display
--
-- Copy a whole panel section, rename the nick, and change positions
-- as needed.
----------------------------------------------------------------

-----------------------------
-- shared helpers
-----------------------------

local function dbg(...)
    print("[panel]", ...)
end

local function safe_set_text(mod, text)
    if not mod then return end
    local ok = pcall(function()
        if type(mod.setText) == "function" then
            mod:setText(text)
        else
            mod.text = text
        end
    end)
    if not ok then
        dbg("failed to set text on module")
    end
end

local function safe_set_color(mod, r, g, b, emit)
    if not mod or type(mod.setColor) ~= "function" then return end
    local ok = pcall(function()
        mod:setColor(r, g, b, emit or 1.0)
    end)
    if not ok then
        dbg("failed to set color on module")
    end
end

-- list of per panel event handlers
local panel_handlers = {}

-- clean old listeners once
event.ignoreAll()
event.clear()

----------------------------------------------------------------
--=== PANEL: Right Lower 1 =====================================
----------------------------------------------------------------

-- panel nick for this section
local P1_NICK = "Right Lower 1"

-- get the panel
local p1_ids = component.findComponent(P1_NICK)
local p1 = p1_ids and p1_ids[1] and component.proxy(p1_ids[1]) or nil

if p1 then
    dbg("P1: found panel nick", P1_NICK)
else
    dbg("P1: no panel with nick", P1_NICK)
end

-- P1 BUTTON ------------------------------------------
-- component: button
-- purpose: simple toggle, changes its own color
-- slot: x=0, y=0, panelIndex=0
local P1_BUTTON_POS = { x = 0, y = 0, panelIndex = 0 }
local p1_button = p1 and p1:getModule(P1_BUTTON_POS.x, P1_BUTTON_POS.y, P1_BUTTON_POS.panelIndex)
local p1_button_state = false

if p1_button then
    event.listen(p1_button)
    safe_set_color(p1_button, 0.2, 0.2, 0.2, 1)
    dbg("P1: button at (0,0,0)")
end

-- P1 LEVER -------------------------------------------
-- component: lever
-- purpose: simple on/off, mirrored into text display
-- slot: x=2, y=0, panelIndex=0
local P1_LEVER_POS = { x = 2, y = 0, panelIndex = 0 }
local p1_lever = p1 and p1:getModule(P1_LEVER_POS.x, P1_LEVER_POS.y, P1_LEVER_POS.panelIndex)

if p1_lever then
    event.listen(p1_lever)
    dbg("P1: lever at (2,0,0)")
end

-- P1 POTENTIOMETER -----------------------------------
-- component: potentiometer
-- purpose: show how to react to events, update numeric value
-- slot: x=4, y=0, panelIndex=0
local P1_POT_POS = { x = 4, y = 0, panelIndex = 0 }
local p1_pot = p1 and p1:getModule(P1_POT_POS.x, P1_POT_POS.y, P1_POT_POS.panelIndex)
local p1_pot_value = 0

if p1_pot then
    event.listen(p1_pot)
    dbg("P1: pot at (4,0,0)")
end

-- P1 TEXT DISPLAY ------------------------------------
-- component: text display
-- purpose: show current state text
-- slot: x=0, y=2, panelIndex=0
local P1_TEXT_POS = { x = 0, y = 2, panelIndex = 0 }
local p1_text = p1 and p1:getModule(P1_TEXT_POS.x, P1_TEXT_POS.y, P1_TEXT_POS.panelIndex)

if p1_text then
    safe_set_text(p1_text, "Right Lower 1")
    dbg("P1: text display at (0,2,0)")
end

-- P1 EVENT HANDLER -----------------------------------
local function panel1_handle(evName, src, a1, a2, a3, a4)
    -- button trigger
    if p1_button and src == p1_button and evName == "Trigger" then
        p1_button_state = not p1_button_state
        dbg("P1: button Trigger, state =", p1_button_state)
        if p1_button_state then
            safe_set_color(p1_button, 0, 1, 0, 8)
        else
            safe_set_color(p1_button, 0.2, 0.2, 0.2, 1)
        end
        if p1_text then
            safe_set_text(p1_text, p1_button_state and "Button ON" or "Button OFF")
        end
    end

    -- lever change
    if p1_lever and src == p1_lever and evName == "ChangeState" then
        local s = p1_lever.state
        dbg("P1: lever ChangeState", s)
        if p1_text then
            safe_set_text(p1_text, s and "Lever ON" or "Lever OFF")
        end
    end

    -- pot any event, simple value and print
    if p1_pot and src == p1_pot then
        dbg("P1: pot event", evName, a1, a2, a3, a4)
        -- example logic: if a1 is boolean, count up/down
        if type(a1) == "boolean" then
            if a1 then
                p1_pot_value = p1_pot_value + 1
            else
                p1_pot_value = p1_pot_value - 1
            end
        end
        if p1_text then
            safe_set_text(p1_text, "Pot value " .. tostring(p1_pot_value))
        end
    end
end

table.insert(panel_handlers, panel1_handle)

----------------------------------------------------------------
--=== PANEL: Right Lower 2 =====================================
----------------------------------------------------------------

-- panel nick for this section
local P2_NICK = "Right Lower 2"

local p2_ids = component.findComponent(P2_NICK)
local p2 = p2_ids and p2_ids[1] and component.proxy(p2_ids[1]) or nil

if p2 then
    dbg("P2: found panel nick", P2_NICK)
else
    dbg("P2: no panel with nick", P2_NICK)
end

-- P2 BUTTON ------------------------------------------
-- example: second button, different slot
-- slot: x=0, y=0, panelIndex=0
local P2_BUTTON_POS = { x = 0, y = 0, panelIndex = 0 }
local p2_button = p2 and p2:getModule(P2_BUTTON_POS.x, P2_BUTTON_POS.y, P2_BUTTON_POS.panelIndex)
local p2_button_state = false

if p2_button then
    event.listen(p2_button)
    safe_set_color(p2_button, 0.2, 0.2, 0.2, 1)
    dbg("P2: button at (0,0,0)")
end

-- P2 TEXT DISPLAY ------------------------------------
-- slot: x=1, y=0, panelIndex=0
local P2_TEXT_POS = { x = 1, y = 0, panelIndex = 0 }
local p2_text = p2 and p2:getModule(P2_TEXT_POS.x, P2_TEXT_POS.y, P2_TEXT_POS.panelIndex)

if p2_text then
    safe_set_text(p2_text, "Right Lower 2")
    dbg("P2: text display at (1,0,0)")
end

-- P2 EVENT HANDLER -----------------------------------
local function panel2_handle(evName, src, a1, a2, a3, a4)
    if p2_button and src == p2_button and evName == "Trigger" then
        p2_button_state = not p2_button_state
        dbg("P2: button Trigger, state =", p2_button_state)
        if p2_button_state then
            safe_set_color(p2_button, 1, 0.5, 0, 8)  -- orange
        else
            safe_set_color(p2_button, 0.2, 0.2, 0.2, 1)
        end
        if p2_text then
            safe_set_text(p2_text, p2_button_state and "Factory RUN" or "Factory STOP")
        end
    end
end

table.insert(panel_handlers, panel2_handle)

----------------------------------------------------------------
--=== PANEL: Right Lower 3 =====================================
----------------------------------------------------------------

-- panel nick for this section
local P3_NICK = "Right Lower 3"

local p3_ids = component.findComponent(P3_NICK)
local p3 = p3_ids and p3_ids[1] and component.proxy(p3_ids[1]) or nil

if p3 then
    dbg("P3: found panel nick", P3_NICK)
else
    dbg("P3: no panel with nick", P3_NICK)
end

-- P3 BUTTON ------------------------------------------
-- slot: x=0, y=0, panelIndex=0
local P3_BUTTON_POS = { x = 0, y = 0, panelIndex = 0 }
local p3_button = p3 and p3:getModule(P3_BUTTON_POS.x, P3_BUTTON_POS.y, P3_BUTTON_POS.panelIndex)
local p3_button_state = false

if p3_button then
    event.listen(p3_button)
    safe_set_color(p3_button, 0.2, 0.2, 0.2, 1)
    dbg("P3: button at (0,0,0)")
end

-- P3 LEVER -------------------------------------------
-- slot: x=1, y=0, panelIndex=0
local P3_LEVER_POS = { x = 1, y = 0, panelIndex = 0 }
local p3_lever = p3 and p3:getModule(P3_LEVER_POS.x, P3_LEVER_POS.y, P3_LEVER_POS.panelIndex)

if p3_lever then
    event.listen(p3_lever)
    dbg("P3: lever at (1,0,0)")
end

-- P3 TEXT DISPLAY ------------------------------------
-- slot: x=2, y=0, panelIndex=0
local P3_TEXT_POS = { x = 2, y = 0, panelIndex = 0 }
local p3_text = p3 and p3:getModule(P3_TEXT_POS.x, P3_TEXT_POS.y, P3_TEXT_POS.panelIndex)

if p3_text then
    safe_set_text(p3_text, "Right Lower 3")
    dbg("P3: text display at (2,0,0)")
end

-- P3 EVENT HANDLER -----------------------------------
local function panel3_handle(evName, src, a1, a2, a3, a4)
    -- button toggles state text
    if p3_button and src == p3_button and evName == "Trigger" then
        p3_button_state = not p3_button_state
        dbg("P3: button Trigger, state =", p3_button_state)
        if p3_text then
            safe_set_text(p3_text, p3_button_state and "Power ENABLED" or "Power DISABLED")
        end
    end

    -- lever mirrors own state to text
    if p3_lever and src == p3_lever and evName == "ChangeState" then
        local s = p3_lever.state
        dbg("P3: lever ChangeState", s)
        if p3_text then
            safe_set_text(p3_text, s and "Master ON" or "Master OFF")
        end
    end
end

table.insert(panel_handlers, panel3_handle)

----------------------------------------------------------------
-- MAIN EVENT LOOP
----------------------------------------------------------------

dbg("control-panel.lua ready for Right Lower 1/2/3")

while true do
    local evName, src, a1, a2, a3, a4 = event.pull()
    for _, handler in ipairs(panel_handlers) do
        handler(evName, src, a1, a2, a3, a4)
    end
end