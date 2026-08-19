local roblox = require("@lune/roblox")
Vector2 = roblox.Vector2
Vector3 = roblox.Vector3
Enum = roblox.Enum
RaycastParams = {
    new = function()
        return {}
    end,
}

local Catalog = require("../../games/Catalog")
local Definition = require("../../games/hoodrivals/Definition")
local Targeting = require("../../games/hoodrivals/Targeting")

assert(table.find(Catalog, "games/hoodrivals/Definition"))
assert(Definition.id == "hoodrivals")
assert(Definition.manifest.gameIds[1] == 10648640958)
assert(table.find(Definition.manifest.placeIds, 113272123504853))
assert(table.find(Definition.features.capabilities, "silentAim"))
assert(table.find(Definition.features.capabilities, "triggerBot"))
assert(table.find(Definition.features.capabilities, "rapidFire"))
assert(table.find(Definition.features.capabilities, "autoReload"))
assert(table.find(Definition.features.capabilities, "fastReload"))
assert(Definition.defaults.rapidFireDelay == 40)
assert(Definition.defaults.autoReload == false)
assert(Definition.defaults.fastReload == false)
assert(table.find(Definition.sources, "games/hoodrivals/Adapter"))

local localPlayer = { Team = "Blue" }
local enemy = {
    Team = "Red",
    Character = {
        FindFirstChildOfClass = function()
            return { Health = 100 }
        end,
    },
}
local teammate = {
    Team = "Blue",
    Character = enemy.Character,
}
assert(Targeting.isOpponent(localPlayer, enemy))
assert(not Targeting.isOpponent(localPlayer, teammate))
localPlayer.Team = { Name = "FFA" }
assert(Targeting.isOpponent(localPlayer, teammate), "FFA must treat every other living player as hostile")
localPlayer.Team = "Blue"
local enemyPart = {
    IsDescendantOf = function(_self, character)
        return character == enemy.Character
    end,
}
assert(Targeting.hasLineOfFire({
    Raycast = function()
        return { Instance = enemyPart }
    end,
}, Vector3.zero, {
    character = enemy.Character,
    position = Vector3.new(0, 0, -10),
}, {}))
assert(not Targeting.hasLineOfFire({
    Raycast = function()
        return { Instance = { IsDescendantOf = function() return false end } }
    end,
}, Vector3.zero, {
    character = enemy.Character,
    position = Vector3.new(0, 0, -10),
}, {}))

local Firearm = require("../../games/hoodrivals/Firearm")
local TriggerBot = require("../../games/hoodrivals/features/TriggerBot")
local aimClosure = loadstring("return function() return ScreenPointToRay, Raycast end", "FirearmLocal")()
getconstants = function(value)
    if value == aimClosure then
        return { "ScreenPointToRay", "CurrentCamera" }
    end
    return {}
end
local getInfo = function(value, field)
    if value == aimClosure then
        return field == "s" and "Workspace.Player.FirearmLocal" or "GetAimDirection"
    end
    return ""
end
local fireClosure = function() end
local reloadClosure = function() end
local firearm = Firearm.new({
    searchClosures = function(_script, queries)
        assert(queries.aimDirection.name == "GetAimDirection")
        assert(queries.fire.name == "OnFire")
        assert(queries.reload.name == "Reload")
        return {
            aimDirection = aimClosure,
            fire = fireClosure,
            reload = reloadClosure,
        }
    end,
})
firearm:refresh({})
assert(#firearm.aimDirections == 1 and firearm.aimDirections[1] == aimClosure)
assert(firearm.fire == fireClosure and firearm.reload == reloadClosure)
local clip = { Value = 10 }
local weapon = {
    FindFirstChild = function(_self, name)
        if name == "Stats" then
            return {
                FindFirstChild = function(_stats, child)
                    return child == "ClipSize" and clip or nil
                end,
            }
        end
    end,
}
local livePlayer = {
    Character = {
        FindFirstChildOfClass = function()
            return { Health = 100 }
        end,
    },
    GetAttribute = function()
        return false
    end,
}
local liveWorkspace = {
    GetAttribute = function(_self, name)
        return name == "CanDamage" and true or nil
    end,
}
assert(TriggerBot.ready(liveWorkspace, livePlayer, weapon))
liveWorkspace.GetAttribute = function()
    return false
end
assert(not TriggerBot.ready(liveWorkspace, livePlayer, weapon), "Lobby state must suppress native fire")
liveWorkspace.GetAttribute = function()
    return true
end
clip.Value = 0
assert(not TriggerBot.ready(liveWorkspace, livePlayer, weapon), "Empty weapons must suppress native fire")

print("hood-rivals-contracts-ok")
