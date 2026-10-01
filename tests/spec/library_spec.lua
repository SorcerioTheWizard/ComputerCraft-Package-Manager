-- CCPM Library Spec
--
-- Tests for what programs get from `require("/ccpm/lib/ccpm")`.

-- MARK: Imports
local ccpm = require("ccpm")
local fakeRegistry = require("support.fake_registry")
local files = require("ccpm.files")
local installer = require("ccpm.installer")
local sandbox = require("support.sandbox")
local state = require("ccpm.state")
local ui = require("ccpm.ui")

-- MARK: Functions
--- Runs a function with captured output.
---@param answer boolean How to answer questions.
---@param fn function The function.
---@return boolean ok If the function succeeded.
---@return any result Its result or error.
---@return string output Everything printed.
local function captured(answer, fn)
    ui.startCapture(answer)
    local ok, result = pcall(fn)
    local texts = {}
    for i, line in ipairs(ui.stopCapture()) do
        texts[i] = line.text
    end

    return ok, result, table.concat(texts, "\n")
end

-- MARK: Tests
describe("ccpm.requires", function()
    sandbox.use()

    local served

    beforeEach(function()
        served = fakeRegistry.new()
        served:add("greeter", "1.0.0", { files = { ["lib/greeter.lua"] = "return { greet = function() return 'hi 1' end }" } })
        served:add("greeter", "2.0.0", { files = { ["lib/greeter/init.lua"] = "return { greet = function() return 'hi 2' end }" } })
        served:add("tool", "1.0.0")
        served:serve()
        package.loaded.greeter = nil
    end)

    it("asks, installs, and loads a missing library", function()
        local ok, greeter, output = captured(true, function() return ccpm.requires("greeter", "^2.0.0") end)
        check.truthy(ok, tostring(greeter))
        check.equals(greeter.greet(), "hi 2")
        check.contains(output, "This program needs packages CCPM will install:")
        check.contains(output, "+ greeter 2.0.0")

        -- Keep it installed for good, within the range asked for
        local record = assert(state.get("greeter"))
        check.equals(record.explicit, true)
        check.equals(record.range, "^2.0.0")
    end)

    it("loads installed libraries without asking", function()
        captured(true, function() ccpm.requires("greeter", "1") end)
        package.loaded.greeter = nil

        local ok, greeter, output = captured(false, function() return ccpm.requires("greeter", "^1.0.0") end)
        check.truthy(ok, tostring(greeter))
        check.equals(greeter.greet(), "hi 1")
        check.equals(output, "")
    end)

    it("upgrades an installed package that is too old", function()
        captured(true, function() ccpm.requires("greeter", "1") end)
        package.loaded.greeter = nil

        local ok, greeter, output = captured(true, function() return ccpm.requires("greeter", ">=2") end)
        check.truthy(ok, tostring(greeter))
        check.equals(greeter.greet(), "hi 2")
        check.contains(output, "~ greeter 1.0.0 -> 2.0.0")
    end)

    it("installs without asking when automatic", function()
        local ok, _, output = captured(false, function() return ccpm.requires("tool", nil, { auto = true }) end)
        check.truthy(ok)
        check.falsy(output:find("Continue?", 1, true))
    end)

    it("loads libraries named differently from their package", function()
        served:add("pinestore/pixel", "1.0.0", { files = { ["lib/pixel_lite.lua"] = "return { name = 'pixel lite' }" } })
        served:serve()
        package.loaded.pixel_lite = nil

        local ok, pixel = captured(true, function() return ccpm.requires("pinestore/pixel") end)
        check.truthy(ok, tostring(pixel))
        check.equals(pixel.name, "pixel lite")
    end)

    it("returns true for packages without a library", function()
        local ok, result = captured(true, function() return ccpm.requires("tool") end)
        check.truthy(ok)
        check.equals(result, true)
    end)

    it("fails at the caller when declined or impossible", function()
        local ok, err = captured(false, function()
            local greeter = ccpm.requires("greeter")
            return greeter
        end)
        check.falsy(ok)
        check.contains(err, "library_spec.lua")
        check.contains(err, "this program needs greeter *, which was not installed")
        check.equals(state.get("greeter"), nil)

        ok, err = captured(true, function() return ccpm.requires("missing") end)
        check.falsy(ok)
        check.contains(err, "`missing` was not found")
    end)
end)

describe("ccpm folders and versions", function()
    sandbox.use()

    it("creates data folders and finds shared assets", function()
        check.equals(ccpm.dataPath("tool"), "/sandbox/data/tool")
        check.truthy(fs.isDir("/sandbox/data/tool"))
        check.equals(ccpm.dataPath("tool", "settings.json"), "/sandbox/data/tool/settings.json")
        check.equals(ccpm.sharePath("tool", "icon.nfp"), "/sandbox/share/tool/icon.nfp")
        check.errors(function() ccpm.dataPath("../escape") end, "expected a name")
    end)

    it("reports installed versions and the environment", function()
        check.equals(ccpm.version(), nil)
        state.put({ name = "ccpm", version = "0.2.0", registry = "test", kind = "files", files = {}, dependencies = {}, explicit = true })
        check.equals(ccpm.version(), "0.2.0")
        check.equals(ccpm.installed("missing"), nil)
        check.equals(ccpm.env().kind, "computer")
    end)

    it("lets the calling program require installed libraries", function()
        check.contains(package.path, "/ccpm/lib/?.lua")
    end)
end)

describe("loading ccpm on CC: Tweaked", function()
    sandbox.use()

    it("loads by absolute path with CC: Tweaked's default require path, then finds installed libraries", function()
        -- Install CCPM's libraries and a library package where a computer would have them
        fs.copy("/src/lib/ccpm", "/sandbox/lib/ccpm")
        files.write("/sandbox/lib/pixel.lua", "return { name = 'pixel' }")

        -- Build a program environment the way CC: Tweaked's shell does, with its fixed default path
        local env = setmetatable({}, { __index = _ENV })
        env.require, env.package = require("cc.require").make(env, "/somewhere")
        env.package.path = "?;?.lua;?/init.lua;/rom/modules/main/?;/rom/modules/main/?.lua;/rom/modules/main/?/init.lua"

        -- Plain names fail, like they do on a real server
        check.falsy(pcall(env.require, "ccpm"))

        -- The absolute path works, and makes installed libraries requirable
        local ok, loaded = pcall(env.require, "/sandbox/lib/ccpm")
        check.truthy(ok, tostring(loaded))
        check.equals(type(loaded.requires), "function")
        check.equals(env.require("pixel").name, "pixel")
    end)
end)

describe("ccpm kiosk helpers", function()
    local original = os.pullEvent

    afterEach(function()
        ccpm.allowTerminate()
        os.pullEvent = original
        installer.setStartup("doorlock", nil)
    end)

    it("blocks and restores Ctrl+T", function()
        ccpm.preventTerminate()
        check.equals(os.pullEvent, os.pullEventRaw)
        ccpm.allowTerminate()
        check.equals(os.pullEvent, original)
    end)

    it("restores Ctrl+T after a protected function, even when it fails", function()
        local a, b = ccpm.withoutTerminate(function(x) return x, os.pullEvent == os.pullEventRaw end, 5)
        check.equals(a, 5)
        check.equals(b, true)
        check.equals(os.pullEvent, original)

        check.errors(function() ccpm.withoutTerminate(function() error("boom", 0) end) end, "boom")
        check.equals(os.pullEvent, original)
    end)

    it("registers and removes programs at boot", function()
        files.write("/doorlock.lua", "print('locked')")
        ccpm.runAtStartup("doorlock", "/doorlock.lua")
        check.contains(files.read(installer.startupPath("doorlock")), 'shell.run("/doorlock.lua")')

        ccpm.removeFromStartup("doorlock")
        check.falsy(fs.exists(installer.startupPath("doorlock")))
        check.errors(function() ccpm.runAtStartup("doorlock", "/missing.lua") end, "was not found")
        fs.delete("/doorlock.lua")
    end)
end)
