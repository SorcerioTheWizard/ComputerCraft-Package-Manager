-- CCPM Test Harness
--
-- A minimal `describe`/`it` test framework with assertions for specs run inside CraftOS-PC.

-- MARK: Constants
local SUITE_SEPARATOR = " > "

-- MARK: State
---@class HarnessSuite
---@field name string
---@field tests { name: string, fn: function }[]
---@field children HarnessSuite[]
---@field beforeEach function[]
---@field afterEach function[]
---@field parent HarnessSuite|nil

---@type HarnessSuite
local rootSuite = { name = "", tests = {}, children = {}, beforeEach = {}, afterEach = {} }

---@type HarnessSuite
local currentSuite = rootSuite

-- MARK: Private Functions
--- Renders a value as readable text for assertion messages.
---@param value any The value to render.
---@return string text The rendered value.
local function describeValue(value)
    -- Serialize tables so their contents are visible
    if type(value) == "table" then
        local ok, text = pcall(textutils.serialize, value, { compact = true })
        if ok then
            return text
        end
    end

    -- Quote strings so whitespace differences are visible
    if type(value) == "string" then
        return string.format("%q", value)
    end

    return tostring(value)
end

--- Checks if two values are deeply equal.
---@param a any The first value.
---@param b any The second value.
---@return boolean equal If the values are deeply equal.
local function deepEquals(a, b)
    -- Compare non-tables directly
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end

    -- Check every key of `a` against `b`
    for key, value in pairs(a) do
        if not deepEquals(value, b[key]) then
            return false
        end
    end

    -- Check `b` has no extra keys
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end

    return true
end

--- Raises an assertion failure pointing at the spec line that called the assertion.
---@param message string The failure message.
---@param custom string|nil An optional message from the spec.
local function fail(message, custom)
    -- Prefix the spec's own message
    if custom then
        message = custom .. ": " .. message
    end

    -- Level 3 skips `fail` and the assertion function
    error(message, 3)
end

--- Collects the hooks of a suite and all of its parents in outermost-first order.
---@param suite HarnessSuite The innermost suite.
---@param field "beforeEach"|"afterEach" The hook list to collect.
---@return function[] hooks The collected hooks.
local function collectHooks(suite, field)
    -- Walk up the chain
    local chain = {}
    while suite do
        table.insert(chain, 1, suite)
        suite = suite.parent
    end

    -- Flatten the hooks
    local hooks = {}
    for _, entry in ipairs(chain) do
        for _, hook in ipairs(entry[field]) do
            hooks[#hooks + 1] = hook
        end
    end

    return hooks
end

--- Runs a single test with its hooks.
---@param suite HarnessSuite The suite containing the test.
---@param test { name: string, fn: function } The test to run.
---@return boolean ok If the test passed.
---@return string|nil err The failure message if it failed.
local function runTest(suite, test)
    -- Run the before hooks and the test
    local ok, err = pcall(function()
        for _, hook in ipairs(collectHooks(suite, "beforeEach")) do
            hook()
        end
        test.fn()
    end)

    -- Always run the after hooks, innermost first
    local afterHooks = collectHooks(suite, "afterEach")
    for i = #afterHooks, 1, -1 do
        local hookOk, hookErr = pcall(afterHooks[i])
        if ok and not hookOk then
            ok, err = false, hookErr
        end
    end

    return ok, err and tostring(err) or nil
end

--- Runs a suite and its children, recording results.
---@param suite HarnessSuite The suite to run.
---@param prefix string The full name of the parent suites.
---@param results HarnessResults The results to record into.
local function runSuite(suite, prefix, results)
    -- Build this suite's full name
    local fullName = prefix
    if suite.name ~= "" then
        fullName = (prefix == "") and suite.name or (prefix .. SUITE_SEPARATOR .. suite.name)
    end

    -- Run the tests
    for _, test in ipairs(suite.tests) do
        local ok, err = runTest(suite, test)
        local testName = (fullName == "") and test.name or (fullName .. SUITE_SEPARATOR .. test.name)
        if ok then
            results.passed = results.passed + 1
        else
            results.failures[#results.failures + 1] = { name = testName, message = err or "unknown error" }
        end
    end

    -- Run the children
    for _, child in ipairs(suite.children) do
        runSuite(child, fullName, results)
    end
end

-- MARK: Functions
local harness = {}

--- Declares a group of tests.
---@param name string The name of the group.
---@param fn function The function declaring the group's tests.
function harness.describe(name, fn)
    -- Create the child suite
    local suite = { name = name, tests = {}, children = {}, beforeEach = {}, afterEach = {}, parent = currentSuite }
    currentSuite.children[#currentSuite.children + 1] = suite

    -- Collect its contents
    local previous = currentSuite
    currentSuite = suite
    fn()
    currentSuite = previous
end

--- Declares a single test.
---@param name string The name of the test.
---@param fn function The test body.
function harness.it(name, fn)
    currentSuite.tests[#currentSuite.tests + 1] = { name = name, fn = fn }
end

--- Registers a function to run before each test in the current group.
---@param fn function The hook.
function harness.beforeEach(fn)
    currentSuite.beforeEach[#currentSuite.beforeEach + 1] = fn
end

--- Registers a function to run after each test in the current group, even when the test fails.
---@param fn function The hook.
function harness.afterEach(fn)
    currentSuite.afterEach[#currentSuite.afterEach + 1] = fn
end

--- Loads a spec file into its own top level suite.
---@param path string The absolute path of the spec file.
function harness.loadSpec(path)
    -- Give the spec the harness globals on top of the normal environment
    local env = setmetatable({
        describe = harness.describe,
        it = harness.it,
        beforeEach = harness.beforeEach,
        afterEach = harness.afterEach,
        check = harness.check,
    }, { __index = _ENV })

    -- Load the spec as its own suite
    local fn, err = loadfile(path, nil, env)
    harness.describe(fs.getName(path), function()
        if not fn then
            harness.it("loads", function() error(err, 0) end)
            return
        end

        -- Report errors raised while declaring tests as a failing test
        local ok, declareErr = pcall(fn)
        if not ok then
            harness.it("declares", function() error(declareErr, 0) end)
        end
    end)
end

---@class HarnessResults
---@field passed integer
---@field failures { name: string, message: string }[]

--- Runs all declared tests.
---@return HarnessResults results The results of the run.
function harness.run()
    local results = { passed = 0, failures = {} }
    runSuite(rootSuite, "", results)
    return results
end

-- MARK: Assertions
harness.check = {}

--- Asserts that two values are equal with `==`.
---@param actual any The actual value.
---@param expected any The expected value.
---@param message string|nil An optional message.
function harness.check.equals(actual, expected, message)
    if actual ~= expected then
        fail("expected " .. describeValue(expected) .. ", got " .. describeValue(actual), message)
    end
end

--- Asserts that two values are deeply equal.
---@param actual any The actual value.
---@param expected any The expected value.
---@param message string|nil An optional message.
function harness.check.same(actual, expected, message)
    if not deepEquals(actual, expected) then
        fail("expected " .. describeValue(expected) .. ", got " .. describeValue(actual), message)
    end
end

--- Asserts that a value is truthy.
---@param value any The value.
---@param message string|nil An optional message.
function harness.check.truthy(value, message)
    if not value then
        fail("expected a truthy value, got " .. describeValue(value), message)
    end
end

--- Asserts that a value is falsy.
---@param value any The value.
---@param message string|nil An optional message.
function harness.check.falsy(value, message)
    if value then
        fail("expected a falsy value, got " .. describeValue(value), message)
    end
end

--- Asserts that a function raises an error, optionally matching a Lua pattern.
---@param fn function The function to call.
---@param pattern string|nil A Lua pattern the error message must match.
---@param message string|nil An optional message.
---@return string err The raised error message.
function harness.check.errors(fn, pattern, message)
    -- Call the function
    local ok, err = pcall(fn)
    if ok then
        fail("expected an error, but none was raised", message)
    end

    -- Match the message
    err = tostring(err)
    if pattern and not err:find(pattern) then
        fail("expected an error matching " .. describeValue(pattern) .. ", got " .. describeValue(err), message)
    end

    return err
end

--- Asserts that a string contains a plain substring.
---@param text string The text to search.
---@param part string The substring to find.
---@param message string|nil An optional message.
function harness.check.contains(text, part, message)
    if type(text) ~= "string" or not text:find(part, 1, true) then
        fail("expected " .. describeValue(text) .. " to contain " .. describeValue(part), message)
    end
end

return harness
