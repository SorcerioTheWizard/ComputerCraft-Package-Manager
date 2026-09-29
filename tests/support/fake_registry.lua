-- CCPM Fake Registry
--
-- Builds a registry in memory and serves it, and its package files, through the fake `http` API.

-- MARK: Imports
local config = require("ccpm.config")
local fakeHttp = require("support.fake_http")
local semver = require("ccpm.semver")
local sha256 = require("ccpm.sha256")

-- MARK: Constants
local REGISTRY_URL = "https://registry.test/"
local FILE_HOST = "https://raw.githubusercontent.com/"

-- MARK: Classes
---@class FakeRegistry
---@field packages table<string, table<string, table>> Manifests keyed by name, then version.
---@field routes table<string, string|table> Extra responses, like file contents.
---@field hosts string[] The URL prefixes the registry allows.
local FakeRegistry = {}
FakeRegistry.__index = FakeRegistry

--- Adds a package version.
---@param name string The package name.
---@param version string The version.
---@param options { files: table<string, string>|nil, dependencies: table<string, string>|nil, compat: table|nil, startup: string|nil, kind: string|nil, badHash: boolean|nil, url: string|nil }|nil File contents keyed by install path, and manifest keys.
---@return FakeRegistry self The registry, for chaining.
function FakeRegistry:add(name, version, options)
    options = options or {}
    local contents = options.files or { ["bin/" .. name .. ".lua"] = "print(" .. string.format("%q", name .. " " .. version) .. ")" }

    -- Serve each file at a pinned URL
    local fileEntries = {}
    local paths = {}
    for path in pairs(contents) do
        paths[#paths + 1] = path
    end
    table.sort(paths)
    for _, path in ipairs(paths) do
        local url = options.url or (FILE_HOST .. "test/" .. name .. "/" .. version .. "/" .. path)
        self.routes[url] = contents[path]
        fileEntries[#fileEntries + 1] = { url = url, path = path, sha256 = options.badHash and string.rep("0", 64) or sha256.hex(contents[path]) }
    end

    self.packages[name] = self.packages[name] or {}
    self.packages[name][version] = {
        kind = options.kind or "files",
        files = fileEntries,
        dependencies = options.dependencies,
        compat = options.compat,
        startup = options.startup,
    }

    return self
end

--- Builds the responses serving the registry.
---@return table<string, string|table> routes Responses keyed by URL.
function FakeRegistry:allRoutes()
    local routes = {}
    for url, body in pairs(self.routes) do
        routes[url] = body
    end

    -- Build the index and manifests
    local index = { format = 1, hosts = self.hosts, packages = {} }
    for name, versions in pairs(self.packages) do
        local list = {}
        for version, manifest in pairs(versions) do
            list[#list + 1] = assert(semver.parse(version))
            routes[REGISTRY_URL .. "packages/" .. name .. "/" .. version .. ".json"] = textutils.serializeJSON(manifest)
        end
        table.sort(list, function(a, b) return b < a end)

        local texts = {}
        for i, version in ipairs(list) do
            texts[i] = tostring(version)
        end
        index.packages[name] = { description = "The " .. name .. " package.", author = "Tester", latest = texts[1], versions = texts }
    end
    routes[REGISTRY_URL .. "index.json"] = textutils.serializeJSON(index)

    return routes
end

--- Points CCPM at this registry and serves it. Call again after adding versions.
---@param blocked string[]|nil URL prefixes the fake server blocks.
function FakeRegistry:serve(blocked)
    config.save({ registries = { { name = "test", url = REGISTRY_URL } }, hosts = {} })
    fakeHttp.install(self:allRoutes(), blocked)
end

-- MARK: Functions
local fakeRegistry = {}

--- Creates an empty fake registry.
---@return FakeRegistry registry The registry.
function fakeRegistry.new()
    return setmetatable({ packages = {}, routes = {}, hosts = { FILE_HOST } }, FakeRegistry)
end

fakeRegistry.URL = REGISTRY_URL

return fakeRegistry
