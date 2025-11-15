-- factory-display.lua
-- Discover all Manufacturer buildings and render a summary on a screen.
-- Auto refresh every 60s, and on button press on a control panel.

------------------------------------------------------
-- CONFIG
------------------------------------------------------

-- Screen nick (your large display)
local SCREEN_NICK = "Video Wall"

-- Control panel nick (the panel that has your refresh button)
local PANEL_NICK  = "Factory Overview Panel"   -- change to your panel's nick

-- Button position on that panel
-- For a Large Control Panel, leave BTN_PANEL_INDEX as nil and use (x, y)
-- For a Large Vertical Control Panel, set BTN_PANEL_INDEX = 0, 1 or 2
local BTN_X            = 0
local BTN_Y            = 0
local BTN_PANEL_INDEX  = nil     -- nil for Large Control Panel, 0/1/2 for Vertical

-- Auto refresh interval in seconds
local REFRESH_INTERVAL = 60

-- Optional: cap the max number of data rows printed
local MAX_ROWS = 200

------------------------------------------------------
-- SMALL HELPERS
------------------------------------------------------

local function padRight(s, n)
    s = tostring(s)
    if #s > n then
        return s:sub(1, n)
    end
    return s .. string.rep(" ", n - #s)
end

local function padLeft(s, n)
    s = tostring(s)
    if #s > n then
        return s:sub(#s - n + 1)
    end
    return string.rep(" ", n - #s) .. s
end

local function log(msg)
    print("[factory-display] " .. msg)
end

------------------------------------------------------
-- SCAN MANUFACTURERS
------------------------------------------------------

local function scan_manufacturers()
    -- Manufacturer is the base for all recipe-using machines (constructors, etc)
    local ids = component.findComponent(classes.Manufacturer)
    local manufacturers = component.proxy(ids or {})

    local stats = {}   -- stats[buildingType][recipeName] = count; plus __total
    local total = 0

    for _, m in ipairs(manufacturers) do
        -- Building type via reflection getType().internalName
        local t = m:getType()
        local buildingType = (t and t.internalName) or "UnknownBuilding"

        -- Current recipe via Manufacturer.getRecipe().internalName
        local recipeClass = m:getRecipe()
        local recipeName = (recipeClass and recipeClass.internalName) or "<no recipe>"

        if not stats[buildingType] then
            stats[buildingType] = { __total = 0 }
        end

        local b = stats[buildingType]
        b[recipeName] = (b[recipeName] or 0) + 1
        b.__total = b.__total + 1

        total = total + 1
    end

    return stats, total
end

------------------------------------------------------
-- GPU + SCREEN SETUP (bind to "Video Wall")
------------------------------------------------------

local function init_gpu_screen()
    -- get first GPU T1 from PCI devices
    local gpu = computer.getPCIDevices(classes.GPUT1)[1]
    if not gpu then
        error("No GPU T1 found in this computer")
    end

    local screen

    -- 1) Try to find the nicked screen "Video Wall" on the network
    local ids = { component.findComponent(SCREEN_NICK) }
    if #ids > 0 then
        screen = component.proxy(ids[1])
        log("Using screen by nick: " .. SCREEN_NICK)
    end

    -- 2) If that fails, fall back to computer screen driver
    if not screen then
        local pciScreen = computer.getPCIDevices(classes.FINComputerScreen)[1]
        if pciScreen then
            screen = pciScreen
            log("Using computer screen driver (no '" .. SCREEN_NICK .. "' found)")
        end
    end

    -- 3) If still no screen, fall back to first Screen component on network
    if not screen then
        local compId = component.findComponent(classes.Screen)[1]
        if not compId then
            error("No Screen found at all (no '" .. SCREEN_NICK .. "', no ScreenDriver, no Large Screen)")
        end
        screen = component.proxy(compId)
        log("Using first Screen component (no nicked screen or ScreenDriver found)")
    end

    -- Bind GPU to the chosen screen
    gpu:bindScreen(screen)
    local w, h = gpu:getSize()

    -- Clear the screen
    gpu:setBackground(0, 0, 0, 0)
    gpu:fill(0, 0, w, h, " ")
    gpu:flush()

    return gpu, w, h
end

------------------------------------------------------
-- CONTROL PANEL BUTTON SETUP
------------------------------------------------------

local function init_panel_button()
    if not PANEL_NICK or PANEL_NICK == "" then
        log("No PANEL_NICK configured, button refresh disabled")
        return nil, nil
    end

    local ids = { component.findComponent(PANEL_NICK) }
    if #ids == 0 then
        log("No panel found with nick '" .. PANEL_NICK .. "', button refresh disabled")
        return nil, nil
    end

    local panel = component.proxy(ids[1])
    if not panel then
        log("Failed to proxy panel '" .. PANEL_NICK .. "', button refresh disabled")
        return nil, nil
    end

    local button
    if BTN_PANEL_INDEX == nil then
        -- Large Control Panel: getModule(x, y)
        button = panel:getModule(BTN_X, BTN_Y)
    else
        -- Large Vertical Control Panel: getModule(x, y, panelIndex)
        button = panel:getModule(BTN_X, BTN_Y, BTN_PANEL_INDEX)
    end

    if not button then
        log("No module at (" .. BTN_X .. "," .. BTN_Y
            .. (BTN_PANEL_INDEX and ("," .. BTN_PANEL_INDEX) or "")
            .. ") on panel '" .. PANEL_NICK .. "'")
        return panel, nil
    end

    -- Clear any old listeners and then listen to this button
    if event.ignoreAll then event.ignoreAll() end
    if event.clear then event.clear() end

    event.listen(button)
    log("Listening for button 'Trigger' on panel '" .. PANEL_NICK .. "'")

    return panel, button
end

------------------------------------------------------
-- RENDER TABLE ON SCREEN
------------------------------------------------------

local function draw_table(gpu, w, h, stats, total)
    -- Column layout
    local colBuildingWidth = 18
    local colRecipeWidth   = 40
    local colCountWidth    = 6

    local function drawLine(y, text)
        if y >= h then
            return false
        end
        if #text > w then
            text = text:sub(1, w)
        end
        gpu:setText(0, y, text)
        return true
    end

    local row = 0

    -- Title
    drawLine(row, "Factory Overview (" .. SCREEN_NICK .. ")")
    row = row + 2

    -- Header
    local header =
        padRight("Building", colBuildingWidth) .. " " ..
        padRight("Recipe",   colRecipeWidth)   .. " " ..
        padLeft("Count",     colCountWidth)
    drawLine(row, header)
    row = row + 1

    -- Separator
    local sep = string.rep("-", math.min(w, colBuildingWidth + 1 + colRecipeWidth + 1 + colCountWidth))
    drawLine(row, sep)
    row = row + 1

    -- Sort building types
    local buildingKeys = {}
    for buildingType in pairs(stats) do
        table.insert(buildingKeys, buildingType)
    end
    table.sort(buildingKeys)

    local dataRows = 0

    for _, buildingType in ipairs(buildingKeys) do
        local recipes = stats[buildingType]

        -- Sort recipe names (excluding __total)
        local recipeKeys = {}
        for recipeName in pairs(recipes) do
            if recipeName ~= "__total" then
                table.insert(recipeKeys, recipeName)
            end
        end
        table.sort(recipeKeys)

        for _, recipeName in ipairs(recipeKeys) do
            dataRows = dataRows + 1
            if dataRows > MAX_ROWS then break end

            local count = recipes[recipeName]

            local line =
                padRight(buildingType, colBuildingWidth) .. " " ..
                padRight(recipeName,   colRecipeWidth)   .. " " ..
                padLeft(count,         colCountWidth)

            if not drawLine(row, line) then
                break
            end
            row = row + 1
        end

        if dataRows > MAX_ROWS or row >= h then
            break
        end

        -- Per-building subtotal row
        local subtotal =
            padRight(buildingType, colBuildingWidth) .. " " ..
            padRight("<ALL>",      colRecipeWidth)   .. " " ..
            padLeft(recipes.__total or 0, colCountWidth)

        if not drawLine(row, subtotal) then
            break
        end
        row = row + 1

        -- Blank line between building types
        if row < h then
            row = row + 1
        end
    end

    -- Footer
    if row + 2 < h then
        row = row + 1
        drawLine(row, sep)
        row = row + 1
        drawLine(row, "Total Manufacturers: " .. tostring(total))
    end

    gpu:flush()
end

------------------------------------------------------
-- MAIN LOOP
------------------------------------------------------

local function refresh(gpu, w, h)
    local stats, total = scan_manufacturers()
    draw_table(gpu, w, h, stats, total)
    log("Display refreshed")
end

local function main()
    log("Starting factory display")

    local gpu, w, h = init_gpu_screen()
    log("Screen '" .. SCREEN_NICK .. "' size: " .. w .. "x" .. h)

    local _, button = init_panel_button()

    -- Initial draw
    refresh(gpu, w, h)
    local lastScan = computer.uptime and computer.uptime() or 0

    while true do
        local now = computer.uptime and computer.uptime() or lastScan
        local elapsed = now - lastScan
        local timeout = REFRESH_INTERVAL - elapsed
        if timeout < 0 then timeout = 0 end

        -- Wait for either a signal or the timeout
        local ev, sender = event.pull(timeout)

        if not ev then
            -- Timeout hit, do periodic refresh
            refresh(gpu, w, h)
            lastScan = computer.uptime and computer.uptime() or lastScan
        else
            -- Got some event
            if button and sender == button and ev == "Trigger" then
                log("Button Trigger pressed, refreshing now")
                refresh(gpu, w, h)
                lastScan = computer.uptime and computer.uptime() or lastScan
            end
        end
    end
end

main()