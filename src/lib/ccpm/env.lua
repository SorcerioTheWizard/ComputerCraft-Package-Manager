-- CCPM Environment
--
-- Reads the ComputerCraft and Minecraft versions from `_HOST` and checks packages' compatibility ranges against them.

-- MARK: Imports
local semver = require("ccpm.semver")

-- MARK: Constants
local MINECRAFT = "Minecraft"

-- Names of the `compat` keys and how to describe them
local COMPAT_LABELS = { cc = "ComputerCraft", mc = "Minecraft" }
local COMPAT_ORDER = { "cc", "mc" }

-- MARK: Functions
local env = {}

---@class Environment
---@field host string The raw `_HOST` text.
---@field cc Version|nil The ComputerCraft version, if it could be read.
---@field mc Version|nil The Minecraft version, if running in Minecraft.
---@field platform string `Minecraft`, or the emulator name, like `CraftOS-PC v2.8.3`.
---@field kind string|nil `computer`, `turtle`, `pocket`, or `command`.
---@field color boolean|nil If the computer is advanced.

--- Reads versions from `_HOST` style text, like `ComputerCraft 1.93.0 (Minecraft 1.15.2)`.
---@param host string The host text.
---@return Environment environment The environment, without the computer kind.
function env.parse(host)
    -- Read the ComputerCraft version
    local ccText = host:match("^ComputerCraft (%S+)")

    -- Read what is running ComputerCraft
    local platform = host:match("%((.+)%)%s*$") or "unknown"
    local mcText = platform:match("^" .. MINECRAFT .. " (%S+)$")

    return {
        host = host,
        cc = ccText and semver.coerce(ccText),
        mc = mcText and semver.coerce(mcText),
        platform = mcText and MINECRAFT or platform,
    }
end

--- Describes the computer this is running on.
---@return Environment environment The environment.
function env.current()
    local environment = env.parse(_HOST or "")

    -- Tell the kinds of computer apart
    if turtle then
        environment.kind = "turtle"
    elseif pocket then
        environment.kind = "pocket"
    elseif commands then
        environment.kind = "command"
    else
        environment.kind = "computer"
    end
    environment.color = term.isColor()

    return environment
end

--- Checks a package's compatibility ranges against an environment.
---@param compat table<string, string>|nil The `compat` ranges, keyed by `cc` and `mc`.
---@param environment Environment The environment to check.
---@return string[] errors Reasons the package does not work here.
---@return string[] warnings Reasons it might not work here.
function env.checkCompat(compat, environment)
    local errors, warnings = {}, {}
    for _, key in ipairs(COMPAT_ORDER) do
        local text = compat and compat[key]
        local label = COMPAT_LABELS[key]
        if text then
            local range = semver.parseRange(text)
            local version = environment[key]
            if not range then
                -- Skip ranges this client cannot read
                warnings[#warnings + 1] = "ignoring the unreadable " .. label .. " range `" .. text .. "`"
            elseif not version then
                -- Warn when the version cannot be read, like Minecraft on an emulator
                warnings[#warnings + 1] = "needs " .. label .. " `" .. text .. "`, but this computer's " .. label .. " version is unknown (" .. environment.platform .. ")"
            elseif not range:test(version) then
                errors[#errors + 1] = "needs " .. label .. " `" .. text .. "`, but this computer runs " .. tostring(version)
            end
        end
    end

    return errors, warnings
end

return env
