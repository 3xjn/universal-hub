local roblox = require("@lune/roblox")
Vector2 = roblox.Vector2
Vector3 = roblox.Vector3
CFrame = roblox.CFrame
local ObservationRuntime = require("../games/rivals/world/ObservationRuntime")

local rangeHealth, rangeMaximum = ObservationRuntime.rangeHealth({
    Health = math.huge,
    MaxHealth = math.huge,
})
assert(rangeHealth == 150 and rangeMaximum == 150, "infinite range dummies must stay ESP-safe")

local near = { character = {}, player = { team = "enemy" }, position = Vector3.new(0, 0, -10) }
near.character.FindFirstChildOfClass = function()
    return { Health = 80, MaxHealth = 100 }
end
local far = { character = {}, player = { team = "enemy" }, position = Vector3.new(0, 0, -2001) }
far.character.FindFirstChildOfClass = near.character.FindFirstChildOfClass
local teammate = { character = {}, player = { team = "team" }, position = Vector3.new(0, 0, -12) }
teammate.character.FindFirstChildOfClass = near.character.FindFirstChildOfClass
local targeting = {
    observePlayers = function(options)
        local result = {}
        for _, observation in ipairs({ near, far, teammate }) do
            if options.isEligible(observation.player, observation.character) then
                table.insert(result, observation)
            end
        end
        return result
    end,
    observeCharacter = function()
        return nil
    end,
}
local workspace = {
    CurrentCamera = { CFrame = CFrame.identity },
    FindFirstChild = function()
        return nil
    end,
}
local runtime = ObservationRuntime.new({
    equippedWeapon = function()
        return "native item"
    end,
    getFighter = function()
        return nil
    end,
    getPlayerTone = function(player)
        return player.team
    end,
    isOpponent = function(player)
        return player.team == "enemy"
    end,
    targeting = targeting,
    workspace = workspace,
})
local observations = runtime:update(Vector2.zero)
assert(#observations == 1 and observations[1] == near)
assert(near.health == 80 and near.maxHealth == 100 and near.weapon == "native item")
local opponents, visual = runtime:update(Vector2.zero, true, false)
assert(
    #opponents == 1 and opponents[1] == near,
    "Combat observations must remain opponents-only when teammate ESP is enabled"
)
assert(
    #visual == 1 and visual[1] == teammate and teammate.tone == "team",
    "Allies audience mode must render teammates without mixing enemy ESP"
)
local _, everyone = runtime:update(Vector2.zero, true, true)
assert(
    #everyone == 2 and table.find(everyone, near) and table.find(everyone, teammate),
    "Multi-select audience mode must combine enemies and allies"
)
local _, nobody = runtime:update(Vector2.zero, false, false)
assert(#nobody == 0, "Clearing both audience choices must render no player ESP")
near.character.FindFirstChildOfClass = function()
    return nil
end
observations = runtime:update(Vector2.zero)
assert(
    observations[1].health == nil and observations[1].maxHealth == nil,
    "missing native health must remain unknown"
)

local range = {
    GetChildren = function()
        return {}
    end,
}
local hurtDummy = {}
local hurtHumanoid = { Health = math.huge, MaxHealth = math.huge }
function hurtDummy:IsA(className)
    return className == "Model"
end
function hurtDummy:FindFirstChildOfClass(className)
    return className == "Humanoid" and hurtHumanoid or nil
end
function hurtDummy:GetAttribute(name)
    return name == "EnvironmentID" and "range" or nil
end
local hurtEffect = {
    GetChildren = function()
        return { hurtDummy }
    end,
}
local rangeRuntime = ObservationRuntime.new({
    getFighter = function()
        return { Data = { IsInShootingRange = true, EnvironmentID = "range" } }
    end,
    targeting = {
        observePlayers = function()
            return {}
        end,
        observeCharacter = function(character)
            return { character = character, position = Vector3.new(0, 0, -10) }
        end,
    },
    workspace = {
        CurrentCamera = { CFrame = CFrame.identity },
        FindFirstChild = function(_, name)
            return name == "ShootingRangeEntities" and range
                or name == "HurtEffect" and hurtEffect
                or nil
        end,
    },
})
local hurtObservations = rangeRuntime:update(Vector2.zero)
assert(
    #hurtObservations == 1
        and hurtObservations[1].health == 150
        and hurtObservations[1].maxHealth == 150,
    "a hit range dummy must remain observable while RIVALS reparents it into HurtEffect"
)

local motionClock = 0
local motionRoot = {
    AssemblyLinearVelocity = Vector3.new(30, 12, 0),
    Position = Vector3.zero,
}
local motionCharacter = {}
function motionCharacter:FindFirstChild(name)
    return name == "HumanoidRootPart" and motionRoot or nil
end
function motionCharacter:FindFirstChildOfClass(className)
    return className == "Humanoid" and { Health = 100, MaxHealth = 100 } or nil
end
local motionObservation = {
    character = motionCharacter,
    player = {},
    position = motionRoot.Position,
}
local motionRuntime = ObservationRuntime.new({
    clock = function()
        return motionClock
    end,
    getFighter = function()
        return nil
    end,
    isOpponent = function()
        return true
    end,
    targeting = {
        observePlayers = function()
            motionObservation.position = motionRoot.Position
            return { motionObservation }
        end,
    },
    workspace = workspace,
})
motionRuntime:update(Vector2.zero)
motionClock = 0.05
motionRuntime:update(Vector2.zero)
assert(
    motionObservation.velocity == Vector3.new(30, 0, 0),
    "sampled motion must remove native vertical velocity when position is stationary"
)
motionClock = 0.1
motionRoot.Position = Vector3.new(3, 0.5, 0)
motionRuntime:update(Vector2.zero)
assert(
    math.abs(motionObservation.velocity.X - 30) < 1e-6
        and math.abs(motionObservation.velocity.Y - 5) < 1e-6,
    "sampled motion must preserve real vertical displacement without dropping horizontal lead"
)

print("rivals-observation-runtime-contracts-ok")
