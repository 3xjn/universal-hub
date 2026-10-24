local roblox = require("@lune/roblox")
CFrame = roblox.CFrame
Enum = roblox.Enum
Vector3 = roblox.Vector3

local Controller = require("../games/mm2/Controller")
local Agent = Controller.Agent
local Clearance = Controller.Clearance
local Jumps = Controller.Jumps
local Ladders = Controller.Ladders
local Route = Controller.Route
local Slopes = Controller.Slopes

local function part(className, position, size, classes)
    local self = {
        CanCollide = true,
        CFrame = CFrame.new(position),
        Name = className,
        Parent = true,
        Position = position,
        Size = size,
    }
    function self:IsA(name)
        return name == className or (classes and classes[name] == true) or name == "Instance"
    end
    return self
end

local function characterOf(children, tool)
    local byName = {}
    for name, child in pairs(children) do
        byName[name] = child
    end
    return {
        FindFirstChild = function(_, name)
            return byName[name]
        end,
        GetChildren = function()
            local list = {}
            for _, child in pairs(byName) do
                table.insert(list, child)
            end
            if tool then
                table.insert(list, tool)
            end
            return list
        end,
    }
end

local function r15(hipHeight)
    local root = part("Part", Vector3.new(0, 3, 0), Vector3.new(2, 2, 1), { BasePart = true })
    local leftFoot = part("MeshPart", Vector3.new(-0.3, 0.3, 0), Vector3.new(1, 0.6, 1), { BasePart = true })
    local rightFoot = part("MeshPart", Vector3.new(0.3, 0.3, 0), Vector3.new(1, 0.6, 1), { BasePart = true })
    local head = part("Part", Vector3.new(0, 4.9, 0), Vector3.new(1.2, 1.2, 1.2), { BasePart = true })
    local strayLeg = part("Part", Vector3.new(0, 1, 0), Vector3.new(1, 10, 1), { BasePart = true })
    local handle = part("MeshPart", Vector3.new(1.5, 3, 0), Vector3.new(0.4, 0.4, 6), { BasePart = true })
    local tool = {
        Name = "Knife",
        GetDescendants = function()
            return { handle }
        end,
    }
    function tool:IsA(name)
        return name == "Tool" or name == "Instance"
    end
    local character = characterOf({
        Head = head,
        ["Left Leg"] = strayLeg,
        LeftFoot = leftFoot,
        RightFoot = rightFoot,
    }, tool)
    local humanoid = {
        HipHeight = hipHeight,
        JumpHeight = 7.2,
        JumpPower = 50,
        MaxSlopeAngle = 89,
        UseJumpPower = false,
    }
    return {
        character = character,
        handle = handle,
        head = head,
        humanoid = humanoid,
        root = root,
        tool = tool,
    }
end

local rig = r15(2)
local profile = Agent.profile(rig.character, rig.humanoid, rig.root)

assert(profile.rig == "R15", "MM2 pathfinding must describe an R15 body")
assert(
    math.abs(profile.footOffset - 3) < 1e-4,
    "R15 feet must sit HipHeight plus half the root below the root when the soles agree"
)
assert(
    math.abs(profile.hipHeight - 2) < 1e-4,
    "A matching R15 HipHeight must be kept"
)
assert(
    math.abs(profile.height - (4.9 + 0.6 - 0)) < 1e-4,
    "Agent height must run from the soles to the top of the head"
)
assert(math.abs(profile.radius - 1) < 1e-4, "Agent radius must be half the wider root axis")
assert(
    profile.bodySize.Y > 5 and profile.bodySize.Z == 1,
    "Body casts must cover the R15 head and the root depth, not a short wide box"
)
assert(Agent.equippedTool(rig.character) == rig.tool, "The equipped gear must be the character's Tool")

local zeroed = r15(0)
local zeroedProfile = Agent.profile(zeroed.character, zeroed.humanoid, zeroed.root)
assert(
    math.abs(zeroedProfile.footOffset - 3) < 1e-4,
    "A gear that zeroes HipHeight must still stand on the R15 soles"
)

local inflated = r15(6)
local inflatedProfile = Agent.profile(inflated.character, inflated.humanoid, inflated.root)
assert(
    math.abs(inflatedProfile.footOffset - 3) < 1e-4 and math.abs(inflatedProfile.hipHeight - 2) < 1e-4,
    "A gear that inflates HipHeight must not lift the foot plane off the soles"
)
assert(
    math.abs(inflatedProfile.height - profile.height) < 1e-4 and math.abs(inflatedProfile.radius - 1) < 1e-4,
    "An equipped tool must not change R15 agent height or radius"
)

local move = {
    character = rig.character,
    humanoid = rig.humanoid,
    root = rig.root,
}
Controller.syncProfile(move, true)
local groundedOffset = move.profile.footOffset
rig.humanoid.HipHeight = 0
Controller.syncProfile(move, false)
assert(
    move.profile.footOffset == groundedOffset,
    "An airborne or climbing R15 pose must keep the grounded foot offset"
)
rig.humanoid.HipHeight = 2

assert(rig.handle.CanCollide == true)
Controller.syncTool(move)
assert(rig.handle.CanCollide == false, "Pathfinding must clear collision on the equipped tool")
assert(math.abs(move.profile.radius - 1) < 1e-4, "Clearing tool collision must not widen the agent")
Controller.syncTool(move)
assert(rig.handle.CanCollide == false, "Holding the same tool must not restore its collision early")
Controller.release(move)
assert(rig.handle.CanCollide == true, "Releasing the move must restore equipped-tool collision")

local feet = Controller.feet(move)
assert(
    math.abs(feet.Y - 0) < 1e-4,
    "Controller feet must be the R15 soles, not the root"
)

local spacing = 0.6
local steep = math.rad(65)
local steepRise = math.tan(steep) * spacing
local steepSamples = {}
for index = 0, 3 do
    table.insert(steepSamples, {
        normalY = math.cos(steep),
        y = steepRise * index,
    })
end
assert(Slopes.classify(steepSamples, 89, spacing) == "ramp", "A 65 degree incline must be walkable at the R15 slope limit")
assert(
    Slopes.classify(steepSamples, 60, spacing) == "blocked",
    "The same incline must stay blocked when MaxSlopeAngle cannot walk it"
)
assert(Slopes.walkable(0.57, 89) == true, "A 55 degree surface must be walkable for a default R15 humanoid")
assert(Slopes.blocksProbe(math.cos(steep), 89) == false, "A forward hit on a walkable ramp must not count as a wall")
assert(Slopes.blocksProbe(0, 89) == true, "A vertical face must still block the walk")

local stairSamples = {}
for index = 0, 3 do
    table.insert(stairSamples, { normalY = 1, y = 0.5 * index })
end
assert(Slopes.classify(stairSamples, 89, spacing) == "stairs", "Short flat treads must stay stairs")
assert(
    Slopes.classify({
        { normalY = 1, y = 0 },
        { normalY = 1, y = 0 },
        { normalY = 1, y = 3 },
    }, 89, spacing) == "blocked",
    "A sudden flat lip must be a box, not a ramp"
)
assert(
    Slopes.classify({
        { normalY = 1, y = 0 },
        { normalY = 1, y = 0 },
    }, 89, spacing) == "flat"
)

local box = Jumps.hop({
    agentHeight = profile.height,
    ceilingY = nil,
    feetY = 0,
    jumpHeight = 7.2,
    landingDistance = 1.3,
    landingY = 3,
    topY = 3,
    useJumpPower = false,
    jumpPower = 50,
})
assert(math.abs(box.jumpHeight - 7.2) < 1e-4, "R15 jumps must use JumpHeight unless UseJumpPower is set")
assert(Jumps.accept(box) == true, "A landing on the box top must be accepted")
assert(
    Jumps.accept(Jumps.hop({
        agentHeight = profile.height,
        feetY = 0,
        jumpHeight = 7.2,
        landingDistance = 3,
        landingY = 0,
        topY = 3,
        useJumpPower = false,
    })) == false,
    "A 3-stud probe that hits the floor behind the box must not count as a landing"
)
assert(
    Jumps.accept(Jumps.hop({
        agentHeight = profile.height,
        feetY = 0,
        jumpHeight = 7.2,
        landingDistance = 3,
        landingY = 3,
        topY = 3,
        useJumpPower = false,
    })) == true,
    "A wider box whose top is still under the probe must remain a landing"
)
assert(
    Jumps.headClears(0, profile.height, profile.height + 0.2) == false,
    "Head clearance must reject a ceiling the R15 head cannot clear"
)
assert(
    Jumps.accept(Jumps.hop({
        agentHeight = profile.height,
        ceilingY = profile.height + 0.2,
        feetY = 0,
        jumpHeight = 7.2,
        landingDistance = 1.3,
        landingY = 3,
        topY = 3,
    })) == false,
    "A box hop must fail when the head would hit"
)
assert(
    Jumps.accept(Jumps.hop({
        agentHeight = profile.height,
        feetY = 0,
        jumpHeight = 7.2,
        landingDistance = 1.3,
        landingY = 8,
        topY = 8,
        useJumpPower = false,
    })) == false,
    "A box taller than the R15 jump must be rejected"
)

local flatWalk = Controller.decide({
    box = box,
    desired = Vector3.new(0, 0, -1),
    profile = profile,
    slope = "flat",
})
assert(flatWalk.kind == "walk" and flatWalk.jump == false, "Flat ground must be walked, not hopped")

local rampWalk = Controller.decide({
    box = box,
    desired = Vector3.new(0, 0, -1),
    profile = profile,
    slope = "ramp",
})
assert(rampWalk.kind == "walk" and rampWalk.jump == false, "A walkable slope must not turn into a box jump")

local hop = Controller.decide({
    box = box,
    desired = Vector3.new(0, 0, -1),
    profile = profile,
    slope = "blocked",
})
assert(hop.kind == "jump" and hop.jump == true, "A blocked lip with a reachable top must jump")

local narrow = Controller.decide({
    desired = Vector3.new(0, 0, -4),
    passage = {
        left = 0.3,
        right = 1.4,
        side = Vector3.new(1, 0, 0),
    },
    profile = {
        bodySize = Vector3.new(1.2, profile.height, 1),
        radius = 0.6,
    },
    slope = "flat",
})
assert(narrow.kind == "walk" and math.abs(narrow.direction.X) > 0.2, "A gap wider than the R15 body must recenter")
assert(
    Clearance.centerOffset(0.3, 1.4, 1.2) ~= 0,
    "Doorway centering must run below the old 1.8 stud span when the body fits"
)
assert(
    Clearance.centerOffset(0.3, 1.4, 2) == 0,
    "A gap narrower than the body must not pretend to fit"
)
assert(Clearance.passageFits(1.7, 1.2) == true)
assert(Clearance.passageFits(1.7, 2) == false)

local modes = Route.modes(profile, false)
assert(#modes == 4, "Body and tight radii must each be tried with and without a jump")
assert(modes[1].AgentCanJump == false, "A level goal must try walking before jumping")
assert(math.abs(modes[1].AgentRadius - 1) < 1e-4, "The first capsule must be the R15 body radius")
assert(math.abs(modes[1].AgentHeight - profile.height) < 1e-4, "Agent height must be the measured R15 body")
assert(modes[1].AgentCanClimb == true)
assert(modes[1].WaypointSpacing == 2)
assert(modes[2].AgentRadius < profile.radius and modes[2].WaypointSpacing == 1, "Tight spaces must use a finer waypoint spacing")
assert(Route.modes(profile, true)[1].AgentCanJump == true, "A raised goal must try a jump before a walk")
local parameters = Controller.parameters(move, true)
assert(parameters[1].AgentHeight == profile.height and parameters[1].AgentCanJump == true)

local origin = Route.planOrigin(Vector3.new(4, 18, -2), profile.footOffset, 10)
assert(
    math.abs(origin.Y - (10 + profile.footOffset)) < 1e-4,
    "An airborne plan must restart at R15 standing height over the ground"
)
assert(Route.startAligned(10, 10) == true)
assert(Route.startAligned(14, 10) == false)

assert(
    Route.waypointReached({
        cornerClear = true,
        footY = 0,
        position = Vector3.new(0, 3, 0),
        waypointPosition = Vector3.new(0.4, 0, 0),
    }) == true,
    "A waypoint at the soles must count as reached from the R15 root"
)
assert(
    Route.waypointReached({
        cornerClear = true,
        footY = 3,
        position = Vector3.new(0, 3, 0),
        waypointPosition = Vector3.new(0.4, 0, 0),
    }) == false,
    "Treating the root as the feet must not accept a floor waypoint"
)

local named = Ladders.classify({
    class = "Model",
    named = true,
    parts = { { canCollide = true } },
    size = Vector3.new(2, 5, 0.4),
    upY = 0.9,
})
assert(named ~= nil and named.kind == "named" and named.height == 5, "A slightly leaning R15-height ladder must be detected")
assert(Ladders.classify({
    class = "Model",
    named = true,
    parts = { { canCollide = true } },
    size = Vector3.new(2, 5, 0.4),
    upY = 0.8,
}) == nil, "A steep prop must not become a ladder")
assert(Ladders.classify({
    class = "Model",
    embeddedTruss = true,
    named = true,
    parts = { { canCollide = true } },
    size = Vector3.new(2, 10, 0.4),
    upY = 1,
}) == nil)
assert(Ladders.classify({
    class = "Model",
    named = true,
    parts = { { canCollide = true } },
    size = Vector3.new(2, 3, 0.4),
    upY = 1,
}) == nil)
assert(Ladders.classify({
    class = "Model",
    named = true,
    parts = { { canCollide = true } },
    size = Vector3.new(4, 10, 4),
    upY = 1,
}) == nil, "A room-sized model must not be classified as a ladder")

local rungParts = {
    { canCollide = true, size = Vector3.new(0.3, 8, 0.3), upY = 1 },
    { canCollide = true, size = Vector3.new(0.3, 8, 0.3), upY = 1 },
}
for index = 0, 4 do
    table.insert(rungParts, {
        canCollide = true,
        localY = -3 + index * 1.2,
        size = Vector3.new(1.6, 0.2, 0.3),
        upY = 1,
    })
end
local rungs = Ladders.classify({
    class = "Model",
    named = false,
    parts = rungParts,
    size = Vector3.new(2, 8, 0.4),
    upY = 1,
})
assert(rungs ~= nil and rungs.kind == "rungs", "Unnamed rung geometry must still be a ladder")

local ladderCF = CFrame.new(0, 5, 0)
local ladderSize = Vector3.new(2, 10, 0.4)
local placed = Ladders.trussPlacement(ladderCF, ladderSize, profile.radius, 1)
assert(
    placed.cframe.Position.Z < -0.5 and math.abs(placed.cframe.Position.X) < 1e-4,
    "The climb truss must sit in front of the ladder face"
)
local halfDepth = placed.size.Z / 2
local trussMin = placed.cframe.Position.Z - halfDepth
local trussMax = placed.cframe.Position.Z + halfDepth
assert(
    trussMax < 0 or trussMin > 0,
    "The climb truss must not contain the ladder center"
)
assert(placed.size.Y == ladderSize.Y, "The climb truss must keep the ladder height")
assert(Ladders.trussProperties().CanCollide == true and Ladders.trussProperties().Transparency == 1)
assert(Ladders.approachSign(false, true) == -1)
assert(Ladders.approachSign(true, true) == 1)

local rotated = CFrame.new(10, 5, 20) * CFrame.Angles(0, math.rad(90), 0)
local rotatedSize = Vector3.new(8, 12, 1)
local beside = rotated:PointToObjectSpace(rotated:PointToWorldSpace(Vector3.new(0, 0, 2)))
local along = rotated:PointToObjectSpace(rotated:PointToWorldSpace(Vector3.new(10, 0, 0)))
assert(Ladders.near(beside.X, beside.Y, beside.Z, rotatedSize, 4) == true, "A root in front of a rotated ladder must count as near")
assert(
    Ladders.near(along.X, along.Y, along.Z, rotatedSize, 4) == false,
    "A point far along a rotated ladder must not pass an object-space reach test"
)

local early = {
    climbing = true,
    feetY = 10,
    goalY = 12.5,
    near = true,
    topY = 12.5,
    toward = Vector3.new(0, 0, -1),
}
assert(
    Ladders.intent(early) == "up",
    "R15 must keep climbing while the root has reached the lip and the feet have not"
)
local climb = Controller.decide({
    desired = Vector3.new(0, 0, -1),
    ladder = early,
    profile = profile,
    slope = "flat",
})
assert(climb.kind == "climb" and climb.intent == "up" and climb.jump == false, "Climbing must not jump, or the R15 climb cancels")
assert(climb.direction.Y > 0.5)

local lip = {
    climbing = true,
    feetY = 12.2,
    goalY = 12.5,
    lipHop = false,
    near = true,
    topY = 12.5,
    toward = Vector3.new(0, 0, -1),
    exitFlat = Vector3.new(0, 0, -2),
}
assert(Ladders.intent(lip) == "dismount", "Dismount must start when the feet reach the lip")
local dismount = Controller.decide({
    ladder = lip,
    profile = profile,
})
assert(dismount.kind == "climb" and dismount.intent == "dismount" and dismount.jump == false)
assert(Ladders.lipHop(12.0, 12.5, true) == true)
assert(Ladders.lipHop(10, 12.5, true) == false, "A lip hop must not fire halfway up the ladder")
assert(Ladders.intent({
    feetY = 12.4,
    flatToExit = 0.8,
    near = true,
    topY = 12.5,
}) == "done")
assert(Ladders.intent({
    feetY = 8,
    goalY = 4,
    near = true,
    topY = 12,
}) == "down")

local mockLadder = {
    Name = "Ladder",
    CFrame = CFrame.new(0, 6, 0),
    CanCollide = true,
    Size = Vector3.new(1.5, 8, 0.5),
}
function mockLadder:IsA(name)
    return name == "BasePart" or name == "Instance"
end
local fromPart = Ladders.specFromObject(mockLadder)
assert(fromPart ~= nil and fromPart.named == true and fromPart.class == "BasePart")
assert(Ladders.classify(fromPart) ~= nil, "A named ladder part must classify through the instance adapter")

print("mm2-pathfinding-contracts-ok")
