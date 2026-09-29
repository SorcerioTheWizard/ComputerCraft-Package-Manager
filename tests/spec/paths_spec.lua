-- CCPM Paths Spec
--
-- Tests for `ccpm.paths`.

-- MARK: Imports
local paths = require("ccpm.paths")

-- MARK: Tests
describe("paths", function()
    afterEach(function()
        paths.setRoot(nil)
    end)

    it("defaults to /ccpm", function()
        check.equals(paths.root(), "/ccpm")
        check.equals(paths.bin(), "/ccpm/bin")
        check.equals(paths.lib(), "/ccpm/lib")
        check.equals(paths.pkg(), "/ccpm/pkg")
        check.equals(paths.etc(), "/ccpm/etc")
        check.equals(paths.cache(), "/ccpm/cache")
    end)

    it("places package data under the root", function()
        check.equals(paths.data("orescanner"), "/ccpm/data/orescanner")
    end)

    it("normalizes a custom root", function()
        paths.setRoot("sandbox//root/")
        check.equals(paths.root(), "/sandbox/root")
        check.equals(paths.bin(), "/sandbox/root/bin")
    end)

    it("keeps startup at the system level", function()
        paths.setRoot("/sandbox")
        check.equals(paths.startup(), "/startup")
    end)
end)
