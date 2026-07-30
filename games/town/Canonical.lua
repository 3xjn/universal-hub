local Canonical = {}

local CHECKSUM_PREFIX = "sha256-c14n-v1:"
local UINT32 = 4294967296

local SHA256_CONSTANTS = {
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
}

local ESCAPES = {
    [34] = "\\\"",
    [92] = "\\\\",
}

local function add32(...)
    local total = 0
    for index = 1, select("#", ...) do
        total += select(index, ...)
    end
    return total % UINT32
end

local function validUtf8(value)
    local succeeded, length = pcall(utf8.len, value)
    return succeeded and length ~= nil
end

local function encodeString(value)
    assert(validUtf8(value), "Canonical strings must contain valid UTF-8")
    local output = { "\"" }
    for index = 1, #value do
        local byte = string.byte(value, index)
        local escaped = ESCAPES[byte]
        if escaped then
            table.insert(output, escaped)
        elseif byte < 32 then
            table.insert(output, ("\\u%04x"):format(byte))
        else
            table.insert(output, string.char(byte))
        end
    end
    table.insert(output, "\"")
    return table.concat(output)
end

local function encodeNumber(value)
    assert(value == value and value ~= math.huge and value ~= -math.huge, "Canonical numbers must be finite")
    if value == 0 then
        return "0"
    end
    if value % 1 == 0 then
        return ("%.0f"):format(value)
    end

    local encoded = ("%.17g"):format(value):lower():gsub("e%+", "e")
    local mantissa, sign, exponent = encoded:match("^(.-)e([%-]?)(%d+)$")
    if mantissa then
        exponent = exponent:gsub("^0+", "")
        if exponent == "" then
            exponent = "0"
        end
        encoded = mantissa .. "e" .. sign .. exponent
    end
    return encoded
end

local function tableKind(value)
    local count = 0
    local maximum = 0
    local numeric = true
    local textual = true
    for key in pairs(value) do
        count += 1
        if type(key) == "number" and key >= 1 and key % 1 == 0 then
            maximum = math.max(maximum, key)
        else
            numeric = false
        end
        if type(key) ~= "string" then
            textual = false
        end
    end
    if count == 0 then
        return "array", 0
    end
    if numeric then
        assert(maximum == count, "Canonical arrays must be dense")
        return "array", count
    end
    assert(textual, "Canonical objects require string keys and cannot mix key types")
    return "object", count
end

local encodeValue

local function encodeArray(value, length)
    local output = { "[" }
    for index = 1, length do
        if index > 1 then
            table.insert(output, ",")
        end
        table.insert(output, encodeValue(value[index]))
    end
    table.insert(output, "]")
    return table.concat(output)
end

local function encodeObject(value)
    local keys = {}
    for key in pairs(value) do
        table.insert(keys, key)
    end
    table.sort(keys)

    local output = { "{" }
    for index, key in ipairs(keys) do
        if index > 1 then
            table.insert(output, ",")
        end
        table.insert(output, encodeString(key))
        table.insert(output, ":")
        table.insert(output, encodeValue(value[key]))
    end
    table.insert(output, "}")
    return table.concat(output)
end

encodeValue = function(value)
    local valueType = type(value)
    if valueType == "boolean" then
        return value and "true" or "false"
    elseif valueType == "number" then
        return encodeNumber(value)
    elseif valueType == "string" then
        return encodeString(value)
    elseif valueType == "table" then
        local kind, length = tableKind(value)
        return kind == "array" and encodeArray(value, length) or encodeObject(value)
    end
    error("Canonical values must be booleans, finite numbers, UTF-8 strings, dense arrays, or objects", 2)
end

function Canonical.encode(value)
    return encodeValue(value)
end

function Canonical.sha256Bytes(source)
    assert(type(source) == "string", "SHA-256 source must be a string")
    local bytes = {}
    for index = 1, #source do
        bytes[index] = string.byte(source, index)
    end
    local bitLength = #bytes * 8
    table.insert(bytes, 0x80)
    while #bytes % 64 ~= 56 do
        table.insert(bytes, 0)
    end

    local highLength = math.floor(bitLength / UINT32)
    local lowLength = bitLength % UINT32
    for shift = 24, 0, -8 do
        table.insert(bytes, bit32.band(bit32.rshift(highLength, shift), 0xff))
    end
    for shift = 24, 0, -8 do
        table.insert(bytes, bit32.band(bit32.rshift(lowLength, shift), 0xff))
    end

    local hash = {
        0x6a09e667,
        0xbb67ae85,
        0x3c6ef372,
        0xa54ff53a,
        0x510e527f,
        0x9b05688c,
        0x1f83d9ab,
        0x5be0cd19,
    }

    for offset = 1, #bytes, 64 do
        local words = {}
        for wordIndex = 1, 16 do
            local byteIndex = offset + (wordIndex - 1) * 4
            words[wordIndex] = add32(
                bit32.lshift(bytes[byteIndex], 24),
                bit32.lshift(bytes[byteIndex + 1], 16),
                bit32.lshift(bytes[byteIndex + 2], 8),
                bytes[byteIndex + 3]
            )
        end
        for wordIndex = 17, 64 do
            local previous = words[wordIndex - 15]
            local sigma0 = bit32.bxor(
                bit32.rrotate(previous, 7),
                bit32.rrotate(previous, 18),
                bit32.rshift(previous, 3)
            )
            previous = words[wordIndex - 2]
            local sigma1 = bit32.bxor(
                bit32.rrotate(previous, 17),
                bit32.rrotate(previous, 19),
                bit32.rshift(previous, 10)
            )
            words[wordIndex] = add32(sigma1, words[wordIndex - 7], sigma0, words[wordIndex - 16])
        end

        local a, b, c, d, e, f, g, h = table.unpack(hash)
        for wordIndex = 1, 64 do
            local sum1 = bit32.bxor(
                bit32.rrotate(e, 6),
                bit32.rrotate(e, 11),
                bit32.rrotate(e, 25)
            )
            local choice = bit32.bxor(bit32.band(e, f), bit32.band(bit32.bnot(e), g))
            local temporary1 = add32(h, sum1, choice, SHA256_CONSTANTS[wordIndex], words[wordIndex])
            local sum0 = bit32.bxor(
                bit32.rrotate(a, 2),
                bit32.rrotate(a, 13),
                bit32.rrotate(a, 22)
            )
            local majority = bit32.bxor(bit32.band(a, b), bit32.band(a, c), bit32.band(b, c))
            local temporary2 = add32(sum0, majority)
            h = g
            g = f
            f = e
            e = add32(d, temporary1)
            d = c
            c = b
            b = a
            a = add32(temporary1, temporary2)
        end

        hash[1] = add32(hash[1], a)
        hash[2] = add32(hash[2], b)
        hash[3] = add32(hash[3], c)
        hash[4] = add32(hash[4], d)
        hash[5] = add32(hash[5], e)
        hash[6] = add32(hash[6], f)
        hash[7] = add32(hash[7], g)
        hash[8] = add32(hash[8], h)
    end

    local output = {}
    for _, value in ipairs(hash) do
        table.insert(output, ("%08x"):format(value))
    end
    return table.concat(output)
end

function Canonical.checksum(value)
    local encoded = Canonical.encode(value)
    return CHECKSUM_PREFIX .. Canonical.sha256Bytes(encoded) .. ":" .. tostring(#encoded)
end

function Canonical.verify(value, expected)
    return type(expected) == "string" and Canonical.checksum(value) == expected
end

Canonical.algorithm = "sha256-c14n-v1"

return Canonical
