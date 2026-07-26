local ProjectileAim = {}

local RICOCHET_BOUNCES = 2
local RICOCHET_MAX_DISTANCE = 2048
local RICOCHET_REDIRECT_ANGLE = math.rad(7.5)
local RICOCHET_REDIRECT_RADIUS = 128
local RICOCHET_SURFACE_OFFSET = 0.05
local SPLASH_TRACE_STEPS = 12
local SLINGSHOT_STEP = 1 / 20
local SLINGSHOT_TARGET_RADIUS = 2.5

local function itemName(item)
    if not item then
        return nil
    end

    local info = item.Info
    if type(info) == "table" then
        return info.DisplayName or info.Name or info.ItemName or item.Name
    end
    return item.Name
end

function ProjectileAim.reflectDirection(direction, normal)
    return (direction - normal * (2 * direction:Dot(normal))).Unit
end

function ProjectileAim.reflectPoint(point, planePosition, planeNormal)
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

function ProjectileAim.traceRicochet(origin, direction, target, raycast, maxBounces, redirectAngle, maxDistance)
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
        rayDirection = ProjectileAim.reflectDirection(rayDirection, result.Normal)
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

function ProjectileAim.solveRicochet(origin, target, raycast, maxDistance)
    maxDistance = maxDistance or RICOCHET_MAX_DISTANCE
    local forward = (target - origin).Unit

    for _, probeDirection in ipairs(ricochetProbeDirections(forward)) do
        local sampledSurface = raycast(origin, probeDirection * maxDistance)
        if sampledSurface and sampledSurface.Normal and sampledSurface.Position then
            local image = ProjectileAim.reflectPoint(target, sampledSurface.Position, sampledSurface.Normal)
            local oneBounceDirection = (image - origin).Unit
            local oneBounce = ProjectileAim.traceRicochet(
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
                local firstReflection = ProjectileAim.reflectDirection(oneBounceDirection, firstSurface.Normal)
                local secondOrigin = firstSurface.Position + firstReflection * RICOCHET_SURFACE_OFFSET
                local secondSurface = raycast(secondOrigin, firstReflection * maxDistance)
                if secondSurface and secondSurface.Normal and secondSurface.Position then
                    local secondImage = ProjectileAim.reflectPoint(target, secondSurface.Position, secondSurface.Normal)
                    local firstImage = ProjectileAim.reflectPoint(
                        secondImage,
                        firstSurface.Position,
                        firstSurface.Normal
                    )
                    local twoBounce = ProjectileAim.traceRicochet(
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

function ProjectileAim.isSplashProjectile(item)
    local info = item and item.Info
    return type(info) == "table"
        and info.DamageType == "Splash"
        and info.IsProjectile == true
        and type(info.ProjectileSpeed) == "number"
        and info.ProjectileSpeed > 0
        and type(info.ShootExplosionRadius) == "number"
        and info.ShootExplosionRadius > 0
end

function ProjectileAim.isDirectProjectile(item)
    local info = item and item.Info
    return type(info) == "table"
        and info.IsProjectile == true
        and info.IsRaycast ~= true
        and info.DamageType ~= "Splash"
        and (info.ProjectileMaxHits or 1) <= 1
        and (info.RaycastBounceCount or 0) == 0
        and itemName(item) ~= "Slingshot"
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

local function projectileLaunchOrigin(cameraOrigin, direction, info)
    local spawnOffset = info and info.ProjectileSpawnOffset
    if typeof(spawnOffset) ~= "CFrame" or direction.Magnitude <= 1e-6 then
        return cameraOrigin
    end

    return (CFrame.lookAt(cameraOrigin, cameraOrigin + direction) * spawnOffset).Position
end

function ProjectileAim.solveProjectileAim(origin, observation, info, worldGravity)
    local targetPosition = observation and observation.position
    local speed = info and info.ProjectileSpeed
    if not targetPosition or type(speed) ~= "number" or speed <= 0 then
        return nil
    end

    local targetVelocity = observationVelocity(observation)
    local gravity = (worldGravity or 196.2) * (info.ProjectileGravity or 0)
    local lifetime = type(info.ProjectileLifetime) == "number" and info.ProjectileLifetime or math.huge
    local predictedPosition = targetPosition
    local launchOrigin = origin
    local direction
    local flightTime

    for _ = 1, 6 do
        direction, flightTime = ballisticDirection(launchOrigin, predictedPosition, speed, gravity)
        if not direction or not flightTime or flightTime > lifetime then
            return nil
        end
        predictedPosition = targetPosition + targetVelocity * flightTime
        launchOrigin = projectileLaunchOrigin(origin, direction, info)
    end

    direction, flightTime = ballisticDirection(launchOrigin, predictedPosition, speed, gravity)
    if not direction or not flightTime or flightTime > lifetime then
        return nil
    end
    return {
        direction = direction,
        flightTime = flightTime,
        launchOrigin = launchOrigin,
        predictedPosition = predictedPosition,
    }
end

function ProjectileAim.solveSplashAim(origin, observation, info, raycast, worldGravity, networkLatency)
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

function ProjectileAim.simulateSlingshot(origin, direction, target, info, raycast, worldGravity)
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

function ProjectileAim.solveSlingshot(origin, observation, info, raycast, worldGravity)
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
    local straightRicochet = ProjectileAim.solveRicochet(origin, predictedTarget, raycast)
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
        local solution = ProjectileAim.simulateSlingshot(
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

function ProjectileAim.projectTrajectory(camera, path)
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


ProjectileAim.MAX_DISTANCE = RICOCHET_MAX_DISTANCE

return ProjectileAim
