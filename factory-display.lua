 log("No panel found with nick '" .. PANEL_NICK .. "', controls disabled")
        return nil, nil
    end

    local panel = component.proxy(ids[1])
    if not panel then
        log("Failed to proxy panel '" .. PANEL_NICK .. "', controls disabled")
        return nil, nil
    end

    local button = panel:getModule(BTN_X, BTN_Y, BTN_PANEL_INDEX or 0)
    if button then
        event.listen(button)
        log("Listening for button 'Trigger' on panel '" .. PANEL_NICK .. "'")
    else
        log("No button at (" .. BTN_X .. "," .. BTN_Y .. "," .. (BTN_PANEL_INDEX or 0)
            .. ") on panel '" .. PANEL_NICK .. "'")
    end

    local pot = nil
    if POT_X and POT_Y then
        pot = panel:getModule(POT_X, POT_Y, POT_PANEL_INDEX or 0)
        if pot then
            log("Potentiometer detected at (" .. POT_X .. "," .. POT_Y .. "," .. (POT_PANEL_INDEX or 0)
                .. ") on panel '" .. PANEL_NICK .. "'")
        else
            log("No potentiometer at (" .. POT_X .. "," .. POT_Y .. "," .. (POT_PANEL_INDEX or 0)
                .. ") on panel '" .. PANEL_NICK .. "'")
        end
    end

    return button, pot
end

-- Read pot value (0..1) and map to seconds, clamped to POT_MIN_SECONDS..POT_MAX_SECONDS
local function read_pot_interval(pot, currentInterval)
    if not pot then
        return currentInterval or REFRESH_INTERVAL_DEFAULT
    end

    local raw
    local ok, val = pcall(function()
        return pot.value
    end)

    if ok and type(val) == "number" then
        raw = val
    else
        -- Couldn't read, keep existing interval
        return currentInterval or REFRESH_INTERVAL_DEFAULT
    end

    if raw < 0 then raw = 0 end
    if raw > 1 then raw = 1 end

    local minS = POT_MIN_SECONDS
    local maxS = POT_MAX_SECONDS

    local seconds = minS + (1 - raw) * (maxS - minS)

    if seconds < POT_MIN_SECONDS then seconds = POT_MIN_SECONDS end
    if seconds > POT_MAX_SECONDS then seconds = POT_MAX_SECONDS end

    return seconds
end

------------------------------------------------------
-- RENDER TABLE ON SCREEN
------------------------------------------------------

local function draw_table(gpu, w, h, stats, totalCount, lastDiscovery, refreshIntervalSeconds, overallEff)
    -- Clear every frame so old rows do not linger
    gpu:setBackground(0, 0, 0, 0)
    gpu:fill(0, 0, w, h, " ")

    -- Column layout
    local colBuildingWidth = 16
    local colRecipeWidth   = 28
    local colCountWidth    = 4
    local colInWidth       = 18
    local colOutWidth      = 18
    local colClkWidth      = 6
    local colEffWidth      = 6

    local totalWidth = colBuildingWidth + 1 +
                       colRecipeWidth   + 1 +
                       colCountWidth    + 1 +
                       colInWidth       + 1 +
                       colOutWidth      + 1 +
                       colClkWidth      + 1 +
                       colEffWidth

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

    -- Title and last discovery line
    local title = "Factory Overview (" .. SCREEN_NICK .. ")"
    if row < h then
        gpu:setText(0, row, title)
        local label = "Last Discovery Ran On " .. (lastDiscovery or "?")
        if refreshIntervalSeconds then
            label = label .. string.format("  (Refresh: %.1fs)", refreshIntervalSeconds)
        end
        local x = w - #label
        if x < #title + 2 then
            x = #title + 2
        end
        if x < w then
            gpu:setText(x, row, label)
        end
    end
    row = row + 2

    -- Header
    local header =
        padRight("Building",            colBuildingWidth) .. " " ..
        padRight("Recipe",              colRecipeWidth)   .. " " ..
        padLeft ("Cnt",                 colCountWidth)    .. " " ..
        padLeft ("Input Live/Max",      colInWidth)       .. " " ..
        padLeft ("Output Live/Max",     colOutWidth)      .. " " ..
        padLeft ("Clk%",                colClkWidth)      .. " " ..
        padLeft ("Eff%",                colEffWidth)
    drawLine(row, header)
    row = row + 1

    -- Separator
    local sep = string.rep("-", math.min(w, totalWidth))
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

        -- Sort recipe names
        local recipeKeys = {}
        for recipeName in pairs(recipes) do
            table.insert(recipeKeys, recipeName)
        end
        table.sort(recipeKeys)

        for _, recipeName in ipairs(recipeKeys) do
            dataRows = dataRows + 1
            if dataRows > MAX_ROWS then break end

            local r = recipes[recipeName]

            local clkAvg = 0
            if r.clkSamples and r.clkSamples > 0 then
                clkAvg = (r.clkSum / r.clkSamples) * 100
            end

            local eff = 0
            if r.outMax and r.outMax > 0 then
                eff = (r.outNow / r.outMax) * 100
            end

            local line =
                padRight(buildingType,                  colBuildingWidth) .. " " ..
                padRight(recipeName,                    colRecipeWidth)   .. " " ..
                padLeft (r.count or 0,                  colCountWidth)    .. " " ..
                padLeft (format_pair(r.inNow,  r.inMax), colInWidth)      .. " " ..
                padLeft (format_pair(r.outNow, r.outMax),colOutWidth)     .. " " ..
                padLeft (string.format("%d", math.floor(clkAvg + 0.5)), colClkWidth) .. " " ..
                padLeft (string.format("%d", math.floor(eff    + 0.5)), colEffWidth)

            if not drawLine(row, line) then
                break
            end
            row = row + 1

            if row >= h then
                break
            end
        end

        if dataRows > MAX_ROWS or row >= h then
            break
        end

        -- Blank line between building types
        if row < h then
            row = row + 1
        end
    end

    -- Footer with global totals
    if row + 2 < h then
        row = row + 1
        drawLine(row, sep)
        row = row + 1

        local effPct = math.floor((overallEff or 0) + 0.5)
        local footer = string.format(
            "Total machines: %d   Overall efficiency: %d%%",
            totalCount or 0,
            effPct
        )
        drawLine(row, footer)
    end

    gpu:flush()
end

------------------------------------------------------
-- MAIN LOOP
------------------------------------------------------

local function main()
    log("Starting factory display")

    -- Clean up old listeners once
    if event.ignoreAll then event.ignoreAll() end
    if event.clear then event.clear() end

    local gpu, w, h = init_gpu_screen()
    log("Screen '" .. SCREEN_NICK .. "' size: " .. w .. "x" .. h)

    local button, pot = init_controls()

    -- Initial discovery and draw
    discover_manufacturers()
    local stats, totalCount, overallEff = aggregate_stats()

    local refreshInterval = REFRESH_INTERVAL_DEFAULT
    if pot then
        refreshInterval = read_pot_interval(pot, refreshInterval)
        log(string.format("Initial refresh interval: %.1fs", refreshInterval))
    else
        log(string.format("Using default refresh interval: %.1fs", refreshInterval))
    end

    local now = computer.uptime and computer.uptime() or 0
    local lastDiscoveryTime = now
    local lastRefreshTime   = now
    local lastPotSampleTime = now

    draw_table(gpu, w, h, stats, totalCount, LAST_DISCOVERY_STRING, refreshInterval, overallEff)

    while true do
        now = computer.uptime and computer.uptime() or lastRefreshTime

        local nextDiscoveryDue = lastDiscoveryTime + DISCOVERY_INTERVAL
        local nextRefreshDue   = lastRefreshTime   + refreshInterval
        local nextWake         = math.min(nextDiscoveryDue, nextRefreshDue)

        local timeout = nextWake - now
        if timeout < 0 then timeout = 0 end

        local ev, sender = event.pull(timeout)
        now = computer.uptime and computer.uptime() or now

        -- Handle button presses for manual discovery
        if ev and button and sender == button and ev == "Trigger" then
            log("Refresh button pressed, running discovery now")
            discover_manufacturers()
            stats, totalCount, overallEff = aggregate_stats()
            draw_table(gpu, w, h, stats, totalCount, LAST_DISCOVERY_STRING, refreshInterval, overallEff)
            lastDiscoveryTime = now
            lastRefreshTime   = now
        end

        -- Periodic discovery
        if now - lastDiscoveryTime >= DISCOVERY_INTERVAL then
            log("Running scheduled manufacturer discovery...")
            discover_manufacturers()
            lastDiscoveryTime = now
        end

        -- Periodic live refresh
        if now - lastRefreshTime >= refreshInterval then
            -- Sample pot at most once per second to avoid spamming warnings
            if pot and (now - lastPotSampleTime) >= 1 then
                local newInterval = read_pot_interval(pot, refreshInterval)
                if newInterval and math.abs(newInterval - refreshInterval) >= 0.1 then
                    refreshInterval = newInterval
                    log(string.format("Refresh interval updated from pot: %.1fs", refreshInterval))
                end
                lastPotSampleTime = now
            end

            stats, totalCount, overallEff = aggregate_stats()
            draw_table(gpu, w, h, stats, totalCount, LAST_DISCOVERY_STRING, refreshInterval, overallEff)
            lastRefreshTime = now
        end
    end
end

main()
