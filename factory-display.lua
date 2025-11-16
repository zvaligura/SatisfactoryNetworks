-- factory-display.lua
-- Discover all Manufacturer buildings and render a summary on "Video Wall".
-- Auto refresh every 60s and manual refresh via a panel button.

------------------------------------------------------
-- CONFIG
------------------------------------------------------

-- Large Screen nick
local SCREEN_NICK = "Video Wall Left"

-- Optional control panel nick + button for manual refresh
-- If you do not have this yet, set PANEL_NICK = "".
local PANEL_NICK  = "Control Room Left 1"  -- or "" to disable

-- Button position on that panel (Large Vertical Control Panel)
local BTN_X            = 1
local BTN_Y            = 9
local BTN_PANEL_INDEX  = 0     -- 0/1/2 for vertical panel

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

-- Get a string like "2025-11-16T02:14:32" or nil if magicTime is missing
local function get_time_string()
    if not computer.magicTime then
        return nil
    end
    local ok, unix, culture, iso = pcall(computer.magicTime)
    if not ok then
        return nil
    end
    return iso or culture or tostring(unix)
end

------------------------------------------------------
-- SCAN MANUFACTURERS
------------------------------------------------------

local function scan_manufacturers()
    -- Manufacturer is the base for all recipe using machines
    local ids = component.findComponent(classes.Manufacturer)
    local manufacturers = component.proxy(ids or {})

    local stats = {}   -- stats[buildingType][recipeName] = count; plus __total
    local total = 0

    for _, m in ipairs(manufacturers) do
        -- Building type
        local t = m:getType()
        local buildingType = (t and t.internalName) or "UnknownBuilding"

        -- Current recipe
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
    -- GPU T1
    local gpu = computer.getPCIDevices(classes.GPUT1)[1]
    if not gpu then
        error("No GPU T1 found in this computer")
    end

    local screen

    -- 1) Try to find the nicked Large Screen "Video Wall" on the network
    local ids = component.findComponent(SCREEN_NICK)
    if ids and #ids > 0 then
        screen = component.proxy(ids[1])
        log("Using screen by nick: " .. SCREEN_NICK)
    end

    -- 2) Fallback to computer screen driver
    if not screen then
        local scrs = computer.getPCIDevices(classes.FINComputerScreen)
        if scrs and scrs[1] then
            screen = scrs[1]
            log("Using computer screen driver (no '" .. SCREEN_NICK .. "' found)")
        end
    end

    -- 3) Fallback to first Screen component on network
    if not screen then
        local sids = component.findComponent(classes.Screen)
        if sids and #sids > 0 then
            screen = component.proxy(sids[1])
            log("Using first Screen component (no nicked screen or ScreenDriver found)")
        else
            error("No Screen found at all for GPU to bind")
        end
    end

    gpu:bindScreen(screen)
    local w, h = gpu:getSize()

    -- Clear the screen once at start
    gpu:setBackground(0, 0, 0, 0)
    gpu:fill(0, 0, w, h, " ")
    gpu:flush()

    return gpu, w, h
end

------------------------------------------------------
-- CONTROL PANEL BUTTON SETUP (optional)
------------------------------------------------------

local function init_panel_button()
    if not PANEL_NICK or PANEL_NICK == "" then
        log("No PANEL_NICK configured, button refresh disabled")
        return nil
    end

    local ids = component.findComponent(PANEL_NICK)
    if not ids or #ids == 0 then
        log("No panel found with nick '" .. PANEL_NICK .. "', button refresh disabled")
        return nil
    end

    local panel = component.proxy(ids[1])
    if not panel then
        log("Failed to proxy panel '" .. PANEL_NICK .. "', button refresh disabled")
        return nil
    end

    -- Large Vertical Control Panel: getModule(x, y, panelIndex)
    local button = panel:getModule(BTN_X, BTN_Y, BTN_PANEL_INDEX or 0)

    if not button then
        log("No module at (" .. BTN_X .. "," .. BTN_Y .. "," .. (BTN_PANEL_INDEX or 0)
            .. ") on panel '" .. PANEL_NICK .. "'")
        return nil
    end

    event.listen(button)
    log("Listening for button 'Trigger' on panel '" .. PANEL_NICK .. "'")

    return button
end

------------------------------------------------------
-- RENDER TABLE ON SCREEN
------------------------------------------------------

local function draw_table(gpu, w, h, stats, total, last_time)
    -- Clear every frame so old rows do not linger
    gpu:setBackground(0, 0, 0, 0)
    gpu:fill(0, 0, w, h, " ")

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

    -- Title and last refresh line
    local title = "Factory Overview (" .. SCREEN_NICK .. ")"
    if row < h then
        gpu:setText(0, row, title)
        if last_time then
            local label = "Last: " .. last_time
            local x = w - #label
            if x < #title + 2 then
                x = #title + 2
            end
            if x < w then
                gpu:setText(x, row, label)
            end
        end
    end
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

        -- Per building subtotal row
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
-- REFRESH WRAPPER
------------------------------------------------------

local function refresh(gpu, w, h)
    local stats, total = scan_manufacturers()
    local time_str = get_time_string()
    draw_table(gpu, w, h, stats, total, time_str)
    if time_str then
        log("Display refreshed at " .. time_str)
    else
        log("Display refreshed")
    end
end

------------------------------------------------------
-- MAIN
------------------------------------------------------

local function main()
    log("Starting factory display")

    -- Clean up old listeners once
    event.ignoreAll()
    event.clear()

    local gpu, w, h = init_gpu_screen()
    log("Screen '" .. SCREEN_NICK .. "' size: " .. w .. "x" .. h)

    local button = init_panel_button()

    -- First draw
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
            -- Timeout hit, periodic refresh
            refresh(gpu, w, h)
            lastScan = computer.uptime and computer.uptime() or lastScan
        else
            -- Got some event
            if button and sender == button and ev == "Trigger" then
                log("Refresh button pressed, refreshing now")
                refresh(gpu, w, h)
                lastScan = computer.uptime and computer.uptime() or lastScan
            end
        end
    end
end

main()
