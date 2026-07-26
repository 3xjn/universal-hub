local Targeting = {}

local HEAD_CROWN_FRACTIONS = { 0.45, 0.35, 0.25 }

local function observationKey(observation)
    return observation
        and (observation.character or observation.player or observation.part)
        or nil
end

function Targeting.closestObservation(observations, origin, options)
    if not origin then
        return nil
    end

    options = options or {}
    local nearest
    local nearestDistance = math.huge
    for _, observation in ipairs(observations or {}) do
        local position = type(options.resolvePosition) == "function"
                and options.resolvePosition(observation)
            or observation.position
        local screenDistance = observation.screenDistance
        local insideFov = options.maxScreenDistance == nil
            or type(screenDistance) == "number" and screenDistance <= options.maxScreenDistance
        local eligible = options.isEligible == nil
            or options.isEligible(observation.player, observation.character)
        if position
            and insideFov
            and eligible
            and (options.includeBlocked or observation.visible)
        then
            local distance = (position - origin).Magnitude
            if (options.maxDistance == nil or distance <= options.maxDistance)
                and distance < nearestDistance
            then
                nearest = observation
                nearestDistance = distance
            end
        end
    end
    return nearest
end

function Targeting.selectObservation(observations, currentKey, nearest)
    if currentKey then
        for _, observation in ipairs(observations or {}) do
            if observationKey(observation) == currentKey then
                local retained = nearest({ observation })
                if retained then
                    return retained, currentKey
                end
                break
            end
        end
    end

    local selected = nearest(observations or {})
    return selected, observationKey(selected)
end

function Targeting.visibleHeadPoint(observation, origin, raycast)
    local character = observation and observation.character
    local head = character
        and character.FindFirstChild
        and character:FindFirstChild("Head")
    if not head then
        return nil, nil
    end
    if not origin or type(raycast) ~= "function" or not head.CFrame or not head.Size then
        return head.Position, head
    end

    local function exposed(point)
        local result = raycast(origin, point - origin)
        local instance = result and result.Instance
        if not instance or instance == head then
            return true
        end
        return instance.IsDescendantOf
            and instance:IsDescendantOf(character)
            and instance.GetAttribute
            and instance:GetAttribute("IsCritical") == true
    end

    if exposed(head.Position) then
        return head.Position, head
    end
    for _, fraction in ipairs(HEAD_CROWN_FRACTIONS) do
        local point = head.CFrame:PointToWorldSpace(
            Vector3.new(0, head.Size.Y * fraction, 0)
        )
        if exposed(point) then
            return point, head
        end
    end
    return nil, head
end

function Targeting.applyAimRates(observation, settings, random, options)
    if not observation or not observation.position then
        return observation
    end

    random = random or math.random
    local missRate = math.clamp(settings.missRate or 0, 0, 100)
    if missRate > 0 and random() * 100 < missRate then
        local character = observation.character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then
            return observation
        end

        local result = table.clone(observation)
        local width = root.Size and root.Size.X or 2
        result.intentionalMiss = true
        result.part = root
        result.position = observation.position + root.CFrame.RightVector * (width * 0.5 + 2.5)
        return result
    end

    local headshotRate = math.clamp(settings.headshotRate or 0, 0, 100)
    if headshotRate > 0 and random() * 100 < headshotRate then
        local character = observation.character
        local head = character and character:FindFirstChild("Head")
        if head then
            local result = table.clone(observation)
            result.intentionalMiss = false
            result.preferHead = true
            local position = Targeting.visibleHeadPoint(
                observation,
                options and options.origin,
                options and options.raycast
            )
            if position then
                result.part = head
                result.position = position
            end
            return result
        end
    end

    return observation
end

function Targeting.rotationToward(origin, target)
    local direction = (target - origin).Unit
    return Vector2.new(math.asin(direction.Y), math.atan2(-direction.X, -direction.Z))
end

function Targeting.smoothRotation(current, target, smoothness, deltaTime)
    smoothness = math.clamp(smoothness or 0, 0, 100)
    if smoothness <= 0 or not current then
        return target
    end

    local speed = math.max(1.5, 30 * (1 - smoothness / 100))
    local alpha = 1 - math.exp(-speed * math.max(deltaTime or 1 / 60, 0))
    local yawDelta = (target.Y - current.Y + math.pi) % (math.pi * 2) - math.pi
    return Vector2.new(
        current.X + (target.X - current.X) * alpha,
        current.Y + yawDelta * alpha
    )
end

function Targeting.humanRotation(current, target, smoothness, deltaTime, state)
    if not current then
        return target
    end

    state = state or {}
    local stepTime = math.max(deltaTime or 1 / 60, 1 / 240)
    local smooth = math.clamp(smoothness or 0, 0, 100)
    local yawError = (target.Y - current.Y + math.pi) % (math.pi * 2) - math.pi
    local error = Vector2.new(target.X - current.X, yawError)
    local targetMotion = Vector2.zero
    if state.lastTarget then
        targetMotion = Vector2.new(
            target.X - state.lastTarget.X,
            (target.Y - state.lastTarget.Y + math.pi) % (math.pi * 2) - math.pi
        )
    end
    state.lastTarget = target

    local targetSpeed = targetMotion.Magnitude / stepTime
    local baseSpeed = math.max(1.5, 30 * (1 - smooth / 100))
    local trackingSpeed = baseSpeed + math.min(targetSpeed * 0.8, 24)
    local alpha = 1 - math.exp(-trackingSpeed * stepTime)
    local curve = Vector2.zero
    if error.Magnitude > 1e-6 then
        local curveMagnitude = math.min(error.Magnitude * 0.08, math.rad(0.35))
        local curveSign = state.curveSign or 1
        curve = Vector2.new(-error.Y, error.X).Unit * curveMagnitude * curveSign
    end

    local step = error * alpha + targetMotion * 0.55 + curve * alpha
    local maximumStep = error.Magnitude * 0.85
    if step.Magnitude > maximumStep and maximumStep > 0 then
        step = step.Unit * maximumStep
    end
    return current + step
end

return Targeting
