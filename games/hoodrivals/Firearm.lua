local Firearm = {}
Firearm.__index = Firearm

function Firearm.new(closure)
    return setmetatable({ closure = closure }, Firearm)
end

function Firearm:refresh(firearmLocal)
    local found = self.closure.searchClosures(firearmLocal, {
        aimDirection = { name = "GetAimDirection", upvalueIndex = 1 },
        fire = { name = "OnFire", upvalueIndex = 1 },
        reload = { name = "Reload", upvalueIndex = 1 },
    })
    self.aimDirections = found.aimDirection and { found.aimDirection } or {}
    self.fire = found.fire or self.fire
    self.reload = found.reload or self.reload
    return self
end

function Firearm:shoot()
    return self.fire and pcall(self.fire, true) or false
end

function Firearm:startReload()
    return self.reload and pcall(self.reload) or false
end

function Firearm:canHit(workspace, target, weapon, localCharacter)
    local aimDirection = self.aimDirections and self.aimDirections[1]
    if not aimDirection or not target or not target.character then
        return false
    end
    local succeeded, direction, origin = pcall(aimDirection, 0)
    if not succeeded or typeof(direction) ~= "Vector3" or typeof(origin) ~= "Vector3" then
        return false
    end
    local stats = weapon and weapon:FindFirstChild("Stats")
    local range = stats and stats:FindFirstChild("Range")
    local radius = weapon and weapon:GetAttribute("DamageRadius") or 1.15
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {
        localCharacter,
        workspace.CurrentCamera,
        workspace:FindFirstChild("apes"),
        workspace:FindFirstChild("OBJECTS"),
    }
    params.IgnoreWater = true
    local result = workspace:Spherecast(
        origin,
        radius,
        direction.Unit * (range and range.Value or 1000),
        params
    )
    return result ~= nil
        and result.Instance ~= nil
        and result.Instance:IsDescendantOf(target.character)
end

return Firearm
