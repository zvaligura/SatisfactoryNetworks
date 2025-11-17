-- factory-display.lua
-- Discover all Manufacturer buildings and render a summary on "Video Wall".
-- Auto refresh every 60s and manual refresh via a panel button.
-- Shows "Last: 11/15 @ 8:35:38pm" in the top right (Central time).
-- Uses human-readable building and recipe names.

------------------------------------------------------
-- CONFIG
------------------------------------------------------

-- Large Screen nick
local SCREEN_NICK = "Video Wall Left"

-- Optional control panel nick plus button for manual refresh.
-- If you do not have this yet, set PANEL_NICK = "".
local PANEL_NICK  = "Control Room Left 1"  -- or "" to disable

-- Button position on that panel (Large Vertical Control Panel)
local BTN_X            = 1
local BTN_Y            = 9
local BTN_PANEL_INDEX  = 0     -- 0 or 1 or 2 for vertical panel

-- Auto refresh interval in seconds
local REFRESH_INTERVAL = 60

-- Optional: cap the max number of recipe rows printed
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

-- Turn a Manufacturer type into a nice building name
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

-- Format a per minute rate nicely
local function format_rate(v)
    v = tonumber(v) or 0
    if v < 0.01 then
        return "0.0"
    end
    -- one decimal place
    v = math.floor(v * 10 + 0.5) / 10
    if v >= 1000 then
        return string.format("%.1fk", v / 1000)
    else
        return string.format("%.1f", v)
    end
end

local function format_percent_value(ratio)
    ratio = tonumber(ratio) or 0
    local pct = ratio * 100
    if pct < 0 then pct = 0 end
    pct = math.floor(pct + 0.5)
    if pct > 999 then pct = 999 end
    return string.format("%3d%%", pct)
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
                itemName = safe_prop(item, "name")
                         or safe_prop(item, "displayName")
                         or safe_prop(item, "internalName")
                         or itemName
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
-- SCAN MANUFACTURERS
------------------------------------------------------

-- For a single machine, compute its per minute IO and potentials
-- Returns:
--   inPerMin, outPerMin, maxInPerMin, maxOutPerMin,
--   inItems, outItems, potential, maxPotential
local function get_machine_rates(m, recipeClass)
    -- Cycle time is seconds per craft at 100 percent potential
    local cycleTime = tonumber(safe_prop(m, "cycleTime")) or 0
    if cycleTime <= 0 then
        return 0, 0, 0, 0, {}, {}, 0, 0
    end

    -- Potential behaves like clock speed (1.0 = 100%)
    local potential = safe_prop(m, "potential")
                  or safe_prop(m, "currentPotential")
                  or 1
    potential = tonumber(potential) or 1

    local maxPotential = safe_prop(m, "maxPotential")
                      or safe_prop(m, "maxDefaultPotential")
                      or potential
    maxPotential = tonumber(maxPotential) or potential

    if potential < 0 then potential = 0 end
    if maxPotential < potential then
        maxPotential = potential
    end

    local baseCyclesPerMin = 60 / cycleTime
    local cyclesPerMin     = baseCyclesPerMin * potential
    local maxCyclesPerMin  = baseCyclesPerMin * maxPotential

    local inMap, outMap = get_recipe_io(recipeClass)

    local inPerMin, outPerMin    = 0, 0
    local maxInPerMin, maxOutPerMin = 0, 0
    local inItems  = {}
    local outItems = {}

    for itemName, amt in pairs(inMap) do
        amt = tonumber(amt) or 0
        if amt > 0 then
            local cur = amt * cyclesPerMin
            local maxv = amt * maxCyclesPerMin
            inPerMin    = inPerMin    + cur
            maxInPerMin = maxInPerMin + maxv
            inItems[itemName] = { cur = cur, max = maxv }
        end
    end

    for itemName, amt in pairs(outMap) do
        amt = tonumber(amt) or 0
        if amt > 0 then
            local cur = amt * cyclesPerMin
            local maxv = amt * maxCyclesPerMin
            outPerMin    = outPerMin    + cur
            maxOutPerMin = maxOutPerMin + maxv
            outItems[itemName] = { cur = cur, max = maxv }
        end
    end

    return inPerMin, outPerMin, maxInPerMin, maxOutPerMin,
           inItems, outItems, potential, maxPotential
end

local function scan_manufacturers()
    -- Manufacturer is the base for all recipe using machines
    local ids = component.findComponent(classes.Manufacturer)
    local manufacturers = component.proxy(ids or {})

    -- stats[buildingType][recipeName] = {
    --   count,
    --   inPerMin, outPerMin, maxInPerMin, maxOutPerMin,
    --   inItems[itemName]  = { cur, max },
    --   outItems[itemName] = { cur, max },
    --   potentialSum, maxPotentialSum
    -- }
    local stats = {}
    local totalCount = 0

    for _, m in ipairs(manufacturers) do
        -- Human-friendly building type (e.g. "Smelter", "Constructor")
        local buildingType = get_building_display_name(m)

        -- Current recipe (e.g. "Copper Sheet" instead of "Recipe_CopperSheet_C")
        local recipeClass = m:getRecipe()
        local recipeName  = get_recipe_display_name(recipeClass)

        if not stats[buildingType] then
            stats[buildingType] = {}
        end

        local recipes = stats[buildingType]
        local r = recipes[recipeName]
        if not r then
            r = {
                count           = 0,
                inPerMin        = 0,
                outPerMin       = 0,
                maxInPerMin     = 0,
                maxOutPerMin    = 0,
                inItems         = {},
                outItems        = {},
                potentialSum    = 0,
                maxPotentialSum = 0
            }
            recipes[recipeName] = r
        end

        local inPerMin, outPerMin, maxInPerMin, maxOutPerMin,
              inItems, outItems, potential, maxPotential =
            get_machine_rates(m, recipeClass)

        r.count        = r.count + 1
        r.inPerMin     = r.inPerMin     + inPerMin
        r.outPerMin    = r.outPerMin    + outPerMin
        r.maxInPerMin  = r.maxInPerMin  + maxInPerMin
        r.maxOutPerMin = r.maxOutPerMin + maxOutPerMin
        r.potentialSum    = r.potentialSum    + (potential or 0)
        r.maxPotentialSum = r.maxPotentialSum + (maxPotential or 0)

        -- Aggregate per-item input rates
        for itemName, data in pairs(inItems) do
            local ri = r.inItems[itemName]
            if not ri then
                ri = { cur = 0, max = 0 }
                r.inItems[itemName] = ri
            end
            ri.cur = ri.cur + (data.cur or 0)
            ri.max = ri.max + (data.max or 0)
        end

        -- Aggregate per-item output rates
        for itemName, data in pairs(outItems) do
            local ro = r.outItems[itemName]
            if not ro then
                ro = { cur = 0, max = 0 }
                r.outItems[itemName] = ro
            end
            ro.cur = ro.cur + (data.cur or 0)
            ro.max = ro.max + (data.max or 0)
        end

        totalCount = totalCount + 1
    end

    return stats, totalCount
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

local function draw_table(gpu, w, h, stats, totalCount, last_time)
    -- Clear every frame so old rows do not linger
    gpu:setBackground(0, 0, 0, 0)
    gpu:fill(0, 0, w, h, " ")

    -- Column layout
    local colBuildingWidth = 14
    local colRecipeWidth   = 26
    local colCountWidth    = 4
    local colInNowWidth    = 8
    local colInMaxWidth    = 8
    local colOutNowWidth   = 8
    local colOutMaxWidth   = 8
    local colEffWidth      = 5
    local colClkWidth      = 5

    local totalWidth = colBuildingWidth + 1 +
                       colRecipeWidth   + 1 +
                       colCountWidth    + 1 +
                       colInNowWidth    + 1 +
                       colInMaxWidth    + 1 +
                       colOutNowWidth   + 1 +
                       colOutMaxWidth   + 1 +
                       colEffWidth      + 1 +
                       colClkWidth

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

    local function sorted_keys(t)
        local keys = {}
        for k in pairs(t or {}) do
            table.insert(keys, k)
        end
        table.sort(keys)
        return keys
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
        padLeft("Cnt",       colCountWidth)    .. " " ..
        padLeft("InNow",     colInNowWidth)    .. " " ..
        padLeft("InMax",     colInMaxWidth)    .. " " ..
        padLeft("OutNow",    colOutNowWidth)   .. " " ..
        padLeft("OutMax",    colOutMaxWidth)   .. " " ..
        padLeft("Eff%",      colEffWidth)      .. " " ..
        padLeft("Clk%",      colClkWidth)
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
    local grandInNow, grandOutNow = 0, 0
    local grandMaxIn, grandMaxOut = 0, 0
    local grandPotentialSum, grandMachineCount = 0, 0

    for _, buildingType in ipairs(buildingKeys) do
        local recipes = stats[buildingType]

        -- Sort recipe names
        local recipeKeys = {}
        for recipeName in pairs(recipes) do
            table.insert(recipeKeys, recipeName)
        end
        table.sort(recipeKeys)

        local buildingCount = 0
        local buildingInNow, buildingOutNow = 0, 0
        local buildingMaxIn, buildingMaxOut = 0, 0
        local buildingPotentialSum, buildingMachineCount = 0, 0

        for _, recipeName in ipairs(recipeKeys) do
            dataRows = dataRows + 1
            if dataRows > MAX_ROWS then break end

            local r = recipes[recipeName]

            buildingCount        = buildingCount        + (r.count or 0)
            buildingInNow        = buildingInNow        + (r.inPerMin or 0)
            buildingOutNow       = buildingOutNow       + (r.outPerMin or 0)
            buildingMaxIn        = buildingMaxIn        + (r.maxInPerMin or 0)
            buildingMaxOut       = buildingMaxOut       + (r.maxOutPerMin or 0)
            buildingPotentialSum = buildingPotentialSum + (r.potentialSum or 0)
            buildingMachineCount = buildingMachineCount + (r.count or 0)

            grandInNow        = grandInNow        + (r.inPerMin or 0)
            grandOutNow       = grandOutNow       + (r.outPerMin or 0)
            grandMaxIn        = grandMaxIn        + (r.maxInPerMin or 0)
            grandMaxOut       = grandMaxOut       + (r.maxOutPerMin or 0)
            grandPotentialSum = grandPotentialSum + (r.potentialSum or 0)
            grandMachineCount = grandMachineCount + (r.count or 0)

            local effRatio = 0
            if r.maxOutPerMin and r.maxOutPerMin > 0 then
                effRatio = (r.outPerMin or 0) / r.maxOutPerMin
            end

            local avgClockRatio = 0
            if r.count and r.count > 0 then
                -- potential is 1.0 for 100%
                avgClockRatio = (r.potentialSum or 0) / r.count
            end

            local line =
                padRight(buildingType, colBuildingWidth) .. " " ..
                padRight(recipeName,   colRecipeWidth)   .. " " ..
                padLeft(r.count or 0,  colCountWidth)    .. " " ..
                padLeft(format_rate(r.inPerMin or 0),    colInNowWidth)  .. " " ..
                padLeft(format_rate(r.maxInPerMin or 0), colInMaxWidth)  .. " " ..
                padLeft(format_rate(r.outPerMin or 0),   colOutNowWidth) .. " " ..
                padLeft(format_rate(r.maxOutPerMin or 0),colOutMaxWidth) .. " " ..
                padLeft(format_percent_value(effRatio),  colEffWidth)    .. " " ..
                padLeft(format_percent_value(avgClockRatio), colClkWidth)

            if not drawLine(row, line) then
                break
            end
            row = row + 1

            if row >= h then
                break
            end

            -- Per-item breakdown for multi-input/multi-output recipes
            local inKeys  = sorted_keys(r.inItems or {})
            local outKeys = sorted_keys(r.outItems or {})

            local inCount, outCount = 0, 0
            for _ in pairs(r.inItems or {}) do inCount = inCount + 1 end
            for _ in pairs(r.outItems or {}) do outCount = outCount + 1 end

            -- Only show subrows if there are multiple inputs or outputs
            if (inCount > 1) or (outCount > 1) then
                -- Inputs
                for _, itemName in ipairs(inKeys) do
                    local item = r.inItems[itemName]
                    local sub =
                        padRight("", colBuildingWidth) .. " " ..
                        padRight("IN: " .. itemName, colRecipeWidth) .. " " ..
                        padLeft("", colCountWidth)    .. " " ..
                        padLeft(format_rate(item.cur or 0), colInNowWidth)  .. " " ..
                        padLeft(format_rate(item.max or 0), colInMaxWidth)  .. " " ..
                        padLeft("", colOutNowWidth)   .. " " ..
                        padLeft("", colOutMaxWidth)   .. " " ..
                        padLeft("", colEffWidth)      .. " " ..
                        padLeft("", colClkWidth)

                    if not drawLine(row, sub) then
                        break
                    end
                    row = row + 1
                    if row >= h then break end
                end

                if row >= h then
                    break
                end

                -- Outputs
                for _, itemName in ipairs(outKeys) do
                    local item = r.outItems[itemName]
                    local sub =
                        padRight("", colBuildingWidth) .. " " ..
                        padRight("OUT: " .. itemName, colRecipeWidth) .. " " ..
                        padLeft("", colCountWidth)    .. " " ..
                        padLeft("", colInNowWidth)   .. " " ..
                        padLeft("", colInMaxWidth)   .. " " ..
                        padLeft(format_rate(item.cur or 0), colOutNowWidth) .. " " ..
                        padLeft(format_rate(item.max or 0), colOutMaxWidth) .. " " ..
                        padLeft("", colEffWidth)      .. " " ..
                        padLeft("", colClkWidth)

                    if not drawLine(row, sub) then
                        break
                    end
                    row = row + 1
                    if row >= h then break end
                end
            end

            if row >= h then
                break
            end
        end

        if dataRows > MAX_ROWS or row >= h then
            break
        end

        -- Per building subtotal row
        local utilB = 0
        if buildingMaxOut > 0 then
            utilB = buildingOutNow / buildingMaxOut
        end

        local avgClockB = 0
        if buildingMachineCount > 0 then
            avgClockB = buildingPotentialSum / buildingMachineCount
        end

        local subtotal =
            padRight(buildingType, colBuildingWidth) .. " " ..
            padRight("<ALL>",      colRecipeWidth)   .. " " ..
            padLeft(buildingCount, colCountWidth)    .. " " ..
            padLeft(format_rate(buildingInNow),  colInNowWidth)  .. " " ..
            padLeft(format_rate(buildingMaxIn),  colInMaxWidth)  .. " " ..
            padLeft(format_rate(buildingOutNow), colOutNowWidth) .. " " ..
            padLeft(format_rate(buildingMaxOut), colOutMaxWidth) .. " " ..
            padLeft(format_percent_value(utilB), colEffWidth)    .. " " ..
            padLeft(format_percent_value(avgClockB), colClkWidth)

        if not drawLine(row, subtotal) then
            break
        end
        row = row + 1

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

        local utilTotal = 0
        if grandMaxOut > 0 then
            utilTotal = grandOutNow / grandMaxOut
        end

        local clockTotal = 0
        if grandMachineCount > 0 then
            clockTotal = grandPotentialSum / grandMachineCount
        end

        local footer = string.format(
            "Total machines: %d   In: %s/%s per min   Out: %s/%s per min   Eff: %s   Clk: %s",
            totalCount or 0,
            format_rate(grandInNow),
            format_rate(grandMaxIn),
            format_rate(grandOutNow),
            format_rate(grandMaxOut),
            format_percent_value(utilTotal),
            format_percent_value(clockTotal)
        )
        drawLine(row, footer)
    end

    gpu:flush()
end

------------------------------------------------------
-- REFRESH WRAPPER
------------------------------------------------------

local function refresh(gpu, w, h)
    local stats, totalCount = scan_manufacturers()
    local time_str = get_time_string()
    draw_table(gpu, w, h, stats, totalCount, time_str)
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
