-- CCPM Net Spec
--
-- Tests for `ccpm.net`.

-- MARK: Imports
local net = require("ccpm.net")
local files = require("ccpm.files")
local fakeHttp = require("support.fake_http")
local sandbox = require("support.sandbox")

-- MARK: Constants
local BASE = "https://example.com/"

-- MARK: Tests
describe("net", function()
    sandbox.use()

    beforeEach(function()
        fakeHttp.install({
            [BASE .. "text"] = "hello\r\n",
            [BASE .. "data.json"] = '{"a":[1,2]}',
            [BASE .. "bad.json"] = "{",
            [BASE .. "error"] = { code = 500 },
        }, { "https://blocked.example/" })
    end)

    it("downloads bytes", function()
        check.equals(net.get(BASE .. "text"), "hello\r\n")
    end)

    it("explains HTTP failures", function()
        local body, err = net.get(BASE .. "error")
        check.equals(body, nil)
        check.contains(err, "HTTP 500")

        _, err = net.get(BASE .. "missing")
        check.contains(err, "HTTP 404")
    end)

    it("explains blocked URLs without requesting them", function()
        local body, err = net.get("https://blocked.example/x")
        check.equals(body, nil)
        check.contains(err, "blocked by this server's HTTP rules")
        check.same(fakeHttp.requests(), {})
    end)

    it("explains a disabled HTTP API", function()
        _G.http = nil
        local _, err = net.get(BASE .. "text")
        check.contains(err, "HTTP is disabled")
    end)

    it("decodes JSON", function()
        check.same(net.getJSON(BASE .. "data.json"), { a = { 1, 2 } })

        local data, err = net.getJSON(BASE .. "bad.json")
        check.equals(data, nil)
        check.contains(err, "is not valid JSON")
    end)

    it("downloads into files", function()
        check.truthy(net.download(BASE .. "text", "/sandbox/out.txt"))
        check.equals(files.read("/sandbox/out.txt"), "hello\r\n")

        local ok, err = net.download(BASE .. "missing", "/sandbox/missing.txt")
        check.falsy(ok)
        check.contains(err, "404")
        check.falsy(fs.exists("/sandbox/missing.txt"))
    end)
end)
