-- CCPM CLI Runner
--
-- Runs `ccpm` commands with captured output and a fake shell for specs.

-- MARK: Imports
local cli = require("ccpm.cli")
local ui = require("ccpm.ui")

-- MARK: Functions
local cliRunner = {}

--- Creates a fake shell that records path and completion changes.
---@return table shellApi The fake shell.
function cliRunner.fakeShell()
    local fake = { currentPath = ".:/rom/programs", completions = {}, runs = {} }
    fake.path = function() return fake.currentPath end
    fake.setPath = function(value) fake.currentPath = value end
    fake.setCompletionFunction = function(program, fn) fake.completions[program] = fn end
    fake.run = function(...) fake.runs[#fake.runs + 1] = { ... } return true end

    return fake
end

--- Runs a `ccpm` command.
---@param argv string[] The program arguments.
---@param options { answer: boolean|nil, shell: table|nil }|nil How to answer questions, and the shell to use.
---@return boolean ok If the command succeeded.
---@return string output Everything printed, one line per message.
---@return { text: string, kind: string }[] lines The printed messages.
function cliRunner.run(argv, options)
    options = options or {}
    ui.startCapture(options.answer)
    local ok = cli.run(argv, options.shell or cliRunner.fakeShell())
    local lines = ui.stopCapture()

    local texts = {}
    for i, line in ipairs(lines) do
        texts[i] = line.text
    end

    return ok, table.concat(texts, "\n"), lines
end

return cliRunner
