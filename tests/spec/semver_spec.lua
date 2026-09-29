-- CCPM Semver Spec
--
-- Tests for `ccpm.semver`, mirroring the cases in the registry's `test_semver.py`.

-- MARK: Imports
local semver = require("ccpm.semver")

-- MARK: Constants
local RANGE_CASES = {
    { "*", { "0.0.1", "9.9.9" }, { "1.0.0-beta" } },
    { "", { "1.0.0" }, {} },
    { "1.2.3", { "1.2.3" }, { "1.2.4" } },
    { "=1.2.3", { "1.2.3" }, { "1.2.2" } },
    { "1.20", { "1.20.0", "1.20.6" }, { "1.19.9", "1.21.0" } },
    { "1", { "1.0.0", "1.99.0" }, { "2.0.0" } },
    { "^1.2.3", { "1.2.3", "1.9.0" }, { "1.2.2", "2.0.0" } },
    { "^0.2.3", { "0.2.3", "0.2.9" }, { "0.3.0" } },
    { "^0.0.3", { "0.0.3" }, { "0.0.4" } },
    { "^1.2", { "1.2.0", "1.9.9" }, { "2.0.0" } },
    { "^0.0", { "0.0.5" }, { "0.1.0" } },
    { "~1.2.3", { "1.2.3", "1.2.9" }, { "1.3.0" } },
    { "~1", { "1.5.0" }, { "2.0.0" } },
    { ">=1.19 <1.21", { "1.19.0", "1.20.4" }, { "1.18.2", "1.21.0" } },
    { ">1.2", { "1.3.0" }, { "1.2.9" } },
    { "<=1.2", { "1.2.9" }, { "1.3.0" } },
    { ">1.2.3", { "1.2.4" }, { "1.2.3" } },
    { "<1.2.3", { "1.2.2" }, { "1.2.3" } },
    { "1.2.3 || >=2.0.0", { "1.2.3", "2.5.0" }, { "1.5.0" } },
    { ">=1.0.0-beta.2 <2.0.0", { "1.0.0-beta.3", "1.0.0" }, { "1.0.0-beta.1", "1.1.0-beta.1" } },
}

-- MARK: Functions
--- Parses a version the test knows is valid.
---@param text string The version text.
---@return Version version The version.
local function v(text)
    return assert(semver.parse(text))
end

-- MARK: Tests
describe("semver.parse", function()
    it("parses versions", function()
        local version = v("1.0.0-beta.2")
        check.same({ version.major, version.minor, version.patch }, { 1, 0, 0 })
        check.same(version.prerelease, { "beta", "2" })
        check.equals(tostring(v("1.0.0-rc.1")), "1.0.0-rc.1")
    end)

    for _, text in ipairs({ "1.2", "01.2.3", "1.2.3+build", "v1.2.3", "1.2.3-", "" }) do
        it("rejects `" .. text .. "`", function()
            local version, err = semver.parse(text)
            check.equals(version, nil)
            check.contains(err, "is not a semantic version")
        end)
    end

    it("orders by semver precedence", function()
        local ordered = { "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0.1", "1.10.0", "2.0.0" }
        for i = 1, #ordered - 1 do
            check.truthy(v(ordered[i]) < v(ordered[i + 1]), ordered[i] .. " < " .. ordered[i + 1])
            check.falsy(v(ordered[i + 1]) <= v(ordered[i]), ordered[i + 1] .. " <= " .. ordered[i])
        end
        check.truthy(v("1.2.3") == v("1.2.3"))
    end)
end)

describe("semver.parseRange", function()
    for _, case in ipairs(RANGE_CASES) do
        local text, matching, failing = case[1], case[2], case[3]
        it("handles `" .. text .. "`", function()
            local range = assert(semver.parseRange(text))
            for _, version in ipairs(matching) do
                check.truthy(range:test(v(version)), version .. " should satisfy " .. text)
            end
            for _, version in ipairs(failing) do
                check.falsy(range:test(v(version)), version .. " should not satisfy " .. text)
            end
        end)
    end

    for _, text in ipairs({ "^", ">=x", "1.2.3.4", "^1.2.3 ~", "1.2.3 ||| 2" }) do
        it("rejects `" .. text .. "`", function()
            local range, err = semver.parseRange(text)
            check.equals(range, nil)
            check.contains(err, "is not a valid range")
        end)
    end

    it("picks the best version", function()
        local versions = { v("1.0.0"), v("1.4.0"), v("2.0.0"), v("1.5.0-beta") }
        check.equals(tostring(assert(semver.parseRange("^1.0.0")):best(versions)), "1.4.0")
        check.equals(assert(semver.parseRange("^3.0.0")):best(versions), nil)
    end)
end)

describe("semver.coerce", function()
    it("pads loose versions", function()
        check.equals(tostring(semver.coerce("1.20")), "1.20.0")
        check.equals(tostring(semver.coerce("1.20.1-pre1")), "1.20.1")
        check.equals(tostring(semver.coerce(" 1 ")), "1.0.0")
        check.equals(semver.coerce("v2"), nil)
    end)
end)
