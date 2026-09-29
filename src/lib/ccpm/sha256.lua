-- CCPM SHA-256
--
-- A pure Lua SHA-256 for checking downloaded files against the hashes recorded in the registry.

-- MARK: Imports
local band, bnot, bxor, rrotate, rshift = bit32.band, bit32.bnot, bit32.bxor, bit32.rrotate, bit32.rshift

-- MARK: Constants
local MODULUS = 2 ^ 32
local BLOCK_SIZE = 64

-- Yield this often so hashing large files does not trip the "too long without yielding" limit
local BLOCKS_PER_YIELD = 256
local YIELD_EVENT = "ccpm_sha256_yield"

local INITIAL_STATE = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
}

local ROUND_CONSTANTS = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

-- MARK: Private Functions
--- Pads a message to a whole number of blocks, ending with its bit length.
---@param data string The message.
---@return string padded The padded message.
local function pad(data)
    -- Append the end marker and zeros up to 8 bytes short of a block
    local zeros = (BLOCK_SIZE - (#data + 9) % BLOCK_SIZE) % BLOCK_SIZE
    local bits = #data * 8

    -- Append the bit length as a big-endian 64-bit number
    local length = {}
    for i = 8, 1, -1 do
        length[i] = string.char(bits % 256)
        bits = math.floor(bits / 256)
    end

    return data .. "\128" .. string.rep("\0", zeros) .. table.concat(length)
end

--- Mixes one block into the hash state.
---@param state integer[] The eight state words, updated in place.
---@param data string The padded message.
---@param offset integer The index of the block's first byte.
---@param words integer[] A reusable 64 word schedule.
local function processBlock(state, data, offset, words)
    -- Read the block as big-endian words
    for i = 1, 16 do
        local a, b, c, d = data:byte(offset + (i - 1) * 4, offset + (i - 1) * 4 + 3)
        words[i] = ((a * 256 + b) * 256 + c) * 256 + d
    end

    -- Extend the schedule
    for i = 17, 64 do
        local w15, w2 = words[i - 15], words[i - 2]
        local s0 = bxor(rrotate(w15, 7), rrotate(w15, 18), rshift(w15, 3))
        local s1 = bxor(rrotate(w2, 17), rrotate(w2, 19), rshift(w2, 10))
        words[i] = (words[i - 16] + s0 + words[i - 7] + s1) % MODULUS
    end

    -- Run the rounds
    local a, b, c, d, e, f, g, h = state[1], state[2], state[3], state[4], state[5], state[6], state[7], state[8]
    for i = 1, 64 do
        local s1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
        local choice = bxor(band(e, f), band(bnot(e), g))
        local temp1 = (h + s1 + choice + ROUND_CONSTANTS[i] + words[i]) % MODULUS
        local s0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
        local majority = bxor(band(a, b), band(a, c), band(b, c))
        local temp2 = (s0 + majority) % MODULUS

        h, g, f, e, d, c, b, a = g, f, e, (d + temp1) % MODULUS, c, b, a, (temp1 + temp2) % MODULUS
    end

    -- Add the result to the state
    local mixed = { a, b, c, d, e, f, g, h }
    for i = 1, 8 do
        state[i] = (state[i] + mixed[i]) % MODULUS
    end
end

-- MARK: Functions
local sha256 = {}

--- Hashes a string of bytes.
---@param data string The bytes to hash.
---@return string hex The lowercase hex digest.
function sha256.hex(data)
    -- Prepare the message and state
    local padded = pad(data)
    local state = { table.unpack(INITIAL_STATE) }
    local words = {}

    -- Mix in every block, yielding now and then
    local blocks = 0
    for offset = 1, #padded, BLOCK_SIZE do
        processBlock(state, padded, offset, words)
        blocks = blocks + 1
        if blocks % BLOCKS_PER_YIELD == 0 then
            os.queueEvent(YIELD_EVENT)
            os.pullEvent(YIELD_EVENT)
        end
    end

    -- Format the digest
    local parts = {}
    for i = 1, 8 do
        parts[i] = string.format("%08x", state[i])
    end

    return table.concat(parts)
end

return sha256
