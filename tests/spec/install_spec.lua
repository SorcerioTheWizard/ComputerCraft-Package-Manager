-- CCPM Install Spec
--
-- Tests for the one command installer, `install.lua`, using the real CCPM sources as the published package.

-- MARK: Imports
local fakeHttp = require("support.fake_http")
local fakeRegistry = require("support.fake_registry")
local files = require("ccpm.files")

-- MARK: Constants
local INSTALLER = "/repo/install.lua"
local ROOT = "/ccpm"
local HOOK = "/startup/00_ccpm.lua"

-- MARK: Functions
--- Collects CCPM's real files as install paths mapped to their contents.
---@param version string A version to embed, so versions can be told apart.
---@return table<string, string> contents The file contents keyed by install path.
local function realFiles(version)
    local contents = { ["bin/ccpm.lua"] = assert(files.read("/src/bin/ccpm.lua")) .. "\n-- " .. version .. "\n" }
    for _, name in ipairs(fs.list("/src/lib/ccpm")) do
        contents["lib/ccpm/" .. name] = assert(files.read(fs.combine("/src/lib/ccpm", name)))
    end

    return contents
end

--- Deletes everything the installer creates.
local function cleanUp()
    fs.delete(ROOT)
    fs.delete(HOOK)
    settings.unset("shell.package_path")
    settings.save()
    fakeHttp.restore()
end

-- MARK: Tests
describe("install.lua", function()
    local served

    beforeEach(function()
        cleanUp()
        served = fakeRegistry.new()
        served:add("ccpm", "0.1.0", { files = realFiles("0.1.0") })
        fakeHttp.install(served:allRoutes())
    end)

    afterEach(cleanUp)

    it("installs CCPM from the registry and sets up the computer", function()
        shell.run(INSTALLER, fakeRegistry.URL)

        -- Check the package
        local record = assert(files.readJSON(ROOT .. "/pkg/ccpm.json"))
        check.equals(record.version, "0.1.0")
        check.equals(record.explicit, true)
        check.equals(record.range, "*")
        check.truthy(fs.exists(ROOT .. "/bin/ccpm.lua"))
        check.truthy(fs.exists(ROOT .. "/lib/ccpm/cli.lua"))

        -- Check the computer
        check.truthy(fs.exists(HOOK))
        check.contains(settings.get("shell.package_path"), "/ccpm/lib/?.lua")
        check.falsy(fs.exists("/.ccpm-install"))

        -- Check it remembers the registry it came from
        local config = assert(files.readJSON(ROOT .. "/etc/config.json"))
        check.equals(config.registries[1].url, fakeRegistry.URL)
    end)

    it("upgrades an existing installation when run again", function()
        shell.run(INSTALLER, fakeRegistry.URL)

        served:add("ccpm", "0.2.0", { files = realFiles("0.2.0") })
        fakeHttp.install(served:allRoutes())
        shell.run(INSTALLER, fakeRegistry.URL)

        local record = assert(files.readJSON(ROOT .. "/pkg/ccpm.json"))
        check.equals(record.version, "0.2.0")
        check.equals(record.range, "*")
        check.contains(files.read(ROOT .. "/bin/ccpm.lua"), "-- 0.2.0")
    end)

    it("installs nothing when a file fails its hash check", function()
        served = fakeRegistry.new()
        served:add("ccpm", "0.1.0", { files = realFiles("0.1.0"), badHash = true })
        fakeHttp.install(served:allRoutes())

        shell.run(INSTALLER, fakeRegistry.URL)
        check.falsy(fs.exists(ROOT .. "/bin/ccpm.lua"))
        check.falsy(fs.exists(HOOK))
        check.falsy(fs.exists("/.ccpm-install"))
    end)
end)
