-- CCPM Sandbox
--
-- Points CCPM at a fresh root folder for each test and cleans it up afterwards.

-- MARK: Imports
local paths = require("ccpm.paths")
local fakeHttp = require("support.fake_http")
local harness = require("harness")

-- MARK: Constants
local SANDBOX_ROOT = "/sandbox"

-- MARK: Functions
local sandbox = {}

--- Starts a test with an empty CCPM root and no network access.
---@return string root The sandbox root.
function sandbox.setup()
    fs.delete(SANDBOX_ROOT)
    paths.setRoot(SANDBOX_ROOT)

    -- Answer every request with 404 until the test serves something
    fakeHttp.install({})

    return SANDBOX_ROOT
end

--- Ends a test, deleting the sandbox and restoring the real root and `http` API.
function sandbox.teardown()
    fs.delete(SANDBOX_ROOT)
    paths.setRoot(nil)
    fakeHttp.restore()
end

--- Registers `setup` and `teardown` as hooks of the current group.
function sandbox.use()
    harness.beforeEach(sandbox.setup)
    harness.afterEach(sandbox.teardown)
end

return sandbox
