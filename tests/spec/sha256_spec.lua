-- CCPM SHA-256 Spec
--
-- Tests for `ccpm.sha256` against digests computed with Python's `hashlib`.

-- MARK: Imports
local sha256 = require("ccpm.sha256")

-- MARK: Constants
local ALL_BYTES = {}
for i = 0, 255 do
    ALL_BYTES[#ALL_BYTES + 1] = string.char(i)
end

local VECTORS = {
    { "", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" },
    { "abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" },
    { "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1" },
    { string.rep("a", 55), "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318" },
    { string.rep("a", 56), "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a" },
    { string.rep("a", 63), "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34" },
    { string.rep("a", 64), "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb" },
    { string.rep("a", 1000), "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3" },
    { table.concat(ALL_BYTES), "40aff2e9d2d8922e47afd4648e6967497158785fbd1da870e7110266bf944880" },
}

-- MARK: Tests
describe("sha256.hex", function()
    for _, vector in ipairs(VECTORS) do
        it("hashes " .. #vector[1] .. " bytes", function()
            check.equals(sha256.hex(vector[1]), vector[2])
        end)
    end

    it("hashes large input without erroring", function()
        check.equals(#sha256.hex(string.rep("x", 100000)), 64)
    end)
end)
