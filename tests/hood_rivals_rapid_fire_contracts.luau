local RapidFire = require("../games/hoodrivals/features/RapidFire")

local fireRate = { Value = 0.12 }
local gunType = { Value = "Semi" }
local stats = {
    FindFirstChild = function(_self, name)
        return name == "FireRate" and fireRate
            or name == "GunType" and gunType
            or nil
    end,
}
local weapon = {
    Parent = true,
    FindFirstChild = function(_self, name)
        return name == "Stats" and stats or nil
    end,
}

local rapidFire = RapidFire.new()
rapidFire:update({ rapidFire = true, rapidFireDelay = 30 }, weapon)
assert(fireRate.Value == 0.03)
assert(gunType.Value == "Auto")

rapidFire:update({ rapidFire = false }, weapon)
assert(fireRate.Value == 0.12)
assert(gunType.Value == "Semi")

rapidFire:update({ rapidFire = true, rapidFireDelay = 10 }, weapon)
rapidFire:stop()
assert(fireRate.Value == 0.12)
assert(gunType.Value == "Semi")

print("hood-rivals-rapid-fire-contracts-ok")
