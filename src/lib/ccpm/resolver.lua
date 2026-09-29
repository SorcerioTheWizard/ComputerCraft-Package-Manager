-- CCPM Resolver
--
-- Turns install and update requests into a plan of package versions that satisfy every dependency range and compatibility check.

-- MARK: Imports
local env = require("ccpm.env")
local registry = require("ccpm.registry")
local semver = require("ccpm.semver")

-- MARK: Constants
-- Constraints are keyed by `name@version`, so the user's key cannot clash with a package
local REQUESTED_BY_USER = "you"

-- Give up on dependency graphs that would take too long to search
local MAX_ATTEMPTS = 500

-- MARK: Types
---@class ResolveRequest
---@field name string The package name.
---@field range string The accepted version range.
---@field explicit boolean If the user asked for the package, rather than it being a dependency.
---@field upgrade boolean|nil If a newer version should replace an installed one that still satisfies the range.

---@class PlanStep
---@field name string The package name.
---@field version string The version to install.
---@field previous InstalledPackage|nil The installed record being replaced.
---@field registry LoadedRegistry The registry it comes from.
---@field manifest table The version manifest.
---@field explicit boolean If the user asked for the package.
---@field range string|nil The range the user asked for, kept so updates respect it.
---@field warnings string[] Compatibility warnings.

---@class Plan
---@field steps PlanStep[] Changes in dependency order, dependencies first.
---@field unchanged string[] Requested packages that were already installed at the version to use.

---@class ResolveContext
---@field registries LoadedRegistry[] The registries in priority order.
---@field installed table<string, InstalledPackage> Installed records keyed by name.
---@field environment Environment The computer to check compatibility against.
---@field force boolean|nil If compatibility errors should be ignored.

---@alias Constraints table<string, { range: VersionRange, text: string }>

---@class SearchState
---@field chosen table<string, { version: Version, step: PlanStep|nil }> Versions picked so far; kept installed versions have no step.
---@field constraints table<string, Constraints> Ranges each package must satisfy, keyed by package name.
---@field queue string[] Packages still to pick versions for.

-- MARK: Private Functions
--- Formats who requires which range of a package, for error messages.
---@param constraints Constraints The constraints keyed by who added them.
---@return string text The description, like `app@1.2.0 (^1.1.0), you (^1.0.0)`.
local function describeConstraints(constraints)
    local parts = {}
    for source, constraint in pairs(constraints) do
        parts[#parts + 1] = source .. " (" .. constraint.text .. ")"
    end
    table.sort(parts)

    return table.concat(parts, ", ")
end

--- Checks a version against every constraint.
---@param constraints Constraints The constraints keyed by who added them.
---@param version Version The version.
---@return boolean satisfied If every constraint passes.
local function satisfiesAll(constraints, version)
    for _, constraint in pairs(constraints) do
        if not constraint.range:test(version) then
            return false
        end
    end

    return true
end

--- Lists the keys of a table in sorted order.
---@param map table<string, any>|nil The table.
---@return string[] keys The sorted keys.
local function sortedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys)

    return keys
end

--- Copies a search state so a branch can change it without affecting others.
---@param state SearchState The state.
---@return SearchState copy The copy.
local function copyState(state)
    local copy = { chosen = {}, constraints = {}, queue = {} }
    for name, picked in pairs(state.chosen) do
        copy.chosen[name] = picked
    end
    for name, byName in pairs(state.constraints) do
        copy.constraints[name] = {}
        for source, constraint in pairs(byName) do
            copy.constraints[name][source] = constraint
        end
    end
    for i, name in ipairs(state.queue) do
        copy.queue[i] = name
    end

    return copy
end

--- Adds a constraint on a package.
---@param state SearchState The state to change.
---@param name string The constrained package.
---@param source string Who adds it, like `tool@1.2.0` or `you`.
---@param text string The range.
---@return string|nil err The error message if the range is invalid.
local function constrain(state, name, source, text)
    local range, err = semver.parseRange(text)
    if not range then
        return source .. " requires " .. name .. " with " .. err
    end
    state.constraints[name] = state.constraints[name] or {}
    state.constraints[name][source] = { range = range, text = text }

    return nil
end

--- Replaces the constraints a package places on its dependencies.
---@param state SearchState The state to change.
---@param owner string The package.
---@param version string The package version.
---@param dependencies table<string, string>|nil The ranges keyed by package name.
---@return string|nil err The error message if a range is invalid.
local function constrainFrom(state, owner, version, dependencies)
    -- Drop the constraints of any other version of the same package
    local prefix = owner .. "@"
    for _, byName in pairs(state.constraints) do
        for key in pairs(byName) do
            if key:sub(1, #prefix) == prefix then
                byName[key] = nil
            end
        end
    end

    -- Add the new ones
    for _, name in ipairs(sortedKeys(dependencies)) do
        local err = constrain(state, name, prefix .. version, dependencies[name])
        if err then
            return err
        end
    end

    return nil
end

-- MARK: Classes
---@class Resolution
---@field context ResolveContext What is available and installed.
---@field requests table<string, ResolveRequest> The requests keyed by name.
---@field manifests table<string, table|string> Downloaded manifests, or download errors, keyed by `name@version`.
---@field attempts integer How many versions have been tried.
---@field err string|nil The first reason a branch failed, reported if every branch fails.
local Resolution = {}
Resolution.__index = Resolution

--- Creates a resolution.
---@param context ResolveContext What is available and installed.
---@return Resolution resolution The resolution.
function Resolution.new(context)
    return setmetatable({ context = context, requests = {}, manifests = {}, attempts = 0 }, Resolution)
end

--- Records why a branch failed, keeping the first reason.
---@param message string The reason.
function Resolution:fail(message)
    self.err = self.err or message
end

--- Downloads a manifest once per resolution.
---@param source LoadedRegistry The registry listing the package.
---@param name string The package name.
---@param version string The version.
---@return table|nil manifest The manifest, or `nil` if it could not be downloaded.
---@return string|nil err The error message if it could not.
function Resolution:manifest(source, name, version)
    local key = name .. "@" .. version
    if self.manifests[key] == nil then
        local manifest, err = registry.fetchManifest(source, name, version)
        self.manifests[key] = manifest or err
    end

    local cached = self.manifests[key]
    if type(cached) == "string" then
        return nil, cached
    end

    return cached
end

--- Lists the versions to try for a package, best first.
--- The installed version comes first unless upgrading, so dependencies only change when they must.
---@param name string The package name.
---@return { version: Version, keep: boolean }[]|nil candidates The candidates, or `nil` if the package is unknown.
---@return LoadedRegistry|nil source The registry listing it.
function Resolution:candidates(name)
    local record = self.context.installed[name]
    local installedVersion = record and semver.parse(record.version)
    local request = self.requests[name]
    local candidates = {}

    -- Prefer keeping the installed version
    if installedVersion and not (request and request.upgrade) then
        candidates[#candidates + 1] = { version = installedVersion, keep = true }
    end

    -- Then try the registry's versions from highest to lowest
    local entry, source = registry.find(self.context.registries, name)
    if entry then
        for _, version in ipairs(registry.versions(entry)) do
            local isInstalled = installedVersion ~= nil and version == installedVersion
            if not (isInstalled and candidates[1] and candidates[1].keep) then
                candidates[#candidates + 1] = { version = version, keep = isInstalled }
            end
        end
    elseif not installedVersion then
        return nil, nil
    end

    return candidates, source
end

--- Picks a new version of a package in a state, queueing its dependencies.
---@param state SearchState The state to change.
---@param name string The package name.
---@param version Version The version.
---@param source LoadedRegistry The registry it comes from.
---@param manifest table The version manifest.
---@param warnings string[] Compatibility warnings.
---@return boolean ok If the version fits the versions already picked.
function Resolution:choose(state, name, version, source, manifest, warnings)
    -- Describe the change
    local record = self.context.installed[name]
    local request = self.requests[name]
    local step = {
        name = name,
        version = tostring(version),
        previous = record,
        registry = source,
        manifest = manifest,
        explicit = (request and request.explicit) or (record and record.explicit) or false,
        range = (request and request.explicit) and request.range or (record and record.range),
        warnings = warnings,
    }
    state.chosen[name] = { version = version, step = step }

    -- Replace its constraints with the new version's
    local err = constrainFrom(state, name, step.version, manifest.dependencies)
    if err then
        self:fail(err)
        return false
    end

    -- Reject it if it conflicts with a dependency already picked, otherwise queue the dependency
    for _, dependency in ipairs(sortedKeys(manifest.dependencies)) do
        local picked = state.chosen[dependency]
        local wanted = state.constraints[dependency]
        if picked and not satisfiesAll(wanted, picked.version) then
            self:fail("no single version of " .. dependency .. " satisfies " .. describeConstraints(wanted))
            return false
        end
        state.queue[#state.queue + 1] = dependency
    end

    return true
end

--- Searches for versions of every queued package, backtracking when a choice leads to a conflict.
---@param state SearchState The state to continue from.
---@return SearchState|nil solved The solved state, or `nil` if this branch has no solution.
function Resolution:search(state)
    -- Skip queued packages that are already satisfied
    local name
    while #state.queue > 0 do
        local queued = table.remove(state.queue, 1)
        local picked = state.chosen[queued]
        if not picked then
            name = queued
            break
        end
        if not satisfiesAll(state.constraints[queued] or {}, picked.version) then
            self:fail("no single version of " .. queued .. " satisfies " .. describeConstraints(state.constraints[queued]))
            return nil
        end
    end
    if not name then
        return state
    end

    -- Find what could be installed
    local wanted = state.constraints[name] or {}
    local candidates, source = self:candidates(name)
    if not candidates then
        self:fail("package `" .. name .. "` was not found in any registry")
        return nil
    end

    -- Try each satisfying candidate
    local incompatible = {}
    for _, candidate in ipairs(candidates) do
        if satisfiesAll(wanted, candidate.version) then
            -- Give up on graphs too large to search
            self.attempts = self.attempts + 1
            if self.attempts > MAX_ATTEMPTS then
                self.err = "the dependencies are too tangled to resolve; try installing fewer packages at once"
                return nil
            end

            local branch = copyState(state)
            local ok = true
            if candidate.keep then
                branch.chosen[name] = { version = candidate.version }
            else
                ---@cast source LoadedRegistry
                local manifest, err = self:manifest(source, name, tostring(candidate.version))
                if not manifest then
                    self:fail(err or "")
                    return nil
                end

                -- Skip versions that do not work on this computer unless forced
                local errors, warnings = env.checkCompat(manifest.compat, self.context.environment)
                if #errors > 0 and not self.context.force then
                    incompatible[#incompatible + 1] = tostring(candidate.version) .. ": " .. table.concat(errors, "; ")
                    ok = false
                else
                    for i, message in ipairs(errors) do
                        table.insert(warnings, i, message)
                    end
                    ok = self:choose(branch, name, candidate.version, source, manifest, warnings)
                end
            end

            -- Continue down this branch
            if ok then
                local solved = self:search(branch)
                if solved then
                    return solved
                end
                if self.attempts > MAX_ATTEMPTS then
                    return nil
                end
            end
        end
    end

    -- Explain why nothing matched
    if #incompatible > 0 then
        self:fail("no version of " .. name .. " works on this computer (use --force to install anyway):\n  " .. table.concat(incompatible, "\n  "))
    else
        self:fail("no version of " .. name .. " satisfies " .. describeConstraints(wanted))
    end
    return nil
end

--- Orders the changes of a solved state so dependencies come first.
---@param solved SearchState The solved state.
---@param requests ResolveRequest[] The requests, whose order is kept where dependencies allow.
---@return Plan plan The plan.
function Resolution:toPlan(solved, requests)
    local plan = { steps = {}, unchanged = {} }
    local visited = {}

    -- Add each change after its dependencies
    local function add(name)
        if visited[name] then
            return
        end
        visited[name] = true
        local picked = solved.chosen[name]
        if picked and picked.step then
            for _, dependency in ipairs(sortedKeys(picked.step.manifest.dependencies)) do
                add(dependency)
            end
            plan.steps[#plan.steps + 1] = picked.step
        end
    end
    for _, request in ipairs(requests) do
        add(request.name)
        if not solved.chosen[request.name].step then
            plan.unchanged[#plan.unchanged + 1] = request.name
        end
    end

    return plan
end

-- MARK: Functions
local resolver = {}

--- Plans the changes needed to satisfy a set of requests.
---@param context ResolveContext What is available and installed.
---@param requests ResolveRequest[] The packages to install or update.
---@return Plan|nil plan The plan, or `nil` if the requests cannot be satisfied.
---@return string|nil err The error message if they cannot.
function resolver.resolve(context, requests)
    local resolution = Resolution.new(context)
    local state = { chosen = {}, constraints = {}, queue = {} }

    -- Start from what installed packages already require
    for _, name in ipairs(sortedKeys(context.installed)) do
        local record = context.installed[name]
        local err = constrainFrom(state, name, record.version, record.dependencies)
        if err then
            return nil, err
        end
    end

    -- Add what the user asked for
    for _, request in ipairs(requests) do
        local err = constrain(state, request.name, REQUESTED_BY_USER, request.range)
        if err then
            return nil, err
        end
        resolution.requests[request.name] = request
        state.queue[#state.queue + 1] = request.name
    end

    -- Search for a combination that works
    local solved = resolution:search(state)
    if not solved then
        return nil, resolution.err
    end

    return resolution:toPlan(solved, requests)
end

return resolver
