-- CCPM Config
--
-- Loads and saves the registries CCPM installs from and the extra hosts the user allows.

-- MARK: Imports
local files = require("ccpm.files")
local paths = require("ccpm.paths")

-- MARK: Constants
local CONFIG_FILE = "config.json"

local PRIMARY_REGISTRY = {
    name = "ccpm",
    url = "https://raw.githubusercontent.com/SorcerioTheWizard/CCPM-Registry/dist/",
}

-- MARK: Private Functions
--- Gets the path of the config file.
---@return string path The absolute path.
local function configPath()
    return paths.join(paths.etc(), CONFIG_FILE)
end

-- MARK: Functions
local config = {}

---@class RegistryConfig
---@field name string A short name to refer to the registry by.
---@field url string The base URL holding `index.json`, ending in `/`.

---@class Config
---@field registries RegistryConfig[] Registries in priority order.
---@field hosts string[] URL prefixes the user allows in addition to each registry's own hosts.

--- Loads the config, filling in defaults for anything missing.
---@return Config config The config.
function config.load()
    local data = files.readJSON(configPath())
    if type(data) ~= "table" then
        data = {}
    end

    return {
        registries = (type(data.registries) == "table" and #data.registries > 0) and data.registries or { PRIMARY_REGISTRY },
        hosts = type(data.hosts) == "table" and data.hosts or {},
    }
end

--- Saves the config.
---@param data Config The config.
function config.save(data)
    files.writeJSON(configPath(), data)
end

--- Gets the registry every CCPM installation starts with.
---@return RegistryConfig registry A copy of the primary registry.
function config.primaryRegistry()
    return { name = PRIMARY_REGISTRY.name, url = PRIMARY_REGISTRY.url }
end

--- Checks if a URL starts with one of the allowed prefixes.
---@param url string The URL.
---@param prefixes string[] The allowed prefixes.
---@return boolean allowed If the URL is allowed.
function config.isAllowedUrl(url, prefixes)
    for _, prefix in ipairs(prefixes) do
        if url:sub(1, #prefix) == prefix then
            return true
        end
    end

    return false
end

return config
