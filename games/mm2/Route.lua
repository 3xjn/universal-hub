local Route = {}

local DEFAULT_COSTS = {
    CollectorDanger = 50,
    CollectorRailing = math.huge,
}

function Route.directWalk(feetY, targetY, clear)
    return clear == true and type(feetY) == "number" and type(targetY) == "number" and math.abs(targetY - feetY) < 2
end

-- While airborne, start the path at standing root height over the ground
-- actually under the character. The old +3 assumed a fixed hip.
function Route.planOrigin(rootPosition, footOffset, groundY)
    if type(groundY) == "number" and type(footOffset) == "number" then
        return Vector3.new(rootPosition.X, groundY + footOffset, rootPosition.Z), groundY
    end
    local offset = type(footOffset) == "number" and footOffset or 3
    return rootPosition, rootPosition.Y - offset
end

function Route.startAligned(waypointY, feetY)
    return type(waypointY) == "number" and type(feetY) == "number" and math.abs(waypointY - feetY) <= 3.5
end

function Route.heightOffset(firstWaypointY, feetY)
    if type(firstWaypointY) ~= "number" or type(feetY) ~= "number" then
        return 0
    end
    return math.clamp(firstWaypointY - feetY, -2, 2)
end

function Route.reachedGoal(endpoint, goal, collecting)
    if typeof(endpoint) ~= "Vector3" or typeof(goal) ~= "Vector3" then
        return false
    end
    local offset = endpoint - goal
    if Vector3.new(offset.X, 0, offset.Z).Magnitude >= 3 then
        return false
    end
    if collecting == true then
        return offset.Magnitude < 3 and math.abs(offset.Y) < 1.8
    end
    return offset.Y >= -4 and offset.Y <= 1.8
end

function Route.waypointReached(args)
    if type(args) ~= "table" or typeof(args.position) ~= "Vector3" or typeof(args.waypointPosition) ~= "Vector3" then
        return false
    end
    local delta = args.waypointPosition - args.position
    local footY = type(args.footY) == "number" and args.footY or args.position.Y
    local heightError = math.abs(args.waypointPosition.Y - (footY + (args.navHeightOffset or 0)))
    if heightError > 1.8 then
        return false
    end
    local flat = Vector3.new(delta.X, 0, delta.Z)
    local cornerClear = args.cornerClear ~= false
    if flat.Magnitude <= 1.2 then
        return cornerClear
    end
    if args.action == "Jump" then
        return false
    end
    if typeof(args.previousPosition) ~= "Vector3" then
        return false
    end
    local segment = args.waypointPosition - args.previousPosition
    segment = Vector3.new(segment.X, 0, segment.Z)
    if segment.Magnitude < 0.1 then
        return false
    end
    local along = (-flat):Dot(segment.Unit)
    local cross = ((-flat) - segment.Unit * along).Magnitude
    return along >= 0 and along <= 2.5 and cross <= 1.2 and cornerClear
end

-- Body radius first, then a slightly tighter capsule for narrow maps.
-- AgentHeight follows the R15 body. The equipped tool is not part of it.
function Route.modes(profile, goalRaised, costs)
    local radii = { profile.radius }
    if type(profile.tightRadius) == "number" and profile.tightRadius < profile.radius - 0.05 then
        table.insert(radii, profile.tightRadius)
    end
    local jumps = goalRaised == true and { true, false } or { false, true }
    local sets = {}
    for _, canJump in ipairs(jumps) do
        for _, radius in ipairs(radii) do
            table.insert(sets, {
                AgentCanClimb = true,
                AgentCanJump = canJump,
                AgentHeight = profile.height,
                AgentRadius = radius,
                Costs = costs or DEFAULT_COSTS,
                WaypointSpacing = radius < profile.radius - 0.05 and 1 or 2,
            })
        end
    end
    return sets
end

return Route
