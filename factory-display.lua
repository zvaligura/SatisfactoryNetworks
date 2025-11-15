-- factory-display.lua
-- Discover all Manufacturer buildings on this network
-- and render a table on a screen using the GPU.

------------------------------------------------------
-- CONFIG
------------------------------------------------------

-- Optional: cap the max number of data rows printed
local MAX_ROWS = 200

------------------------------------------------------
-- HELPERS: table printing formatting
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
    -- Manufacturer is the base class for all recipe-using machines
    -- (constructors, assemblers, refineries, etc.) 
    local ids = component.findComponent(classes.Manufacturer)
    local manufacturers = component.proxy(ids or {})

    local stats = {}   -- stats[buildingType][recipeName] = count; plus __total
    local total = 0

    for _, m in ipairs(manufacturers) do
        -- Building type via getType().internalName 
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
-- GPU + SCREEN SETUP (Random Plot pattern)
------------------------------------------------------

local function init_gpu_screen()
    -- get first T1 GPU available from PCI-Interface 
    local gpu = computer.getPCIDevices(classes.GPUT1)[1]
    if not gpu then
        error("No GPU T1 found!")
    end

    -- get first Screen-Driver available from PCI-Interface
    local screen = computer.getPCIDevices(classes["FINComputerScreen"])[1]
    -- if no screen found, try to find large screen from component network 
    if not screen then
        local compId = component.findComponent(classes.Screen)[1]
        if not compId then
            error("No Screen found!")
        end
        screen = component.proxy(compId)
    end

    -- setup gpu
    gpu:bindScreen(screen)
    local w, h = gpu:getSize()

    -- clear screen
    gpu:setBackground(0, 0, 0, 0)
    gpu:fill(0, 0, w, h, " ")
    gpu:flush()

    return gpu, w, h
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
        -- Truncate to screen width
        if #text > w then
            text = text:sub(1, w)
        end
        gpu:setText(0, y, text)
        return true
    end

    local row = 0

    -- Title
    drawLine(row, "Factory Overview")
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
-- MAIN
------------------------------------------------------

local function main()
    log("Starting factory display scan...")

    local stats, total = scan_manufacturers()
    log("Scan done, manufacturers: " .. tostring(total))

    local gpu, w, h = init_gpu_screen()
    log("Screen size: " .. w .. "x" .. h)

    draw_table(gpu, w, h, stats, total)

    log("Display updated.")

    -- Keep the program alive so the computer stays "running".
    -- This doesn't change the screen anymore, just idles.
    while true do
        event.pull(5)
    end
end

main()
