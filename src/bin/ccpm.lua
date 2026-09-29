-- CCPM
--
-- The `ccpm` program, which installs, updates, and removes ComputerCraft packages.

-- MARK: Imports
-- Find the libraries installed next to this program, even before `ccpm setup` has run
local lib = "/" .. fs.combine(fs.getDir(fs.getDir(shell.getRunningProgram())), "lib")
package.path = lib .. "/?.lua;" .. lib .. "/?/init.lua;" .. package.path

local cli = require("ccpm.cli")

-- MARK: Execution
cli.run({ ... }, shell)
