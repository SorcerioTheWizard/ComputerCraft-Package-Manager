-- CCPM Paths
--
-- Resolves where CCPM keeps its programs, libraries, package records, config, and cache on the computer.

-- MARK: Constants
local DEFAULT_ROOT = "/ccpm"
local STARTUP_DIR = "/startup"

-- MARK: State
local root = DEFAULT_ROOT

-- MARK: Functions
local paths = {}

--- Joins path parts into an absolute path.
---@param ... string The path parts.
---@return string path The absolute path.
function paths.join(...)
    return "/" .. fs.combine(...)
end

--- Gets the CCPM root folder.
---@return string path The absolute root folder.
function paths.root()
    return root
end

--- Sets the CCPM root folder so tests can install into an isolated location.
---@param path string|nil The new root folder, or `nil` to restore the default.
function paths.setRoot(path)
    root = path and paths.join(path) or DEFAULT_ROOT
end

--- Gets the folder installed programs are placed in, which is added to the shell path.
---@return string path The absolute folder.
function paths.bin()
    return paths.join(root, "bin")
end

--- Gets the folder installed libraries are placed in, which is added to the `require` path.
---@return string path The absolute folder.
function paths.lib()
    return paths.join(root, "lib")
end

--- Gets the folder holding one record per installed package.
---@return string path The absolute folder.
function paths.pkg()
    return paths.join(root, "pkg")
end

--- Gets the folder holding CCPM's configuration.
---@return string path The absolute folder.
function paths.etc()
    return paths.join(root, "etc")
end

--- Gets the folder holding downloaded registry indexes.
---@return string path The absolute folder.
function paths.cache()
    return paths.join(root, "cache")
end

--- Gets the folder holding a package's own data, like its config and saves.
---@param name string The package name.
---@return string path The absolute folder.
function paths.data(name)
    return paths.join(root, "data", name)
end

--- Gets the folder CraftOS runs every file of at boot.
---@return string path The absolute folder.
function paths.startup()
    return STARTUP_DIR
end

return paths
