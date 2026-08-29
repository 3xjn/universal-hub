local roblox = require("@lune/roblox")
Vector2 = roblox.Vector2
Vector3 = roblox.Vector3
CFrame = roblox.CFrame

local ObservationRuntime = require("../games/rivals/world/ObservationRuntime")

local onScreenCharacter = {}
function onScreenCharacter:FindFirstChildOfClass()
    return { Health = 100, MaxHealth = 100 }
end
local onScreenPlayer = { Character = onScreenCharacter, team = "enemy" }
local onScreen = {
    character = onScreenCharacter,
    player = onScreenPlayer,
    position = Vector3.new(0, 0, -10),
    visible = true,
}

local offscreenRoot = { Position = Vector3.new(12, 0, 0) }
local offscreenHumanoid = { Health = 100, MaxHealth = 100 }
local offscreenCharacter = {}
function offscreenCharacter:FindFirstChild(name)
    return name == "HumanoidRootPart" and offscreenRoot or nil
end
function offscreenCharacter:FindFirstChildOfClass(className)
    return className == "Humanoid" and offscreenHumanoid or nil
end
local offscreenPlayer = { Character = offscreenCharacter, team = "enemy" }

local runtime = ObservationRuntime.new({
    getFighter = function()
        return nil
    end,
    getPlayerTone = function(player)
        return player.team
    end,
    isOpponent = function(player)
        return player.team == "enemy"
    end,
    players = {
        GetPlayers = function()
            return { onScreenPlayer, offscreenPlayer }
        end,
    },
    targeting = {
        observePlayers = function()
            return { onScreen }
        end,
    },
    workspace = {
        CurrentCamera = { CFrame = CFrame.identity },
        FindFirstChild = function()
            return nil
        end,
    },
})

local observations, visuals = runtime:update(Vector2.zero, false, true, true)
assert(
    #observations == 2
        and observations[2].character == offscreenCharacter
        and observations[2].offscreen == true
        and observations[2].screenDistance == nil,
    "360 Target Mode must acquire opponents outside the current viewport"
)
assert(
    #visuals == 1 and visuals[1] == onScreen,
    "offscreen 360 candidates must not leak into ESP rendering"
)

print("rivals-target-mode-contracts-ok")
