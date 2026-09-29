-- CCPM UI Spec
--
-- Tests for wrapping, tables, and colors in `ccpm.ui`.

-- MARK: Imports
local ui = require("ccpm.ui")

-- MARK: Functions
--- Captures what a function prints at a width.
---@param width integer The line width.
---@param fn function The function.
---@return string[] lines The printed lines.
local function captured(width, fn)
    ui.startCapture(true, width)
    local ok, err = pcall(fn)
    local lines = {}
    for i, line in ipairs(ui.stopCapture()) do
        lines[i] = line.text
    end
    assert(ok, err)

    return lines
end

-- MARK: Tests
describe("ui.line", function()
    it("wraps at word boundaries with a hanging indent", function()
        local lines = captured(20, function()
            ui.line({ { "  " }, { "Fast and modular 2D teletext rendering library" } }, 2)
        end)
        check.same(lines, { "  Fast and modular", "  2D teletext", "  rendering library" })
    end)

    it("keeps colored runs together and splits words longer than a line", function()
        local lines = captured(10, function()
            ui.line({ { "name", "name" }, { " 1.0.0", "dim" }, { " abcdefghijklmnop" } })
        end)
        check.same(lines, { "name 1.0.0", "abcdefghij", "klmnop" })
    end)

    it("cuts text off at a number of lines", function()
        local lines = captured(20, function()
            ui.line({ { "  " }, { "one two three four five six seven eight nine ten" } }, 2, 2)
        end)
        check.same(lines, { "  one two three four", "  five six seven..." })
    end)

    it("labels errors and warnings so they read without color", function()
        local lines = captured(80, function()
            ui.error("it broke")
            ui.warn("careful")
        end)
        check.same(lines, { "Error: it broke", "Warning: careful" })
    end)
end)

describe("ui.table", function()
    it("aligns columns and wraps the last one under itself", function()
        local lines = captured(40, function()
            ui.table({
                { { "Author" }, { "Tester and friends of the project" } },
                { { "Page" }, { "https://example.com/a/long/path" } },
            }, 2)
        end)
        check.same(lines, { "  Author  Tester and friends of the", "          project", "  Page    https://example.com/a/long/pat", "          h" })
    end)

    it("falls back to a short indent when the last column would start too far right", function()
        local lines = captured(24, function()
            ui.table({ { { "a-very-long-package-name" }, { "some words here" } } })
        end)
        check.equals(lines[2], "  some words here")
    end)
end)
