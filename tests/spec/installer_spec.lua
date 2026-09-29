-- CCPM Installer Spec
--
-- Tests for `ccpm.installer` through `ccpm.manager`.

-- MARK: Imports
local fakeHttp = require("support.fake_http")
local fakeRegistry = require("support.fake_registry")
local files = require("ccpm.files")
local installer = require("ccpm.installer")
local manager = require("ccpm.manager")
local sandbox = require("support.sandbox")
local sha256 = require("ccpm.sha256")
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

    it("installs files without a published hash, refusing web pages", function()
        served:add("ext/live", "1.0.0", { files = { ["bin/live.lua"] = "print('live')" }, unhashed = true })
        served:add("ext/page", "1.0.0", { files = { ["bin/page.lua"] = "<html></html>" }, unhashed = true, webPage = true })
        served:serve()

        check.same(install("ext/live"), {})
        local record = assert(state.get("ext/live"))
        check.equals(record.files[1].sha256, sha256.hex("print('live')"))

        local _, err = install("ext/page")
        check.contains(err, "is a web page, not a file")
        check.falsy(fs.exists("/sandbox/bin/page.lua"))
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

    it("runs installers from the root folder and records them", function()
        files.write("/sandbox-setup.lua", 'local f = fs.open(shell.resolve("sandbox-marker.txt"), "w") f.write(shell.dir()) f.close()')
        served:add("ext/app", "2026.929.1", { command = "/sandbox-setup.lua" })
        served:serve()
        shell.setDir("sandbox")

        check.same(install("ext/app"), {})
        check.equals(shell.dir(), "sandbox")
        check.equals(files.read("/sandbox-marker.txt"), "")
        local record = assert(state.get("ext/app"))
        check.equals(record.kind, "installer")
        check.equals(record.command, "/sandbox-setup.lua")
        check.same(record.files, {})

        -- Leave its files in place when removed
        local removed, _, untracked = manager.remove({ "ext/app" })
        check.same(removed, { "ext/app" })
        check.same(untracked, { "ext/app" })
        check.truthy(fs.exists("/sandbox-marker.txt"))

        shell.setDir("")
        fs.delete("/sandbox-setup.lua")
        fs.delete("/sandbox-marker.txt")
    end)

    it("records nothing when an installer fails", function()
        served:add("ext/broken", "1.0.0", { command = "/sandbox-missing-installer.lua" })
        served:serve()

        local removed, err = install("ext/broken")
        check.equals(removed, nil)
        check.contains(err, "its installer `/sandbox-missing-installer.lua` failed")
        check.equals(state.get("ext/broken"), nil)
    end)

    it("lets external packages install single file libraries", function()
        served:add("ext/pixel", "1.0.0", { files = { ["lib/pixel_lite.lua"] = "return {}" } })
        served:add("native", "1.0.0", { files = { ["lib/pixel_lite.lua"] = "return {}" } })
        served:serve()

        check.same(install("ext/pixel"), {})
        check.truthy(fs.exists("/sandbox/lib/pixel_lite.lua"))

        local _, err = install("native")
        check.contains(err, "outside the folders native may install to")
    end)

    it("reports installs to the source a package was synced from", function()
        served:add("pinestore/radar", "1.0.0", { files = { ["bin/radar.lua"] = "print('radar')" }, origin = { source = "pinestore", id = "12", url = "https://pinestore.cc/projects/12/radar" } })
        served:add("plain", "1.0.0")
        served:serve()

        check.same(install("pinestore/radar", "plain"), {})
        local posts = fakeHttp.posts()
        check.equals(#posts, 1)
        check.equals(posts[1].url, "https://pinestore.cc/api/log/download")
        check.same(textutils.unserializeJSON(posts[1].body), { projectId = "12" })
        check.equals(posts[1].headers["Content-Type"], "application/json")
    end)
end)
