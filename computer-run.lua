-- computer-run.lua
-- EEPROM code that fetches and runs a Lua file from GitHub

-- Edit these four values per computer if you want:
local GITHUB_USER   = "zvaligura"
local GITHUB_REPO   = "SatisfactoryNetworks"
local GITHUB_BRANCH = "main"
local TARGET_FILE   = "light-test.lua"

local function log(level, msg)
    print("[" .. level .. "] " .. msg)
end

local function main()
    log("Info", "=== computer-run starting ===")
    log("Info", "Repo:   " .. GITHUB_USER .. "/" .. GITHUB_REPO)
    log("Info", "Branch: " .. GITHUB_BRANCH)
    log("Info", "Target: " .. TARGET_FILE)

    -- Get internet card via classes.FINInternetCard
    local devices = computer.getPCIDevices(classes.FINInternetCard)
    local card = devices and devices[1]

    if not card then
        log("Fatal", "No FINInternetCard found in this computer")
        computer.beep(0.3)
        return
    end

    local url =
        "https://raw.githubusercontent.com/"
        .. GITHUB_USER .. "/"
        .. GITHUB_REPO .. "/"
        .. GITHUB_BRANCH .. "/"
        .. TARGET_FILE

    log("Info", "Requesting: " .. url)

    -- Make HTTP request
    local req = card:request(url, "GET", "")
    -- await() returns whatever the HTTP call returns.
    -- The official example ignores the first value, so we do the same pattern.
    local ok, data = req:await()

    if not data then
        log("Fatal", "Request failed or returned no data. First return value was: " .. tostring(ok))
        computer.beep(0.3)
        return
    end

    log("Info", "Download ok, loading chunk")

    local chunk, err = load(data, "=" .. TARGET_FILE)
    if not chunk then
        log("Fatal", "Failed to load Lua chunk: " .. tostring(err))
        computer.beep(0.3)
        return
    end

    log("Info", "Running " .. TARGET_FILE)

    local ok_run, err_run = pcall(chunk)
    if not ok_run then
        log("Fatal", "Runtime error in " .. TARGET_FILE .. ": " .. tostring(err_run))
        computer.beep(0.3)
        return
    end

    log("Info", TARGET_FILE .. " finished")
end

main()