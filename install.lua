-- CCPM Installer
--
-- Installs CCPM with one command: `wget run https://raw.githubusercontent.com/SorcerioTheWizard/ComputerCraft-Package-Manager/master/install.lua`.

-- This file's URL is public and must never move. Keep it small: it only borrows CCPM's own code to install CCPM properly.

-- MARK: Constants
local DEFAULT_REGISTRY = "https://raw.githubusercontent.com/SorcerioTheWizard/CCPM-Registry/dist/"
local PACKAGE = "ccpm"
local TEMP_DIR = "/.ccpm-install"
local LIB_PREFIX = "lib/" .. PACKAGE .. "/"

-- MARK: Functions
--- Downloads a URL as exact bytes.
---@param url string The URL.
---@return string body The response body.
local function get(url)
    if not http then
        error("HTTP is disabled on this computer. Enable `http.enabled` in the ComputerCraft config.", 0)
    end

    local response, err = http.get({ url = url, binary = true })
    if not response then
        error("Could not download " .. url .. ": " .. tostring(err), 0)
    end
    local body = response.readAll() or ""
    response.close()

    return body
end

--- Downloads and decodes a JSON URL.
---@param url string The URL.
---@return table data The decoded data.
local function getJSON(url)
    local data = textutils.unserializeJSON(get(url))
    if type(data) ~= "table" then
        error(url .. " is not valid JSON.", 0)
    end

    return data
end

--- Downloads CCPM's libraries into the temporary folder so they can install CCPM.
---@param registryUrl string The registry's base URL.
---@return string version The version downloaded.
local function fetchLibraries(registryUrl)
    -- Find the newest CCPM
    local index = getJSON(registryUrl .. "index.json")
    local entry = type(index.packages) == "table" and index.packages[PACKAGE]
    if not entry then
        error("The registry does not list " .. PACKAGE .. ".", 0)
    end
    local manifest = getJSON(registryUrl .. "packages/" .. PACKAGE .. "/" .. entry.latest .. ".json")

    -- Download its libraries
    for _, file in ipairs(manifest.files or {}) do
        if file.path:sub(1, #LIB_PREFIX) == LIB_PREFIX then
            local path = fs.combine(TEMP_DIR, file.path)
            fs.makeDir(fs.getDir(path))
            local handle = assert(fs.open(path, "wb"))
            handle.write(get(file.url))
            handle.close()
        end
    end

    return entry.latest
end

--- Installs CCPM with its own code, which checks every file against the registry's hashes.
---@param registryUrl string The registry's base URL.
local function install(registryUrl)
    -- Load the downloaded libraries
    local lib = TEMP_DIR .. "/lib"
    package.path = lib .. "/?.lua;" .. lib .. "/?/init.lua;" .. package.path
    local config = require("ccpm.config")
    local manager = require("ccpm.manager")
    local setup = require("ccpm.setup")
    local state = require("ccpm.state")

    -- Use a custom registry when one was given
    if registryUrl ~= DEFAULT_REGISTRY then
        local settings = config.load()
        settings.registries = { { name = PACKAGE, url = registryUrl } }
        config.save(settings)
    end

    -- Update an installed CCPM, or install it, replacing any copy that was not installed through a registry
    local plan, err
    if state.get(PACKAGE) then
        plan, err = manager.planUpdate({ PACKAGE }, { force = true })
    else
        plan, err = manager.planInstall({ { name = PACKAGE, range = "*" } }, { force = true })
    end
    if not plan then
        error(err, 0)
    end
    local removed, applyErr = manager.apply(plan, true)
    if not removed then
        error(applyErr, 0)
    end

    -- Connect it to the computer
    setup.install(shell)
end

-- MARK: Execution
local registryUrl = ... or DEFAULT_REGISTRY
if registryUrl:sub(-1) ~= "/" then
    registryUrl = registryUrl .. "/"
end

-- Install, always cleaning up the temporary folder
print("Installing CCPM...")
fs.delete(TEMP_DIR)
local ok, result = pcall(function()
    local version = fetchLibraries(registryUrl)
    install(registryUrl)
    return version
end)
fs.delete(TEMP_DIR)

-- Report the result
if not ok then
    printError("CCPM could not be installed: " .. tostring(result))
    return
end
term.setTextColor(term.isColor() and colors.green or colors.white)
print("CCPM " .. result .. " is installed.")
term.setTextColor(colors.white)
print("Run `ccpm help` to get started, or `ccpm search <words>` to find packages.")
