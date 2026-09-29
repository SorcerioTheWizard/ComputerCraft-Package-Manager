-- CCPM Files Spec
--
-- Tests for `ccpm.files`.

-- MARK: Imports
local files = require("ccpm.files")
local sandbox = require("support.sandbox")

-- MARK: Tests
describe("files", function()
    sandbox.use()

    it("round-trips bytes exactly", function()
        local bytes = "line\r\nnext\0\255"
        files.write("/sandbox/deep/dir/data.bin", bytes)

        check.equals(files.read("/sandbox/deep/dir/data.bin"), bytes)
        check.falsy(fs.exists("/sandbox/deep/dir/data.bin.tmp"))
    end)

    it("replaces existing files", function()
        files.write("/sandbox/a.txt", "old")
        files.write("/sandbox/a.txt", "new")

        check.equals(files.read("/sandbox/a.txt"), "new")
    end)

    it("round-trips JSON and reports invalid JSON", function()
        files.writeJSON("/sandbox/a.json", { name = "tool", list = { 1, 2 } })
        check.same(files.readJSON("/sandbox/a.json"), { name = "tool", list = { 1, 2 } })

        files.write("/sandbox/bad.json", "{ nope")
        local data, err = files.readJSON("/sandbox/bad.json")
        check.equals(data, nil)
        check.contains(err, "is not valid JSON")

        check.equals(files.readJSON("/sandbox/missing.json"), nil)
    end)

    it("prunes emptied folders up to the stop folder", function()
        files.write("/sandbox/lib/tool/util/a.lua", "a")
        files.write("/sandbox/lib/tool/b.lua", "b")

        files.deleteAndPrune("/sandbox/lib/tool/util/a.lua", "/sandbox/lib")
        check.falsy(fs.exists("/sandbox/lib/tool/util"))
        check.truthy(fs.exists("/sandbox/lib/tool"))

        files.deleteAndPrune("/sandbox/lib/tool/b.lua", "/sandbox/lib")
        check.falsy(fs.exists("/sandbox/lib/tool"))
        check.truthy(fs.exists("/sandbox/lib"))
    end)
end)
