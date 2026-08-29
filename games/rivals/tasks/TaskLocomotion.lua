local TaskLocomotion = {}
TaskLocomotion.__index = TaskLocomotion

local function horizontal(vector)
    return Vector3.new(vector.X, 0, vector.Z)
end

local function unitOrZero(vector)
    return vector.Magnitude > 0.01 and vector.Unit or Vector3.zero
end

local function seededSign(seed)
    return type(seed) == "number" and math.abs(math.floor(seed)) % 2 == 1 and -1 or 1
end

local function highGroundRoute(
    routes,
    toward,
    allowApproach,
    preferredKey,
    preferredMinimum,
    preferredMaximum,
    currentDistance
)
    local selected
    local selectedScore = -math.huge
    local preferred
    local preferredScore = -math.huge
    for _, route in ipairs(routes or {}) do
        local direction = typeof(route.direction) == "Vector3" and unitOrZero(horizontal(route.direction))
            or Vector3.zero
        local approach = direction:Dot(toward)
        local projectedDistance = route.projectedDistance
        local preservesRange = type(projectedDistance) == "number"
        if
            preservesRange
            and type(preferredMaximum) == "number"
            and currentDistance > preferredMaximum
        then
            preservesRange = projectedDistance < currentDistance - 0.5
        elseif
            preservesRange
            and type(preferredMinimum) == "number"
            and currentDistance < preferredMinimum
        then
            preservesRange = projectedDistance >= currentDistance - 0.25
        elseif preservesRange then
            preservesRange = (type(preferredMinimum) ~= "number"
                    or projectedDistance >= preferredMinimum)
                and (type(preferredMaximum) ~= "number"
                    or projectedDistance <= preferredMaximum)
        end
        local eligible = route.supported == true
            and route.clear == true
            and type(route.exposed) == "boolean"
            and type(route.elevation) == "number"
            and route.elevation >= 0.75
            and approach >= -0.25
            and (allowApproach or approach <= 0.2)
            and preservesRange
        if eligible then
            local score = route.elevation + (route.exposed == false and 0.75 or 0)
            if route.key == preferredKey then
                preferred = route
                preferredScore = score
            end
            if not selected or score > selectedScore then
                selected = route
                selectedScore = score
            end
        end
    end
    return preferred
            and selected
            and preferredScore >= selectedScore - 0.5
            and preferred
        or selected
end

local function safestRoute(routes, desired, preferredKey)
    local selected
    local selectedAlignment = -math.huge
    local preferred
    local preferredAlignment = -math.huge
    for _, route in ipairs(routes or {}) do
        if
            route.supported == true
            and route.clear == true
            and typeof(route.direction) == "Vector3"
        then
            local direction = unitOrZero(horizontal(route.direction))
            local alignment = direction:Dot(desired)
            if route.key == preferredKey then
                preferred = route
                preferredAlignment = alignment
            end
            if alignment > selectedAlignment then
                selected = route
                selectedAlignment = alignment
            end
        end
    end
    if preferred and preferredAlignment >= selectedAlignment - 0.15 then
        return preferred, preferredAlignment
    end
    return selected, selectedAlignment
end

function TaskLocomotion.new()
    return setmetatable({
        engagementKey = nil,
        engagementRevision = 0,
        invalidated = false,
        lastDistance = math.huge,
        lastProgressAt = 0,
        nextSlideAt = 0,
        routeKey = nil,
        strafeSign = 1,
    }, TaskLocomotion)
end

function TaskLocomotion:reset()
    self.engagementKey = nil
    self.invalidated = false
    self.lastDistance = math.huge
    self.lastProgressAt = 0
    self.nextSlideAt = 0
    self.routeKey = nil
    self.strafeSign = 1
end

function TaskLocomotion:invalidate()
    self.invalidated = true
end

function TaskLocomotion:plan(state)
    local offset = horizontal(state.targetPosition - state.position)
    local distance = offset.Magnitude
    local toward = unitOrZero(offset)
    local engagementKey = state.targetKey or "anonymous"
    if self.engagementKey ~= engagementKey then
        self.engagementKey = engagementKey
        self.engagementRevision += 1
        self.strafeSign = seededSign((state.engagementSeed or 0) + self.engagementRevision)
        self.lastDistance = distance
        self.lastProgressAt = state.now
        self.routeKey = nil
        self.invalidated = false
    elseif distance < self.lastDistance - 0.75 then
        self.lastDistance = distance
        self.lastProgressAt = state.now
    elseif self.invalidated or state.now - self.lastProgressAt >= 0.65 and state.clear == false then
        self.strafeSign = -self.strafeSign
        self.lastDistance = distance
        self.lastProgressAt = state.now
        self.invalidated = false
    end

    local strafe = Vector3.new(-toward.Z, 0, toward.X) * self.strafeSign
    local away = -toward
    local profile = state.weaponProfile or {}
    local tactical = state.tactical or {}
    local healthRatio = state.healthRatio
    local survivalObjective = state.objective == "wins" or state.objective == "streaks"
    local retreatHealth = survivalObjective and 0.5 or 0.35
    local vulnerable = type(healthRatio) == "number" and healthRatio <= retreatHealth
        or profile.ready == false
    local finishOpportunity = state.objective == "eliminations"
        and type(state.targetHealthRatio) == "number"
        and state.targetHealthRatio <= 0.25
    local intent
    local direction

    if typeof(state.hazardDirection) == "Vector3" and state.hazardDirection.Magnitude > 0.01 then
        intent = "evade"
        direction = state.hazardDirection.Unit
    elseif vulnerable then
        intent = "retreat"
        direction = unitOrZero(away * 0.82 + strafe * 0.58)
    elseif tactical.hardPush == true and state.lineBlocked == false then
        intent = "pressure"
        direction = unitOrZero(toward * 0.96 + strafe * 0.2)
    elseif
        (tactical.avoidSniperPeek == true or tactical.pushSniper == true)
        and state.lineBlocked == nil
    then
        intent = "hold"
        direction = Vector3.zero
    elseif tactical.avoidSniperPeek == true and state.lineBlocked == false then
        intent = "seekCover"
        direction = unitOrZero(toward * 0.12 + strafe)
    elseif tactical.pushSniper == true and state.lineBlocked == true then
        intent = "pressure"
        direction = unitOrZero(toward * 0.9 + strafe * 0.3)
    elseif tactical.pushSniper == true and distance < 7 then
        intent = "kite"
        direction = unitOrZero(away * 0.75 + strafe * 0.65)
    elseif tactical.pushSniper == true then
        intent = "pressure"
        direction = unitOrZero(toward * 0.88 + strafe * 0.48)
    elseif state.lineBlocked == true then
        intent = "flank"
        direction = unitOrZero(toward * 0.68 + strafe * 0.74)
    elseif state.clear == false then
        intent = "flank"
        direction = strafe
    elseif finishOpportunity then
        intent = "pressure"
        direction = unitOrZero(toward * 0.92 + strafe * 0.3)
    elseif profile.kind == "melee" then
        intent = distance > (profile.reach or 7) and "pressure" or "kite"
        direction = intent == "pressure" and unitOrZero(toward * 0.92 + strafe * 0.3)
            or unitOrZero(away * 0.65 + strafe * 0.76)
    elseif
        profile.sustained == true
        and type(profile.preferredMinimum) == "number"
        and type(profile.preferredMaximum) == "number"
    then
        local preferredMinimum = profile.preferredMinimum
        local preferredMaximum = profile.preferredMaximum
        if distance > preferredMaximum then
            intent = "pressure"
            direction = unitOrZero(toward * 0.72 + strafe * 0.7)
        elseif distance < preferredMinimum then
            intent = "kite"
            direction = unitOrZero(away * 0.82 + strafe * 0.58)
        else
            intent = "hold"
            direction = unitOrZero(away * 0.12 + strafe)
        end
    elseif type(profile.preferredMaximum) == "number" and distance > profile.preferredMaximum then
        intent = "pressure"
        direction = unitOrZero(toward * 0.82 + strafe * 0.58)
    elseif
        type(profile.preferredMinimum) == "number"
        and distance < profile.preferredMinimum
    then
        intent = "kite"
        direction = unitOrZero(away * 0.8 + strafe * 0.6)
    elseif distance > 20 then
        intent = "pressure"
        direction = unitOrZero(toward * 0.82 + strafe * 0.58)
    elseif distance < 8 then
        intent = "kite"
        direction = unitOrZero(away * 0.8 + strafe * 0.6)
    else
        intent = "hold"
        direction = unitOrZero(toward * 0.35 + strafe)
    end

    local preferredMinimum = profile.preferredMinimum
    local allowHighGroundApproach = type(preferredMinimum) ~= "number"
        or distance >= preferredMinimum
    local takeHighGround = not vulnerable
        and intent ~= "evade"
        and intent ~= "seekCover"
        and distance > 12
        and highGroundRoute(
            state.routes,
            toward,
            allowHighGroundApproach,
            self.routeKey,
            profile.preferredMinimum,
            profile.preferredMaximum,
            distance
        )
    local routeKey
    if takeHighGround then
        intent = "highGround"
        direction = unitOrZero(horizontal(takeHighGround.direction))
        routeKey = takeHighGround.key
    end

    if state.routesKnown == true then
        local safe, alignment = safestRoute(state.routes, direction, self.routeKey)
        if safe and alignment >= 0.15 then
            direction = unitOrZero(horizontal(safe.direction))
            routeKey = safe.key
        else
            direction = Vector3.zero
            intent = "hold"
            routeKey = "hold"
        end
    end

    local slide = state.clear == true
        and state.grounded == true
        and (intent == "pressure" or intent == "flank" or intent == "highGround")
        and distance > 20
        and state.now >= self.nextSlideAt
    if slide then
        self.nextSlideAt = state.now + 2.1
    end
    self.routeKey = routeKey
    return {
        direction = direction,
        intent = intent,
        routeKey = routeKey,
        slide = slide,
        strafeSign = self.strafeSign,
    }
end

return TaskLocomotion
