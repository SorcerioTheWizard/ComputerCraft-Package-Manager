-- CCPM State
--
-- Records which packages are installed, at which versions, and which files each one owns.

-- MARK: Imports
local files = require("ccpm.files")
local paths = require("ccpm.paths")

-- MARK: Constants
local RECORD_SUFFIX = ".json"

-- MARK: Private Functions
--- Gets the path of a package's record.
---@param name string The package name, which may contain `/` for external packages.
---@return string path The absolute path.
local function recordPath(name)
    return paths.join(paths.pkg(), name .. RECORD_SUFFIX)
end

--- Collects the package names recorded under a folder.
---@param dir string The folder to search.
---@param prefix string The name prefix of records in this folder.
---@param names string[] The list to add names to.
local function collectNames(dir, prefix, names)
    for _, entry in ipairs(fs.list(dir)) do
        local path = fs.combine(dir, entry)
        if fs.isDir(path) then
            collectNames(path, prefix .. entry .. "/", names)
        elseif entry:sub(-#RECORD_SUFFIX) == RECORD_SUFFIX then
            names[#names + 1] = prefix .. entry:sub(1, -#RECORD_SUFFIX - 1)
        end
    end
end

-- MARK: Functions
local state = {}

---@class InstalledFile
---@field path string The install path relative to the CCPM root.
---@field sha256 string The hash of the installed contents.

---@class InstalledPackage
---@field name string The package name.
---@field version string The installed version.
---@field registry string The name of the registry it came from.
---@field kind "files"|"installer" How it was installed.
---@field files InstalledFile[] The files it owns.
---@field dependencies table<string, string> The ranges it needs, keyed by package name.
---@field startup string|nil The program run at boot.
---@field command string|nil The command that installed it, for packages that run their own installer.
---@field explicit boolean If the user asked for it, rather than it being installed as a dependency.

--- Gets the record of an installed package.
---@param name string The package name.
---@return InstalledPackage|nil record The record, or `nil` if the package is not installed.
function state.get(name)
    return files.readJSON(recordPath(name))
end

--- Lists every installed package, sorted by name.
---@return InstalledPackage[] records The records.
function state.list()
    local names = {}
    if fs.isDir(paths.pkg()) then
        collectNames(paths.pkg(), "", names)
    end
    table.sort(names)

    -- Read each record
    local records = {}
    for _, name in ipairs(names) do
        local record = state.get(name)
        if record then
            records[#records + 1] = record
        end
    end

    return records
end

--- Saves the record of an installed package.
---@param record InstalledPackage The record.
function state.put(record)
    files.writeJSON(recordPath(record.name), record)
end

--- Deletes the record of a package.
---@param name string The package name.
function state.remove(name)
    files.deleteAndPrune(recordPath(name), paths.pkg())
end

--- Finds the installed package that owns a file.
---@param path string The install path relative to the CCPM root.
---@return string|nil name The owning package, or `nil` if no package owns it.
function state.findOwner(path)
    for _, record in ipairs(state.list()) do
        for _, file in ipairs(record.files or {}) do
            if file.path == path then
                return record.name
            end
        end
    end

    return nil
end

--- Lists the installed packages that depend on a package.
---@param name string The package name.
---@return string[] names The dependent packages, sorted by name.
function state.dependents(name)
    local names = {}
    for _, record in ipairs(state.list()) do
        if record.dependencies and record.dependencies[name] then
            names[#names + 1] = record.name
        end
    end

    return names
end

return state
