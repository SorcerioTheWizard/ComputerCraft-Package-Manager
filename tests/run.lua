-- CCPM Test Runner
--
-- Runs every spec under `/tests/spec` inside CraftOS-PC and writes the results to an output folder.

-- MARK: Constants
local SPEC_DIR = "/tests/spec"
local SPEC_SUFFIX = "_spec.lua"
local RESULTS_FILE = "results.txt"
local STATUS_FILE = "status"

-- MARK: Imports
-- Resolve the sources and test support before anything else
package.path = "/src/lib/?.lua;/src/lib/?/init.lua;/tests/?.lua;" .. package.path

local harness = require("harness")

-- MARK: Functions
--- Writes text to a file, replacing its contents.
---@param path string The file path.
---@param text string The text to write.
local function writeFile(path, text)
    local file = assert(fs.open(path, "w"))
    file.write(text)
    file.close()
end

--- Lists the spec files to run, sorted by name.
---@param filter string|nil A plain substring spec file names must contain.
---@return string[] paths The absolute paths of the specs.
local function findSpecs(filter)
    local paths = {}
    for _, name in ipairs(fs.list(SPEC_DIR)) do
        -- Keep matching spec files
        local isSpec = name:sub(-#SPEC_SUFFIX) == SPEC_SUFFIX
        if isSpec and (not filter or name:find(filter, 1, true)) then
            paths[#paths + 1] = fs.combine(SPEC_DIR, name)
        end
    end
    table.sort(paths)

    return paths
end

--- Formats test results as a report.
---@param results HarnessResults The results.
---@return string report The report text.
local function formatReport(results)
    -- List the failures
    local lines = {}
    for _, failure in ipairs(results.failures) do
        lines[#lines + 1] = "FAIL " .. failure.name
        lines[#lines + 1] = "     " .. failure.message
    end

    -- Add the summary
    lines[#lines + 1] = string.format("%d passed, %d failed", results.passed, #results.failures)

    return table.concat(lines, "\n") .. "\n"
end

-- MARK: Execution
local outDir, filter = ...
outDir = outDir or "/"

-- Run the specs, reporting a crash of the runner itself as a failure
local ok, err = pcall(function()
    for _, path in ipairs(findSpecs(filter)) do
        harness.loadSpec("/" .. path)
    end

    local results = harness.run()
    writeFile(fs.combine(outDir, RESULTS_FILE), formatReport(results))
    writeFile(fs.combine(outDir, STATUS_FILE), #results.failures == 0 and "pass" or "fail")
end)

if not ok then
    writeFile(fs.combine(outDir, RESULTS_FILE), "Test runner crashed: " .. tostring(err) .. "\n")
    writeFile(fs.combine(outDir, STATUS_FILE), "fail")
end
