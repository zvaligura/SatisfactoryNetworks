-- factory-display.lua
-- Discover all Manufacturer buildings once ("discovery") and then
-- periodically read live productivity/clock to render a summary on a screen.
-- Discovery is heavy so it runs every 60s or when you press the panel button.
-- Live data refresh is controlled by a potentiometer on the same panel.

------------------------------------------------------
-- CONFIG
------------------------------------------------------

-- Large Screen nick
local SCREEN_NICK = "Video Wall Left"

-- Optional control panel nick plus button for manual discovery refresh.
-- If you do not have this yet, set PANEL_NICK = "".
local PANEL_NICK  = "Control Room Left 1"  -- or "" to disable

-- Button position on that panel (Large Vertical Control Panel)
local BTN_X            = 1
local BTN_Y            = 9
local BTN_PANEL_INDEX  = 0     -- 0 or 1 or 2 for vertical panel

-- Potentiometer position on the same panel (optional)
-- This controls how often the LIVE data is refreshed.
-- If you do not have a pot here, it will just use the default interval.
local POT_X            = 1
local POT_Y            = 7
local POT_PANEL_INDEX  = 0

-- Discovery interval in seconds (expensive scan of all manufacturers)
local DISCOVERY_INTERVAL = 60

-- Default live refresh interval (seconds) if pot is missing or unreadable
local REFRESH_INTERVAL_DEFAULT = 15

-- Clamp for pot-based refresh interval (seconds)
local POT_MIN_SECONDS = 5   -- never refresh faster than this
local POT_MAX_SECONDS = 60  -- never slower than this via pot

-- Optional: cap the max number of data rows printed
local MAX_ROWS = 200

-- Timezone offset from the time returned by computer.magicTime()
-- Central Standard Time is UTC-6. If your display is off by an hour,
-- change this to -5 or whatever you need.
local TIMEZONE_OFFSET_HOURS = -6

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

-- simple integer with thousands separators
local function format_int(v)
    if not v then v = 0 end
    local n = math.floor(v + 0.5)
    local s = tostring(n)
    local result = ""
    local count = 0
    for i = #s, 1, -1 do
        local ch = s:sub(i, i)
        result = ch .. result
        count = count + 1
        if count == 3 and i > 1 then
            result = "," .. result
            count = 0
        end
    end
    return result
end

local function format_pair(nowVal, maxVal)
    return format_int(nowVal) .. "/" .. format_int(maxVal)
end

-- days in month with leap year handling
local function days_in_month(year, month)
    local m31 = {1,3,5,7,8,10,12}
    local m30 = {4,6,9,11}
    for _, m in ipairs(m31) do
        if m == month then return 31 end
    end
    for _, m in ipairs(m30) do
        if m == month then return 30 end
    end
    -- February
    local is_leap = (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
    return is_leap and 29 or 28
end

-- Apply hour offset and wrap across day/month/year as needed
local function apply_hour_offset(year, month, day, hour, offset)
    local h = hour + offset

    while h < 0 do
        h = h + 24
        day = day - 1
        if day < 1 then
            month = month - 1
            if month < 1 then
                month = 12
                year = year - 1
            end
            day = days_in_month(year, month)
        end
    end

    while h >= 24 do
        h = h - 24
        day = day + 1
        local dim = days_in_month(year, month)
        if day > dim then
            day = 1
            month = month + 1
            if month > 12 then
                month = 1
                year = year + 1
            end
        end
    end

    return year, month, day, h
end

-- Get a string like "11/15 @ 8:35:38pm" using local time from magicTime,
-- adjusted by TIMEZONE_OFFSET_HOURS
local function get_time_string()
    if not computer.magicTime then
        return nil
    end

    local ok, unix, culture, iso = pcall(computer.magicTime)
    if not ok then
        return nil
    end

    local s = iso or culture
    if not s then
        return tostring(unix)
    end

    -- Expect something like "2025-11-16T02:14:32"
    local year, month, day, hour, min, sec =
        s:match("(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
    if not year then
        -- If format is unexpected, just return the raw string
        return s
    end

    year  = tonumber(year)
    month = tonumber(month)
    day   = tonumber(day)
    hour  = tonumber(hour)
    min   = tonumber(min)
    sec   = tonumber(sec)

    -- Apply timezone offset
    year, month, day, hour = apply_hour_offset(
        year, month, day, hour, TIMEZONE_OFFSET_HOURS
    )

    -- Convert to 12 hour time with am/pm
    local ampm = "am"
    local h12 = hour

    if hour == 0 then
        h12 = 12
        ampm = "am"
    elseif hour == 12 then
        h12 = 12
        ampm = "pm"
    elseif hour > 12 then
        h12 = hour - 12
        ampm = "pm"
    else
        h12 = hour
        ampm = "am"
    end

    return string.format("%02d/%02d @ %d:%02d:%02d%s",
        month, day, h12, min, sec, ampm)
end

-- Safe property access on reflection objects (building types / recipes)
local function safe_prop(obj, key)
    if not obj then return nil end
    local ok, val = pcall(function()
        return obj[key]
    end)
    if ok then
        return val
    end
    return nil
end

-- Turn a Manufacturer type into a nice building name:
-- prefer displayName or name over internalName
local function get_building_display_name(m)
    local t = m:getType()
    if not t then
        return "Unknown"
    end

    local dn = safe_prop(t, "displayName")
            or safe_prop(t, "name")
            or safe_prop(t, "internalName")

    if not dn or dn == "" then
        dn = "Unknown"
    end
    return dn
end

-- Turn a Recipe class into a nice recipe name
local function get_recipe_display_name(recipeClass)
    if not recipeClass then
        return "<no recipe>"
    end

    local n = safe_prop(recipeClass, "name")
          or safe_prop(recipeClass, "displayName")
          or safe_prop(recipeClass, "internalName")

    if not n or n == "" then
        n = "<no recipe>"
    end
    return n
end

------------------------------------------------------
-- RECIPE IO HELPERS
------------------------------------------------------

-- Try to get a table of ingredient or product entries from a recipe
local function safe_get_entries(recipeClass, kind)
    if not recipeClass then return {} end
    local fn_name = (kind == "ingredients") and "getIngredients" or "getProducts"
    local ok, result = pcall(function()
        return recipeClass[fn_name](recipeClass)
    end)
    if not ok or type(result) ~= "table" then
        return {}
    end
    return result
end

-- Convert a list of entries into a map itemName -> totalAmountPerCycle
local function parse_io_entries(entries)
    local out = {}
    for _, entry in ipairs(entries) do
        if entry then
            local amount
            local item
            if type(entry) == "table" then
                amount = entry.amount or entry.count or entry.quantity or entry.Quantity or 0
                item = entry.item or entry.Item or entry.product or entry.Product or entry.itemClass
            else
                amount = safe_prop(entry, "amount") or safe_prop(entry, "count") or 0
                item = safe_prop(entry, "item") or safe_prop(entry, "Item") or safe_prop(entry, "product")
            end

            local itemName = "<item>"
            if type(item) == "string" then
                itemName = item
            elseif item then
                itemName = safe_prop(item, "name") or safe_prop(item, "displayName") or safe_prop(item, "internalName") or itemName
            end

            amount = tonumber(amount) or 0
            if amount > 0 then
                out[itemName] = (out[itemName] or 0) + amount
            end
        end
    end
    return out
end

local function get_recipe_io(recipeClass)
    local ingredients = safe_get_entries(recipeClass, "ingredients")
    local products    = safe_get_entries(recipeClass, "products")
    local inMap  = parse_io_entries(ingredients)
    local outMap = parse_io_entries(products)
    return inMap, outMap
end

------------------------------------------------------
-- GLOBAL MACHINE CACHE (DISCOVERY)
------------------------------------------------------

-- MACHINES is a list of entries like:
-- { machine = <proxy>, buildingType = "Constructor", recipeName = "Wire",
--   designIn = <items/min at current clock>, designOut = <items/min at current clock> }
local MACHINES = {}
local LAST_DISCOVERY_STRING = nil

local function discover_manufacturers()
    MACHINES = {}

    -- Manufacturer is the base for all recipe-using machines
    local ids = component.findComponent(classes.Manufacturer)
    local manufacturers = component.proxy(ids or {})

    local totalCount = 0

    for _, m in ipairs(manufacturers) do
        local buildingType = get_building_display_name(m)
        local recipeClass  = m:getRecipe()
        local recipeName   = get_recipe_display_name(recipeClass)

        local inMap, outMap = get_recipe_io(recipeClass)

        local cycleTime = tonumber(safe_prop(m, "cycleTime")) or 0
        if cycleTime > 0 then
            -- current clock / potential factor
            local potential = safe_prop(m, "currentPotential") or safe_prop(m, "potential") or 1
            potential = tonumber(potential) or 1
            if potential < 0 then potential = 0 end

            local cyclesPerMin = (60 / cycleTime) * potential

            local designIn, designOut = 0, 0
            for _, amt in pairs(inMap) do
                amt = tonumber(amt) or 0
                designIn = designIn + amt * cyclesPerMin
            end
            for _, amt in pairs(outMap) do
                amt = tonumber(amt) or 0
                designOut = designOut + amt * cyclesPerMin
            end

            table.insert(MACHINES, {
                machine      = m,
                buildingType = buildingType,
                recipeName   = recipeName,
                designIn     = designIn,
                designOut    = designOut,
            })

            totalCount = totalCount + 1
        end
    end

    LAST_DISCOVERY_STRING = get_time_string()
    log("Discovered " .. totalCount .. " manufacturers")
end

------------------------------------------------------
-- LIVE DATA AGGREGATION
------------------------------------------------------

-- Build stats from MACHINES using live productivity / clock
-- Returns:
--   stats[building][recipe] = {count, inNow, inMax, outNow, outMax, clkSum, clkSamples}
--   totalCount, overallEffPct
local function aggregate_stats()
    local stats = {}
    local totalCount = 0

    local effNum, effDen = 0, 0

    for _, info in ipairs(MACHINES) do
        local m = info.machine

        -- live productivity 0..1 (or more if overproducing)
        local prod = tonumber(safe_prop(m, "productivity")) or 0
        if prod < 0 then prod = 0 end

        -- live clock / potential factor (for Clk%)
        local potential = safe_prop(m, "currentPotential") or safe_prop(m, "potential") or 1
        potential = tonumber(potential) or 1
        if potential < 0 then potential = 0 end

        local inMax  = info.designIn or 0
        local outMax = info.designOut or 0

        local inNow  = inMax  * prod
        local outNow = outMax * prod

        local buildingType = info.buildingType
        local recipeName   = info.recipeName

        if not stats[buildingType] then
            stats[buildingType] = {}
        end
        local recipes = stats[buildingType]

        local r = recipes[recipeName]
        if not r then
            r = {
                count      = 0,
                inNow      = 0,
                inMax      = 0,
                outNow     = 0,
                outMax     = 0,
                clkSum     = 0,
                clkSamples = 0,
            }
            recipes[recipeName] = r
        end

        r.count      = r.count      + 1
        r.inNow      = r.inNow      + inNow
        r.inMax      = r.inMax      + inMax
        r.outNow     = r.outNow     + outNow
        r.outMax     = r.outMax     + outMax
        r.clkSum     = r.clkSum     + potential
        r.clkSamples = r.clkSamples + 1

        effNum = effNum + outNow
        effDen = effDen + outMax

        totalCount = totalCount + 1
    end

    local overallEff = 0
    if effDen > 0 then
        overallEff = (effNum / effDen) * 100
    end

    return stats, totalCount, overallEff
end

------------------------------------------------------
-- GPU AND SCREEN SETUP
------------------------------------------------------

local function init_gpu_screen()
    -- Prefer GPU T2, fall back to T1
    local gpu = computer.getPCIDevices(classes.GPUT2)[1]
    local gpuName = "GPUT2"

    if not gpu then
        gpu = computer.getPCIDevices(classes.GPUT1)[1]
        gpuName = "GPUT1"
    end

    if not gpu then
        error("No GPU T2 or T1 found in this computer")
    end

    local screen

    -- 1) Try to find the nicked Large Screen on the network
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

    log(string.format("Bound %s to screen, size %dx%d", gpuName, w, h))

    -- Clear the screen once at start
    gpu:setBackground(0, 0, 0, 0)
    gpu:fill(0, 0, w, h, " ")
    gpu:flush()

    return gpu, w, h
end

------------------------------------------------------
-- CONTROL PANEL (BUTTON + POT)
------------------------------------------------------

local function init_controls()
    if not PANEL_NICK or PANEL_NICK == "" then
        log("No PANEL_NICK configured, controls disabled")
        return nil, nil
    end

    local ids = component.findComponent(PANEL_NICK)
    if not ids or #ids == 0 then
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
