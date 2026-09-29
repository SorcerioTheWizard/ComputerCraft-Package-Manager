-- CCPM Harness Spec
--
-- Tests for the assertions of the test harness itself.

-- MARK: Tests
describe("check", function()
    it("compares tables deeply", function()
        check.same({ a = { 1, 2 }, b = "x" }, { a = { 1, 2 }, b = "x" })
        check.errors(function() check.same({ a = 1 }, { a = 1, b = 2 }) end, "expected")
    end)

    it("matches error patterns", function()
        local err = check.errors(function() error("boom 42", 0) end, "boom %d+")
        check.equals(err, "boom 42")
        check.errors(function() check.errors(function() end) end, "none was raised")
    end)

    it("finds plain substrings", function()
        check.contains("a.b(c)", ".b(")
        check.errors(function() check.contains("abc", "z") end, "to contain")
    end)
end)

describe("hooks", function()
    local log = {}

    beforeEach(function()
        log[#log + 1] = "before"
    end)

    afterEach(function()
        log[#log + 1] = "after"
    end)

    it("runs the before hook first", function()
        check.equals(log[#log], "before")
    end)

    it("runs the after hook between tests", function()
        check.same(log, { "before", "after", "before" })
    end)
end)
