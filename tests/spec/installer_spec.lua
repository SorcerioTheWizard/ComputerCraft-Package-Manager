-- CCPM Installer Spec
--
-- Tests for `ccpm.installer` through `ccpm.manager`.

-- MARK: Imports
local fakeRegistry = require("support.fake_registry")
local files = require("ccpm.files")
local installer = require("ccpm.installer")
local manager = require("ccpm.manager")
local sandbox = require("support.sandbox")
local state = require("ccpm.state")

-- MARK: Functions
--- Plans and applies an install, failing the test if planning fails.
---@param ... string The package arguments.
---@return string[]|nil removed Orphans removed afterwards, or `nil` if applying failed.
---@return string|nil err The error message if applying failed.
local function install(...)
    local specs = {}
    for _, text in ipairs({ ... }) do
        specs[#specs + 1] = manager.parseSpec(text)
    end

    return manager.apply(assert(manager.planInstall(specs)))
end

--- Lists installed package names.
---@return string[] names The names.
local function installedNames()
    local names = {}
    for _, record in ipairs(state.list()) do
        names[#names + 1] = record.name .. "@" .. record.version
    end

    return names
end

-- MARK: Tests
describe("installer", function()
    sandbox.use()

    local served

    beforeEach(function()
        served = fakeRegistry.new()
    end)

    afterEach(function()
        for _, name in ipairs(fs.isDir("/startup") and fs.list("/startup") or {}) do
            if name:find("ccpm", 1, true) then
                fs.delete(fs.combine("/startup", name))
            end
        end
    end)

    it("installs files and records them", function()
        served:add("lib-a", "1.0.0", { files = { ["lib/lib-a/init.lua"] = "return 1", ["share/lib-a/icon.nfp"] = "f" } })
        served:add("app", "1.0.0", { dependencies = { ["lib-a"] = "*" } })
        served:serve()

        check.same(install("app"), {})
        check.equals(files.read("/sandbox/bin/app.lua"), 'print("app 1.0.0")')
        check.equals(files.read("/sandbox/lib/lib-a/init.lua"), "return 1")
        check.truthy(fs.exists("/sandbox/share/lib-a/icon.nfp"))

        local record = assert(state.get("lib-a"))
        check.equals(record.explicit, false)
        check.equals(#record.files, 2)
        check.equals(assert(state.get("app")).explicit, true)
    end)

    it("replaces files and removes the ones a new version dropped", function()
        served:add("app", "1.0.0", { files = { ["bin/app.lua"] = "v1", ["bin/app-old.lua"] = "old" } })
        served:serve()
        install("app")

        served:add("app", "2.0.0", { files = { ["bin/app.lua"] = "v2" } })
        served:serve()
        manager.apply(assert(manager.planUpdate(nil)))

        check.equals(files.read("/sandbox/bin/app.lua"), "v2")
        check.falsy(fs.exists("/sandbox/bin/app-old.lua"))
        check.same(installedNames(), { "app@2.0.0" })
    end)

    it("removes dependencies a new version dropped", function()
        served:add("helper", "1.0.0")
        served:add("app", "1.0.0", { dependencies = { helper = "*" } })
        served:serve()
        install("app")

        served:add("app", "2.0.0")
        served:serve()
        check.same(manager.apply(assert(manager.planUpdate({ "app" }))), { "helper" })
        check.same(installedNames(), { "app@2.0.0" })
    end)

    it("changes nothing when any file fails its checks", function()
        served:add("good", "1.0.0")
        served:add("bad", "1.0.0", { badHash = true })
        served:serve()

        local removed, err = install("good", "bad")
        check.equals(removed, nil)
        check.contains(err, "does not match its recorded hash")
        check.falsy(fs.exists("/sandbox/bin/good.lua"))
        check.same(state.list(), {})
    end)

    it("refuses unsafe paths and disallowed hosts", function()
        served:add("sneaky", "1.0.0", { files = { ["lib/other.lua"] = "x" } })
        served:add("escape", "1.0.0", { files = { ["bin/../../startup.lua"] = "x" } })
        served:add("offsite", "1.0.0", { url = "https://example.com/offsite.lua" })
        served:serve()

        local _, err = install("sneaky")
        check.contains(err, "outside the folders sneaky may install to")
        _, err = install("escape")
        check.contains(err, "not a safe install path")
        _, err = install("offsite")
        check.contains(err, "not on an allowed host")
    end)

    it("refuses files owned by other packages or not managed by CCPM", function()
        served:add("one", "1.0.0", { files = { ["bin/shared.lua"] = "one" } })
        served:add("two", "1.0.0", { files = { ["bin/shared.lua"] = "two" } })
        served:add("three", "1.0.0")
        served:serve()
        install("one")

        local _, err = install("two")
        check.contains(err, "which belongs to one")

        files.write("/sandbox/bin/three.lua", "mine")
        _, err = install("three")
        check.contains(err, "not managed by CCPM")
        check.truthy(manager.apply(assert(manager.planInstall({ manager.parseSpec("three") })), true))
    end)

    it("manages boot files", function()
        served:add("doorlock", "1.0.0", { startup = "bin/doorlock.lua" })
        served:serve()
        install("doorlock")

        local stub = files.read(installer.startupPath("doorlock"))
        check.contains(stub, 'shell.run("/sandbox/bin/doorlock.lua")')

        manager.remove({ "doorlock" })
        check.falsy(fs.exists(installer.startupPath("doorlock")))
    end)

    it("removes packages, refusing to break dependents unless cascading", function()
        served:add("helper", "1.0.0", { files = { ["lib/helper/init.lua"] = "return {}" } })
        served:add("app", "1.0.0", { dependencies = { helper = "*" } })
        served:add("solo", "1.0.0")
        served:serve()
        install("app", "solo")

        -- Refuse to break the dependent
        local removed, err = manager.remove({ "helper" })
        check.equals(removed, nil)
        check.contains(err, "helper is needed by app (use --cascade")

        -- Remove the app and its now unneeded dependency
        check.same(manager.remove({ "app" }), { "app", "helper" })
        check.falsy(fs.exists("/sandbox/bin/app.lua"))
        check.falsy(fs.exists("/sandbox/lib/helper"))
        check.truthy(fs.exists("/sandbox/lib"))
        check.same(installedNames(), { "solo@1.0.0" })

        _, err = manager.remove({ "app" })
        check.contains(err, "app is not installed")
    end)

    it("cascades removals to dependents", function()
        served:add("helper", "1.0.0")
        served:add("app", "1.0.0", { dependencies = { helper = "*" } })
        served:serve()
        install("app")
        state.put((function()
            local record = assert(state.get("helper"))
            record.explicit = true
            return record
        end)())

        check.same(manager.remove({ "helper" }, true), { "helper", "app" })
        check.same(state.list(), {})
    end)

    it("refuses kinds it cannot install yet", function()
        served:add("script", "1.0.0", { kind = "installer" })
        served:serve()

        local _, err = install("script")
        check.contains(err, "cannot install")
    end)
end)
