local Targeting = {}

local function aliveCharacter(player)
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return character and humanoid and humanoid.Health > 0 and character or nil
end

function Targeting.isOpponent(localPlayer, player)
    if player == localPlayer or not aliveCharacter(player) then
        return false
    end
    if localPlayer.Team and localPlayer.Team.Name == "FFA" then
        return true
    end
    return localPlayer.Team == nil or player.Team == nil or player.Team ~= localPlayer.Team
end

function Targeting.point(character, preferHead)
    if not character then
        return nil
    end
    if preferHead then
        return character:FindFirstChild("HeadHitbox")
            or character:FindFirstChild("Head")
    end
    return character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("HumanoidRootPart")
end

function Targeting.select(players, localPlayer, camera, mousePosition, settings, random)
    local closest
    local closestDistance = math.huge
    for _, player in ipairs(players:GetPlayers()) do
        if Targeting.isOpponent(localPlayer, player) then
            local character = player.Character
            local point = Targeting.point(character, true)
            if point then
                local screen, visible = camera:WorldToViewportPoint(point.Position)
                local screenDistance = (Vector2.new(screen.X, screen.Y) - mousePosition).Magnitude
                if visible
                    and (settings.fullScreenAim == true or screenDistance <= (settings.fov or 180))
                    and screenDistance < closestDistance
                then
                    closest = {
                        character = character,
                        part = point,
                        player = player,
                        position = point.Position,
                    }
                    closestDistance = screenDistance
                end
            end
        end
    end
    if not closest then
        return nil
    end

    random = random or math.random
    if random(1, 100) <= (settings.missRate or 0) then
        local root = closest.character:FindFirstChild("HumanoidRootPart")
        if root then
            closest.part = root
            closest.position = root.Position + root.CFrame.RightVector * 4
        end
    elseif random(1, 100) > (settings.headshotRate or 0) then
        local body = Targeting.point(closest.character, false)
        if body then
            closest.part = body
            closest.position = body.Position
        end
    end
    return closest
end

function Targeting.hasLineOfFire(workspace, origin, target, localCharacter)
    if not target or typeof(origin) ~= "Vector3" or typeof(target.position) ~= "Vector3" then
        return false
    end
    local offset = target.position - origin
    if offset.Magnitude <= 1e-3 then
        return false
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = localCharacter and { localCharacter } or {}
    params.IgnoreWater = true
    local result = workspace:Raycast(origin, offset, params)
    return result ~= nil
        and result.Instance ~= nil
        and result.Instance:IsDescendantOf(target.character)
end

function Targeting.acquire(players, localPlayer, workspace, camera, mousePosition, settings)
    local target = Targeting.select(players, localPlayer, camera, mousePosition, settings)
    if target then target.lineOfFire = true end
    return target
end

function Targeting.observations(players, localPlayer, camera)
    local observations = {}
    for _, player in ipairs(players:GetPlayers()) do
        if player ~= localPlayer then
            local character = aliveCharacter(player)
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if root and humanoid then
                local screen, onScreen = camera:WorldToViewportPoint(root.Position)
                table.insert(observations, {
                    bounds = onScreen and {
                        position = Vector2.new(screen.X - 30, screen.Y - 60),
                        size = Vector2.new(60, 120),
                    } or nil,
                    character = character,
                    health = humanoid.Health,
                    maxHealth = humanoid.MaxHealth,
                    part = root,
                    player = player,
                    position = root.Position,
                    tone = Targeting.isOpponent(localPlayer, player) and "enemy" or "team",
                    visible = onScreen,
                })
            end
        end
    end
    return observations
end

return Targeting
