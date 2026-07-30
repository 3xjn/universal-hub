local Canonical = require("../games/town/Canonical")

assert(Canonical.encode({ b = 1, a = 2 }) == "{\"a\":2,\"b\":1}")
assert(Canonical.encode({ 1, true, "x" }) == "[1,true,\"x\"]")
assert(Canonical.encode({}) == "[]")
assert(Canonical.encode(-0) == "0")
assert(Canonical.encode(1.5) == "1.5")
assert(Canonical.encode("a\n\t\"\\") == "\"a\\u000a\\u0009\\\"\\\\\"")
assert(
    Canonical.encode("\0\b\t\n\f\r\31")
        == "\"\\u0000\\u0008\\u0009\\u000a\\u000c\\u000d\\u001f\"",
    "sha256-c14n-v1 must encode every control byte as lowercase \\u00xx"
)

assert(
    Canonical.sha256Bytes("")
        == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "Canonical SHA-256 must match the empty-string FIPS vector"
)
assert(
    Canonical.sha256Bytes("abc")
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    "Canonical SHA-256 must match the abc FIPS vector"
)

local left = Canonical.checksum({
    nested = { z = "last", a = "first" },
    count = 3,
})
local right = Canonical.checksum({
    count = 3,
    nested = { a = "first", z = "last" },
})
assert(left == right, "Canonical checksums must ignore object insertion order")
assert(left:match("^sha256%-c14n%-v1:%x%x%x%x%x%x%x%x") ~= nil)
assert(Canonical.verify({ count = 3, nested = { z = "last", a = "first" } }, left))
assert(not Canonical.verify({ count = 4, nested = { z = "last", a = "first" } }, left))

for _, invalid in ipairs({
    0 / 0,
    math.huge,
    -math.huge,
    function() end,
}) do
    local succeeded = pcall(Canonical.encode, invalid)
    assert(not succeeded, "Canonical encoding must reject unsupported or non-finite values")
end

local sparseSucceeded = pcall(Canonical.encode, {
    [1] = "first",
    [3] = "third",
})
assert(not sparseSucceeded, "Canonical encoding must reject sparse arrays")

print("town-canonical-contracts-ok")
