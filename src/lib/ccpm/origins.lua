-- CCPM Origins
--
-- Tells the external catalogs packages were synced from when one of their projects is installed, so authors keep their download counts.

-- MARK: Constants
local PINESTORE_DOWNLOAD_URL = "https://pinestore.cc/api/log/download"
local JSON_HEADERS = { ["Content-Type"] = "application/json" }

-- Reports keyed by source name
local REPORTERS = {
    pinestore = function(origin)
        http.request(PINESTORE_DOWNLOAD_URL, textutils.serializeJSON({ projectId = origin.id }), JSON_HEADERS)
    end,
}

-- MARK: Functions
local origins = {}

---@class Origin
---@field source string The external source, like `pinestore`.
---@field id string The project's ID in that source.
---@field url string The project's page.

--- Reports an install to the source a package was synced from, without waiting for or depending on the answer.
---@param origin Origin|nil The package's origin, from its index entry.
function origins.reportInstall(origin)
    local reporter = type(origin) == "table" and REPORTERS[origin.source]
    if not reporter or not http then
        return
    end

    -- Never let reporting break an install
    pcall(reporter, origin)
end

return origins
