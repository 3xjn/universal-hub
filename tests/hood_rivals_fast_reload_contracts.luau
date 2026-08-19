local FastReload = require("../games/hoodrivals/features/FastReload")

local reloadTime = { Value = 2, Parent = true }
local sound = { PlaybackSpeed = 1, Parent = true }
local stats = {
    FindFirstChild = function(_self, name)
        return name == "ReloadTime" and reloadTime or nil
    end,
}
local handle = {
    FindFirstChild = function(_self, name)
        return name == "Reload" and sound or nil
    end,
}
local weapon = {
    FindFirstChild = function(_self, name)
        return name == "Stats" and stats or name == "Handle" and handle or nil
    end,
}

local feature = FastReload.new()
feature:update(true, weapon)
assert(reloadTime.Value == 0.1)
assert(sound.PlaybackSpeed == 10)
feature:update(false, weapon)
assert(reloadTime.Value == 2)
assert(sound.PlaybackSpeed == 1)

print("hood-rivals-fast-reload-contracts-ok")
