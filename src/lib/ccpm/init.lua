-- CCPM Library
--
-- What programs get from `require("ccpm")`: installable requirements, package folders, and helpers for kiosk computers.

-- MARK: Imports
-- Modules load in the environment of the program that requires them, so `package` and `require` here are the caller's
local paths = require("ccpm.paths")

-- MARK: Constants
local NAME_PATTERN = "^[%w_%-]+$"

-- MARK: State
-- The real `os.pullEvent`, saved while terminating is blocked
local savedPullEvent = nil

-- MARK: Private Functions
--- Lets the calling program require installed libraries, even when `ccpm setup` has not run.
local function ensureLibraryPath()
    local patterns = paths.join(paths.lib(), "?.lua") .. ";" .. paths.join(paths.lib(), "?/init.lua")
    if not package.path:find(patterns, 1, true) then
        package.path = package.path .. ";" .. patterns
    end
end

--- Checks if an installed package provides a library.
---@param name string The package name.
---@return boolean hasLibrary If `lib/<name>.lua` or `lib/<name>/init.lua` exists.
local function hasLibrary(name)
    return fs.exists(paths.join(paths.lib(), name .. ".lua")) or fs.exists(paths.join(paths.lib(), name, "init.lua"))
end

--- Checks if a package is installed at a version in a range.
---@param name string The package name.
---@param range string The accepted range.
---@return boolean satisfied If a satisfying version is installed.
local function isSatisfied(name, range)
    local semver = require("ccpm.semver")
    local record = require("ccpm.state").get(name)
    local parsed = semver.parseRange(range)
    local version = record and semver.parse(record.version)

    return version ~= nil and parsed ~= nil and parsed:test(version)
end

--- Checks a name used for folders and boot files.
---@param name any The name.
---@param level integer The stack level to report errors at.
local function checkName(name, level)
    if type(name) ~= "string" or not name:match(NAME_PATTERN) then
        error("expected a name made of letters, digits, `-`, and `_`, got " .. tostring(name), level + 1)
    end
end

-- MARK: Functions
local ccpm = {}

---@class RequiresOptions
---@field auto boolean|nil Install without asking, for programs that run unattended like startup programs.

--- Makes sure a package is installed, asking to install it and its dependencies when it is missing, then loads it.
--- Call it where you would call `require`: `local json = ccpm.requires("json", "^1.0")`.
---@param name string The package name.
---@param range string|nil The accepted version range, defaulting to any version.
---@param options RequiresOptions|nil How to install it.
---@return any module The package's library, or `true` if it only installs programs.
function ccpm.requires(name, range, options)
    range = range or "*"
    options = options or {}
    ensureLibraryPath()

    -- Install it when it is missing or too old
    if not isSatisfied(name, range) then
        local manager = require("ccpm.manager")
        local plan, err = manager.planInstall({ { name = name, range = range } })
        if not plan then
            error("this program needs " .. name .. " " .. range .. ", but " .. err, 2)
        end

        local ok, applyErr = manager.confirmAndApply(plan, { yes = options.auto, intro = "This program needs packages CCPM will install:" })
        if not ok then
            error("this program needs " .. name .. " " .. range .. (applyErr == "cancelled" and ", which was not installed" or (", but " .. tostring(applyErr))), 2)
        end
    end

    -- Load its library if it has one
    if hasLibrary(name) then
        return require(name)
    end
    return true
end

--- Gets the version of an installed package.
---@param name string The package name.
---@return string|nil version The installed version, or `nil` if it is not installed.
function ccpm.installed(name)
    local record = require("ccpm.state").get(name)
    return record and record.version or nil
end

--- Gets the version of CCPM itself.
---@return string|nil version The installed version, or `nil` when running from source.
function ccpm.version()
    return ccpm.installed("ccpm")
end

--- Describes the computer: its ComputerCraft and Minecraft versions, kind, and color support.
---@return Environment environment The environment.
function ccpm.env()
    return require("ccpm.env").current()
end

--- Gets a folder for a program's own files, like its settings and saves, creating it if needed.
---@param name string The package or program name.
---@param file string|nil A file inside the folder to get the path of.
---@return string path The absolute path of the folder, or of the file inside it.
function ccpm.dataPath(name, file)
    checkName(name, 2)
    local dir = paths.data(name)
    fs.makeDir(dir)

    return file and paths.join(dir, file) or dir
end

--- Gets the folder holding a package's read-only assets, installed from `share/<name>/`.
---@param name string The package name.
---@param file string|nil A file inside the folder to get the path of.
---@return string path The absolute path of the folder, or of the file inside it.
function ccpm.sharePath(name, file)
    checkName(name, 2)
    local dir = paths.join(paths.root(), "share", name)

    return file and paths.join(dir, file) or dir
end

--- Stops Ctrl+T from terminating programs until `allowTerminate` is called or the computer reboots.
--- This affects every program on the computer, like a door lock that must not be closed.
function ccpm.preventTerminate()
    if not savedPullEvent then
        savedPullEvent = os.pullEvent
        os.pullEvent = os.pullEventRaw
    end
end

--- Lets Ctrl+T terminate programs again.
function ccpm.allowTerminate()
    if savedPullEvent then
        os.pullEvent = savedPullEvent
        savedPullEvent = nil
    end
end

--- Runs a function that Ctrl+T cannot interrupt, allowing it again afterwards even if the function fails.
---@param fn function The function.
---@param ... any Its arguments.
---@return any ... Its results.
function ccpm.withoutTerminate(fn, ...)
    local alreadyPrevented = savedPullEvent ~= nil
    ccpm.preventTerminate()
    local results = table.pack(pcall(fn, ...))
    if not alreadyPrevented then
        ccpm.allowTerminate()
    end

    -- Rethrow failures after restoring
    if not results[1] then
        error(results[2], 0)
    end
    return table.unpack(results, 2, results.n)
end

--- Runs a program every time the computer boots, the same way packages with a startup program are started.
---@param name string A name for the boot entry, used to remove it later.
---@param program string The program to run, resolved like the shell does.
function ccpm.runAtStartup(name, program)
    checkName(name, 2)

    -- Resolve the program to an absolute path
    local resolved = shell and shell.resolveProgram(program) or program
    if not resolved or not fs.exists(resolved) then
        error("program `" .. tostring(program) .. "` was not found", 2)
    end

    require("ccpm.installer").setStartup(name, paths.join(resolved))
end

--- Stops running a program at boot that was added with `runAtStartup`.
---@param name string The name of the boot entry.
function ccpm.removeFromStartup(name)
    checkName(name, 2)
    require("ccpm.installer").setStartup(name, nil)
end

-- MARK: Setup
ensureLibraryPath()

return ccpm
