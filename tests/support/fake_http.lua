-- CCPM Fake HTTP
--
-- Replaces the `http` API with canned responses so specs never touch the network.

-- MARK: State
local saved = nil
local requests = {}
local posts = {}

-- MARK: Private Functions
--- Creates a response handle like the ones `http.get` returns.
---@param code integer The HTTP status code.
---@param body string The response body.
---@param headers table<string, string>|nil The response headers.
---@return table handle The response handle.
local function response(code, body, headers)
    return {
        getResponseCode = function() return code end,
        getResponseHeaders = function() return headers or { ["Content-Type"] = "text/plain" } end,
        readAll = function() return body end,
        close = function() end,
    }
end

-- MARK: Functions
local fakeHttp = {}

--- Installs the fake `http` API.
--- Routes map URLs to a body string, or to `{ code = 404 }` style tables; unknown URLs return 404.
---@param routes table<string, string|{ code: integer, body: string|nil, headers: table|nil }> The canned responses.
---@param blocked string[]|nil URL prefixes the fake server's HTTP rules block.
function fakeHttp.install(routes, blocked)
    saved = saved or _G.http
    requests = {}
    posts = {}
    _G.http = {
        request = function(url, body, headers)
            posts[#posts + 1] = { url = url, body = body, headers = headers }
            return true
        end,

        checkURL = function(url)
            for _, prefix in ipairs(blocked or {}) do
                if url:sub(1, #prefix) == prefix then
                    return false, "Domain not permitted"
                end
            end
            return true
        end,

        get = function(options)
            -- Record the request
            local url = type(options) == "table" and options.url or options
            requests[#requests + 1] = url

            -- Answer from the routes
            local route = routes[url]
            if type(route) == "string" then
                return response(200, route)
            end
            local code = route and route.code or 404
            if code == 200 then
                return response(200, route.body or "", route.headers)
            end
            return nil, "HTTP " .. code, response(code, "")
        end,
    }
end

--- Restores the real `http` API.
function fakeHttp.restore()
    if saved then
        _G.http = saved
        saved = nil
    end
end

--- Lists the URLs requested since the fake was installed.
---@return string[] urls The requested URLs, in order.
function fakeHttp.requests()
    return requests
end

--- Lists the requests sent with `http.request` since the fake was installed.
---@return { url: string, body: string|nil, headers: table|nil }[] posts The requests, in order.
function fakeHttp.posts()
    return posts
end

return fakeHttp
