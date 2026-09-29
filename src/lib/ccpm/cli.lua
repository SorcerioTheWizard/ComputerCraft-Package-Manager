-- CCPM CLI
--
-- The commands of the `ccpm` program, which also drive its help text and tab completion.

-- MARK: Imports
local config = require("ccpm.config")
local env = require("ccpm.env")
local files = require("ccpm.files")
local manager = require("ccpm.manager")
local paths = require("ccpm.paths")
local registry = require("ccpm.registry")
local semver = require("ccpm.semver")
local setup = require("ccpm.setup")
local sha256 = require("ccpm.sha256")
local state = require("ccpm.state")
local ui = require("ccpm.ui")

-- MARK: Constants
local PROGRAM = "ccpm"
local SELF_PACKAGE = "ccpm"
local REGISTRY_NAME_PATTERN = "^[%w_%-]+$"
local URL_PATTERN = "^https?://"

-- Marks for `doctor` results, padded to the same width
local REPORT_MARKS = { ok = { "ok  ", "good" }, warn = { "warn", "caution" }, fail = { "fail", "bad" } }

-- Returned by a command whose arguments are wrong, so its usage is shown
local USAGE = "usage"

-- Flags every command understands, and the ones only some do
local FLAG_ALIASES = { ["-y"] = "--yes" }
local COMMON_FLAGS = { "--yes" }

-- MARK: Private Functions
--- Loads the registries, printing the error if they cannot be loaded.
---@param refresh boolean If indexes should be downloaded even when cached.
---@return LoadedRegistry[]|nil registries The registries, or `nil` if they could not be loaded.
local function loadRegistries(refresh)
    local registries, err = registry.loadAll(refresh)
    if not registries then
        ui.error(err or "the registries could not be loaded")
    end

    return registries
end

--- Finds the newest version of an installed package its range allows.
---@param registries LoadedRegistry[] The registries.
---@param record InstalledPackage The installed package.
---@return Version|nil newest The newest allowed version, or `nil` if the package is not in a registry.
local function newestAllowed(registries, record)
    local entry = registry.find(registries, record.name)
    local range = semver.parseRange(record.range or "*")
    if not entry or not range then
        return nil
    end

    return range:best(registry.versions(entry))
end

--- Builds a labeled detail row for `ui.table`, like `Author  Tester`.
---@param label string The label.
---@param value string The value.
---@param role Role|nil The value's role, defaulting to plain text.
---@return Segment[] row The row.
local function field(label, value, role)
    return { { label, "dim" }, { value, role } }
end

--- Describes a count of packages, like `1 package` or `3 packages`.
---@param count integer The count.
---@return string text The description.
local function packages(count)
    return count .. (count == 1 and " package" or " packages")
end

--- Counts the keys of a table.
---@param map table The table.
---@return integer count The number of keys.
local function countKeys(map)
    local count = 0
    for _ in pairs(map) do
        count = count + 1
    end

    return count
end

--- Prints one line of a `doctor` report.
---@param result "ok"|"warn"|"fail" The result.
---@param text string The line.
local function report(result, text)
    ui.line({ REPORT_MARKS[result], { "  " .. text } }, 6)
end

-- MARK: Commands
---@class Command
---@field name string The command name.
---@field usage string The arguments it takes.
---@field summary string What it does.
---@field flags string[] The flags it accepts, besides the common ones.
---@field subcommands string[]|nil Subcommands to complete.
---@field complete "installed"|"available"|nil What to complete its arguments with.
---@field run fun(args: string[], flags: table<string, boolean>, shellApi: table|nil): boolean|string

---@type Command[]
local COMMANDS = {}

COMMANDS[#COMMANDS + 1] = {
    name = "install",
    usage = "<package>[@<range>] ...",
    summary = "Install packages and what they need.",
    flags = { "--force" },
    complete = "available",
    run = function(args, flags)
        if #args == 0 then
            return USAGE
        end

        local specs = {}
        for _, arg in ipairs(args) do
            specs[#specs + 1] = manager.parseSpec(arg)
        end
        local plan, err = manager.planInstall(specs, { force = flags.force })
        if not plan then
            ui.error(err or "the packages could not be resolved")
            return false
        end

        return manager.confirmAndApply(plan, { yes = flags.yes, force = flags.force, nothing = "Nothing to install." })
    end,
}

COMMANDS[#COMMANDS + 1] = {
    name = "remove",
    usage = "<package> ...",
    summary = "Remove packages and their leftovers.",
    flags = { "--cascade" },
    complete = "installed",
    run = function(args, flags)
        if #args == 0 then
            return USAGE
        end

        -- Keep CCPM from removing itself
        for _, name in ipairs(args) do
            if name == SELF_PACKAGE then
                ui.error("CCPM cannot remove itself. Delete `" .. paths.root() .. "` and `" .. setup.hookPath() .. "` to uninstall it.")
                return false
            end
        end

        if not flags.yes and not ui.confirm("Remove " .. table.concat(args, ", ") .. "?") then
            ui.note("Cancelled.")
            return false
        end

        local removed, err, untracked = manager.remove(args, flags.cascade)
        if not removed then
            ui.error(err or "the packages could not be removed")
            return false
        end
        ui.success("Removed " .. table.concat(removed, ", ") .. ".")
        for _, name in ipairs(untracked or {}) do
            ui.warn(name .. " was installed by its own installer, so the files it created were left in place.")
        end

        return true
    end,
}

COMMANDS[#COMMANDS + 1] = {
    name = "update",
    usage = "[<package> ...]",
    summary = "Update installed packages.",
    flags = { "--force" },
    complete = "installed",
    run = function(args, flags)
        local plan, err = manager.planUpdate(#args > 0 and args or nil, { force = flags.force })
        if not plan then
            ui.error(err or "the updates could not be resolved")
            return false
        end
        plan.unchanged = {}

        return manager.confirmAndApply(plan, { yes = flags.yes, force = flags.force, nothing = "Everything is up to date." })
    end,
}

COMMANDS[#COMMANDS + 1] = {
    name = "upgrade",
    usage = "",
    summary = "Update CCPM itself.",
    flags = {},
    run = function(_, flags, shellApi)
        if not state.get(SELF_PACKAGE) then
            ui.error("CCPM was not installed from a registry, so it cannot upgrade itself.")
            return false
        end

        local plan, err = manager.planUpdate({ SELF_PACKAGE })
        if not plan then
            ui.error(err or "the upgrade could not be resolved")
            return false
        end
        plan.unchanged = {}
        if not manager.confirmAndApply(plan, { yes = flags.yes, force = flags.force, nothing = "CCPM is up to date." }) then
            return false
        end

        -- Let the new version refresh its own boot hook
        if #plan.steps > 0 and shellApi then
            shellApi.run(paths.join(paths.bin(), PROGRAM .. ".lua"), "setup")
        end
        return true
    end,
}

COMMANDS[#COMMANDS + 1] = {
    name = "list",
    usage = "",
    summary = "List installed packages.",
    flags = { "--outdated" },
    run = function(_, flags)
        local records = state.list()
        if #records == 0 then
            ui.say("No packages are installed.")
            return true
        end

        -- Look up newer versions when asked
        local registries = nil
        if flags.outdated then
            registries = loadRegistries(true)
            if not registries then
                return false
            end
        end

        -- List every package, or only the ones with updates
        local rows = {}
        for _, record in ipairs(records) do
            if registries then
                local newest = newestAllowed(registries, record)
                local installed = semver.parse(record.version)
                if newest and installed and installed < newest then
                    rows[#rows + 1] = { { record.name, "name" }, { record.version .. " -> " .. tostring(newest), "dim" } }
                end
            else
                rows[#rows + 1] = { { record.name, "name" }, { record.version, "dim" }, { record.explicit and "" or "dependency", "faint" } }
            end
        end

        if #rows == 0 then
            ui.say("Everything is up to date.")
        else
            ui.paged(function() ui.table(rows) end)
        end
        return true
    end,
}

COMMANDS[#COMMANDS + 1] = {
    name = "search",
    usage = "<words> ...",
    summary = "Find packages by name or description.",
    flags = {},
    run = function(args)
        if #args == 0 then
            return USAGE
        end
        local registries = loadRegistries(false)
        if not registries then
            return false
        end

        local results = registry.search(registries, table.concat(args, " "))
        if #results == 0 then
            ui.say("No packages match.")
            return true
        end

        -- Show each result's name and version, then its description indented beneath
        ui.paged(function()
            for _, result in ipairs(results) do
                ui.line({ { result.name, "name" }, { " " .. result.entry.latest, "dim" } }, 2)
                ui.line({ { "  " }, { result.entry.description or "" } }, 2, 2)
            end
            ui.note(packages(#results) .. ". Install one with `ccpm install <name>`.")
        end)
        return true
    end,
}

COMMANDS[#COMMANDS + 1] = {
    name = "info",
    usage = "<package>",
    summary = "Show details about a package.",
    flags = {},
    complete = "available",
    run = function(args)
        if #args ~= 1 then
            return USAGE
        end
        local registries = loadRegistries(false)
        if not registries then
            return false
        end

        local name = args[1]
        local entry, source = registry.find(registries, name)
        local record = state.get(name)
        if not entry and not record then
            ui.error("package `" .. name .. "` was not found in any registry")
            return false
        end

        -- Describe the package
        ui.line({ { name, "name" }, { " " .. (entry and entry.latest or record.version), "dim" } })
        local rows = {}
        if entry and source then
            ui.say(entry.description or "")
            rows[#rows + 1] = field("Author", entry.author or "unknown")
            for _, pair in ipairs({ { "License", entry.license }, { "Repository", entry.repository }, { "Homepage", entry.homepage } }) do
                if pair[2] then
                    rows[#rows + 1] = field(pair[1], pair[2])
                end
            end
            if entry.tags and #entry.tags > 0 then
                rows[#rows + 1] = field("Tags", table.concat(entry.tags, ", "))
            end
            if entry.origin then
                rows[#rows + 1] = field("Source", entry.origin.source)
                rows[#rows + 1] = field("Page", entry.origin.url)
            end
            rows[#rows + 1] = field("Registry", source.name)
            rows[#rows + 1] = field("Versions", table.concat(entry.versions or {}, ", "))
        end

        -- Describe the installed copy
        rows[#rows + 1] = field("Installed", record and (record.version .. (record.explicit and "" or ", as a dependency")) or "no", record and "good" or nil)
        ui.blank()
        ui.table(rows, 2)
        return true
    end,
}

COMMANDS[#COMMANDS + 1] = {
    name = "refresh",
    usage = "",
    summary = "Download the latest package lists.",
    flags = {},
    run = function()
        local registries = loadRegistries(true)
        if not registries then
            return false
        end

        ui.success("Refreshed " .. #registries .. (#registries == 1 and " registry." or " registries."))
        return true
    end,
}

COMMANDS[#COMMANDS + 1] = {
    name = "env",
    usage = "",
    summary = "Show this computer's game versions.",
    flags = {},
    run = function()
        local current = env.current()
        ui.table({
            field("ComputerCraft", current.cc and tostring(current.cc) or "unknown"),
            field("Minecraft", current.mc and tostring(current.mc) or ("unknown, running on " .. current.platform)),
            field("Computer", (current.color and "advanced " or "") .. tostring(current.kind)),
            field("_HOST", current.host, "dim"),
        })
        return true
    end,
}

COMMANDS[#COMMANDS + 1] = {
    name = "hosts",
    usage = "[list | add <url prefix> | remove <url prefix>]",
    summary = "Manage where files may come from.",
    flags = {},
    subcommands = { "list", "add", "remove" },
    run = function(args)
        local action, prefix = args[1] or "list", args[2]
        local settings = config.load()

        -- List the registries' hosts and the user's
        if action == "list" and not prefix then
            for _, source in ipairs(settings.registries) do
                local index = files.readJSON(paths.join(paths.cache(), source.name .. ".json"))
                ui.line({ { "From registry " }, { source.name, "name" }, { ":" } })
                for _, host in ipairs(index and index.hosts or {}) do
                    ui.line({ { "  " }, { host, "dim" } }, 2)
                end
                if not index then
                    ui.line({ { "  " }, { "Run `ccpm refresh` to load them.", "faint" } }, 2)
                end
            end
            ui.say("Added by you:")
            for _, host in ipairs(settings.hosts) do
                ui.line({ { "  " }, { host, "dim" } }, 2)
            end
            if #settings.hosts == 0 then
                ui.line({ { "  " }, { "None. Add one with `ccpm hosts add <url prefix>`.", "faint" } }, 2)
            end
            return true
        end

        -- Require exactly one prefix
        if not prefix or args[3] then
            return USAGE
        end

        if action == "add" then
            if not prefix:match(URL_PATTERN) then
                ui.error("A host must be a URL prefix starting with `https://`, like `https://example.com/files/`.")
                return false
            end
            for _, host in ipairs(settings.hosts) do
                if host == prefix then
                    ui.say("`" .. prefix .. "` is already allowed.")
                    return true
                end
            end
            settings.hosts[#settings.hosts + 1] = prefix
            config.save(settings)
            ui.success("Allowed files from `" .. prefix .. "`.")
            return true
        elseif action == "remove" then
            for i, host in ipairs(settings.hosts) do
                if host == prefix then
                    table.remove(settings.hosts, i)
                    config.save(settings)
                    ui.success("Removed `" .. prefix .. "`.")
                    return true
                end
            end
            ui.error("`" .. prefix .. "` was not added with `ccpm hosts add`; hosts listed by a registry cannot be removed.")
            return false
        end

        return USAGE
    end,
}

COMMANDS[#COMMANDS + 1] = {
    name = "registry",
    usage = "[list | add <name> <url> | remove <name>]",
    summary = "Manage the registries to install from.",
    flags = {},
    subcommands = { "list", "add", "remove" },
    run = function(args)
        local action = args[1] or "list"
        local settings = config.load()

        -- List registries in priority order
        if action == "list" and #args <= 1 then
            local rows = {}
            for i, source in ipairs(settings.registries) do
                rows[i] = { { i .. ".", "dim" }, { source.name, "name" }, { source.url, "dim" } }
            end
            ui.table(rows)
            return true
        end

        if action == "add" and #args == 3 then
            local name, url = args[2], args[3]
            if not name:match(REGISTRY_NAME_PATTERN) then
                ui.error("A registry name may only use letters, digits, `-`, and `_`.")
                return false
            end
            if not url:match(URL_PATTERN) then
                ui.error("A registry URL must start with `https://`.")
                return false
            end
            for _, source in ipairs(settings.registries) do
                if source.name == name then
                    ui.error("A registry named `" .. name .. "` already exists.")
                    return false
                end
            end

            -- Check the registry works before saving it
            local source = { name = name, url = url:sub(-1) == "/" and url or (url .. "/") }
            local loaded, err = registry.load(source, settings.hosts, true)
            if not loaded then
                ui.error(err or "the registry could not be loaded")
                return false
            end
            settings.registries[#settings.registries + 1] = source
            config.save(settings)
            ui.success("Added registry `" .. name .. "` with " .. packages(countKeys(loaded.packages)) .. ".")
            return true
        elseif action == "remove" and #args == 2 then
            for i, source in ipairs(settings.registries) do
                if source.name == args[2] then
                    table.remove(settings.registries, i)
                    config.save(settings)
                    local cache = paths.join(paths.cache(), source.name .. ".json")
                    if fs.exists(cache) then
                        fs.delete(cache)
                    end
                    ui.success("Removed registry `" .. source.name .. "`.")
                    return true
                end
            end
            ui.error("There is no registry named `" .. args[2] .. "`.")
            return false
        end

        return USAGE
    end,
}

COMMANDS[#COMMANDS + 1] = {
    name = "doctor",
    usage = "",
    summary = "Check CCPM and packages for problems.",
    flags = {},
    run = function()
        local failures = 0
        local function fail(text)
            failures = failures + 1
            report("fail", text)
        end

        -- Check each registry can be downloaded and read
        local settings = config.load()
        for _, source in ipairs(settings.registries) do
            local loaded, err = registry.load(source, settings.hosts, true)
            if loaded then
                report("ok", "registry `" .. source.name .. "` is reachable")
            else
                fail(err or ("registry `" .. source.name .. "` could not be loaded"))
            end
        end

        -- Check the computer is set up
        if setup.isHookInstalled() then
            report("ok", "boot hook is installed")
        else
            fail("boot hook is missing or outdated; run `ccpm setup`")
        end
        if setup.isPackagePathConfigured() then
            report("ok", "installed libraries can be required")
        else
            fail("installed libraries cannot be required; run `ccpm setup`")
        end

        -- Check every installed package
        local records = state.list()
        local installed = {}
        for _, record in ipairs(records) do
            installed[record.name] = record
        end
        for _, record in ipairs(records) do
            local problems = 0
            for _, file in ipairs(record.files or {}) do
                local data = files.read(paths.join(paths.root(), file.path))
                if not data then
                    fail(record.name .. ": `" .. file.path .. "` is missing; run `ccpm install " .. record.name .. "@" .. record.version .. " --force`")
                    problems = problems + 1
                elseif sha256.hex(data) ~= file.sha256 then
                    report("warn", record.name .. ": `" .. file.path .. "` was changed since it was installed")
                    problems = problems + 1
                end
            end
            for dependency, text in pairs(record.dependencies or {}) do
                local range = semver.parseRange(text)
                local dependencyRecord = installed[dependency]
                local version = dependencyRecord and semver.parse(dependencyRecord.version)
                if not version or not range or not range:test(version) then
                    fail(record.name .. " needs " .. dependency .. " " .. text .. ", which is not installed")
                    problems = problems + 1
                end
            end
            if problems == 0 then
                report("ok", record.name .. " " .. record.version)
            end
        end

        ui.blank()
        if failures == 0 then
            ui.success("No problems found.")
        else
            ui.error(failures .. (failures == 1 and " problem" or " problems") .. " found.")
        end
        return failures == 0
    end,
}

COMMANDS[#COMMANDS + 1] = {
    name = "setup",
    usage = "",
    summary = "Set this computer up for CCPM again.",
    flags = {},
    run = function(_, _, shellApi)
        setup.install(shellApi)
        ui.success("CCPM is set up. Installed programs can be run by name and installed libraries can be required.")
        return true
    end,
}

COMMANDS[#COMMANDS + 1] = {
    name = "help",
    usage = "[<command>]",
    summary = "Show how to use a command.",
    flags = {},
    run = nil,
}

-- MARK: Functions
local cli = {}

--- Finds a command by name.
---@param name string|nil The command name.
---@return Command|nil command The command, or `nil` if there is none.
function cli.findCommand(name)
    for _, command in ipairs(COMMANDS) do
        if command.name == name then
            return command
        end
    end

    return nil
end

--- Lists every command name.
---@return string[] names The names in help order.
function cli.commandNames()
    local names = {}
    for _, command in ipairs(COMMANDS) do
        names[#names + 1] = command.name
    end

    return names
end

--- Lists the flags a command accepts.
---@param command Command The command.
---@return string[] flags The flags.
function cli.flagsOf(command)
    local flags = {}
    for _, flag in ipairs(command.flags) do
        flags[#flags + 1] = flag
    end
    for _, flag in ipairs(COMMON_FLAGS) do
        flags[#flags + 1] = flag
    end

    return flags
end

--- Prints how to use CCPM, or one command.
---@param command Command|nil The command, or `nil` for every command.
function cli.printHelp(command)
    -- Describe one command
    if command then
        ui.line({ { "Usage: ", "dim" }, { PROGRAM .. " " .. command.name .. (command.usage ~= "" and (" " .. command.usage) or "") } }, 7)
        ui.say(command.summary)
        ui.line({ { "Flags: ", "dim" }, { table.concat(cli.flagsOf(command), ", ") } }, 7)
        return
    end

    -- Describe every command
    local record = state.get(SELF_PACKAGE)
    local rows = {}
    for _, entry in ipairs(COMMANDS) do
        rows[#rows + 1] = { { entry.name, "name" }, { entry.summary } }
    end
    ui.paged(function()
        ui.line({ { "CCPM", "name" }, { " " .. (record and record.version or "dev"), "dim" }, { ", the ComputerCraft package manager." } })
        ui.line({ { "Usage: ", "dim" }, { PROGRAM .. " <command> [arguments]" } }, 7)
        ui.blank()
        ui.table(rows, 2)
    end)
end

--- Runs the `ccpm` program.
---@param argv string[] The program arguments.
---@param shellApi table|nil The running shell.
---@return boolean ok If the command succeeded.
function cli.run(argv, shellApi)
    -- Find the command
    local command = cli.findCommand(argv[1])
    if not command or command.name == "help" then
        cli.printHelp(command and cli.findCommand(argv[2]) or nil)
        return command ~= nil or argv[1] == nil
    end

    -- Split flags from arguments
    local allowed = {}
    for _, flag in ipairs(cli.flagsOf(command)) do
        allowed[flag] = true
    end
    local args, flags = {}, {}
    for i = 2, #argv do
        local arg = FLAG_ALIASES[argv[i]] or argv[i]
        if arg:sub(1, 1) == "-" then
            if not allowed[arg] then
                ui.error("`" .. command.name .. "` does not understand `" .. arg .. "`.")
                cli.printHelp(command)
                return false
            end
            flags[arg:sub(3)] = true
        else
            args[#args + 1] = arg
        end
    end

    -- Run it, showing usage when the arguments are wrong
    local ok, result = pcall(command.run, args, flags, shellApi)
    if not ok then
        ui.error(tostring(result))
        return false
    elseif result == USAGE then
        cli.printHelp(command)
        return false
    end

    return result == true
end

return cli
