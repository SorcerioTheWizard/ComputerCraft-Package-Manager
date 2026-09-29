-- CCPM Registry Spec
--
-- Tests for `ccpm.registry`.

-- MARK: Imports
local config = require("ccpm.config")
local fakeHttp = require("support.fake_http")
local fakeRegistry = require("support.fake_registry")
local registry = require("ccpm.registry")
local sandbox = require("support.sandbox")

-- MARK: Tests
describe("registry", function()
    sandbox.use()

    local served

    beforeEach(function()
        served = fakeRegistry.new()
        served:add("tool", "1.0.0"):add("tool", "1.10.0"):add("tool", "1.2.0")
        served:add("radar", "0.1.0")
        served:serve()
    end)

    it("downloads and caches the index", function()
        local loaded = assert(registry.loadAll())
        check.equals(#loaded, 1)
        check.same(loaded[1].hosts, { "https://raw.githubusercontent.com/" })
        check.truthy(fs.exists("/sandbox/cache/test.json"))

        -- Read the cache without downloading again
        fakeHttp.install({})
        check.truthy(registry.loadAll())

        -- Download again when refreshing
        local _, err = registry.loadAll(true)
        check.contains(err, "could not be loaded")
    end)

    it("adds the user's hosts", function()
        local settings = config.load()
        settings.hosts = { "https://example.com/" }
        config.save(settings)

        local loaded = assert(registry.loadAll())
        check.same(loaded[1].hosts, { "https://raw.githubusercontent.com/", "https://example.com/" })
    end)

    it("rejects index formats it cannot read", function()
        fakeHttp.install({ [fakeRegistry.URL .. "index.json"] = '{"format":2,"packages":{}}' })
        local _, err = registry.loadAll(true)
        check.contains(err, "run `ccpm upgrade`")
    end)

    it("sorts versions and fetches manifests", function()
        local loaded = assert(registry.loadAll())
        local entry, source = registry.find(loaded, "tool")
        check.truthy(entry)
        ---@cast entry IndexEntry
        ---@cast source LoadedRegistry

        local texts = {}
        for i, version in ipairs(registry.versions(entry)) do
            texts[i] = tostring(version)
        end
        check.same(texts, { "1.10.0", "1.2.0", "1.0.0" })

        local manifest = assert(registry.fetchManifest(source, "tool", "1.2.0"))
        check.equals(manifest.files[1].path, "bin/tool.lua")
        check.equals(registry.find(loaded, "missing"), nil)
    end)

    it("prefers the first registry listing a package", function()
        local first = { name = "first", packages = { tool = { description = "first" } } }
        local second = { name = "second", packages = { tool = { description = "second" }, extra = { description = "extra" } } }

        local entry, source = registry.find({ first, second }, "tool")
        check.equals(entry and entry.description, "first")
        check.equals(source and source.name, "first")
    end)

    it("searches names, descriptions, and tags", function()
        local loaded = assert(registry.loadAll())
        loaded[1].packages.radar.tags = { "mining" }

        local names = {}
        for _, result in ipairs(registry.search(loaded, "MINING radar")) do
            names[#names + 1] = result.name
        end
        check.same(names, { "radar" })
        check.equals(#registry.search(loaded, "package"), 2)
        check.equals(#registry.search(loaded, "nothing"), 0)
    end)

    it("matches the starts of words and ranks name matches first", function()
        local source = {
            name = "test",
            packages = {
                shovel = { description = "Digs more dirt." },
                orescanner = { description = "Finds ores." },
                mapper = { description = "Maps ore veins." },
            },
        }

        local names = {}
        for i, result in ipairs(registry.search({ source }, "ore")) do
            names[i] = result.name
        end
        check.same(names, { "orescanner", "mapper" })
    end)
end)
