-- CCPM Completion
--
-- Completes `ccpm` commands, flags, and package names in the shell.

-- MARK: Imports
local choice = require("cc.completion").choice

-- MARK: Private Functions
--- Lists the names of installed packages.
---@return string[] names The names.
local function installedNames()
    local names = {}
    for _, record in ipairs(require("ccpm.state").list()) do
        names[#names + 1] = record.name
    end

    return names
end

-- MARK: Functions
local completion = {}

--- Completes an argument of the `ccpm` program, as a shell completion function.
---@param _ table The shell.
---@param index integer Which argument is being completed, starting at 1.
---@param text string The text typed so far.
---@param previous string[] The program and the arguments before this one.
---@return string[] suffixes The possible endings of the text.
function completion.complete(_, index, text, previous)
    -- Load the commands only when completing, to keep boot fast
    local cli = require("ccpm.cli")

    -- Complete the command
    if index == 1 then
        return choice(text, cli.commandNames(), true)
    end
    local command = cli.findCommand(previous[2])
    if not command then
        return {}
    end

    -- Complete flags, subcommands, and packages
    if text:sub(1, 1) == "-" then
        return choice(text, cli.flagsOf(command), true)
    elseif command.name == "help" and index == 2 then
        return choice(text, cli.commandNames(), false)
    elseif command.subcommands then
        return index == 2 and choice(text, command.subcommands, true) or {}
    elseif command.complete == "installed" then
        return choice(text, installedNames(), true)
    elseif command.complete == "available" then
        return choice(text, require("ccpm.registry").cachedNames(), true)
    end

    return {}
end

return completion
