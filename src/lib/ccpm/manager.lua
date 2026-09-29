-- CCPM Manager
--
-- The high level install, update, and remove operations shared by the `ccpm` program and the `ccpm` library.

-- MARK: Imports
local env = require("ccpm.env")
local installer = require("ccpm.installer")
local origins = require("ccpm.origins")
local registry = require("ccpm.registry")
local resolver = require("ccpm.resolver")
local state = require("ccpm.state")
local ui = require("ccpm.ui")

-- MARK: Constants
local ANY_VERSION = "*"
local DEFAULT_INTRO = "CCPM will make these changes:"

-- MARK: Private Functions
--- Maps installed records by name.
---@return table<string, InstalledPackage> installed The records keyed by name.
local function installedByName()
    local installed = {}
    for _, record in ipairs(state.list()) do
        installed[record.name] = record
    end

    return installed
end

--- Loads everything the resolver needs.
---@param options { force: boolean|nil, refresh: boolean|nil }|nil The options.
---@return ResolveContext|nil context The context, or `nil` if the registries could not be loaded.
---@return string|nil err The error message if they could not.
local function loadContext(options)
    options = options or {}
    local registries, err = registry.loadAll(options.refresh ~= false)
    if not registries then
        return nil, err
    end

    return { registries = registries, installed = installedByName(), environment = env.current(), force = options.force }
end

-- MARK: Functions
local manager = {}

---@class PackageSpec
---@field name string The package name.
---@field range string The accepted version range.

--- Parses a package argument like `tool`, `tool@^1.2`, or `pinestore/radar`.
---@param text string The argument.
---@return PackageSpec spec The name and range.
function manager.parseSpec(text)
    local name, range = text:match("^([^@]+)@(.*)$")
    if not name then
        return { name = text, range = ANY_VERSION }
    end

    return { name = name, range = (range ~= "") and range or ANY_VERSION }
end

--- Plans installing packages and their dependencies.
---@param specs PackageSpec[] The packages to install.
---@param options { force: boolean|nil, refresh: boolean|nil }|nil `force` ignores compatibility errors; `refresh` defaults to downloading fresh indexes.
---@return Plan|nil plan The plan, or `nil` if it cannot be satisfied.
---@return string|nil err The error message if it cannot.
function manager.planInstall(specs, options)
    local context, err = loadContext(options)
    if not context then
        return nil, err
    end

    local requests = {}
    for _, spec in ipairs(specs) do
        requests[#requests + 1] = { name = spec.name, range = spec.range, explicit = true }
    end

    -- Remember the requests so installed dependencies asked for by name become explicit
    local plan, resolveErr = resolver.resolve(context, requests)
    if plan then
        plan.promote = {}
        for _, spec in ipairs(specs) do
            plan.promote[spec.name] = spec.range
        end
    end

    return plan, resolveErr
end

--- Plans updating installed packages to the newest versions their ranges allow.
---@param names string[]|nil The packages to update, or `nil` to update everything.
---@param options { force: boolean|nil, refresh: boolean|nil }|nil `force` ignores compatibility errors; `refresh` defaults to downloading fresh indexes.
---@return Plan|nil plan The plan, or `nil` if it cannot be satisfied.
---@return string|nil err The error message if it cannot.
function manager.planUpdate(names, options)
    local context, err = loadContext(options)
    if not context then
        return nil, err
    end

    -- Default to every installed package
    if not names then
        names = {}
        for _, record in ipairs(state.list()) do
            names[#names + 1] = record.name
        end
    end

    -- Keep each package within the range the user installed it with
    local requests = {}
    for _, name in ipairs(names) do
        local record = context.installed[name]
        if not record then
            return nil, name .. " is not installed"
        end
        requests[#requests + 1] = { name = name, range = record.range or ANY_VERSION, explicit = record.explicit, upgrade = true }
    end

    return resolver.resolve(context, requests)
end

--- Applies a plan.
---@param plan Plan The plan.
---@param force boolean|nil If unmanaged files may be overwritten.
---@return string[]|nil removed Dependencies no longer needed and removed afterwards, or `nil` if the plan was not applied.
---@return string|nil err The error message if it was not applied.
function manager.apply(plan, force)
    local removed, err = installer.apply(plan, force)
    if not removed then
        return nil, err
    end

    -- Tell external catalogs about installs of their projects
    for _, step in ipairs(plan.steps) do
        local entry = step.registry.packages[step.name]
        origins.reportInstall(entry and entry.origin)
    end

    -- Mark installed dependencies the user asked for by name as explicit
    for _, name in ipairs(plan.unchanged) do
        local record = plan.promote and plan.promote[name] and state.get(name)
        if record and not record.explicit then
            record.explicit = true
            record.range = plan.promote[name]
            state.put(record)
        end
    end

    return removed
end

---@class ConfirmOptions
---@field yes boolean|nil If the question should be skipped.
---@field force boolean|nil If unmanaged files may be overwritten.
---@field nothing string|nil What to say when the plan changes nothing.
---@field intro string|nil The line shown above the changes.

--- Shows a plan, asks before applying it, and reports the result.
---@param plan Plan The plan.
---@param options ConfirmOptions How to present and apply it.
---@return boolean ok If the plan was applied or had nothing to do.
---@return string|nil err Why it was not applied, `cancelled` if the user declined.
function manager.confirmAndApply(plan, options)
    -- Report requests that are already satisfied
    for _, name in ipairs(plan.unchanged) do
        local record = state.get(name)
        ui.muted(name .. " " .. (record and record.version or "") .. " is already installed.")
    end

    -- Apply quietly when nothing is downloaded
    if #plan.steps == 0 then
        manager.apply(plan, options.force)
        if #plan.unchanged == 0 and options.nothing then
            ui.info(options.nothing)
        end
        return true
    end

    -- Show what will change
    ui.info(options.intro or DEFAULT_INTRO)
    for _, step in ipairs(plan.steps) do
        if step.previous then
            ui.info("  ~ " .. step.name .. " " .. step.previous.version .. " -> " .. step.version)
        else
            ui.info("  + " .. step.name .. " " .. step.version .. (step.explicit and "" or " (dependency)"))
        end
        for _, warning in ipairs(step.warnings) do
            ui.warn("    ! " .. warning)
        end

        -- Warn that installers run code CCPM cannot check or undo
        if step.manifest.kind == "installer" then
            ui.warn("    ! runs `" .. step.manifest.installer.command .. "`, which CCPM cannot check, and the files it creates will not be tracked")
        end

        -- Warn about files downloaded live, like the source's own install command would
        for _, file in ipairs(step.manifest.files or {}) do
            if not file.sha256 then
                ui.warn("    ! files are not verified against a published hash")
                break
            end
        end
    end

    -- Ask first
    if not options.yes and not ui.confirm("Continue?") then
        ui.info("Cancelled.")
        return false, "cancelled"
    end

    -- Apply it
    local removed, err = manager.apply(plan, options.force)
    if not removed then
        ui.error(err or "the changes could not be applied")
        return false, err
    end
    ui.success("Done. " .. #plan.steps .. " package(s) changed.")
    for _, name in ipairs(removed) do
        ui.muted("Removed " .. name .. ", which nothing needs anymore.")
    end

    return true
end

--- Removes packages, and the dependencies nothing else needs afterwards.
---@param names string[] The packages to remove.
---@param cascade boolean|nil If packages depending on them should be removed too.
---@return string[]|nil removed Every package removed, or `nil` if nothing was removed.
---@return string|nil err The error message if nothing was removed.
---@return string[]|nil untracked The removed packages that ran their own installers, whose files were left in place.
function manager.remove(names, cascade)
    return installer.remove(names, cascade)
end

return manager
