-- computer-run.lua
-- Minimal FIN net-loader that pulls a Lua file from GitHub and runs it.

-------------------------------------------------
-- CONFIG - edit per computer
-------------------------------------------------
local GITHUB_USER   = "zvaligura"
local GITHUB_REPO   = "SatisfactoryNetworks"
local GITHUB_BRANCH = "main"

-- Path *inside the repo* to the Lua file you want this computer to run.
-- For now we keep it simple and point at a single file in the root:
--   https://raw.githubusercontent.com/<user>/<repo>/<branch>/light-test.lua
-- Change this per computer later.
local TARGET_FILE   = "light-test.lua"
-------------------------------------------------

local function log(level, msg)
    print("[" .. level .. "] " .. msg)
end

local function buildUrl()
    return "https://raw.githubusercontent.com/"
        .. GITHUB_USER .. "/"
        .. GITHUB_REPO .. "/"
        .. GITHUB_BRANCH .. "/"
        .. TARGET_FILE
end

local function main()
    log("Info", "=== computer-run starting ===")
    log("Info", "Repo:   " .. GITHUB_USER .. "/" .. GITHUB_REPO)
    log("Info", "Branch: " .. GITHUB_BRANCH)
    log("Info", "Target: " .. TARGET_FILE)

    -- Get Internet Card (official pattern) 
    local cards = computer.getPCIDevices(classes.FINInternetCard)
    local internet = cards and cards[1]

    if not internet then
        log("Fatal", "No FINInternetCard found in this computer")
        computer.beep(0.3)
        return
    end

    local url = buildUrl()
    log("Info", "Requesting: " .. url)

    -- Follows the FicsIt-OS bootstrap style:
    --   code, data = internet:request(...):await()
    -- where code is HTTP status, data is response body. 
    local code, data = internet:request(url, "GET", ""):await()

    if code ~= 200 then
        log("Fatal", "HTTP " .. tostring(code) .. " while fetching script")
        log("Fatal", "Check that " .. TARGET_FILE .. " exists in the repo/branch")
        computer.beep(0.3)
        return
    end

    if type(data) ~= "string" then
        log("Fatal", "Unexpected response body type: " .. type(data))
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

    local ok, runErr = pcall(chunk)
    if not ok then
        log("Fatal", "Runtime error in " .. TARGET_FILE .. ": " .. tostring(runErr))
        computer.beep(0.3)
        return
    end

    log("Info", TARGET_FILE .. " finished")
end

main()
