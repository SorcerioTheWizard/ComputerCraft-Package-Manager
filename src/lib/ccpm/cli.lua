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
local FIELD_WIDTH = 11

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

--- Prints a labeled detail line, like `  Author:     Tester`.
---@param label string The label.
---@param value string The value.
local function field(label, value)
    ui.muted("  " .. label .. ":" .. string.rep(" ", FIELD_WIDTH - #label) .. value)
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
---@param ok boolean|nil `true` for a pass, `false` for a failure, `nil` for a warning.
---@param text string The line.
local function report(ok, text)
    if ok then
        ui.success("[ok]   " .. text)
    elseif ok == false then
        ui.error("[fail] " .. text)
    else
        ui.warn("[warn] " .. text)
    end
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
    summary = "Install packages and their dependencies.",
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
    summary = "Remove packages and dependencies nothing else needs.",
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
            ui.info("Cancelled.")
            return false
        end

        local removed, err = manager.remove(args, flags.cascade)
        if not removed then
            ui.error(err or "the packages could not be removed")
            return false
        end
        ui.success("Removed " .. table.concat(removed, ", ") .. ".")

        return true
    end,
}

COMMANDS[#COMMANDS + 1] = {
    name = "update",
    usage = "[<package> ...]",
    summary = "Update packages within the ranges they were installed with.",
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
            ui.info("No packages are installed.")
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

        local lines = {}
        for _, record in ipairs(records) do
            local line = record.name .. " " .. record.version .. (record.explicit and "" or " (dependency)")
            if registries then
                local newest = newestAllowed(registries, record)
                local installed = semver.parse(record.version)
                if newest and installed and installed < newest then
                    lines[#lines + 1] = line .. " -> " .. tostring(newest)
                end
            else
                lines[#lines + 1] = line
            end
        end

        if #lines == 0 then
            ui.info("Everything is up to date.")
        else
            ui.page(lines)
        end
        return true
    end,
}

COMMANDS[#COMMANDS + 1] = {
    name = "search",
    usage = "<words> ...",
    summary = "Search packages by name, description, and tags.",
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
            ui.info("No packages match.")
            return true
        end

        local lines = {}
        for _, result in ipairs(results) do
            lines[#lines + 1] = result.name .. " " .. result.entry.latest
            lines[#lines + 1] = "  " .. (result.entry.description or "")
        end
        ui.page(lines)
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
        ui.info(name)
        if entry and source then
            ui.info("  " .. (entry.description or ""))
            field("Author", entry.author or "unknown")
            for _, pair in ipairs({ { "License", entry.license }, { "Repository", entry.repository }, { "Homepage", entry.homepage } }) do
                if pair[2] then
                    field(pair[1], pair[2])
                end
            end
            if entry.tags and #entry.tags > 0 then
                field("Tags", table.concat(entry.tags, ", "))
            end
            field("Registry", source.name)
            field("Versions", table.concat(entry.versions or {}, ", "))
        end

        -- Describe the installed copy
        field("Installed", record and (record.version .. (record.explicit and "" or " (dependency)")) or "no")
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

        ui.success("Refreshed " .. #registries .. " registry index(es).")
        return true
    end,
}

COMMANDS[#COMMANDS + 1] = {
    name = "env",
    usage = "",
    summary = "Show the versions packages are checked against.",
    flags = {},
    run = function()
        local current = env.current()
        ui.info("ComputerCraft: " .. (current.cc and tostring(current.cc) or "unknown"))
        ui.info("Minecraft:     " .. (current.mc and tostring(current.mc) or ("unknown (" .. current.platform .. ")")))
        ui.info("Computer:      " .. (current.color and "advanced " or "") .. tostring(current.kind))
        ui.muted("_HOST:         " .. current.host)
        return true
    end,
}

COMMANDS[#COMMANDS + 1] = {
    name = "hosts",
    usage = "[list | add <url prefix> | remove <url prefix>]",
    summary = "Manage where package files may be downloaded from.",
    flags = {},
    subcommands = { "list", "add", "remove" },
    run = function(args)
        local action, prefix = args[1] or "list", args[2]
        local settings = config.load()

        -- List the registries' hosts and the user's
        if action == "list" and not prefix then
            for _, source in ipairs(settings.registries) do
                local index = files.readJSON(paths.join(paths.cache(), source.name .. ".json"))
                ui.info("From registry " .. source.name .. ":")
                for _, host in ipairs(index and index.hosts or {}) do
                    ui.muted("  " .. host)
                end
                if not index then
                    ui.muted("  (run `ccpm refresh` to load them)")
                end
            end
            ui.info("Added by you:")
            for _, host in ipairs(settings.hosts) do
                ui.muted("  " .. host)
            end
            if #settings.hosts == 0 then
                ui.muted("  (none)")
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
                    ui.info("`" .. prefix .. "` is already allowed.")
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
    summary = "Manage the registries packages are installed from.",
    flags = {},
    subcommands = { "list", "add", "remove" },
    run = function(args)
        local action = args[1] or "list"
        local settings = config.load()

        -- List registries in priority order
        if action == "list" and #args <= 1 then
            for i, source in ipairs(settings.registries) do
                ui.info(i .. ". " .. source.name)
                ui.muted("   " .. source.url)
            end
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
            ui.success("Added registry `" .. name .. "` with " .. countKeys(loaded.packages) .. " package(s).")
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
    summary = "Check CCPM and installed packages for problems.",
    flags = {},
    run = function()
        local healthy = true
        local function fail(text)
            healthy = false
            report(false, text)
        end

        -- Check each registry can be downloaded and read
        local settings = config.load()
        for _, source in ipairs(settings.registries) do
            local loaded, err = registry.load(source, settings.hosts, true)
            if loaded then
                report(true, "registry `" .. source.name .. "` is reachable")
            else
                fail(err or ("registry `" .. source.name .. "` could not be loaded"))
            end
        end

        -- Check the computer is set up
        if setup.isHookInstalled() then
            report(true, "boot hook is installed")
        else
            fail("boot hook is missing or outdated; run `ccpm setup`")
        end
        if setup.isPackagePathConfigured() then
            report(true, "installed libraries can be required")
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
                    report(nil, record.name .. ": `" .. file.path .. "` was changed since it was installed")
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
                report(true, record.name .. " " .. record.version)
            end
        end

        if healthy then
            ui.success("No problems found.")
        end
        return healthy
    end,
}

COMMANDS[#COMMANDS + 1] = {
    name = "setup",
    usage = "",
    summary = "Add CCPM's programs and libraries to this computer's paths.",
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
    summary = "Show how to use CCPM or a command.",
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
    if command then
        ui.info("Usage: " .. PROGRAM .. " " .. command.name .. (command.usage ~= "" and (" " .. command.usage) or ""))
        ui.muted(command.summary)
        ui.muted("Flags: " .. table.concat(cli.flagsOf(command), ", "))
        return
    end

    local record = state.get(SELF_PACKAGE)
    ui.info("CCPM " .. (record and record.version or "(development)") .. ", the ComputerCraft package manager.")
    ui.info("Usage: " .. PROGRAM .. " <command> [arguments] [flags]")
    local lines = {}
    for _, entry in ipairs(COMMANDS) do
        lines[#lines + 1] = "  " .. entry.name .. string.rep(" ", 9 - #entry.name) .. entry.summary
    end
    ui.page(lines)
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
