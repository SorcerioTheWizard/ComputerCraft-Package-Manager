-- CCPM Environment Spec
--
-- Tests for `ccpm.env`.

-- MARK: Imports
local env = require("ccpm.env")

-- MARK: Constants
local IN_GAME = env.parse("ComputerCraft 1.93.0 (Minecraft 1.15.2)")
local EMULATOR = env.parse("ComputerCraft 1.112.0 (CraftOS-PC v2.8.3)")

-- MARK: Tests
describe("env.parse", function()
    it("reads versions in Minecraft", function()
        check.equals(tostring(IN_GAME.cc), "1.93.0")
        check.equals(tostring(IN_GAME.mc), "1.15.2")
        check.equals(IN_GAME.platform, "Minecraft")
    end)

    it("reads emulators without a Minecraft version", function()
        check.equals(tostring(EMULATOR.cc), "1.112.0")
        check.equals(EMULATOR.mc, nil)
        check.equals(EMULATOR.platform, "CraftOS-PC v2.8.3")
    end)

    it("tolerates unknown hosts", function()
        local unknown = env.parse("")
        check.equals(unknown.cc, nil)
        check.equals(unknown.platform, "unknown")
    end)
end)

describe("env.current", function()
    it("describes this computer", function()
        local current = env.current()
        check.equals(current.host, _HOST)
        check.equals(current.kind, "computer")
        check.equals(type(current.color), "boolean")
    end)
end)

describe("env.checkCompat", function()
    it("passes matching and missing ranges", function()
        local errors, warnings = env.checkCompat({ cc = ">=1.90", mc = "1.15" }, IN_GAME)
        check.same(errors, {})
        check.same(warnings, {})

        errors, warnings = env.checkCompat(nil, IN_GAME)
        check.same(errors, {})
        check.same(warnings, {})
    end)

    it("fails ranges that do not match", function()
        local errors = env.checkCompat({ cc = ">=1.100", mc = ">=1.19" }, IN_GAME)
        check.equals(#errors, 2)
        check.contains(errors[1], "needs ComputerCraft `>=1.100`, but this computer runs 1.93.0")
        check.contains(errors[2], "needs Minecraft `>=1.19`")
    end)

    it("warns about unknown versions and unreadable ranges", function()
        local errors, warnings = env.checkCompat({ cc = "not a range", mc = "1.20" }, EMULATOR)
        check.same(errors, {})
        check.equals(#warnings, 2)
        check.contains(warnings[1], "unreadable ComputerCraft range")
        check.contains(warnings[2], "Minecraft version is unknown (CraftOS-PC v2.8.3)")
    end)
end)
