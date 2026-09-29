---@meta
-- CCPM ComputerCraft Types
--
-- Declares the ComputerCraft additions to standard Lua libraries for the Lua language server; never loaded at runtime.

--- Queues an event to be pulled by `os.pullEvent`.
---@param name string The event name.
---@param ... any The event parameters.
function os.queueEvent(name, ...) end

--- Waits for an event, raising an error if the program is terminated.
---@param filter string|nil The event name to wait for.
---@return string name The event name.
---@return any ... The event parameters.
function os.pullEvent(filter) end

--- Waits for an event, including `terminate`.
---@param filter string|nil The event name to wait for.
---@return string name The event name.
---@return any ... The event parameters.
function os.pullEventRaw(filter) end

--- Gets the version of CraftOS, like `CraftOS 1.9`.
---@return string version The version.
function os.version() end

--- Gets the ID of this computer.
---@return integer id The ID.
function os.getComputerID() end

--- Gets the label of this computer.
---@return string|nil label The label.
function os.getComputerLabel() end

--- Reboots the computer.
function os.reboot() end

--- Shuts down the computer.
function os.shutdown() end
