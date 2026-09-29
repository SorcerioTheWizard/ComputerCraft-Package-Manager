-- CCPM Resolver Spec
--
-- Tests for `ccpm.resolver` through `ccpm.manager`'s planning functions.

-- MARK: Imports
local fakeRegistry = require("support.fake_registry")
local manager = require("ccpm.manager")
local sandbox = require("support.sandbox")
local state = require("ccpm.state")

-- MARK: Functions
--- Summarizes a plan as `name@version` strings in order.
---@param plan Plan|nil The plan.
---@return string[] steps The summary.
local function summarize(plan)
    local steps = {}
    for _, step in ipairs(assert(plan).steps) do
        steps[#steps + 1] = step.name .. "@" .. step.version
    end

    return steps
end

--- Records a package as installed without touching its files.
---@param name string The package name.
---@param version string The version.
---@param extra table|nil Fields to override.
local function markInstalled(name, version, extra)
    local record = { name = name, version = version, registry = "test", kind = "files", files = {}, dependencies = {}, explicit = true }
    for key, value in pairs(extra or {}) do
        record[key] = value
    end
    state.put(record)
end

-- MARK: Tests
describe("resolver", function()
    sandbox.use()

    local served

    beforeEach(function()
        served = fakeRegistry.new()
    end)

    it("picks the highest satisfying version and orders dependencies first", function()
        served:add("base", "1.0.0"):add("base", "1.5.0"):add("base", "2.0.0")
        served:add("util", "1.0.0", { dependencies = { base = "^1.0.0" } })
        served:add("app", "1.0.0", { dependencies = { util = "*", base = ">=1.2" } })
        served:serve()

        check.same(summarize(manager.planInstall({ manager.parseSpec("app") })), { "base@1.5.0", "util@1.0.0", "app@1.0.0" })
    end)

    it("honors requested ranges and marks only requests as explicit", function()
        served:add("base", "1.0.0"):add("base", "2.0.0")
        served:add("app", "1.0.0", { dependencies = { base = "*" } })
        served:serve()

        local plan = assert(manager.planInstall({ manager.parseSpec("app"), manager.parseSpec("base@1") }))
        check.same(summarize(plan), { "base@1.0.0", "app@1.0.0" })
        check.equals(plan.steps[1].explicit, true)
        check.equals(plan.steps[1].range, "1")
        check.equals(plan.steps[2].explicit, true)
    end)

    it("keeps installed packages that satisfy their ranges", function()
        served:add("base", "1.0.0"):add("base", "1.1.0")
        served:add("app", "1.0.0", { dependencies = { base = "^1.0.0" } })
        served:serve()
        markInstalled("base", "1.0.0", { explicit = false })

        local plan = assert(manager.planInstall({ manager.parseSpec("app"), manager.parseSpec("base") }))
        check.same(summarize(plan), { "app@1.0.0" })
        check.same(plan.unchanged, { "base" })
    end)

    it("upgrades a kept dependency when a new version needs it", function()
        served:add("base", "1.0.0"):add("base", "2.0.0")
        served:add("app", "2.0.0", { dependencies = { base = "^2.0.0" } })
        served:serve()
        markInstalled("base", "1.0.0", { explicit = false })

        check.same(summarize(manager.planInstall({ manager.parseSpec("app") })), { "base@2.0.0", "app@2.0.0" })
    end)

    it("respects the ranges installed packages place on dependencies", function()
        served:add("base", "1.0.0"):add("base", "2.0.0")
        served:serve()
        markInstalled("base", "1.0.0")
        markInstalled("app", "1.0.0", { dependencies = { base = "^1.0.0" } })

        local plan, err = manager.planInstall({ manager.parseSpec("base@2") })
        check.equals(plan, nil)
        check.contains(err, "app@1.0.0 (^1.0.0)")
        check.contains(err, "you (2)")
    end)

    it("reports conflicts between new dependencies", function()
        served:add("base", "1.0.0"):add("base", "2.0.0")
        served:add("one", "1.0.0", { dependencies = { base = "^1.0.0" } })
        served:add("two", "1.0.0", { dependencies = { base = "^2.0.0" } })
        served:serve()

        local _, err = manager.planInstall({ manager.parseSpec("one"), manager.parseSpec("two") })
        check.contains(err, "base satisfies one@1.0.0 (^1.0.0), two@1.0.0 (^2.0.0)")
    end)

    it("reports missing packages and versions", function()
        served:add("base", "1.0.0")
        served:serve()

        local _, err = manager.planInstall({ manager.parseSpec("nothing") })
        check.contains(err, "`nothing` was not found")

        _, err = manager.planInstall({ manager.parseSpec("base@^2") })
        check.contains(err, "no version of base satisfies you (^2)")
    end)

    it("skips incompatible versions unless forced", function()
        served:add("tool", "1.0.0"):add("tool", "2.0.0", { compat = { cc = ">=99" } })
        served:serve()

        check.same(summarize(manager.planInstall({ manager.parseSpec("tool") })), { "tool@1.0.0" })

        local _, err = manager.planInstall({ manager.parseSpec("tool@2") })
        check.contains(err, "works on this computer (use --force")

        local plan = assert(manager.planInstall({ manager.parseSpec("tool@2") }, { force = true }))
        check.same(summarize(plan), { "tool@2.0.0" })
        check.contains(plan.steps[1].warnings[1], "needs ComputerCraft `>=99`")
    end)

    it("backtracks when a later dependency rules out an earlier choice", function()
        served:add("base", "1.0.0"):add("base", "1.5.0"):add("base", "2.0.0")
        served:add("zeta", "1.0.0", { dependencies = { base = "~1.0.0" } })
        served:add("app", "1.0.0", { dependencies = { base = "*", zeta = "*" } })
        served:serve()

        check.same(summarize(manager.planInstall({ manager.parseSpec("app") })), { "base@1.0.0", "zeta@1.0.0", "app@1.0.0" })
    end)

    it("handles dependency cycles", function()
        served:add("one", "1.0.0", { dependencies = { two = "*" } })
        served:add("two", "1.0.0", { dependencies = { one = "*" } })
        served:serve()

        check.same(summarize(manager.planInstall({ manager.parseSpec("one") })), { "two@1.0.0", "one@1.0.0" })
    end)

    it("plans updates within the installed ranges", function()
        served:add("tool", "1.0.0"):add("tool", "1.5.0"):add("tool", "2.0.0")
        served:add("other", "1.0.0")
        served:serve()
        markInstalled("tool", "1.0.0", { range = "^1.0.0" })
        markInstalled("other", "1.0.0")

        local plan = assert(manager.planUpdate(nil))
        check.same(summarize(plan), { "tool@1.5.0" })
        check.equals(plan.steps[1].previous.version, "1.0.0")

        local _, err = manager.planUpdate({ "missing" })
        check.contains(err, "missing is not installed")
    end)

    it("parses package arguments", function()
        check.same(manager.parseSpec("tool"), { name = "tool", range = "*" })
        check.same(manager.parseSpec("tool@^1.2"), { name = "tool", range = "^1.2" })
        check.same(manager.parseSpec("tool@"), { name = "tool", range = "*" })
        check.same(manager.parseSpec("pinestore/radar@1"), { name = "pinestore/radar", range = "1" })
    end)
end)
