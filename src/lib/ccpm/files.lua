-- CCPM Files
--
-- Reads and writes files byte for byte and as JSON, replacing files whole so an interrupted write never leaves half a file.

-- MARK: Constants
local TEMP_SUFFIX = ".tmp"

-- MARK: Functions
local files = {}

--- Reads a whole file as bytes.
---@param path string The file path.
---@return string|nil data The contents, or `nil` if the file cannot be read.
function files.read(path)
    local handle = fs.open(path, "rb")
    if not handle then
        return nil
    end

    local data = handle.readAll() or ""
    handle.close()

    return data
end

--- Writes bytes to a file, creating its folder and replacing it whole.
---@param path string The file path.
---@param data string The contents.
function files.write(path, data)
    -- Write next to the target first
    fs.makeDir(fs.getDir(path))
    local temp = path .. TEMP_SUFFIX
    local handle = assert(fs.open(temp, "wb"))
    handle.write(data)
    handle.close()

    -- Swap it into place
    if fs.exists(path) then
        fs.delete(path)
    end
    fs.move(temp, path)
end

--- Reads a JSON file.
---@param path string The file path.
---@return any|nil data The decoded data, or `nil` if the file is missing or invalid.
---@return string|nil err The error message if the file is invalid.
function files.readJSON(path)
    local text = files.read(path)
    if not text then
        return nil
    end

    local data, err = textutils.unserializeJSON(text)
    if data == nil then
        return nil, "`" .. path .. "` is not valid JSON: " .. tostring(err)
    end

    return data
end

--- Writes data to a JSON file.
---@param path string The file path.
---@param data any The data to encode.
function files.writeJSON(path, data)
    files.write(path, textutils.serializeJSON(data))
end

--- Deletes a file and then any folders it leaves empty, up to but not including a stop folder.
---@param path string The file path.
---@param stop string The folder to stop at.
function files.deleteAndPrune(path, stop)
    if fs.exists(path) then
        fs.delete(path)
    end

    -- Remove emptied parent folders
    local dir = "/" .. fs.getDir(path)
    stop = "/" .. fs.combine(stop)
    while dir ~= stop and dir ~= "/" and fs.isDir(dir) and #fs.list(dir) == 0 do
        fs.delete(dir)
        dir = "/" .. fs.getDir(dir)
    end
end

return files
