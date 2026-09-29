-- CCPM Config Spec
--
-- Tests for `ccpm.config`.

-- MARK: Imports
local config = require("ccpm.config")
local files = require("ccpm.files")
local sandbox = require("support.sandbox")

-- MARK: Tests
describe("config", function()
    sandbox.use()

    it("defaults to the primary registry", function()
        local loaded = config.load()
        check.same(loaded.registries, { config.primaryRegistry() })
        check.same(loaded.hosts, {})
    end)

    it("round-trips changes", function()
        local loaded = config.load()
        loaded.hosts[#loaded.hosts + 1] = "https://example.com/"
        loaded.registries[#loaded.registries + 1] = { name = "extra", url = "https://example.com/registry/" }
        config.save(loaded)

        check.same(config.load(), loaded)
    end)

    it("recovers from a damaged file", function()
        files.write("/sandbox/etc/config.json", "garbage")
        check.same(config.load().registries, { config.primaryRegistry() })
    end)

    it("matches URL prefixes", function()
        local prefixes = { "https://raw.githubusercontent.com/", "https://pastebin.com/raw/" }
        check.truthy(config.isAllowedUrl("https://pastebin.com/raw/abc", prefixes))
        check.falsy(config.isAllowedUrl("https://pastebin.com/abc", prefixes))
        check.falsy(config.isAllowedUrl("http://raw.githubusercontent.com/x", prefixes))
    end)
end)
