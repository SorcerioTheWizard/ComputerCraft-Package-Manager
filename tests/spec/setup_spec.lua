-- CCPM Setup Spec
--
-- Tests for `ccpm.setup` and `ccpm.completion`.

-- MARK: Imports
local cliRunner = require("support.cli_runner")
local completion = require("ccpm.completion")
local fakeRegistry = require("support.fake_registry")
local files = require("ccpm.files")
local sandbox = require("support.sandbox")
local setup = require("ccpm.setup")

-- MARK: Tests
describe("setup", function()
    sandbox.use()

    afterEach(function()
        setup.uninstall()
    end)

    it("installs the hook and the require path once", function()
        local fakeShell = cliRunner.fakeShell()
        setup.install(fakeShell)
        setup.install(fakeShell)

        -- Check the computer
        check.truthy(setup.isHookInstalled())
        check.truthy(setup.isPackagePathConfigured())
        local packagePath = settings.get("shell.package_path")
        local _, count = packagePath:gsub("/sandbox/lib/%?%.lua", "")
        check.equals(count, 1)

        -- Check the running shell
        check.equals(fakeShell.currentPath, ".:/rom/programs:/sandbox/bin")
        check.truthy(fakeShell.completions["sandbox/bin/ccpm.lua"])
    end)

    it("writes a hook that sets up a shell at boot", function()
        setup.install(nil)

        -- Run the hook against a fake shell
        local fakeShell = cliRunner.fakeShell()
        local env = setmetatable({ shell = fakeShell, package = { path = "" } }, { __index = _ENV })
        local hook = assert(load(assert(files.read(setup.hookPath())), "hook", "t", env))
        env.require = require
        hook()

        check.equals(fakeShell.currentPath, ".:/rom/programs:/sandbox/bin")
        check.contains(env.package.path, "/sandbox/lib/?.lua")
        check.truthy(fakeShell.completions["sandbox/bin/ccpm.lua"])
    end)

    it("uninstalls cleanly", function()
        setup.install(nil)
        setup.uninstall()

        check.falsy(fs.exists(setup.hookPath()))
        check.falsy(setup.isPackagePathConfigured())
    end)

    it("notices an outdated hook", function()
        setup.install(nil)
        files.write(setup.hookPath(), "-- old")
        check.falsy(setup.isHookInstalled())
    end)
end)

describe("completion", function()
    sandbox.use()

    beforeEach(function()
        local served = fakeRegistry.new()
        served:add("alpha", "1.0.0"):add("alpine", "1.0.0")
        served:serve()
        cliRunner.run({ "install", "alpha", "-y" })
    end)

    it("completes commands, subcommands, and flags", function()
        check.same(completion.complete(nil, 1, "inst", { "ccpm" }), { "all " })
        check.same(completion.complete(nil, 2, "a", { "ccpm", "hosts" }), { "dd " })
        check.same(completion.complete(nil, 3, "x", { "ccpm", "hosts", "add" }), {})
        check.same(completion.complete(nil, 2, "--c", { "ccpm", "remove" }), { "ascade " })
        check.same(completion.complete(nil, 2, "up", { "ccpm", "help" }), { "date", "grade" })
    end)

    it("completes installed and available packages", function()
        check.same(completion.complete(nil, 2, "al", { "ccpm", "remove" }), { "pha " })
        check.same(completion.complete(nil, 2, "al", { "ccpm", "install" }), { "pha ", "pine " })
        check.same(completion.complete(nil, 2, "al", { "ccpm", "nonsense" }), {})
    end)
end)
