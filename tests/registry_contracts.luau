local Registry = require("../modules/Registry")

local registry = Registry.new()
registry:Register({
    id = "universe",
    manifest = {
        gameIds = { 10 },
    },
    new = function() end,
})
registry:Register({
    id = "place",
    manifest = {
        placeIds = { 20 },
    },
    new = function() end,
})

local placeAdapter, placeScore = registry:Resolve({
    gameId = 10,
    placeId = 20,
})
assert(placeAdapter.id == "place" and placeScore == 200, "Place match must override universe match")

local universeAdapter, universeScore = registry:Resolve({
    gameId = 10,
    placeId = 99,
})
assert(universeAdapter.id == "universe" and universeScore == 100)

local missing, missingScore = registry:Resolve({
    gameId = 999,
    placeId = 999,
})
assert(missing == nil and missingScore == 0, "Unsupported games must not pick an adapter")

local listed = registry:List()
assert(listed[1].id == "place" and listed[2].id == "universe", "Adapter listing must be stable")
print("registry-contracts-ok")
