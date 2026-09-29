-- CCPM Registry
--
-- Downloads and caches registry indexes, finds packages across registries, and fetches version manifests.

-- MARK: Imports
local config = require("ccpm.config")
local files = require("ccpm.files")
local net = require("ccpm.net")
local paths = require("ccpm.paths")
local semver = require("ccpm.semver")

-- MARK: Constants
local INDEX_FILE = "index.json"
local SUPPORTED_FORMAT = 1

-- MARK: Private Functions
--- Gets the cache path of a registry's index.
---@param registry RegistryConfig The registry.
---@return string path The absolute path.
local function cachePath(registry)
    return paths.join(paths.cache(), registry.name .. ".json")
end

--- Checks that an index can be read by this version of CCPM.
---@param registry RegistryConfig The registry.
---@param index any The decoded index.
---@return boolean ok If the index is usable.
---@return string|nil err The error message if not.
local function checkIndex(registry, index)
    if type(index) ~= "table" or type(index.packages) ~= "table" then
        return false, "the index of registry `" .. registry.name .. "` is damaged"
    end
    if index.format ~= SUPPORTED_FORMAT then
        return false, "registry `" .. registry.name .. "` uses index format " .. tostring(index.format) .. "; run `ccpm upgrade` to read it"
    end

    return true
end

-- MARK: Functions
local registry = {}

---@class IndexEntry
---@field description string
---@field author string
---@field license string|nil
---@field repository string|nil
---@field homepage string|nil
---@field tags string[]|nil
---@field latest string
---@field versions string[] Versions from highest to lowest.

---@class LoadedRegistry
---@field name string The registry name.
---@field url string The base URL.
---@field hosts string[] The URL prefixes this registry's files may come from, plus the user's own.
---@field packages table<string, IndexEntry> The packages it lists.

--- Loads a registry's index from the cache, or downloads it when missing or when asked to refresh.
---@param source RegistryConfig The registry.
---@param userHosts string[] URL prefixes the user allows everywhere.
---@param refresh boolean|nil If the index should be downloaded even when cached.
---@return LoadedRegistry|nil loaded The loaded registry, or `nil` if it could not be loaded.
---@return string|nil err The error message if it could not be loaded.
function registry.load(source, userHosts, refresh)
    -- Prefer the cached copy unless refreshing
    local index = (not refresh) and files.readJSON(cachePath(source)) or nil
    if index == nil then
        local err
        index, err = net.getJSON(source.url .. INDEX_FILE)
        if index == nil then
            return nil, "registry `" .. source.name .. "` could not be loaded: " .. err
        end
        files.writeJSON(cachePath(source), index)
    end

    -- Check it
    local ok, err = checkIndex(source, index)
    if not ok then
        return nil, err
    end

    -- Allow the registry's hosts and the user's
    local hosts = {}
    for _, prefix in ipairs(index.hosts or {}) do
        hosts[#hosts + 1] = prefix
    end
    for _, prefix in ipairs(userHosts) do
        hosts[#hosts + 1] = prefix
    end

    return { name = source.name, url = source.url, hosts = hosts, packages = index.packages }
end

--- Loads every configured registry in priority order.
---@param refresh boolean|nil If indexes should be downloaded even when cached.
---@return LoadedRegistry[]|nil registries The loaded registries, or `nil` if any failed to load.
---@return string|nil err The error message if any failed.
function registry.loadAll(refresh)
    local settings = config.load()
    local loaded = {}
    for _, source in ipairs(settings.registries) do
        local entry, err = registry.load(source, settings.hosts, refresh)
        if not entry then
            return nil, err
        end
        loaded[#loaded + 1] = entry
    end

    return loaded
end

--- Finds a package in the first registry that lists it.
---@param registries LoadedRegistry[] The registries in priority order.
---@param name string The package name.
---@return IndexEntry|nil entry The package's index entry, or `nil` if no registry lists it.
---@return LoadedRegistry|nil source The registry that lists it.
function registry.find(registries, name)
    for _, source in ipairs(registries) do
        local entry = source.packages[name]
        if entry then
            return entry, source
        end
    end

    return nil, nil
end

--- Parses the versions of an index entry, skipping any this client cannot read.
---@param entry IndexEntry The index entry.
---@return Version[] versions The versions from highest to lowest.
function registry.versions(entry)
    local versions = {}
    for _, text in ipairs(entry.versions or {}) do
        local version = semver.parse(text)
        if version then
            versions[#versions + 1] = version
        end
    end
    table.sort(versions, function(a, b) return b < a end)

    return versions
end

--- Downloads the manifest of a package version.
---@param source LoadedRegistry The registry listing the package.
---@param name string The package name.
---@param version string The version.
---@return table|nil manifest The manifest, or `nil` if it could not be downloaded.
---@return string|nil err The error message if it could not be downloaded.
function registry.fetchManifest(source, name, version)
    local manifest, err = net.getJSON(source.url .. "packages/" .. name .. "/" .. version .. ".json")
    if type(manifest) ~= "table" then
        return nil, err or ("the manifest of " .. name .. " " .. version .. " is damaged")
    end

    return manifest
end

--- Searches the packages of every registry by name, description, and tags.
---@param registries LoadedRegistry[] The registries in priority order.
---@param query string The words to search for, matched without case.
---@return { name: string, entry: IndexEntry, registry: string }[] results The matches, sorted by name, skipping names shadowed by a higher priority registry.
function registry.search(registries, query)
    -- Split the query into lowercase words
    local words = {}
    for word in query:lower():gmatch("%S+") do
        words[#words + 1] = word
    end

    local results, seen = {}, {}
    for _, source in ipairs(registries) do
        for name, entry in pairs(source.packages) do
            if not seen[name] then
                seen[name] = true

                -- Require every word somewhere in the searchable text
                local text = (name .. " " .. (entry.description or "") .. " " .. table.concat(entry.tags or {}, " ")):lower()
                local matches = true
                for _, word in ipairs(words) do
                    if not text:find(word, 1, true) then
                        matches = false
                        break
                    end
                end
                if matches then
                    results[#results + 1] = { name = name, entry = entry, registry = source.name }
                end
            end
        end
    end
    table.sort(results, function(a, b) return a.name < b.name end)

    return results
end

return registry
