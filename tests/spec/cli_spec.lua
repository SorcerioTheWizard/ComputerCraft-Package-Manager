-- CCPM CLI Spec
--
-- Tests for the commands in `ccpm.cli`.

-- MARK: Imports
local cliRunner = require("support.cli_runner")
local config = require("ccpm.config")
local fakeRegistry = require("support.fake_registry")
local files = require("ccpm.files")
local sandbox = require("support.sandbox")
local setup = require("ccpm.setup")
local state = require("ccpm.state")

-- MARK: Constants
local run = cliRunner.run

-- MARK: Tests
describe("cli", function()
    sandbox.use()

    local served

    beforeEach(function()
        served = fakeRegistry.new()
        served:add("base", "1.0.0"):add("base", "1.1.0")
        served:add("app", "1.0.0", { dependencies = { base = "^1.0.0" } })
        served:serve()
    end)

    afterEach(function()
        setup.uninstall()
    end)

    describe("help", function()
        it("lists commands without arguments", function()
            local ok, output = run({})
            check.truthy(ok)
            check.contains(output, "Usage: ccpm <command>")
            check.contains(output, "  install   Install packages and what they need.")
        end)

        it("shows usage for bad arguments and unknown flags", function()
            local ok, output = run({ "install" })
            check.falsy(ok)
            check.contains(output, "Usage: ccpm install <package>[@<range>] ...")

            ok, output = run({ "list", "--bogus" })
            check.falsy(ok)
            check.contains(output, "`list` does not understand `--bogus`")

            ok, output = run({ "nonsense" })
            check.falsy(ok)
            check.contains(output, "Usage: ccpm <command>")
        end)

        it("describes one command", function()
            local _, output = run({ "help", "remove" })
            check.contains(output, "Usage: ccpm remove <package> ...")
            check.contains(output, "--cascade, --yes")
        end)
    end)

    describe("install", function()
        it("shows the plan, asks, and installs", function()
            local ok, output = run({ "install", "app" })
            check.truthy(ok, output)
            check.contains(output, "  + base 1.1.0 dependency")
            check.contains(output, "+ app 1.0.0")
            check.contains(output, "Continue? [Y/n] y")
            check.contains(output, "Installed 2 packages.")
            check.truthy(fs.exists("/sandbox/bin/app.lua"))
        end)

        it("does nothing when declined", function()
            local ok, output = run({ "install", "app" }, { answer = false })
            check.falsy(ok)
            check.contains(output, "Cancelled.")
            check.same(state.list(), {})
        end)

        it("skips the question with --yes and reports errors", function()
            local ok, output = run({ "install", "base", "-y" })
            check.truthy(ok)
            check.falsy(output:find("Continue?", 1, true))

            ok, output = run({ "install", "missing" })
            check.falsy(ok)
            check.contains(output, "`missing` was not found")
        end)

        it("marks dependencies asked for by name as explicit", function()
            run({ "install", "app", "-y" })
            check.equals(assert(state.get("base")).explicit, false)

            local _, output = run({ "install", "base" })
            check.contains(output, "base 1.1.0 is already installed.")
            check.equals(assert(state.get("base")).explicit, true)
        end)
    end)

    describe("installers", function()
        it("warn before running and after removing", function()
            files.write("/sandbox-setup.lua", "-- installs nothing")
            served:add("ext/app", "1.0.0", { command = "/sandbox-setup.lua", origin = { source = "pinestore", id = "5", url = "https://pinestore.cc/projects/5/app" } })
            served:serve()

            local ok, output = run({ "install", "ext/app", "-y" })
            check.truthy(ok, output)
            check.contains(output, "! runs `/sandbox-setup.lua`, which CCPM cannot check")

            served:add("ext/live", "1.0.0", { files = { ["bin/live.lua"] = "print('live')" }, unhashed = true })
            served:serve()
            _, output = run({ "install", "ext/live", "-y" })
            check.contains(output, "! files are not verified against a published hash")

            _, output = run({ "info", "ext/app" })
            check.contains(output, "  Source     pinestore")
            check.contains(output, "  Page       https://pinestore.cc/projects/5/app")

            _, output = run({ "remove", "ext/app", "-y" })
            check.contains(output, "ext/app was installed by its own installer, so the files it created were left in place.")
            fs.delete("/sandbox-setup.lua")
        end)
    end)

    describe("remove", function()
        it("removes packages and unneeded dependencies", function()
            run({ "install", "app", "-y" })
            local ok, output = run({ "remove", "app" })
            check.truthy(ok)
            check.contains(output, "Removed app, base.")
        end)

        it("refuses to break dependents or remove CCPM", function()
            run({ "install", "app", "-y" })
            local ok, output = run({ "remove", "base", "-y" })
            check.falsy(ok)
            check.contains(output, "--cascade")

            ok, output = run({ "remove", "ccpm" })
            check.falsy(ok)
            check.contains(output, "CCPM cannot remove itself")
        end)
    end)

    describe("update and list", function()
        it("updates packages and lists outdated ones", function()
            run({ "install", "base@1.0.0", "-y" })

            -- Allow updates past the exact version that was asked for
            local record = assert(state.get("base"))
            record.range = "^1.0.0"
            state.put(record)

            local _, output = run({ "list", "--outdated" })
            check.contains(output, "base  1.0.0 -> 1.1.0")

            local ok
            ok, output = run({ "update", "-y" })
            check.truthy(ok, output)
            check.contains(output, "~ base 1.0.0 -> 1.1.0")

            _, output = run({ "update" })
            check.contains(output, "Everything is up to date.")

            _, output = run({ "list" })
            check.contains(output, "base  1.1.0")
        end)

        it("explains an empty computer", function()
            local _, output = run({ "list" })
            check.contains(output, "No packages are installed.")
        end)
    end)

    describe("upgrade", function()
        it("requires CCPM to come from a registry", function()
            local ok, output = run({ "upgrade" })
            check.falsy(ok)
            check.contains(output, "cannot upgrade itself")
        end)

        it("updates CCPM and reruns setup with the new version", function()
            served:add("ccpm", "1.0.0"):add("ccpm", "1.1.0")
            served:serve()
            run({ "install", "ccpm@1.0.0", "-y" })
            local record = assert(state.get("ccpm"))
            record.range = "*"
            state.put(record)

            local fakeShell = cliRunner.fakeShell()
            local ok = run({ "upgrade", "-y" }, { shell = fakeShell })
            check.truthy(ok)
            check.equals(assert(state.get("ccpm")).version, "1.1.0")
            check.same(fakeShell.runs, { { "/sandbox/bin/ccpm.lua", "setup" } })
        end)
    end)

    describe("search and info", function()
        it("searches the registries", function()
            local ok, output = run({ "search", "app" })
            check.truthy(ok)
            check.contains(output, "app 1.0.0")
            check.contains(output, "The app package.")

            _, output = run({ "search", "zzz" })
            check.contains(output, "No packages match.")
        end)

        it("describes packages", function()
            local ok, output = run({ "info", "base" })
            check.truthy(ok)
            check.contains(output, "  Author     Tester")
            check.contains(output, "  Versions   1.1.0, 1.0.0")
            check.contains(output, "  Installed  no")

            ok = run({ "info", "missing" })
            check.falsy(ok)
        end)
    end)

    describe("hosts", function()
        it("adds, lists, and removes hosts", function()
            run({ "refresh" })
            check.truthy(run({ "hosts", "add", "https://example.com/" }))
            check.same(config.load().hosts, { "https://example.com/" })

            local _, output = run({ "hosts" })
            check.contains(output, "https://raw.githubusercontent.com/")
            check.contains(output, "https://example.com/")

            check.truthy(run({ "hosts", "remove", "https://example.com/" }))
            check.same(config.load().hosts, {})
        end)

        it("rejects bad hosts", function()
            local ok, output = run({ "hosts", "add", "example.com" })
            check.falsy(ok)
            check.contains(output, "must be a URL prefix")

            ok, output = run({ "hosts", "remove", "https://raw.githubusercontent.com/" })
            check.falsy(ok)
            check.contains(output, "cannot be removed")

            ok, output = run({ "hosts", "add" })
            check.falsy(ok)
            check.contains(output, "Usage: ccpm hosts")
        end)
    end)

    describe("registry", function()
        it("adds registries only when they load", function()
            local ok, output = run({ "registry", "add", "other", "https://registry.test" })
            check.truthy(ok, output)
            check.contains(output, "with 2 packages.")
            check.equals(config.load().registries[2].url, "https://registry.test/")

            ok, output = run({ "registry", "add", "broken", "https://nowhere.test/" })
            check.falsy(ok)
            check.contains(output, "could not be loaded")

            _, output = run({ "registry", "list" })
            check.contains(output, "2.  other")

            check.truthy(run({ "registry", "remove", "other" }))
            check.equals(#config.load().registries, 1)
        end)
    end)

    describe("doctor", function()
        it("reports problems with setup and files", function()
            run({ "install", "app", "-y" })

            local ok, output = run({ "doctor" })
            check.falsy(ok)
            check.contains(output, "boot hook is missing")

            run({ "setup" })
            ok, output = run({ "doctor" })
            check.truthy(ok, output)
            check.contains(output, "No problems found.")

            files.write("/sandbox/bin/base.lua", "edited")
            fs.delete("/sandbox/bin/app.lua")
            ok, output = run({ "doctor" })
            check.falsy(ok)
            check.contains(output, "`bin/base.lua` was changed")
            check.contains(output, "`bin/app.lua` is missing")
        end)
    end)

    describe("env", function()
        it("shows the detected versions", function()
            local ok, output = run({ "env" })
            check.truthy(ok)
            check.contains(output, "ComputerCraft  1.")
            check.contains(output, "Minecraft      unknown, running on CraftOS-PC")
        end)
    end)
end)
