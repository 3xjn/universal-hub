local roblox = require("@lune/roblox")
Vector3 = roblox.Vector3

local TaskLocomotion = require("../games/rivals/tasks/TaskLocomotion")

local locomotion = TaskLocomotion.new()
local first = locomotion:plan({
    now = 0,
    position = Vector3.zero,
    targetPosition = Vector3.new(60, 0, 0),
    grounded = true,
    clear = true,
})
assert(first.intent == "pressure" and first.slide == true)

local retained = locomotion:plan({
    now = 0.2,
    position = Vector3.new(2, 0, 0),
    targetPosition = Vector3.new(60, 0, 0),
    grounded = true,
    clear = true,
})
assert(retained.strafeSign == first.strafeSign, "a progressing push must retain its route")

local replanned = locomotion:plan({
    now = 1,
    position = Vector3.new(2, 0, 0),
    targetPosition = Vector3.new(60, 0, 0),
    grounded = true,
    clear = false,
})
assert(replanned.strafeSign == -retained.strafeSign, "a stalled blocked push must replan")
assert(replanned.slide == false, "a blocked route must not slide")

local highGround = TaskLocomotion.new():plan({
    now = 0,
    position = Vector3.zero,
    targetPosition = Vector3.new(40, 4, 0),
    targetKey = "high-ground-target",
    engagementSeed = 0,
    grounded = true,
    clear = true,
    routesKnown = true,
    routes = {
        { key = "forward", direction = Vector3.new(1, 0, 0), supported = true, clear = true, elevation = 0 },
        {
            key = "left",
            direction = Vector3.new(0, 0, 1),
            supported = true,
            clear = true,
            elevation = 2,
            exposed = true,
            projectedDistance = 40,
        },
        { key = "right", direction = Vector3.new(0, 0, -1), supported = true, clear = true, elevation = 0 },
        { key = "retreat", direction = Vector3.new(-1, 0, 0), supported = true, clear = true, elevation = 0 },
    },
    weaponProfile = { sustained = true, preferredMinimum = 28, preferredMaximum = 52 },
})
assert(
    highGround.intent == "highGround"
        and highGround.routeKey == "left"
        and highGround.direction.Z > 0.9
        and highGround.slide == true,
    "a supported rising route must beat flat strafing and use traversal mobility"
)

local farHighGround = TaskLocomotion.new():plan({
    now = 0,
    position = Vector3.zero,
    targetPosition = Vector3.new(100, 4, 0),
    targetKey = "far-high-ground-target",
    grounded = true,
    clear = true,
    routesKnown = true,
    routes = {
        {
            key = "forward",
            direction = Vector3.new(1, 0, 0),
            supported = true,
            clear = true,
            elevation = 4,
            exposed = false,
            projectedDistance = 80,
        },
        { key = "left", direction = Vector3.new(0, 0, 1), supported = true, clear = true, elevation = 0, exposed = false, projectedDistance = 102 },
        { key = "right", direction = Vector3.new(0, 0, -1), supported = true, clear = true, elevation = 0, exposed = false, projectedDistance = 102 },
        { key = "retreat", direction = Vector3.new(-1, 0, 0), supported = true, clear = true, elevation = 0, exposed = false, projectedDistance = 120 },
    },
    weaponProfile = { sustained = true, preferredMinimum = 22.5, preferredMaximum = 50 },
})
assert(
    farHighGround.intent == "highGround" and farHighGround.routeKey == "forward",
    "far ranged combat must take a supported rising route that closes toward the weapon band"
)

local coveredHighGround = TaskLocomotion.new():plan({
    now = 0,
    position = Vector3.zero,
    targetPosition = Vector3.new(40, 0, 0),
    targetKey = "covered-high-ground-target",
    grounded = true,
    clear = true,
    routesKnown = true,
    routes = {
        { key = "left", direction = Vector3.new(0, 0, 1), supported = true, clear = true, elevation = 3, exposed = true, projectedDistance = 40 },
        { key = "right", direction = Vector3.new(0, 0, -1), supported = true, clear = true, elevation = 2.6, exposed = false, projectedDistance = 40 },
    },
    weaponProfile = { preferredMinimum = 28, preferredMaximum = 52 },
})
assert(
    coveredHighGround.intent == "highGround" and coveredHighGround.routeKey == "right",
    "comparable high-ground routes must prefer cover over marginal extra elevation"
)

local safeRetreat = TaskLocomotion.new():plan({
    now = 0,
    position = Vector3.zero,
    targetPosition = Vector3.new(6, 0, 0),
    targetKey = "close-target",
    grounded = true,
    clear = true,
    routesKnown = true,
    routes = {
        { key = "forward", direction = Vector3.new(1, 0, 0), supported = true, clear = true, elevation = 2 },
        { key = "left", direction = Vector3.new(0, 0, 1), supported = true, clear = true, elevation = 0 },
        { key = "right", direction = Vector3.new(0, 0, -1), supported = true, clear = true, elevation = 0 },
        { key = "retreat", direction = Vector3.new(-1, 0, 0), supported = false, clear = false, elevation = -8 },
    },
    weaponProfile = { sustained = true, preferredMinimum = 28, preferredMaximum = 52 },
})
assert(
    safeRetreat.intent == "kite"
        and math.abs(safeRetreat.direction.X) < 0.1
        and math.abs(safeRetreat.direction.Z) > 0.9,
    "close-range kiting must choose a supported lateral ramp route instead of backing over an edge"
)

local firstEngagement = TaskLocomotion.new():plan({
    now = 0,
    position = Vector3.zero,
    targetPosition = Vector3.new(30, 0, 0),
    targetKey = "first",
    engagementSeed = 0,
    grounded = true,
    clear = true,
})
local secondEngagement = TaskLocomotion.new():plan({
    now = 0,
    position = Vector3.zero,
    targetPosition = Vector3.new(30, 0, 0),
    targetKey = "second",
    engagementSeed = 1,
    grounded = true,
    clear = true,
})
assert(
    firstEngagement.direction.Z * secondEngagement.direction.Z < 0,
    "equally safe engagements may choose opposite deterministic strafe sides without frame jitter"
)

local unknownSniperPlan = TaskLocomotion.new():plan({
    now = 0,
    position = Vector3.zero,
    targetPosition = Vector3.new(30, 0, 0),
    targetKey = "unknown-sniper",
    grounded = true,
    clear = true,
    tactical = { avoidSniperPeek = true, pushSniper = true },
})
assert(
    unknownSniperPlan.intent == "hold" and unknownSniperPlan.direction == Vector3.zero,
    "unknown line of sight must disable aggressive anti-sniper specialization"
)

local survivalPlan = TaskLocomotion.new():plan({
    now = 0,
    position = Vector3.zero,
    targetPosition = Vector3.new(30, 0, 0),
    targetKey = "survival",
    grounded = true,
    clear = true,
    healthRatio = 0.45,
    objective = "wins",
})
assert(
    survivalPlan.intent == "retreat" and survivalPlan.direction.X < 0,
    "win and streak objectives must preserve a wounded bot instead of forcing pressure"
)

local finishPlan = TaskLocomotion.new():plan({
    now = 0,
    position = Vector3.zero,
    targetPosition = Vector3.new(40, 0, 0),
    targetKey = "finish",
    grounded = true,
    clear = true,
    objective = "eliminations",
    targetHealthRatio = 0.2,
    weaponProfile = { sustained = true, preferredMinimum = 28, preferredMaximum = 52 },
})
assert(
    finishPlan.intent == "pressure" and finishPlan.direction.X > 0.8,
    "elimination objectives must convert a safe low-health finish into pressure"
)

local afkPush = TaskLocomotion.new():plan({
    now = 0,
    position = Vector3.zero,
    targetPosition = Vector3.new(40, 0, 0),
    targetKey = "visible-afk",
    grounded = true,
    clear = true,
    lineBlocked = false,
    tactical = { hardPush = true },
    weaponProfile = { sustained = true, preferredMinimum = 28, preferredMaximum = 52 },
})
assert(
    afkPush.intent == "pressure" and afkPush.direction.X > 0.9 and afkPush.slide == true,
    "a verified visible AFK target must override passive weapon-band holding"
)
local unknownAfk = TaskLocomotion.new():plan({
    now = 0,
    position = Vector3.zero,
    targetPosition = Vector3.new(40, 0, 0),
    targetKey = "unknown-afk",
    grounded = true,
    clear = true,
    tactical = { hardPush = true },
    weaponProfile = { sustained = true, preferredMinimum = 28, preferredMaximum = 52 },
})
assert(
    unknownAfk.intent == "hold" and unknownAfk.slide == false,
    "unknown line of sight must not manufacture an AFK hard-push specialization"
)

print("rivals-task-locomotion-contracts-ok")
