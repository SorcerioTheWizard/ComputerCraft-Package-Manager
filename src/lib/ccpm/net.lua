-- CCPM Net
--
-- Downloads files over HTTP with errors that explain what the player or server owner can do about them.

-- MARK: Imports
local files = require("ccpm.files")

-- MARK: Functions
local net = {}

--- Downloads a URL as exact bytes.
---@param url string The URL.
---@return string|nil body The response body, or `nil` if the download failed.
---@return string|nil err The error message if the download failed.
---@return table<string, string>|nil headers The response headers if the download succeeded.
function net.get(url)
    -- Explain a disabled HTTP API
    if not http then
        return nil, "HTTP is disabled on this computer. Enable `http.enabled` in the ComputerCraft config."
    end

    -- Explain URLs the server blocks
    local allowed, reason = http.checkURL(url)
    if not allowed then
        return nil, "`" .. url .. "` is blocked by this server's HTTP rules (" .. tostring(reason) .. "). Ask the server owner to allow it."
    end

    -- Download in binary mode so hashes match the bytes served
    local response, err, failure = http.get({ url = url, binary = true })
    if not response then
        local code = failure and failure.getResponseCode()
        if failure then
            failure.close()
        end
        return nil, "`" .. url .. "` could not be downloaded: " .. (code and ("HTTP " .. code) or tostring(err))
    end

    local body = response.readAll() or ""
    local headers = response.getResponseHeaders and response.getResponseHeaders() or {}
    response.close()

    return body, nil, headers
end

--- Checks if response headers describe a web page rather than a file.
---@param headers table<string, string>|nil The response headers.
---@return boolean isWebPage If the content type is HTML.
function net.isWebPage(headers)
    for key, value in pairs(headers or {}) do
        if key:lower() == "content-type" and value:lower():find("text/html", 1, true) then
            return true
        end
    end

    return false
end

--- Downloads and decodes a JSON URL.
---@param url string The URL.
---@return any|nil data The decoded data, or `nil` if the download or decoding failed.
---@return string|nil err The error message if it failed.
function net.getJSON(url)
    local body, err = net.get(url)
    if not body then
        return nil, err
    end

    local data, decodeErr = textutils.unserializeJSON(body)
    if data == nil then
        return nil, "`" .. url .. "` is not valid JSON: " .. tostring(decodeErr)
    end

    return data
end

--- Downloads a URL into a file.
---@param url string The URL.
---@param path string The file to write.
---@return boolean ok If the download succeeded.
---@return string|nil err The error message if it failed.
function net.download(url, path)
    local body, err = net.get(url)
    if not body then
        return false, err
    end

    files.write(path, body)
    return true
end

return net
