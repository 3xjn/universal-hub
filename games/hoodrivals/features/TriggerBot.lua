local TriggerBot = {}
TriggerBot.__index = TriggerBot

function TriggerBot.new(options)
    return setmetatable({
        nextAt = 0,
        localPlayer = options.localPlayer,
        workspace = options.workspace,
    }, TriggerBot)
end

function TriggerBot.ready(workspace, localPlayer, weapon)
    local character = localPlayer and localPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local stats = weapon and weapon:FindFirstChild("Stats")
    local clip = stats and stats:FindFirstChild("ClipSize")
    return workspace:GetAttribute("CanDamage") == true
        and localPlayer:GetAttribute("EndScreen") ~= true
        and humanoid ~= nil
        and humanoid.Health > 0
        and clip ~= nil
        and clip.Value > 0
end

function TriggerBot:update(settings, fire, weapon, target)
    if settings.triggerBot ~= true
        or not fire
        or not TriggerBot.ready(self.workspace, self.localPlayer, weapon)
        or not target
        or not target.lineOfFire
        or os.clock() < self.nextAt
    then
        return false
    end
    local stats = weapon:FindFirstChild("Stats")
    local fireRate = stats and stats:FindFirstChild("FireRate")
    pcall(fire, true)
    self.nextAt = os.clock() + math.max(fireRate and fireRate.Value or 0.1, 0.01)
    return true
end

return TriggerBot
