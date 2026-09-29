-- CCPM Semver
--
-- Parses semantic versions and the version range syntax shared with the CCPM registry's `semver.py`.

-- MARK: Constants
local IDENTIFIER_PATTERN = "^[%w%-]+$"
local NUMBER_PATTERN = "^%d+$"
local ALTERNATIVE_SEPARATOR = "||"

-- Longer operators come first so `>=` is not read as `>`
local OPERATORS = { "^", "~", ">=", "<=", ">", "<", "=" }
local ANY_RANGES = { [""] = true, ["*"] = true }

-- MARK: Classes
---@class Version
---@field major integer
---@field minor integer
---@field patch integer
---@field prerelease string[]
local Version = {}
Version.__index = Version

---@class VersionRange
---@field alternatives { op: string, version: Version }[][]
local Range = {}
Range.__index = Range

-- MARK: Private Functions
--- Creates a version.
---@param major integer The major part.
---@param minor integer The minor part.
---@param patch integer The patch part.
---@param prerelease string[]|nil The prerelease identifiers.
---@return Version version The version.
local function newVersion(major, minor, patch, prerelease)
    return setmetatable({ major = major, minor = minor, patch = patch, prerelease = prerelease or {} }, Version)
end

--- Compares two prerelease identifier lists by semver precedence.
---@param a string[] The first identifiers.
---@param b string[] The second identifiers.
---@return integer order `-1`, `0`, or `1`.
local function comparePrerelease(a, b)
    -- Releases sort above their prereleases
    if #a == 0 or #b == 0 then
        return (#a == #b) and 0 or ((#a == 0) and 1 or -1)
    end

    -- Compare identifier by identifier
    for i = 1, math.max(#a, #b) do
        local x, y = a[i], b[i]
        if x == nil then
            return -1
        elseif y == nil then
            return 1
        end

        -- Numeric identifiers sort numerically and below alphanumeric ones
        local xNumber = x:match(NUMBER_PATTERN) and tonumber(x)
        local yNumber = y:match(NUMBER_PATTERN) and tonumber(y)
        if xNumber and yNumber then
            if xNumber ~= yNumber then
                return (xNumber < yNumber) and -1 or 1
            end
        elseif xNumber or yNumber then
            return xNumber and -1 or 1
        elseif x ~= y then
            return (x < y) and -1 or 1
        end
    end

    return 0
end

--- Compares two versions by semver precedence.
---@param a Version The first version.
---@param b Version The second version.
---@return integer order `-1`, `0`, or `1`.
local function compare(a, b)
    for _, key in ipairs({ "major", "minor", "patch" }) do
        if a[key] ~= b[key] then
            return (a[key] < b[key]) and -1 or 1
        end
    end

    return comparePrerelease(a.prerelease, b.prerelease)
end

--- Splits text on a plain separator, keeping empty pieces.
---@param text string The text to split.
---@param separator string The plain separator.
---@return string[] pieces The pieces.
local function split(text, separator)
    local pieces = {}
    local start = 1
    while true do
        local first, last = text:find(separator, start, true)
        if not first then
            pieces[#pieces + 1] = text:sub(start)
            return pieces
        end
        pieces[#pieces + 1] = text:sub(start, first - 1)
        start = last + 1
    end
end

--- Parses a possibly partial version like `1`, `1.20`, or `1.20.1-beta`.
---@param text string The version text.
---@return integer[]|nil parts The numeric parts given, or `nil` if invalid.
---@return string[]|string prerelease The prerelease identifiers, or the error message.
local function parseParts(text)
    local invalid = "`" .. text .. "` is not a version"

    -- Split the prerelease from the numeric core
    local core, prerelease = text:match("^([^-]*)%-(.*)$")
    core = core or text

    -- Read the numeric parts without leading zeros
    local parts = {}
    for _, piece in ipairs(split(core, ".")) do
        if not piece:match(NUMBER_PATTERN) or (#piece > 1 and piece:sub(1, 1) == "0") then
            return nil, invalid
        end
        parts[#parts + 1] = tonumber(piece)
    end
    if #parts > 3 then
        return nil, invalid
    end

    -- Read the prerelease, which only a full version may have
    local identifiers = {}
    if prerelease then
        if #parts ~= 3 then
            return nil, invalid
        end
        for _, identifier in ipairs(split(prerelease, ".")) do
            if not identifier:match(IDENTIFIER_PATTERN) then
                return nil, invalid
            end
            identifiers[#identifiers + 1] = identifier
        end
    end

    return parts, identifiers
end

--- Pads numeric parts to a full version.
---@param parts integer[] One to three numeric parts.
---@param prerelease string[]|nil The prerelease identifiers.
---@return Version version The padded version.
local function pad(parts, prerelease)
    return newVersion(parts[1], parts[2] or 0, parts[3] or 0, prerelease)
end

--- Gets the lowest version above every version starting with the given parts.
---@param parts integer[] One to three numeric parts, like `{ 1, 20 }`.
---@param count integer How many of the parts to keep.
---@return Version version The next version, like `1.21.0` for `{ 1, 20 }`.
local function bump(parts, count)
    local kept = { parts[1], parts[2], parts[3] }
    for i = count + 1, 3 do
        kept[i] = nil
    end
    kept[count] = kept[count] + 1

    return pad(kept)
end

--- Expands one range token into the comparisons it stands for.
---@param token string The token, like `^1.2.0`, `>=1.19`, or `1.20`.
---@return { op: string, version: Version }[]|nil comparators The comparisons, or `nil` if invalid.
---@return string|nil err The error message if invalid.
local function parseComparator(token)
    -- Split the operator from the version
    local op, rest = nil, token
    for _, candidate in ipairs(OPERATORS) do
        if token:sub(1, #candidate) == candidate then
            op, rest = candidate, token:sub(#candidate + 1)
            break
        end
    end
    local parts, prerelease = parseParts(rest)
    if not parts or #parts == 0 then
        return nil, "`" .. rest .. "` is not a version"
    end
    ---@cast prerelease string[]
    local lower = pad(parts, prerelease)
    local isFull = #parts == 3

    -- Match an exact version or every version starting with a partial one
    if op == nil or op == "=" then
        if isFull then
            return { { op = "=", version = lower } }
        end
        return { { op = ">=", version = lower }, { op = "<", version = bump(parts, #parts) } }
    end

    -- Allow changes that do not modify the leftmost non-zero part
    if op == "^" then
        local significant = #parts
        for i, part in ipairs(parts) do
            if part ~= 0 then
                significant = i
                break
            end
        end
        return { { op = ">=", version = lower }, { op = "<", version = bump(parts, significant) } }
    end

    -- Allow patch changes, or minor changes when only a major is given
    if op == "~" then
        return { { op = ">=", version = lower }, { op = "<", version = bump(parts, math.min(#parts, 2)) } }
    end

    -- Treat partial bounds as covering every version starting with them
    if op == ">" and not isFull then
        return { { op = ">=", version = bump(parts, #parts) } }
    elseif op == "<=" and not isFull then
        return { { op = "<", version = bump(parts, #parts) } }
    end

    return { { op = op, version = lower } }
end

--- Checks a version against one comparison.
---@param comparator { op: string, version: Version } The comparison.
---@param version Version The version to check.
---@return boolean passes If the version passes.
local function testComparator(comparator, version)
    local order = compare(version, comparator.version)
    local op = comparator.op
    if op == "=" then
        return order == 0
    elseif op == "<" then
        return order < 0
    elseif op == "<=" then
        return order <= 0
    elseif op == ">" then
        return order > 0
    end

    return order >= 0
end

-- MARK: Version
--- Formats the version as text.
---@return string text The version, like `1.2.3-beta.1`.
function Version:__tostring()
    local text = self.major .. "." .. self.minor .. "." .. self.patch
    if #self.prerelease > 0 then
        text = text .. "-" .. table.concat(self.prerelease, ".")
    end

    return text
end

function Version.__eq(a, b)
    return compare(a, b) == 0
end

function Version.__lt(a, b)
    return compare(a, b) < 0
end

function Version.__le(a, b)
    return compare(a, b) <= 0
end

--- Checks if the version has the same numbers as another, ignoring prereleases.
---@param other Version The other version.
---@return boolean same If the numbers match.
function Version:sameCore(other)
    return self.major == other.major and self.minor == other.minor and self.patch == other.patch
end

-- MARK: Range
--- Checks if a version satisfies the range.
--- Prereleases only satisfy an alternative that names a prerelease of the same `major.minor.patch`.
---@param version Version The version to check.
---@return boolean satisfies If the version satisfies the range.
function Range:test(version)
    for _, comparators in ipairs(self.alternatives) do
        -- Check every comparison
        local passes = true
        for _, comparator in ipairs(comparators) do
            if not testComparator(comparator, version) then
                passes = false
                break
            end
        end

        -- Only allow prereleases the range opted into
        if passes and #version.prerelease > 0 then
            passes = false
            for _, comparator in ipairs(comparators) do
                if #comparator.version.prerelease > 0 and comparator.version:sameCore(version) then
                    passes = true
                    break
                end
            end
        end

        if passes then
            return true
        end
    end

    return false
end

--- Picks the highest version that satisfies the range.
---@param versions Version[] The candidate versions.
---@return Version|nil best The highest satisfying version, or `nil` if none satisfy it.
function Range:best(versions)
    local best = nil
    for _, version in ipairs(versions) do
        if self:test(version) and (best == nil or best < version) then
            best = version
        end
    end

    return best
end

-- MARK: Functions
local semver = {}

--- Parses a full semantic version like `1.2.3` or `1.2.3-beta.1`.
---@param text string The version text.
---@return Version|nil version The version, or `nil` if the text is not a full semantic version.
---@return string|nil err The error message if invalid.
function semver.parse(text)
    local parts, prerelease = parseParts(text)
    if not parts or #parts ~= 3 then
        return nil, "`" .. text .. "` is not a semantic version like `1.2.3`"
    end
    ---@cast prerelease string[]
    local version = pad(parts, prerelease)

    return version, nil
end

--- Parses a version range.
--- The syntax is a subset of npm's: `*`, `1.2.3`, `1.20`, `^1.2.0`, `~1.2.0`, `>=1.19 <1.21`, and alternatives joined by `||`.
---@param text string The range text.
---@return VersionRange|nil range The range, or `nil` if invalid.
---@return string|nil err The error message if invalid.
function semver.parseRange(text)
    local alternatives = {}
    for _, alternative in ipairs(split(text, ALTERNATIVE_SEPARATOR)) do
        -- Collect the tokens
        local tokens = {}
        for token in alternative:gmatch("%S+") do
            tokens[#tokens + 1] = token
        end

        -- Treat an empty or wildcard alternative as matching everything
        local comparators = {}
        if not (#tokens == 0 or (#tokens == 1 and ANY_RANGES[tokens[1]])) then
            for _, token in ipairs(tokens) do
                local expanded, err = parseComparator(token)
                if not expanded then
                    return nil, "`" .. text .. "` is not a valid range: " .. err
                end
                for _, comparator in ipairs(expanded) do
                    comparators[#comparators + 1] = comparator
                end
            end
        end
        alternatives[#alternatives + 1] = comparators
    end

    local range = setmetatable({ alternatives = alternatives }, Range)

    return range, nil
end

--- Reads a version from loose text like `1.20` or `1.20.1-pre1`, padding missing parts with zeros.
---@param text string The text to read.
---@return Version|nil version The version, or `nil` if the text does not start with a number.
function semver.coerce(text)
    local major, rest = text:match("^%s*(%d+)(.*)$")
    if not major then
        return nil
    end

    -- Read up to two more parts
    local parts = { tonumber(major) }
    for _ = 1, 2 do
        local part, remaining = rest:match("^%.(%d+)(.*)$")
        if not part then
            break
        end
        parts[#parts + 1] = tonumber(part)
        rest = remaining
    end

    return pad(parts)
end

return semver
