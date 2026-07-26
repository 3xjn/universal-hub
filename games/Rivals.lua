local Rivals = {
    id = "rivals",
    label = "RIVALS",
    manifest = {
        gameIds = { 6035872082 },
        placeIds = { 17625359962 },
    },
    capabilities = {
        "silentAim",
        "shotAim",
        "triggerBot",
        "humanAim",
        "knifeMovement",
        "bhop",
        "aimSmoothness",
        "headshotRate",
        "missRate",
        "boxes",
        "chams",
        "names",
        "health",
        "weapon",
        "utilityEsp",
        "noFlash",
        "noSmoke",
    },
    optionLabels = {
        humanAim = "Human Aim",
        knifeMovement = "Knife Movement",
        silentAim = "Camera Aim",
        shotAim = "Silent Aim",
    },
    exclusiveOptions = {
        shotAim = { "silentAim", "humanAim" },
        silentAim = { "shotAim" },
    },
    cosmetics = false,
}

local TRIGGER_INTERVAL = 0.1
local TRIGGER_RADIUS = 8
local TRIGGER_DAMAGE_RETENTION = 0.9
local MAX_OBSERVATION_DISTANCE = 2000
local RICOCHET_BOUNCES = 2
local RICOCHET_CACHE_INTERVAL = 0.15
local RICOCHET_MAX_DISTANCE = 2048
local RICOCHET_REDIRECT_ANGLE = math.rad(7.5)
local RICOCHET_REDIRECT_RADIUS = 128
local RICOCHET_SURFACE_OFFSET = 0.05
local SPLASH_CACHE_INTERVAL = 0.1
local SPLASH_TRACE_STEPS = 12
local SLINGSHOT_CACHE_INTERVAL = 0.2
local SLINGSHOT_HUMAN_AIM_MAX_SMOOTHNESS = 65
local SLINGSHOT_STEP = 1 / 20
local SLINGSHOT_TARGET_RADIUS = 2.5
local AUTOMATIC_SHOOT_COOLDOWN = 0.15
local THROWABLE_MAX_DISTANCE = 2000
local THROWABLE_REFRESH_INTERVAL = 0.2
local KNIFE_MOVEMENT_ACQUISITION_DISTANCE = 128
local THROWABLE_TAGS = { "Grenade", "Throwable", "Projectile" }
local THROWABLE_CONTAINERS = { "Projectiles", "Throwables", "Debris", "Effects" }
local THROWABLE_ATTRIBUTES = {
    "DisplayName",
    "GrenadeName",
    "ItemName",
    "ProjectileName",
    "ThrowableName",
    "WeaponName",
}
local THROWABLE_DESCRIPTORS = {
    { tokens = { "smoke" }, label = "SMOKE", tone = "smoke" },
    { tokens = { "flash" }, label = "FLASH", tone = "accent" },
    { tokens = { "molotov", "incendiary", "fire bomb" }, label = "MOLOTOV", tone = "danger" },
    { tokens = { "grenade", "frag" }, label = "GRENADE", tone = "danger" },
    { tokens = { "dynamite" }, label = "DYNAMITE", tone = "danger" },
}
local VISUAL_EFFECT_CLASSES = {
    Beam = true,
    BlurEffect = true,
    ColorCorrectionEffect = true,
    DepthOfFieldEffect = true,
    Frame = true,
    ImageLabel = true,
    ParticleEmitter = true,
    Smoke = true,
}

local function contains(list, value)
    for _, candidate in ipairs(list or {}) do
        if candidate == value then
            return true
        end
    end
    return false
end

function Rivals.match(context)
    if contains(Rivals.manifest.placeIds, context.placeId) then
        return 200
    end
    if contains(Rivals.manifest.gameIds, context.gameId) then
        return 100
    end
    return 0
end

function Rivals.controllersReady(
    cameraController,
    fighterController,
    loadedModules,
    mechanicsController
)
    local cameraReady = false
    local fighterReady = false
    local mechanicsReady = mechanicsController == nil
    for _, module in ipairs(loadedModules or {}) do
        cameraReady = cameraReady or module == cameraController
        fighterReady = fighterReady or module == fighterController
        mechanicsReady = mechanicsReady or module == mechanicsController
    end
    return cameraReady and fighterReady and mechanicsReady
end

local function throwableDescriptor(instance)
    local current = instance
    for _depth = 1, 3 do
        if not current then
            break
        end

        local values = { current.Name }
        if current.GetAttribute then
            for _, attribute in ipairs(THROWABLE_ATTRIBUTES) do
                table.insert(values, current:GetAttribute(attribute))
            end
        end
        for _, value in ipairs(values) do
            if type(value) == "string" then
                local normalized = string.lower(value)
                for _, descriptor in ipairs(THROWABLE_DESCRIPTORS) do
                    for _, token in ipairs(descriptor.tokens) do
                        if string.find(normalized, token, 1, true) then
                            return descriptor, current
                        end
                    end
                end
            end
        end
        current = current.Parent
    end
    return nil
end

local function effectKind(instance)
    local name = string.lower(instance.Name or "")
    if string.find(name, "flash", 1, true)
        or string.find(name, "blind", 1, true)
        or string.find(name, "stun", 1, true)
    then
        return "flash"
    end
    if string.find(name, "smoke", 1, true) then
        return "smoke"
    end
    return nil
end

local function effectStateProperty(instance)
    local supported = false
    if instance.IsA then
        for className in pairs(VISUAL_EFFECT_CLASSES) do
            if instance:IsA(className) then
                supported = true
                break
            end
        end
    end
    if not supported then
        return nil
    end

    local enabledOk, enabled = pcall(function()
        return instance.Enabled
    end)
    if enabledOk and type(enabled) == "boolean" then
        return "Enabled", enabled
    end
    local visibleOk, visible = pcall(function()
        return instance.Visible
    end)
    if visibleOk and type(visible) == "boolean" then
        return "Visible", visible
    end
    return nil
end

function Rivals.updateVisualSuppressions(settings, roots, suppressed)
    local active = {}
    for _, entry in ipairs(roots or {}) do
        local root = entry.instance or entry
        local inheritedKind = entry.kind
        local instances = { root }
        if root and root.GetDescendants then
            for _, descendant in ipairs(root:GetDescendants()) do
                table.insert(instances, descendant)
            end
        end
        for _, instance in ipairs(instances) do
            local kind = effectKind(instance) or inheritedKind
            local shouldSuppress = kind == "flash" and settings.noFlash == true
                or kind == "smoke" and settings.noSmoke == true
            if shouldSuppress then
                local property, value = effectStateProperty(instance)
                if property then
                    active[instance] = true
                    if suppressed[instance] == nil then
                        suppressed[instance] = {
                            property = property,
                            value = value,
                        }
                    end
                    pcall(function()
                        instance[property] = false
                    end)
                end
            end
        end
    end

    for instance, state in pairs(suppressed) do
        if not active[instance] then
            pcall(function()
                instance[state.property] = state.value
            end)
            suppressed[instance] = nil
        end
    end
end

function Rivals.throwableObservation(camera, candidate, environmentID)
    local descriptor, root = throwableDescriptor(candidate)
    if not descriptor or not camera or not root then
        return nil
    end
    if root.Parent == nil and candidate.Parent == nil then
        return nil
    end

    local finished = root.GetAttribute and (
        root:GetAttribute("SimulationFinished") == true
        or root:GetAttribute("Exploded") == true
        or root:GetAttribute("Detonated") == true
    )
    if finished then
        return nil
    end
    local observedEnvironment = root.GetAttribute and root:GetAttribute("EnvironmentID")
    if environmentID ~= nil and observedEnvironment ~= nil and observedEnvironment ~= environmentID then
        return nil
    end

    local part
    if candidate.IsA and candidate:IsA("BasePart") then
        part = candidate
    elseif root.IsA and root:IsA("BasePart") then
        part = root
    else
        part = root.PrimaryPart
            or (root.FindFirstChildWhichIsA and root:FindFirstChildWhichIsA("BasePart", true))
    end
    if not part or not part.Position then
        return nil
    end

    local cameraPosition = camera.CFrame and camera.CFrame.Position
    if cameraPosition and (part.Position - cameraPosition).Magnitude > THROWABLE_MAX_DISTANCE then
        return nil
    end
    local point, onScreen = camera:WorldToViewportPoint(part.Position)
    return {
        key = root,
        label = descriptor.label,
        onScreen = onScreen == true and point.Z > 0,
        polygons = {},
        screenPosition = Vector2.new(point.X, point.Y),
        tone = descriptor.tone,
    }
end

function Rivals.isOpponent(localPlayer, player, character)
    if player == localPlayer or not character then
        return false
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health <= 0 then
        return false
    end

    if localPlayer:GetAttribute("EnvironmentID") ~= player:GetAttribute("EnvironmentID") then
        return false
    end

    local localTeam = localPlayer:GetAttribute("TeamID")
    local playerTeam = player:GetAttribute("TeamID")
    return localTeam == nil or playerTeam == nil or localTeam ~= playerTeam
end

function Rivals.isTargetable(localPlayer, player, character)
    return Rivals.isOpponent(localPlayer, player, character)
        and character:FindFirstChildOfClass("ForceField") == nil
end

function Rivals.closestObservation(observations, origin, options)
    if not origin then
        return nil
    end

    options = options or {}
    local nearest
    local nearestDistance = math.huge
    for _, observation in ipairs(observations or {}) do
        local position = observation.position
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
            if distance < nearestDistance then
                nearest = observation
                nearestDistance = distance
            end
        end
    end
    return nearest
end

function Rivals.itemName(item)
    if not item then
        return nil
    end

    local info = item.Info
    if type(info) == "table" then
        return info.DisplayName or info.Name or info.ItemName or item.Name
    end
    return item.Name
end

function Rivals.applyAimRates(observation, settings, random)
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
            result.part = head
            result.position = head.Position
            return result
        end
    end

    return observation
end

function Rivals.backstabPlan(localPosition, observation, info, acquisitionDistance)
    local health = observation and observation.health
    local character = observation and observation.character
    local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
    if type(health) ~= "number"
        or type(info) ~= "table"
        or type(info.CriticalDamage) ~= "number"
        or health > info.CriticalDamage
        or not targetRoot
        or not targetRoot.CFrame
    then
        return nil
    end

    local offset = localPosition - targetRoot.Position
    local reach = info.HeavyAttackReach or info.AttackReach
    if type(reach) ~= "number" or offset.Magnitude <= 1e-3 then
        return nil
    end

    local rearDirection = offset.Unit
    local rearDot = targetRoot.CFrame.LookVector:Dot(rearDirection)
    local ready = offset.Magnitude <= reach and rearDot <= 0.1
    local acquisitionReach = math.min(24, math.max(16, reach * 2.5))
    if type(acquisitionDistance) == "number" then
        acquisitionReach = math.max(acquisitionReach, acquisitionDistance)
    end
    if not ready and offset.Magnitude > acquisitionReach then
        return nil
    end

    local approachDistance = math.clamp(reach * 0.65, 3.5, 5)
    local approachPosition = targetRoot.Position
        - targetRoot.CFrame.LookVector * approachDistance
    return {
        aimPosition = ready and observation.position or approachPosition,
        approachPosition = approachPosition,
        movePosition = approachPosition,
        path = {
            localPosition,
            approachPosition,
            targetRoot.Position,
        },
        ready = ready,
        rearDot = rearDot,
    }
end

function Rivals.backstabReady(localPosition, observation, info)
    local plan = Rivals.backstabPlan(localPosition, observation, info)
    return plan ~= nil and plan.ready == true
end

function Rivals.rotationToward(origin, target)
    local direction = (target - origin).Unit
    return Vector2.new(math.asin(direction.Y), math.atan2(-direction.X, -direction.Z))
end

function Rivals.redirectCameraData(cameraData, ray, targetPosition)
    if type(cameraData) ~= "table"
        or type(ray) ~= "table"
        or typeof(targetPosition) ~= "Vector3"
    then
        return cameraData, ray
    end

    local byte0 = utf8.char(0)
    local byte1 = utf8.char(1)
    local byte2 = utf8.char(2)
    local byte3 = utf8.char(3)
    local byte4 = utf8.char(4)
    local byte5 = utf8.char(5)
    local redirected = table.clone(cameraData)
    local rayOrigin
    for _, key in ipairs({ byte0, byte1 }) do
        local source = cameraData[key]
        if type(source) == "table"
            and type(source[byte0]) == "number"
            and type(source[byte1]) == "number"
            and type(source[byte2]) == "number"
        then
            local record = table.clone(source)
            local origin = Vector3.new(
                record[byte0],
                record[byte1],
                record[byte2]
            )
            local rotation = Rivals.rotationToward(origin, targetPosition)
            record[byte3] = rotation.X
            record[byte4] = rotation.Y
            record[byte5] = 0
            redirected[key] = record
            rayOrigin = rayOrigin or origin
        end
    end

    if not rayOrigin or type(ray.Distance) ~= "number" then
        return redirected, ray
    end
    local rotation = Rivals.rotationToward(rayOrigin, targetPosition)
    local direction = (
        CFrame.Angles(0, rotation.Y, 0)
        * CFrame.Angles(rotation.X, 0, 0)
    ).LookVector
    local redirectedRay = table.clone(ray)
    redirectedRay.Position = rayOrigin + direction * ray.Distance
    return redirected, redirectedRay
end

function Rivals.smoothRotation(current, target, smoothness, deltaTime)
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

function Rivals.humanRotation(current, target, smoothness, deltaTime, state)
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

function Rivals.reflectDirection(direction, normal)
    return (direction - normal * (2 * direction:Dot(normal))).Unit
end

function Rivals.reflectPoint(point, planePosition, planeNormal)
    return point - planeNormal * (2 * (point - planePosition):Dot(planeNormal))
end

local function withinRedirectAngle(direction, targetDirection, maxAngle)
    return direction:Dot(targetDirection) >= math.cos(maxAngle)
end

local function clearToTarget(origin, target, raycast)
    local displacement = target - origin
    if displacement.Magnitude <= RICOCHET_SURFACE_OFFSET then
        return true
    end

    local result = raycast(origin, displacement)
    return result == nil
        or (result.Position - origin).Magnitude >= displacement.Magnitude - RICOCHET_SURFACE_OFFSET
end

function Rivals.traceRicochet(origin, direction, target, raycast, maxBounces, redirectAngle, maxDistance)
    local position = origin
    local rayDirection = direction.Unit
    local path = { origin }
    maxBounces = maxBounces or RICOCHET_BOUNCES
    redirectAngle = redirectAngle or RICOCHET_REDIRECT_ANGLE
    maxDistance = maxDistance or RICOCHET_MAX_DISTANCE

    for bounce = 1, maxBounces do
        local result = raycast(position, rayDirection * maxDistance)
        if not result or not result.Normal or not result.Position then
            return nil
        end

        table.insert(path, result.Position)
        rayDirection = Rivals.reflectDirection(rayDirection, result.Normal)
        position = result.Position + rayDirection * RICOCHET_SURFACE_OFFSET

        local targetOffset = target - position
        if targetOffset.Magnitude > RICOCHET_SURFACE_OFFSET then
            local targetDirection = targetOffset.Unit
            local exactPath = rayDirection:Dot(targetDirection) >= math.cos(math.rad(0.25))
            local redirectable = targetOffset.Magnitude <= RICOCHET_REDIRECT_RADIUS
                and withinRedirectAngle(rayDirection, targetDirection, redirectAngle)
            if (exactPath or redirectable) and clearToTarget(position, target, raycast) then
                table.insert(path, target)
                return {
                    bounces = bounce,
                    direction = direction.Unit,
                    path = path,
                }
            end
        end
    end

    return nil
end

local function ricochetProbeDirections(forward)
    local reference = math.abs(forward:Dot(Vector3.yAxis)) < 0.95 and Vector3.yAxis or Vector3.xAxis
    local right = forward:Cross(reference).Unit
    local up = right:Cross(forward).Unit
    local directions = { forward }

    for _, angle in ipairs({ math.rad(30), math.rad(60) }) do
        for step = 0, 7 do
            local azimuth = 2 * math.pi * step / 8
            local radial = right * math.cos(azimuth) + up * math.sin(azimuth)
            table.insert(directions, (forward * math.cos(angle) + radial * math.sin(angle)).Unit)
        end
    end
    return directions
end

function Rivals.solveRicochet(origin, target, raycast, maxDistance)
    maxDistance = maxDistance or RICOCHET_MAX_DISTANCE
    local forward = (target - origin).Unit

    for _, probeDirection in ipairs(ricochetProbeDirections(forward)) do
        local sampledSurface = raycast(origin, probeDirection * maxDistance)
        if sampledSurface and sampledSurface.Normal and sampledSurface.Position then
            local image = Rivals.reflectPoint(target, sampledSurface.Position, sampledSurface.Normal)
            local oneBounceDirection = (image - origin).Unit
            local oneBounce = Rivals.traceRicochet(
                origin,
                oneBounceDirection,
                target,
                raycast,
                RICOCHET_BOUNCES,
                RICOCHET_REDIRECT_ANGLE,
                maxDistance
            )
            if oneBounce then
                return oneBounce
            end

            local firstSurface = raycast(origin, oneBounceDirection * maxDistance)
            if firstSurface and firstSurface.Normal and firstSurface.Position then
                local firstReflection = Rivals.reflectDirection(oneBounceDirection, firstSurface.Normal)
                local secondOrigin = firstSurface.Position + firstReflection * RICOCHET_SURFACE_OFFSET
                local secondSurface = raycast(secondOrigin, firstReflection * maxDistance)
                if secondSurface and secondSurface.Normal and secondSurface.Position then
                    local secondImage = Rivals.reflectPoint(target, secondSurface.Position, secondSurface.Normal)
                    local firstImage = Rivals.reflectPoint(
                        secondImage,
                        firstSurface.Position,
                        firstSurface.Normal
                    )
                    local twoBounce = Rivals.traceRicochet(
                        origin,
                        (firstImage - origin).Unit,
                        target,
                        raycast,
                        RICOCHET_BOUNCES,
                        RICOCHET_REDIRECT_ANGLE,
                        maxDistance
                    )
                    if twoBounce and twoBounce.bounces == RICOCHET_BOUNCES then
                        return twoBounce
                    end
                end
            end
        end
    end

    return nil
end

function Rivals.isSplashProjectile(item)
    local info = item and item.Info
    return type(info) == "table"
        and info.DamageType == "Splash"
        and info.IsProjectile == true
        and type(info.ProjectileSpeed) == "number"
        and info.ProjectileSpeed > 0
        and type(info.ShootExplosionRadius) == "number"
        and info.ShootExplosionRadius > 0
end

function Rivals.isDirectProjectile(item)
    local info = item and item.Info
    return type(info) == "table"
        and info.IsProjectile == true
        and info.IsRaycast ~= true
        and info.DamageType ~= "Splash"
        and (info.ProjectileMaxHits or 1) <= 1
        and (info.RaycastBounceCount or 0) == 0
        and Rivals.itemName(item) ~= "Slingshot"
end

local function ballisticDirection(origin, target, speed, gravity)
    local offset = target - origin
    local horizontal = Vector3.new(offset.X, 0, offset.Z)
    local horizontalDistance = horizontal.Magnitude
    if gravity <= 1e-6 or horizontalDistance <= 1e-6 then
        return offset.Unit, offset.Magnitude / speed
    end

    local speedSquared = speed * speed
    local discriminant = speedSquared * speedSquared
        - gravity * (gravity * horizontalDistance * horizontalDistance + 2 * offset.Y * speedSquared)
    if discriminant < 0 then
        return nil
    end

    local angle = math.atan(
        (speedSquared - math.sqrt(discriminant)) / (gravity * horizontalDistance)
    )
    local cosine = math.cos(angle)
    if cosine <= 1e-6 then
        return nil
    end

    local direction = (horizontal.Unit * cosine + Vector3.yAxis * math.sin(angle)).Unit
    return direction, horizontalDistance / (speed * cosine)
end

local function traceProjectile(origin, direction, speed, acceleration, flightTime, raycast)
    local previous = origin
    local previousTime = 0
    for step = 1, SPLASH_TRACE_STEPS do
        local time = flightTime * step / SPLASH_TRACE_STEPS
        local position = origin
            + direction * (speed * time)
            + acceleration * (0.5 * time * time)
        local result = raycast(previous, position - previous)
        if result and result.Position then
            local segmentLength = (position - previous).Magnitude
            local impactAlpha = segmentLength > 1e-6
                    and math.clamp((result.Position - previous).Magnitude / segmentLength, 0, 1)
                or 0
            return result.Position, previousTime + (time - previousTime) * impactAlpha
        end
        previous = position
        previousTime = time
    end
    return nil
end

local function observationVelocity(observation)
    local part = observation and observation.part
    local velocity = part and (part.AssemblyLinearVelocity or part.Velocity)
    if velocity then
        return velocity
    end

    local character = observation and observation.character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return root and (root.AssemblyLinearVelocity or root.Velocity) or Vector3.zero
end

function Rivals.solveProjectileAim(origin, observation, info, worldGravity)
    local targetPosition = observation and observation.position
    local speed = info and info.ProjectileSpeed
    if not targetPosition or type(speed) ~= "number" or speed <= 0 then
        return nil
    end

    local targetVelocity = observationVelocity(observation)
    local gravity = (worldGravity or 196.2) * (info.ProjectileGravity or 0)
    local lifetime = type(info.ProjectileLifetime) == "number" and info.ProjectileLifetime or math.huge
    local predictedPosition = targetPosition
    local direction
    local flightTime

    for _ = 1, 3 do
        direction, flightTime = ballisticDirection(origin, predictedPosition, speed, gravity)
        if not direction or not flightTime or flightTime > lifetime then
            return nil
        end
        predictedPosition = targetPosition + targetVelocity * flightTime
    end

    direction, flightTime = ballisticDirection(origin, predictedPosition, speed, gravity)
    if not direction or not flightTime or flightTime > lifetime then
        return nil
    end
    return {
        direction = direction,
        flightTime = flightTime,
        predictedPosition = predictedPosition,
    }
end

function Rivals.solveSplashAim(origin, observation, info, raycast, worldGravity, networkLatency)
    local targetPosition = observation and observation.position
    local speed = info and info.ProjectileSpeed
    local radius = info and info.ShootExplosionRadius
    if not targetPosition or type(speed) ~= "number" or speed <= 0
        or type(radius) ~= "number" or radius <= 0
    then
        return nil
    end

    local velocity = observationVelocity(observation)
    local lifetime = type(info.ProjectileLifetime) == "number" and info.ProjectileLifetime or math.huge
    local latency = math.clamp(
        type(networkLatency) == "number" and networkLatency or 0,
        0,
        0.25
    )
    local gravity = (worldGravity or 196.2) * (info.ProjectileGravity or 0)
    local predictedPosition = targetPosition
    for _ = 1, 4 do
        local _, travelTime = ballisticDirection(origin, predictedPosition, speed, gravity)
        if not travelTime or travelTime > lifetime then
            return nil
        end
        local updatedPosition = targetPosition + velocity * (travelTime + latency)
        if (updatedPosition - predictedPosition).Magnitude <= 0.25 then
            predictedPosition = updatedPosition
            break
        end
        predictedPosition = updatedPosition
    end

    local directions = {}
    local function addDirection(direction)
        if direction.Magnitude <= 1e-6 then
            return
        end
        direction = direction.Unit
        for _, existing in ipairs(directions) do
            if existing:Dot(direction) > 0.99 then
                return
            end
        end
        table.insert(directions, direction)
    end

    local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
    if horizontalVelocity.Magnitude > 1 then
        local forward = horizontalVelocity.Unit
        addDirection(forward)
        addDirection(-forward)
        addDirection(forward:Cross(Vector3.yAxis))
        addDirection(-forward:Cross(Vector3.yAxis))
    end
    addDirection(Vector3.new(0, -1, 0))
    addDirection((predictedPosition - origin).Unit)
    addDirection(-(predictedPosition - origin).Unit)

    local candidates = {}
    local searchDistance = math.max(radius - (info.ProjectileRaycastRadius or 0), 0.5)
    for _, direction in ipairs(directions) do
        local result = raycast(predictedPosition, direction * searchDistance)
        if result and result.Position then
            table.insert(candidates, {
                distance = (result.Position - predictedPosition).Magnitude,
                position = result.Position,
            })
        end
    end
    table.sort(candidates, function(left, right)
        return left.distance < right.distance
    end)

    local acceleration = Vector3.new(0, -gravity, 0)
    for _, candidate in ipairs(candidates) do
        local direction, flightTime = ballisticDirection(origin, candidate.position, speed, gravity)
        if direction and flightTime and flightTime <= lifetime then
            local impact, impactTime = traceProjectile(
                origin,
                direction,
                speed,
                acceleration,
                flightTime + 1e-3,
                raycast
            )
            local targetAtImpact = impactTime
                and targetPosition + velocity * (impactTime + latency)
            if impact and targetAtImpact and (impact - targetAtImpact).Magnitude <= radius then
                return {
                    direction = direction,
                    flightTime = impactTime,
                    impact = impact,
                    predictedPosition = targetAtImpact,
                }
            end
        end
    end

    return nil
end

local function distanceToSegment(point, segmentStart, segmentEnd)
    local segment = segmentEnd - segmentStart
    local lengthSquared = segment:Dot(segment)
    if lengthSquared <= 1e-6 then
        return (point - segmentStart).Magnitude
    end
    local alpha = math.clamp((point - segmentStart):Dot(segment) / lengthSquared, 0, 1)
    return (point - (segmentStart + segment * alpha)).Magnitude
end

function Rivals.simulateSlingshot(origin, direction, target, info, raycast, worldGravity)
    local speed = info.ProjectileSpeed
    local gravity = (worldGravity or 196.2) * (info.ProjectileGravity or 0)
    local lifetime = info.ProjectileLifetime or 5
    local maximumBounces = math.max((info.ProjectileMaxHits or 1) - 1, 0)
    local restitution = info.ProjectileBounceRestitution or 0.5
    local velocity = direction.Unit * speed
    local acceleration = Vector3.new(0, -gravity, 0)
    local position = origin
    local elapsed = 0
    local bounces = 0
    local path = { origin }

    while elapsed < lifetime do
        local step = math.min(SLINGSHOT_STEP, lifetime - elapsed)
        local nextPosition = position + velocity * step + acceleration * (0.5 * step * step)
        local result = raycast(position, nextPosition - position)
        local segmentEnd = result and result.Position or nextPosition
        if bounces > 0 and distanceToSegment(target, position, segmentEnd) <= SLINGSHOT_TARGET_RADIUS then
            table.insert(path, target)
            return {
                bounces = bounces,
                direction = direction.Unit,
                path = path,
            }
        end

        if result and result.Position and result.Normal then
            bounces += 1
            table.insert(path, result.Position)
            if bounces > maximumBounces then
                return nil
            end

            local impactVelocity = velocity + acceleration * step
            local normalVelocity = result.Normal * impactVelocity:Dot(result.Normal)
            local tangentVelocity = impactVelocity - normalVelocity
            velocity = tangentVelocity - normalVelocity * restitution
            if velocity.Magnitude <= 1e-3 then
                return nil
            end
            position = result.Position + velocity.Unit * RICOCHET_SURFACE_OFFSET
        else
            position = nextPosition
            velocity += acceleration * step
            table.insert(path, position)
        end
        elapsed += step
    end

    return nil
end

function Rivals.solveSlingshot(origin, observation, info, raycast, worldGravity)
    local targetPosition = observation and observation.position
    local speed = info and info.ProjectileSpeed
    if not targetPosition or type(speed) ~= "number" or speed <= 0 then
        return nil
    end

    local velocity = observationVelocity(observation)
    local travelTime = (targetPosition - origin).Magnitude / speed
    local predictedTarget = targetPosition + velocity * travelTime
    local gravity = (worldGravity or 196.2) * (info.ProjectileGravity or 0)
    local baseDirection = ballisticDirection(origin, predictedTarget, speed, gravity)
    if not baseDirection then
        return nil
    end

    local candidates = { baseDirection }
    local straightRicochet = Rivals.solveRicochet(origin, predictedTarget, raycast)
    if straightRicochet then
        table.insert(candidates, straightRicochet.direction)
    end

    local reference = math.abs(baseDirection:Dot(Vector3.yAxis)) < 0.95
        and Vector3.yAxis
        or Vector3.xAxis
    local right = baseDirection:Cross(reference).Unit
    local up = right:Cross(baseDirection).Unit
    local searchAngle = math.rad(12)
    for step = 0, 7 do
        local azimuth = 2 * math.pi * step / 8
        local radial = right * math.cos(azimuth) + up * math.sin(azimuth)
        table.insert(
            candidates,
            (baseDirection * math.cos(searchAngle) + radial * math.sin(searchAngle)).Unit
        )
    end

    for _, candidate in ipairs(candidates) do
        local solution = Rivals.simulateSlingshot(
            origin,
            candidate,
            predictedTarget,
            info,
            raycast,
            worldGravity
        )
        if solution then
            solution.predictedPosition = predictedTarget
            return solution
        end
    end
    return nil
end

function Rivals.projectTrajectory(camera, path)
    local segments = {}
    for index = 1, #path - 1 do
        local fromPoint, fromVisible = camera:WorldToViewportPoint(path[index])
        local toPoint, toVisible = camera:WorldToViewportPoint(path[index + 1])
        if fromVisible and toVisible and fromPoint.Z > 0 and toPoint.Z > 0 then
            table.insert(segments, {
                from = Vector2.new(fromPoint.X, fromPoint.Y),
                to = Vector2.new(toPoint.X, toPoint.Y),
            })
        end
    end
    return segments
end

function Rivals.adsSettled(cameraController, item)
    local info = item and item.Info
    local data = item and item.Data
    if type(info) ~= "table" or info.AimScopePercent == nil
        or type(data) ~= "table" or data.IsAiming ~= true
    then
        return true
    end

    local spring = cameraController._fov_weapons_spring
    return spring ~= nil
        and type(spring.Value) == "number"
        and type(spring.Target) == "number"
        and math.abs(spring.Value - spring.Target) <= 0.5
end

function Rivals.holdToFire(item)
    local info = item and item.Info
    local inputSpamming = type(info) == "table" and info.InputSpammingEnabled
    if type(inputSpamming) ~= "table"
        or type(inputSpamming.StartShooting) ~= "number"
        or info.IsProjectile == true
    then
        return false
    end

    return type(info.InternalUseCooldown) == "number"
        or type(info.ShootCooldown) == "number"
            and info.ShootCooldown <= AUTOMATIC_SHOOT_COOLDOWN
end

function Rivals.damageAtDistance(item, observation, distance)
    local info = item and item.Info
    local startDistance = info and info.RaycastDamageDropoffStartDistance
    local endDistance = info and info.RaycastDamageDropoffEndDistance
    local minimumMultiplier = info and info.RaycastDamageDropoffMultiplier
    local part = observation and observation.part
    local baseDamage = part and part.Name == "Head" and info and info.CriticalDamage
        or info and info.ShootDamage
    if type(baseDamage) ~= "number" then
        return nil
    end
    if type(startDistance) ~= "number"
        or type(endDistance) ~= "number"
        or endDistance <= startDistance
        or type(minimumMultiplier) ~= "number"
        or type(distance) ~= "number"
    then
        return baseDamage
    end

    local alpha = math.clamp((distance - startDistance) / (endDistance - startDistance), 0, 1)
    return baseDamage * (1 + (minimumMultiplier - 1) * alpha)
end

function Rivals.triggerDamageReady(item, observation, distance)
    local info = item and item.Info
    if type(info) ~= "table"
        or type(info.RaycastDamageDropoffStartDistance) ~= "number"
        or type(info.RaycastDamageDropoffEndDistance) ~= "number"
        or type(info.RaycastDamageDropoffMultiplier) ~= "number"
    then
        return true
    end

    local part = observation and observation.part
    local baseDamage = part and part.Name == "Head" and info.CriticalDamage or info.ShootDamage
    local damage = Rivals.damageAtDistance(item, observation, distance)
    local health = observation and observation.health
    return type(baseDamage) == "number"
        and type(damage) == "number"
        and (damage >= baseDamage * TRIGGER_DAMAGE_RETENTION
            or type(health) == "number" and damage >= health)
end

function Rivals.bowChargeTime(item, observation)
    local info = item and item.Info
    local timestamps = info and info.ChargeLevelTimestamps
    local multipliers = info and info.ChargeLevelDamageMultipliers
    if type(timestamps) ~= "table" or type(multipliers) ~= "table" then
        return 0
    end

    local part = observation and observation.part
    local baseDamage = part and part.Name == "Head" and info.CriticalDamage or info.ShootDamage
    local health = observation and observation.health
    if type(baseDamage) ~= "number" or type(health) ~= "number" then
        return timestamps[#timestamps] or 0
    end

    for level, timestamp in ipairs(timestamps) do
        local multiplier = multipliers[level]
        if type(timestamp) == "number"
            and type(multiplier) == "number"
            and baseDamage * multiplier >= health
        then
            return timestamp
        end
    end
    return timestamps[#timestamps] or 0
end

function Rivals.bowQuickShotLethal(item, observation)
    local info = item and item.Info
    if type(info) ~= "table" then
        return false
    end

    local part = observation and observation.part
    local damage = part and part.Name == "Head" and info.CriticalDamage or info.ShootDamage
    local health = observation and observation.health
    if type(damage) ~= "number" or type(health) ~= "number" or damage < health then
        return false
    end

    local shootCooldown = info.ShootCooldown
    local releaseCooldown = info.ChargeReleaseCooldown
    return type(shootCooldown) == "number"
        and type(releaseCooldown) == "number"
        and shootCooldown + TRIGGER_INTERVAL < releaseCooldown
end

function Rivals.new(context)
    assert(context and context.oh, "RIVALS adapter requires Hydroxide")
    assert(context.store, "RIVALS adapter requires a reactive store")
    assert(context.press and context.release, "RIVALS adapter requires held input support")
    assert(context.aimClick, "RIVALS adapter requires secondary click support")
    assert(context.aimPress and context.aimRelease, "RIVALS adapter requires held aiming support")
    assert(context.hookFunction, "RIVALS adapter requires hookfunction")
    assert(context.restoreFunction, "RIVALS adapter requires restorefunction")

    local clock = context.clock or os.clock
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace = game:GetService("Workspace")
    local Lighting = context.lighting or game:GetService("Lighting")
    local CollectionService = context.collectionService or game:GetService("CollectionService")
    local LocalPlayer = Players.LocalPlayer
    local loadModule: (any) -> any = context.requireModule or require
    local controllers = LocalPlayer.PlayerScripts:WaitForChild("Controllers")
    local cameraControllerModule = controllers:WaitForChild("CameraController")
    local fighterControllerModule = controllers:WaitForChild("FighterController")
    local controlsControllerModule = controllers:WaitForChild("ControlsController")
    local mechanicsControllerModule = controllers:WaitForChild("MechanicsController")
    if context.getLoadedModules then
        local deadline = clock() + 30
        repeat
            local succeeded, loadedModules = pcall(context.getLoadedModules)
            if succeeded
                and Rivals.controllersReady(
                    cameraControllerModule,
                    fighterControllerModule,
                    loadedModules,
                    mechanicsControllerModule
                )
            then
                break
            end
            if clock() >= deadline then
                error("RIVALS did not initialize its client controllers within 30 seconds")
            end
            (context.wait or task.wait)(0.1)
        until false
    end
    local CameraController = loadModule(cameraControllerModule)
    local FighterController = loadModule(fighterControllerModule)
    local ControlsController = loadModule(controlsControllerModule)
    local MechanicsController = loadModule(mechanicsControllerModule)
    local spawn = context.spawn or task.spawn
    local hookFunction = context.hookFunction
    local restoreFunction = context.restoreFunction
    local targeting = context.oh.targeting
    local store = context.store
    local stopped = false
    local nextTriggerAt = 0
    local triggerHeld = false
    local triggerHeldAt = 0
    local triggerHeldItem
    local fireHeld = false
    local fireHeldItem
    local ricochetCache
    local splashCache
    local slingshotCache
    local aimPlan
    local humanAimCharacter
    local humanAimState
    local backstabMovement
    local bhopMovement
    local renderDelta = 1 / 60
    local observations = {}
    local throwableCandidates = {}
    local nextThrowableRefreshAt = 0
    local nextVisualRefreshAt = 0
    local suppressedVisuals = setmetatable({}, { __mode = "k" })
    local self = {}
    local getNetworkPing = context.getNetworkPing or function()
        return LocalPlayer:GetNetworkPing()
    end
    local random = context.random or math.random
    local movementDirection = context.movementDirection
    local trajectorySurface
    local trajectoryLines = {}
    local drawing = context.oh.drawing
    if drawing and drawing.supports("Line") then
        trajectorySurface = drawing.createSurface()
    end

    local function collectThrowableCandidates()
        local candidates = {}
        local seen = {}
        local function collect(values)
            for _, value in ipairs(values or {}) do
                if value and not seen[value] then
                    seen[value] = true
                    table.insert(candidates, value)
                end
            end
        end

        if CollectionService and CollectionService.GetTagged then
            for _, tag in ipairs(THROWABLE_TAGS) do
                local succeeded, tagged = pcall(CollectionService.GetTagged, CollectionService, tag)
                if succeeded then
                    collect(tagged)
                end
            end
        end
        for _, name in ipairs(THROWABLE_CONTAINERS) do
            local container = Workspace:FindFirstChild(name)
            if container and container.GetChildren then
                collect(container:GetChildren())
            end
        end
        return candidates
    end

    local function smokeRaycastIgnore()
        if not CollectionService or not CollectionService.GetTagged then
            return {}
        end
        local succeeded, smokeClouds = pcall(CollectionService.GetTagged, CollectionService, "SmokeCloud")
        return succeeded and smokeClouds or {}
    end

    local function observeThrowables(camera, environmentID)
        local now = clock()
        if now >= nextThrowableRefreshAt then
            throwableCandidates = collectThrowableCandidates()
            nextThrowableRefreshAt = now + THROWABLE_REFRESH_INTERVAL
        end

        local utilities = {}
        for _, candidate in ipairs(throwableCandidates) do
            local observation = Rivals.throwableObservation(camera, candidate, environmentID)
            if observation then
                table.insert(utilities, observation)
            end
        end
        return utilities
    end
    observeThrowables = context.observeThrowables or observeThrowables

    local function updateVisualSuppressions(settings)
        local now = clock()
        if now < nextVisualRefreshAt then
            return
        end
        nextVisualRefreshAt = now + 0.1

        local roots = { Lighting, Workspace.CurrentCamera }
        local playerGui = context.playerGui
        if not playerGui and LocalPlayer.FindFirstChildOfClass then
            playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        end
        if playerGui then
            table.insert(roots, playerGui)
        end
        if settings.noSmoke then
            for _, candidate in ipairs(throwableCandidates) do
                local descriptor, root = throwableDescriptor(candidate)
                if descriptor and descriptor.tone == "smoke" then
                    table.insert(roots, {
                        instance = root,
                        kind = "smoke",
                    })
                end
            end
        end
        Rivals.updateVisualSuppressions(settings, roots, suppressedVisuals)
    end

    local function releaseFire()
        if not fireHeld then
            return
        end
        context.release()
        fireHeld = false
        fireHeldItem = nil
    end

    local function fighterFor(player)
        if player == LocalPlayer then
            return FighterController.LocalFighter
        end
        local fighters = FighterController._player_to_fighter
        return type(fighters) == "table" and fighters[player] or nil
    end

    local function equippedWeapon(player)
        local fighter = fighterFor(player)
        return fighter and Rivals.itemName(fighter.EquippedItem) or nil
    end

    local function isKatanaDeflecting(player)
        local fighter = fighterFor(player)
        local item = fighter and fighter.EquippedItem
        local data = item and item.Data
        return Rivals.itemName(item) == "Katana"
            and type(data) == "table"
            and data.FOVOffset == 5
    end

    local function localFighterIsActive()
        local fighter = FighterController.LocalFighter
        local entity = fighter and fighter.Entity
        local humanoid = entity and entity.Humanoid
        return fighter ~= nil
            and CameraController._current_subject == fighter
            and humanoid ~= nil
            and humanoid.Health > 0
    end

    local function localFighterIsInCombat()
        local fighter = FighterController.LocalFighter
        local data = fighter and fighter.Data
        return type(data) == "table"
            and (data.IsInShootingRange == true or data.IsInDuel == true)
    end

    local function toggleMovementInput(input, enabled)
        ControlsController:ToggleInput(input, enabled == true)
    end

    local function clearBackstabInputs()
        toggleMovementInput(Enum.KeyCode.S, false)
        toggleMovementInput(Enum.KeyCode.LeftShift, false)
        toggleMovementInput(Enum.KeyCode.C, false)
        toggleMovementInput(Enum.KeyCode.Space, false)
        if MechanicsController.IsSliding
            and type(MechanicsController.StopSliding) == "function"
        then
            MechanicsController:StopSliding()
        end
    end

    local function releaseBackstabMovement()
        if backstabMovement then
            clearBackstabInputs()
            if backstabMovement.fighter then
                pcall(rawset, backstabMovement.fighter, "GetMoveVector", backstabMovement.originalRawMoveVector)
            end
            backstabMovement = nil
        end
    end

    local function ensureBackstabMovement(fighter)
        if backstabMovement and backstabMovement.fighter ~= fighter then
            releaseBackstabMovement()
        end
        if backstabMovement then
            return true
        end
        if type(fighter) ~= "table" or type(fighter.GetMoveVector) ~= "function" then
            return false
        end

        local originalMoveVector = fighter.GetMoveVector
        local movement = {
            direction = nil,
            fighter = fighter,
            originalMoveVector = originalMoveVector,
            originalRawMoveVector = rawget(fighter, "GetMoveVector"),
            phase = "waitingSlide",
            slideFrames = 0,
        }
        local installed = pcall(rawset, fighter, "GetMoveVector", function(self, ...)
            if backstabMovement == movement and movement.direction then
                return movement.direction
            end
            return originalMoveVector(self, ...)
        end)
        if not installed then
            return false
        end
        backstabMovement = movement
        return true
    end

    local function advanceSlideJump(fighter, movement)
        local function readState(name, fallback)
            local value = fighter[name]
            if type(value) == "function" then
                return value(fighter)
            end
            if type(value) == "boolean" then
                return value
            end
            return fallback
        end

        toggleMovementInput(Enum.KeyCode.LeftShift, true)
        if movement.phase == "jump" then
            toggleMovementInput(Enum.KeyCode.Space, false)
            toggleMovementInput(Enum.KeyCode.C, false)
            movement.phase = "airborne"
        elseif movement.phase == "airborne" then
            toggleMovementInput(Enum.KeyCode.Space, false)
            toggleMovementInput(Enum.KeyCode.C, false)
            if readState("IsGrounded", false) then
                movement.phase = "waitingSlide"
            end
        elseif movement.phase == "sliding" then
            toggleMovementInput(Enum.KeyCode.Space, false)
            toggleMovementInput(Enum.KeyCode.C, true)
            if MechanicsController.IsSliding == true
                or readState("IsSlidingLocally", false)
            then
                movement.slideFrames += 1
                if movement.slideFrames >= 2 then
                    toggleMovementInput(Enum.KeyCode.Space, true)
                    MechanicsController:HighJump()
                    movement.phase = "jump"
                end
            end
        else
            toggleMovementInput(Enum.KeyCode.Space, false)
            toggleMovementInput(Enum.KeyCode.C, false)
            local grounded = readState("IsGrounded", true)
            local canSlide = readState("CanSlide", true)
            if grounded and canSlide then
                toggleMovementInput(Enum.KeyCode.C, true)
                movement.phase = "sliding"
                movement.slideFrames = 0
                spawn(function()
                    MechanicsController:Slide()
                end)
            end
        end
    end

    local function releaseBhopMovement()
        if bhopMovement then
            clearBackstabInputs()
            bhopMovement = nil
        end
    end

    local function isOpponent(player, character)
        return Rivals.isOpponent(LocalPlayer, player, character)
    end

    local function isTargetable(player, character)
        return Rivals.isTargetable(LocalPlayer, player, character)
    end

    local function selectTarget(maxScreenDistance, includeBlocked)
        local settings = store:Get().settings
        local options = {
            includeBlocked = includeBlocked,
            isEligible = isTargetable,
            screenOrigin = UserInputService:GetMouseLocation(),
        }
        if maxScreenDistance then
            options.maxScreenDistance = maxScreenDistance
        elseif not settings.fullScreenAim then
            options.maxScreenDistance = settings.fov
        end
        if settings.humanAim then
            local camera = Workspace.CurrentCamera
            local cameraFrame = camera
                and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
            return Rivals.closestObservation(
                observations,
                cameraFrame and cameraFrame.Position,
                options
            )
        end
        return targeting.nearestObservation(observations, options)
    end

    local function selectBackstabTarget(localPosition, info, acquisitionDistance)
        local nearest
        local nearestDistance = math.huge
        for _, observation in ipairs(observations) do
            local character = observation.character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local plan = Rivals.backstabPlan(
                localPosition,
                observation,
                info,
                acquisitionDistance
            )
            if observation.visible
                and isTargetable(observation.player, character)
                and root
                and plan
            then
                local distance = (localPosition - root.Position).Magnitude
                if distance < nearestDistance then
                    nearest = table.clone(observation)
                    nearest.backstabPlan = plan
                    nearestDistance = distance
                end
            end
        end
        return nearest
    end

    local function plannedAimTarget(target, item)
        local now = clock()
        if aimPlan
            and aimPlan.character == target.character
            and aimPlan.item == item
            and now < aimPlan.expiresAt
        then
            local refreshed = table.clone(target)
            refreshed.intentionalMiss = aimPlan.target.intentionalMiss
            refreshed.part = aimPlan.target.part
            if refreshed.intentionalMiss then
                local character = target.character
                local root = character
                    and character.FindFirstChild
                    and character:FindFirstChild("HumanoidRootPart")
                if root then
                    local width = root.Size and root.Size.X or 2
                    refreshed.part = root
                    refreshed.position = target.position
                        + root.CFrame.RightVector * (width * 0.5 + 2.5)
                end
            elseif refreshed.part and refreshed.part.Name == "Head" then
                local character = target.character
                local head = character and character.FindFirstChild and character:FindFirstChild("Head")
                if head then
                    refreshed.part = head
                    refreshed.position = head.Position
                end
            end
            return refreshed
        end

        local settings = store:Get().settings
        local info = item and item.Info
        local cooldown = type(info) == "table"
                and (info.ShootCooldown or info.AttackCooldown or info.ChargeReleaseCooldown)
            or TRIGGER_INTERVAL
        local planned = Rivals.applyAimRates(target, settings, random)
        if settings.humanAim and planned and not planned.intentionalMiss then
            local character = target.character
            local head = character and character.FindFirstChild and character:FindFirstChild("Head")
            if head then
                planned = table.clone(planned)
                planned.part = head
                planned.position = head.Position
            end
        end
        aimPlan = {
            character = target.character,
            expiresAt = now + math.max(TRIGGER_INTERVAL, cooldown or TRIGGER_INTERVAL),
            item = item,
            target = planned,
        }
        return planned
    end

    local function ricochetRaycast()
        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        raycastParams.IgnoreWater = true

        local excluded = {}
        if LocalPlayer.Character then
            table.insert(excluded, LocalPlayer.Character)
        end
        for _, observation in ipairs(observations) do
            if observation.character then
                table.insert(excluded, observation.character)
            end
        end
        raycastParams.FilterDescendantsInstances = excluded

        return function(origin, displacement)
            return Workspace:Raycast(origin, displacement, raycastParams)
        end
    end
    local environmentRaycast = context.environmentRaycast or ricochetRaycast
    local solveRicochet = context.solveRicochet or Rivals.solveRicochet
    local solveSplashAim = context.solveSplashAim or Rivals.solveSplashAim
    local solveSlingshot = context.solveSlingshot or Rivals.solveSlingshot

    local function renderTrajectory(path)
        if not trajectorySurface then
            return
        end

        local camera = Workspace.CurrentCamera
        local segments = camera and path and Rivals.projectTrajectory(camera, path) or {}
        for index, segment in ipairs(segments) do
            local line = trajectoryLines[index]
            if not line then
                line = trajectorySurface:create("Line", {}, { pointerEvents = false })
                trajectoryLines[index] = line
            end
            line:set({
                Color = Color3.fromRGB(92, 214, 255),
                From = segment.from,
                Thickness = 2,
                To = segment.to,
                Transparency = 0.9,
                Visible = true,
                ZIndex = 20,
            })
        end
        for index = #segments + 1, #trajectoryLines do
            trajectoryLines[index]:set({ Visible = false })
        end
    end

    local function updateObservations()
        local screenOrigin = UserInputService:GetMouseLocation()
        observations = targeting.observePlayers({
            isEligible = isOpponent,
            raycastIgnore = smokeRaycastIgnore(),
            screenOrigin = screenOrigin,
        })

        local fighter = FighterController.LocalFighter
        local data = fighter and fighter.Data
        local camera = Workspace.CurrentCamera
        local rangeEntities = Workspace:FindFirstChild("ShootingRangeEntities")
        if type(data) == "table" and data.IsInShootingRange and camera and rangeEntities then
            for _, entity in ipairs(rangeEntities:GetChildren()) do
                local humanoid = entity:FindFirstChildOfClass("Humanoid")
                local environmentID = entity:GetAttribute("EnvironmentID")
                local root = entity:FindFirstChild("HumanoidRootPart")
                local onScreen = false
                if root then
                    local _viewportPoint
                    _viewportPoint, onScreen = camera:WorldToViewportPoint(root.Position)
                end
                if entity:IsA("Model")
                    and humanoid
                    and humanoid.Health > 0
                    and (data.EnvironmentID == nil or environmentID == data.EnvironmentID)
                    and onScreen
                then
                    local observation = targeting.observeCharacter(entity, {
                        screenOrigin = screenOrigin,
                    })
                    if observation then
                        local health = humanoid.Health
                        local maxHealth = humanoid.MaxHealth
                        if health == math.huge or maxHealth == math.huge then
                            health = 1
                            maxHealth = 1
                        end
                        observation.player = entity
                        observation.health = health
                        observation.maxHealth = maxHealth
                        table.insert(observations, observation)
                    end
                end
            end
        end

        local cameraFrame = camera
            and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
        local cameraPosition = cameraFrame and cameraFrame.Position
        local nearby = {}
        if cameraPosition then
            for _, observation in ipairs(observations) do
                if observation.position
                    and (observation.position - cameraPosition).Magnitude <= MAX_OBSERVATION_DISTANCE
                then
                    table.insert(nearby, observation)
                end
            end
        end
        observations = nearby

        local visibleCount = 0
        for _, observation in ipairs(observations) do
            if observation.player ~= observation.character then
                local character = observation.character
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                observation.health = humanoid and humanoid.Health or 0
                observation.maxHealth = humanoid and humanoid.MaxHealth or 100
                observation.weapon = equippedWeapon(observation.player)
            end
            if observation.visible then
                visibleCount += 1
            end
        end
        return visibleCount
    end

    local function statusText(enemyCount, visibleCount)
        local fighter = FighterController.LocalFighter
        local data = fighter and fighter.Data
        local phase = "Lobby"
        if type(data) == "table" then
            if data.IsInShootingRange then
                return ("Shooting range · %d dummies · %d visible"):format(enemyCount, visibleCount)
            elseif data.IsInDuel then
                phase = "Duel"
            elseif data.IsSpectating ~= true then
                phase = "Active"
            end
        end
        return ("%s · %d enemies · %d visible"):format(phase, enemyCount, visibleCount)
    end

    local function setAimRotation(rotation, instant, character, maximumHumanSmoothness)
        local applied = rotation
        if instant then
            CameraController:SetRotation(rotation)
            return true
        end
        local settings = store:Get().settings
        local smoothness = settings.aimSmoothness
        if settings.humanAim then
            smoothness = math.max(smoothness, 55)
            if maximumHumanSmoothness then
                smoothness = math.min(smoothness, maximumHumanSmoothness)
            end
            if humanAimCharacter ~= character then
                humanAimCharacter = character
                humanAimState = {
                    curveSign = random() < 0.5 and -1 or 1,
                }
            end
            applied = Rivals.humanRotation(
                CameraController.Rotation,
                rotation,
                smoothness,
                renderDelta,
                humanAimState
            )
        else
            humanAimCharacter = nil
            humanAimState = nil
            applied = Rivals.smoothRotation(
                CameraController.Rotation,
                rotation,
                smoothness,
                renderDelta
            )
        end
        CameraController:SetRotation(applied)
        local pitchError = math.abs(rotation.X - applied.X)
        local yawError = math.abs((rotation.Y - applied.Y + math.pi) % (math.pi * 2) - math.pi)
        return math.max(pitchError, yawError) <= math.rad(0.5)
    end

    local function alignCamera(shotOnly)
        local settings = store:Get().settings
        local enabled = shotOnly and settings.shotAim
            or (settings.silentAim and not settings.shotAim)
        if not enabled
            or context.isInputCaptured()
            or not localFighterIsActive()
        then
            return nil
        end
        local function settleAim(rotation, instant, character, maximumSmoothness)
            if shotOnly then
                return true
            end
            return setAimRotation(
                rotation,
                instant,
                character,
                maximumSmoothness
            )
        end

        local fighter = FighterController.LocalFighter
        local item = fighter and fighter.EquippedItem
        local weaponName = Rivals.itemName(item)
        local energyRifle = weaponName == "Energy Rifle"
        local knife = weaponName == "Knife"
        if knife and settings.knifeMovement then
            return nil
        end
        local slingshot = weaponName == "Slingshot"
        local splashProjectile = Rivals.isSplashProjectile(item)
        local entity = fighter and fighter.Entity
        local localRoot = entity and entity.RootPart
        local target
        if knife then
            target = localRoot and selectBackstabTarget(localRoot.Position, item.Info)
        else
            target = selectTarget(nil, energyRifle or slingshot or splashProjectile)
        end
        local camera = Workspace.CurrentCamera
        if not target or not camera then
            return nil
        end

        local cameraFrame = camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame
        local origin = cameraFrame.Position
        local now = clock()
        if knife then
            local plan = target.backstabPlan
            local aimSettled = settleAim(
                Rivals.rotationToward(origin, plan.aimPosition),
                true,
                target.character
            )
            local aligned = {}
            for key, value in pairs(target) do
                aligned[key] = value
            end
            aligned.position = plan.aimPosition
            aligned.aimSettled = aimSettled
            aligned.backstab = plan.ready
            aligned.knifePath = plan.path
            return aligned
        end
        target = plannedAimTarget(target, item)

        if slingshot and target.position then
            local cacheValid = slingshotCache
                and slingshotCache.target == target.character
                and now < slingshotCache.expiresAt
                and (slingshotCache.origin - origin).Magnitude <= 0.5
                and (slingshotCache.targetPosition - target.position).Magnitude <= 0.5
            if not cacheValid then
                slingshotCache = {
                    expiresAt = now + SLINGSHOT_CACHE_INTERVAL,
                    origin = origin,
                    solution = solveSlingshot(
                        origin,
                        target,
                        item.Info,
                        environmentRaycast(),
                        Workspace.Gravity,
                        getNetworkPing()
                    ),
                    target = target.character,
                    targetPosition = target.position,
                }
            end

            if slingshotCache.solution then
                local aimSettled = settleAim(
                    Rivals.rotationToward(origin, origin + slingshotCache.solution.direction),
                    false,
                    target.character,
                    SLINGSHOT_HUMAN_AIM_MAX_SMOOTHNESS
                )
                local aligned = {}
                for key, value in pairs(target) do
                    aligned[key] = value
                end
                aligned.aimSettled = aimSettled
                aligned.slingshot = slingshotCache.solution
                aligned.visible = true
                return aligned
            end
        else
            slingshotCache = nil
        end

        if splashProjectile and target.position then
            local cacheValid = splashCache
                and splashCache.target == target.character
                and splashCache.item == item
                and now < splashCache.expiresAt
                and (splashCache.origin - origin).Magnitude <= 0.5
                and (splashCache.targetPosition - target.position).Magnitude <= 0.5
            if not cacheValid then
                splashCache = {
                    expiresAt = now + SPLASH_CACHE_INTERVAL,
                    item = item,
                    origin = origin,
                    solution = solveSplashAim(
                        origin,
                        target,
                        item.Info,
                        environmentRaycast(),
                        Workspace.Gravity
                    ),
                    target = target.character,
                    targetPosition = target.position,
                }
            end

            if splashCache.solution then
                local aimSettled = settleAim(
                    Rivals.rotationToward(origin, origin + splashCache.solution.direction),
                    false,
                    target.character
                )
                local aligned = {}
                for key, value in pairs(target) do
                    aligned[key] = value
                end
                aligned.aimSettled = aimSettled
                aligned.splashImpact = splashCache.solution
                aligned.visible = true
                return aligned
            end
        else
            splashCache = nil
        end
        if splashProjectile then
            return nil
        end

        if target.visible and Rivals.isDirectProjectile(item) then
            local solution = Rivals.solveProjectileAim(origin, target, item.Info, Workspace.Gravity)
            if solution then
                local aimSettled = settleAim(
                    Rivals.rotationToward(origin, origin + solution.direction),
                    false,
                    target.character
                )
                local aligned = {}
                for key, value in pairs(target) do
                    aligned[key] = value
                end
                aligned.aimSettled = aimSettled
                aligned.projectileAim = solution
                aligned.visible = true
                return aligned
            end
        end

        if target.visible then
            local aimSettled = settleAim(
                Rivals.rotationToward(origin, target.position),
                false,
                target.character
            )
            ricochetCache = nil
            local aligned = table.clone(target)
            aligned.aimSettled = aimSettled
            return aligned
        end
        if not energyRifle or not target.position then
            return nil
        end

        local cacheValid = ricochetCache
            and ricochetCache.target == target.character
            and now < ricochetCache.expiresAt
            and (ricochetCache.origin - origin).Magnitude <= 0.5
            and (ricochetCache.targetPosition - target.position).Magnitude <= 0.5
        if not cacheValid then
            ricochetCache = {
                direction = solveRicochet(origin, target.position, environmentRaycast()),
                expiresAt = now + RICOCHET_CACHE_INTERVAL,
                origin = origin,
                target = target.character,
                targetPosition = target.position,
            }
        end

        local solution = ricochetCache.direction
        if not solution then
            return nil
        end

        local aimSettled = settleAim(
            Rivals.rotationToward(origin, origin + solution.direction),
            false,
            target.character
        )
        local aligned = {}
        for key, value in pairs(target) do
            aligned[key] = value
        end
        aligned.aimSettled = aimSettled
        aligned.ricochet = solution
        aligned.visible = true
        return aligned
    end

    local cameraDataTarget
    local cameraDataOriginal
    local function silentAimPoint(aligned, origin, distance)
        local solution = aligned
            and (aligned.slingshot
                or aligned.splashImpact
                or aligned.projectileAim
                or aligned.ricochet)
        if solution and typeof(solution.direction) == "Vector3" then
            return origin + solution.direction.Unit * distance
        end
        return aligned and aligned.position
    end

    local function installCameraDataHook()
        local fighter = FighterController.LocalFighter
        local target = fighter and fighter.GetCameraData
        if type(target) ~= "function" or target == cameraDataTarget then
            return
        end
        if cameraDataTarget then
            restoreFunction(cameraDataTarget)
        end
        cameraDataTarget = target
        cameraDataOriginal = hookFunction(target, function(self, ...)
            local returned = table.pack(cameraDataOriginal(self, ...))
            local settings = store:Get().settings
            if stopped
                or not settings.shotAim
                or self ~= FighterController.LocalFighter
                or context.isInputCaptured()
            then
                return table.unpack(returned, 1, returned.n)
            end

            local cameraData = returned[1]
            local ray = returned[2]
            local camera = Workspace.CurrentCamera
            local cameraFrame = camera
                and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
            local origin = cameraFrame and cameraFrame.Position
            local distance = type(ray) == "table" and ray.Distance
            if origin and type(distance) == "number" then
                local aligned = alignCamera(true)
                local point = silentAimPoint(aligned, origin, distance)
                if point then
                    returned[1], returned[2] = Rivals.redirectCameraData(
                        cameraData,
                        ray,
                        point
                    )
                end
            end
            return table.unpack(returned, 1, returned.n)
        end)
    end

    local function runBackstabMovement()
        local settings = store:Get().settings
        local fighter = FighterController.LocalFighter
        local root = fighter and fighter.Entity and fighter.Entity.RootPart
        local item = fighter and fighter.EquippedItem
        local forwardHeld = UserInputService:IsKeyDown(Enum.KeyCode.W)
        if not settings.knifeMovement
            or not forwardHeld
            or context.isInputCaptured()
            or not localFighterIsActive()
            or not localFighterIsInCombat()
            or Rivals.itemName(item) ~= "Knife"
            or not root
        then
            releaseBackstabMovement()
            return nil
        end

        local target = selectBackstabTarget(
            root.Position,
            item.Info,
            KNIFE_MOVEMENT_ACQUISITION_DISTANCE
        )
        local plan = target and target.backstabPlan
        local approachPosition = plan and plan.approachPosition
        if not target or not approachPosition then
            releaseBackstabMovement()
            return nil
        end

        if not ensureBackstabMovement(fighter) then
            return nil
        end

        if backstabMovement.target ~= target.character then
            backstabMovement.phase = "waitingSlide"
            backstabMovement.slideFrames = 0
            backstabMovement.target = target.character
        end

        local travel = ((plan.movePosition or approachPosition) - root.Position)
            * Vector3.new(1, 0, 1)
        if plan.ready or travel.Magnitude <= 1e-3 then
            backstabMovement.direction = Vector3.zero
        else
            backstabMovement.direction = travel.Unit
        end
        local camera = Workspace.CurrentCamera
        local cameraFrame = camera
            and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
        local cameraOrigin = cameraFrame and cameraFrame.Position
        local cameraTarget = plan.ready
            and (target.position or plan.aimPosition)
            or (cameraOrigin and travel.Magnitude > 1e-3 and cameraOrigin - travel.Unit)
        local aimSettled = cameraOrigin
            and cameraTarget
            and setAimRotation(
                Rivals.rotationToward(cameraOrigin, cameraTarget),
                true,
                target.character
            )
            or false

        if plan.ready then
            clearBackstabInputs()
            backstabMovement.phase = "ready"
        else
            advanceSlideJump(fighter, backstabMovement)
        end

        local aligned = table.clone(target)
        aligned.position = plan.aimPosition
        aligned.aimSettled = aimSettled
        aligned.backstab = plan.ready
        aligned.knifePath = plan.path
        aligned.visible = true
        return aligned
    end

    local function runBhop(knifeMovementActive)
        if knifeMovementActive then
            bhopMovement = nil
            return
        end

        local settings = store:Get().settings
        local fighter = FighterController.LocalFighter
        local direction = movementDirection and movementDirection()
        local isMoving = typeof(direction) == "Vector3"
            and direction.Magnitude > 0.01
        if direction == nil then
            isMoving = UserInputService:IsKeyDown(Enum.KeyCode.W)
                or UserInputService:IsKeyDown(Enum.KeyCode.A)
                or UserInputService:IsKeyDown(Enum.KeyCode.S)
                or UserInputService:IsKeyDown(Enum.KeyCode.D)
        end
        if not settings.bhop
            or not isMoving
            or context.isInputCaptured()
            or not localFighterIsActive()
            or not localFighterIsInCombat()
        then
            releaseBhopMovement()
            return
        end

        if not bhopMovement or bhopMovement.fighter ~= fighter then
            releaseBhopMovement()
            bhopMovement = {
                fighter = fighter,
                phase = "waitingSlide",
                slideFrames = 0,
            }
        end
        advanceSlideJump(fighter, bhopMovement)
    end

    local function runTriggerBot(alignedTarget)
        local settings = store:Get().settings
        if not settings.triggerBot
            or context.isInputCaptured()
            or not localFighterIsActive()
            or not localFighterIsInCombat()
        then
            releaseFire()
            if triggerHeld then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
            end
            return
        end
        if alignedTarget and alignedTarget.aimSettled == false then
            local humanReticleReady = settings.humanAim
                and (alignedTarget.screenDistance or math.huge) <= TRIGGER_RADIUS
                and not alignedTarget.ricochet
                and not alignedTarget.slingshot
                and not alignedTarget.splashImpact
                and not alignedTarget.projectileAim
            if not humanReticleReady then
                releaseFire()
                return
            end
        end

        local target = alignedTarget or selectTarget(TRIGGER_RADIUS)
        if not target or not target.visible then
            releaseFire()
            if triggerHeld then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
                nextTriggerAt = clock() + TRIGGER_INTERVAL
            end
            return
        end
        if not alignedTarget and (target.screenDistance or math.huge) > TRIGGER_RADIUS then
            releaseFire()
            return
        end
        if isKatanaDeflecting(target.player) then
            releaseFire()
            if triggerHeld then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
            end
            return
        end

        local fighter = FighterController.LocalFighter
        local item = fighter and fighter.EquippedItem
        if Rivals.isSplashProjectile(item)
            and not (alignedTarget and alignedTarget.splashImpact)
        then
            releaseFire()
            return
        end
        if Rivals.itemName(item) == "Knife" then
            releaseFire()
            if not (alignedTarget and alignedTarget.backstab) then
                return
            end
            if triggerHeld then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
            end
            if clock() < nextTriggerAt then
                return
            end
            nextTriggerAt = clock() + (item.Info.HeavyAttackCooldown or TRIGGER_INTERVAL)
            context.aimClick()
            return
        end
        local camera = Workspace.CurrentCamera
        local cameraFrame = camera
            and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
        local targetDistance = cameraFrame
            and target.position
            and (target.position - cameraFrame.Position).Magnitude
        if targetDistance and not Rivals.triggerDamageReady(item, target, targetDistance) then
            releaseFire()
            return
        end
        if item and item.Name == "Bow" and type(item.Info) == "table" then
            releaseFire()
            if not triggerHeld then
                if clock() < nextTriggerAt then
                    return
                end
                if Rivals.bowQuickShotLethal(item, target) then
                    nextTriggerAt = clock() + (item.Info.ShootCooldown or TRIGGER_INTERVAL)
                    context.click()
                    aimPlan = nil
                    return
                end
                triggerHeld = true
                triggerHeldAt = clock()
                triggerHeldItem = item
                context.aimPress()
                return
            end
            if triggerHeldItem ~= item then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
                nextTriggerAt = clock() + TRIGGER_INTERVAL
                return
            end
            if clock() - triggerHeldAt + 1e-3 < Rivals.bowChargeTime(item, target) then
                return
            end

            context.aimRelease()
            triggerHeld = false
            triggerHeldItem = nil
            nextTriggerAt = clock() + (item.Info.ChargeReleaseCooldown or TRIGGER_INTERVAL)
            aimPlan = nil
            return
        end

        if triggerHeld then
            context.aimRelease()
            triggerHeld = false
            triggerHeldItem = nil
        end
        if Rivals.holdToFire(item) then
            if not Rivals.adsSettled(CameraController, item) then
                releaseFire()
                return
            end
            if fireHeld and fireHeldItem == item then
                return
            end
            releaseFire()
            if clock() < nextTriggerAt then
                return
            end
            fireHeld = true
            fireHeldItem = item
            context.press()
            aimPlan = nil
            return
        end

        releaseFire()
        if clock() < nextTriggerAt or not Rivals.adsSettled(CameraController, item) then
            return
        end

        nextTriggerAt = clock() + TRIGGER_INTERVAL
        context.click()
        aimPlan = nil
    end

    local renderConnection = RunService.RenderStepped:Connect(function(deltaTime)
        if stopped then
            return
        end
        installCameraDataHook()
        if type(deltaTime) == "number" and deltaTime > 0 then
            renderDelta = deltaTime
        end

        local visibleCount = updateObservations()
        local activeWeapon = equippedWeapon(LocalPlayer)
        local settings = store:Get().settings
        local utilityObservations = {}
        local fighter = FighterController.LocalFighter
        local data = fighter and fighter.Data
        if (settings.utilityEsp or settings.noSmoke)
            and localFighterIsInCombat()
            and Workspace.CurrentCamera
        then
            local environmentID = type(data) == "table" and data.EnvironmentID
                or LocalPlayer:GetAttribute("EnvironmentID")
            local observedUtilities = observeThrowables(Workspace.CurrentCamera, environmentID)
            if settings.utilityEsp then
                utilityObservations = observedUtilities
            end
        end
        updateVisualSuppressions(settings)
        store:Patch({
            activeWeapon = activeWeapon,
            activeWeaponKind = activeWeapon and "Item" or nil,
            observations = observations,
            utilityObservations = {
                count = #utilityObservations,
            },
            status = statusText(#observations, visibleCount),
        })
        context.render(observations, UserInputService:GetMouseLocation(), utilityObservations)
        local alignedTarget = runBackstabMovement() or alignCamera()
        if not alignedTarget and settings.shotAim then
            alignedTarget = alignCamera(true)
        end
        runBhop(backstabMovement ~= nil)
        local trajectory = alignedTarget
            and ((alignedTarget.ricochet and alignedTarget.ricochet.path)
                or (alignedTarget.slingshot and alignedTarget.slingshot.path)
                or alignedTarget.knifePath)
        renderTrajectory(trajectory)
        runTriggerBot(alignedTarget)
    end)

    function self.stop()
        if stopped then
            return
        end
        stopped = true
        if triggerHeld then
            context.aimRelease()
            triggerHeld = false
        end
        releaseFire()
        releaseBackstabMovement()
        releaseBhopMovement()
        Rivals.updateVisualSuppressions({}, {}, suppressedVisuals)
        if trajectorySurface then
            trajectorySurface:destroy()
        end
        if cameraDataTarget then
            restoreFunction(cameraDataTarget)
            cameraDataTarget = nil
            cameraDataOriginal = nil
        end
        renderConnection:Disconnect()
    end

    self.capabilities = Rivals.capabilities
    self.isOpponent = isOpponent
    self.selectTarget = selectTarget

    function self:cycleSkin() end
    function self:setWear() end
    function self:toggleStatTrak() end
    function self:resetSkin() end
    function self:cycleGlove() end
    function self:setGloveWear() end
    function self:setGloveColor() end
    function self:resetGlove() end

    return self
end

return Rivals
