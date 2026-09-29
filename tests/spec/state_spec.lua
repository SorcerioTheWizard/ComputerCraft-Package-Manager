-- CCPM State Spec
--
-- Tests for `ccpm.state`.

-- MARK: Imports
local state = require("ccpm.state")
local sandbox = require("support.sandbox")

-- MARK: Functions
--- Builds an installed package record.
---@param name string The package name.
---@param extra table|nil Fields to override.
---@return InstalledPackage record The record.
local function record(name, extra)
    local base = {
        name = name,
        version = "1.0.0",
        registry = "ccpm",
        kind = "files",
        files = { { path = "bin/" .. name:gsub("/", "-") .. ".lua", sha256 = string.rep("a", 64) } },
        dependencies = {},
        explicit = true,
    }
    for key, value in pairs(extra or {}) do
        base[key] = value
    end

    return base
end

-- MARK: Tests
describe("state", function()
    sandbox.use()

    it("starts empty", function()
        check.same(state.list(), {})
        check.equals(state.get("tool"), nil)
    end)

    it("stores, lists, and removes records", function()
        state.put(record("zeta"))
        state.put(record("alpha"))
        state.put(record("pinestore/radar"))

        -- List every record sorted by name, including nested external names
        local names = {}
        for _, entry in ipairs(state.list()) do
            names[#names + 1] = entry.name
        end
        check.same(names, { "alpha", "pinestore/radar", "zeta" })
        check.same(state.get("alpha"), record("alpha"))

        -- Remove nested records and their emptied folder
        state.remove("pinestore/radar")
        check.equals(state.get("pinestore/radar"), nil)
        check.falsy(fs.exists("/sandbox/pkg/pinestore"))
    end)

    it("finds file owners and dependents", function()
        state.put(record("base"))
        state.put(record("tool", { dependencies = { base = "^1.0.0" } }))

        check.equals(state.findOwner("bin/base.lua"), "base")
        check.equals(state.findOwner("bin/nothing.lua"), nil)
        check.same(state.dependents("base"), { "tool" })
        check.same(state.dependents("tool"), {})
    end)
end)
