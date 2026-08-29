local roblox = require("@lune/roblox")
Enum = roblox.Enum
Vector3 = roblox.Vector3
local Movement = require("../games/rivals/libraries/Movement")
local WeaponPolicy = require("../games/rivals/libraries/WeaponPolicy")

assert(Movement.isBlockingSurface(nil, 46) == false)
assert(
    Movement.isBlockingSurface({ Normal = Vector3.new(0, 0.8, 0.6) }, 46) == false,
    "native-walkable ramp normals must not be classified as walls"
)
assert(
    Movement.isBlockingSurface({ Normal = Vector3.new(0, 0.5, 0.866) }, 46) == true,
    "surfaces steeper than native MaxSlopeAngle must remain obstacles"
)

local unknownRangeProfile = WeaponPolicy.movementProfile({
    Info = { Type = "Gun", IsRaycast = true, ShootCooldown = 0.1, MaxAmmo = 20 },
})
assert(
    unknownRangeProfile.sustained == true
        and unknownRangeProfile.preferredMinimum == nil
        and unknownRangeProfile.preferredMaximum == nil
        and unknownRangeProfile.ready == nil,
    "missing native range and ammo evidence must keep movement specialization neutral"
)
local emptyProfile = WeaponPolicy.movementProfile({
    Data = { Ammo = 0 },
    Info = { Type = "Gun", IsRaycast = true, ShootCooldown = 0.1, MaxAmmo = 20 },
})
assert(emptyProfile.ready == false, "native empty-ammo evidence must trigger vulnerable movement")
local adsItem = {
    Info = {
        Type = "Gun",
        IsRaycast = true,
        RaycastDamageDropoffStartDistance = 50,
        RaycastDamageDropoffEndDistance = 200,
    },
}
assert(
    WeaponPolicy.shouldTaskAim(adsItem, {
        distance = 40,
        grounded = true,
        intent = "hold",
        lineBlocked = false,
    }) == true,
    "task combat must ADS with a grounded ranged firing angle"
)
assert(
    WeaponPolicy.shouldTaskAim(adsItem, {
        distance = 80,
        grounded = true,
        intent = "flank",
        lineBlocked = false,
    }) == false,
    "task combat must release ADS while traversing to a new angle"
)
assert(
    WeaponPolicy.isAiming({ Data = {} }) == nil
        and WeaponPolicy.isAiming({ Data = { IsAiming = false } }) == false,
    "missing opponent ADS evidence must remain unknown"
)
assert(
    WeaponPolicy.taskCanFinish({
        Info = { Type = "Gun", ShootDamage = 20 },
        Data = { Ammo = 2 },
    }, { health = 30 }, 20) == true,
    "known gun damage and ammo must prove a task finish"
)
assert(
    WeaponPolicy.taskCanFinish({
        Info = { Type = "Melee", Class = "Melee", AttackDamage = 50, AttackReach = 7 },
        Data = {},
    }, { health = 40 }, 5) == true
        and WeaponPolicy.taskCanFinish({
            Info = { Type = "Melee", Class = "Melee", AttackDamage = 50, AttackReach = 7 },
            Data = {},
        }, { health = 40 }, 10) == false,
    "melee finishes must require positive native reach evidence"
)

local moves = {}
local humanoid = {
    Move = function(_, direction, relative)
        table.insert(moves, { direction = direction, relative = relative })
    end,
}
local root = { Position = Vector3.new(0, 0, 0) }
local fighter = {
    Entity = { Humanoid = humanoid, RootPart = root },
    IsGrounded = function()
        return true
    end,
}
local captured = false
local now = 0
local movement = Movement.new({
    controlsController = { ToggleInput = function() end },
    mechanicsController = {},
    getFighter = function()
        return fighter
    end,
    getSettings = function()
        return {}
    end,
    isActive = function()
        return false
    end,
    isTaskActive = function()
        return true
    end,
    isInCombat = function()
        return true
    end,
    isInputCaptured = function()
        return captured
    end,
    userInputService = {},
    clock = function()
        return now
    end,
    spawn = function(fn)
        fn()
    end,
})
movement:updateTaskCombat(Vector3.new(30, 0, 0))
assert(
    #moves == 1
        and moves[1].direction.X > 0.7
        and math.abs(moves[1].direction.Z) > 0.3
        and moves[1].relative == false,
    "task combat must approach distant opponents diagonally through Humanoid:Move"
)
now = 2
movement:updateTaskCombat(Vector3.new(5, 0, 0))
assert(
    moves[2].direction.X < 0 and math.abs(moves[2].direction.Z) > 0.1,
    "task combat must back-strafe instead of standing inside melee range"
)
captured = true
movement:updateTaskCombat(Vector3.new(30, 0, 0))
assert(moves[#moves].direction.Magnitude == 0, "input capture must release owned task movement")
captured = false
movement:updateTaskCombat(Vector3.new(30, 0, 0))
fighter.IsGrounded = nil
movement:updateTaskCombat(Vector3.new(30, 0, 0))
assert(
    moves[#moves].direction == Vector3.zero,
    "unknown grounding must hold instead of executing an unverified route"
)
fighter.IsGrounded = function()
    error("native grounding unavailable")
end
movement:updateTaskCombat(Vector3.new(30, 0, 0))
assert(
    moves[#moves].direction == Vector3.zero,
    "failed native grounding must remain unknown rather than become airborne"
)
fighter.IsGrounded = function()
    return true
end
movement:stop()
assert(moves[#moves].direction.Magnitude == 0, "pause/unload must stop task movement immediately")
local wallMoves = {}
local wallMovement = Movement.new({
    controlsController = { ToggleInput = function() end },
    mechanicsController = {},
    getFighter = function()
        return fighter
    end,
    getSettings = function()
        return {}
    end,
    isActive = function()
        return true
    end,
    isTaskActive = function()
        return true
    end,
    isInCombat = function()
        return true
    end,
    isInputCaptured = function()
        return false
    end,
    userInputService = {},
    spawn = function(fn)
        fn()
    end,
    taskObstacleProbe = function(_origin, direction)
        return direction.X > 0.2
    end,
})
humanoid.Move = function(_, direction)
    table.insert(wallMoves, direction)
end
wallMovement:updateTaskCombat(Vector3.new(30, 0, 0))
assert(
    #wallMoves == 1 and math.abs(wallMoves[1].X) < 0.1 and math.abs(wallMoves[1].Z) > 0.9,
    "blocked approaches must steer laterally along the wall"
)
local hazardMoves = {}
humanoid.Move = function(_, direction)
    table.insert(hazardMoves, direction)
end
local hazardMovement = Movement.new({
    controlsController = { ToggleInput = function() end },
    mechanicsController = {},
    getFighter = function()
        return fighter
    end,
    getSettings = function()
        return {}
    end,
    isActive = function()
        return true
    end,
    isTaskActive = function()
        return true
    end,
    isInCombat = function()
        return true
    end,
    isInputCaptured = function()
        return false
    end,
    userInputService = {},
    spawn = function(fn)
        fn()
    end,
})
hazardMovement:updateTaskCombat(
    Vector3.new(30, 0, 0),
    { { label = "GRENADE", tone = "danger", worldPosition = Vector3.new(3, 0, 0) } }
)
assert(hazardMoves[1].X < 0, "nearby grenades and fire must repel task movement before detonation")
hazardMovement:updateTaskCombat(
    nil,
    { { label = "THROWABLE", tone = "danger", worldPosition = Vector3.new(3, 0, 0) } }
)
assert(
    hazardMoves[#hazardMoves].X < 0,
    "task movement must evade throwables even during target-acquisition gaps"
)
local rifleMoves = {}
humanoid.Move = function(_, direction)
    table.insert(rifleMoves, direction)
end
fighter.EquippedItem = {
    Info = {
        Type = "Gun",
        IsRaycast = true,
        ShootCooldown = 0.1,
        MaxAmmo = 20,
        DamageFallOffStartDist = 52,
        DamageFallOffEndDist = 90,
    },
}
local rifleMovement = Movement.new({
    controlsController = { ToggleInput = function() end },
    mechanicsController = {},
    getFighter = function()
        return fighter
    end,
    getSettings = function()
        return {}
    end,
    isActive = function()
        return true
    end,
    isTaskActive = function()
        return true
    end,
    isInCombat = function()
        return true
    end,
    isInputCaptured = function()
        return false
    end,
    userInputService = {},
    spawn = function(fn)
        fn()
    end,
    taskLineOfSightBlocked = function()
        return false
    end,
})
rifleMovement:updateTaskCombat(Vector3.new(40, 0, 0))
assert(
    rifleMoves[1].X < 0 and math.abs(rifleMoves[1].Z) > 0.9,
    "assault rifles must hold the falloff edge and strafe instead of rushing"
)
rifleMovement.taskLineOfSightBlocked = function()
    return true
end
rifleMovement:updateTaskCombat(Vector3.new(40, 0, 0))
assert(
    rifleMoves[2].X > 0 and math.abs(rifleMoves[2].Z) > rifleMoves[2].X,
    "assault rifles must slice around blocked corners with lateral commitment"
)
rifleMovement.taskLineOfSightBlocked = function()
    return false
end
rifleMovement:updateTaskCombat(
    Vector3.new(40, 0, 0),
    nil,
    { avoidSniperPeek = true, pushSniper = true }
)
assert(
    rifleMoves[3].X > 0 and math.abs(rifleMoves[3].Z) > 0.5,
    "task combat must close through a lateral angle against an aimed-down sniper"
)

local crouchStates = {}
local crouchNow = 0
humanoid.Move = function() end
local crouchMovement = Movement.new({
    controlsController = { ToggleInput = function() end },
    mechanicsController = {
        SetCrouching = function(_, v)
            table.insert(crouchStates, v)
        end,
    },
    getFighter = function()
        return fighter
    end,
    getSettings = function()
        return {}
    end,
    isActive = function()
        return true
    end,
    isTaskActive = function()
        return true
    end,
    isInCombat = function()
        return true
    end,
    isInputCaptured = function()
        return false
    end,
    userInputService = {},
    spawn = function(fn)
        fn()
    end,
    clock = function()
        return crouchNow
    end,
    taskLineOfSightBlocked = function()
        return false
    end,
})
crouchMovement:updateTaskCombat(Vector3.new(40, 0, 0))
crouchNow = 0.3
crouchMovement:updateTaskCombat(Vector3.new(40, 0, 0))
assert(
    crouchStates[1] == true and crouchStates[2] == false,
    "ranged assault-rifle combat must crouch-spam through MechanicsController"
)
crouchNow = 1
crouchMovement:updateTaskCombat(
    Vector3.new(40, 0, 0),
    { { label = "GRENADE", tone = "danger", worldPosition = Vector3.new(3, 0, 0) } }
)
assert(crouchStates[#crouchStates] == false, "hazard evasion must release owned crouching")

local mobilityNow = 0
local mobilitySliding = false
local slides, highJumps, stoppedSlides = 0, 0, 0
fighter.CanSlide = function()
    return true
end
fighter.IsGrounded = function()
    return true
end
fighter.IsSlidingLocally = function()
    return mobilitySliding
end
fighter.EquippedItem = nil
local mobilityMovement = Movement.new({
    controlsController = { ToggleInput = function() end },
    mechanicsController = {
        Slide = function()
            slides += 1
            mobilitySliding = true
        end,
        HighJump = function()
            highJumps += 1
            mobilitySliding = false
        end,
        StopSliding = function()
            stoppedSlides += 1
            mobilitySliding = false
        end,
    },
    getFighter = function()
        return fighter
    end,
    getSettings = function()
        return {}
    end,
    isActive = function()
        return true
    end,
    isTaskActive = function()
        return true
    end,
    isInCombat = function()
        return true
    end,
    isInputCaptured = function()
        return false
    end,
    userInputService = {},
    spawn = function(fn)
        fn()
    end,
    clock = function()
        return mobilityNow
    end,
    taskLineOfSightBlocked = function()
        return false
    end,
    taskObstacleProbe = function()
        return false
    end,
})
mobilityMovement:updateTaskCombat(Vector3.new(40, 0, 0))
mobilityNow = 0.2
mobilityMovement:updateTaskCombat(Vector3.new(40, 0, 0))
assert(
    slides == 1 and highJumps == 1,
    "task combat must chain normal MechanicsController slide and high-jump actions while traversing"
)
assert(
    mobilityMovement.taskMobilityPhase == "awaitingAirborne"
        and mobilityMovement.taskOwnsSlide == true,
    "slide ownership must continue until native airborne or slide-ended evidence arrives"
)
mobilitySliding = true
fighter.IsGrounded = function()
    return nil
end
mobilityNow = 0.3
mobilityMovement:updateTaskCombat(Vector3.new(40, 0, 0))
assert(
    mobilityMovement.taskMobilityPhase == "awaitingAirborne"
        and mobilityMovement.taskOwnsSlide == true,
    "unknown grounding must not manufacture an airborne slide transition"
)
mobilityNow = 0.8
mobilityMovement:updateTaskCombat(Vector3.new(40, 0, 0))
assert(stoppedSlides == 1, "slide-transition timeout must release native sliding")
mobilityMovement:stopTaskCombat()
fighter.IsGrounded = function()
    return true
end

local deferredSlide
local staleSlideCalls, staleStopCalls = 0, 0
local deferredMovement = Movement.new({
    controlsController = { ToggleInput = function() end },
    mechanicsController = {
        Slide = function()
            staleSlideCalls += 1
            mobilitySliding = true
            coroutine.yield()
        end,
        HighJump = function() end,
        StopSliding = function()
            staleStopCalls += 1
            mobilitySliding = false
        end,
    },
    getFighter = function()
        return fighter
    end,
    getSettings = function()
        return {}
    end,
    isActive = function()
        return true
    end,
    isTaskActive = function()
        return true
    end,
    isInCombat = function()
        return true
    end,
    isInputCaptured = function()
        return false
    end,
    userInputService = {},
    clock = function()
        return 0
    end,
    spawn = function(fn)
        deferredSlide = fn
    end,
    taskLineOfSightBlocked = function()
        return false
    end,
    taskObstacleProbe = function()
        return false
    end,
})
deferredMovement:updateTaskCombat(Vector3.new(40, 0, 0))
assert(type(deferredSlide) == "function", "slide execution must be scheduled off-frame")
deferredMovement:stopTaskCombat()
deferredSlide()
assert(staleSlideCalls == 0, "stopped task movement must invalidate a deferred slide call")
deferredSlide = nil
deferredMovement:updateTaskCombat(Vector3.new(40, 0, 0))
local yieldingSlide = coroutine.create(deferredSlide)
assert(coroutine.resume(yieldingSlide) and staleSlideCalls == 1)
deferredMovement:stopTaskCombat()
local taskStopCalls = staleStopCalls
mobilitySliding = true
assert(coroutine.resume(yieldingSlide))
assert(
    staleStopCalls == taskStopCalls and mobilitySliding == true,
    "a stale yielding task slide must not stop a later manual slide"
)

local parkourActions = {}
local parkourNow = 0
local parkourGrounded = true
local parkourSliding = false
fighter.IsGrounded = function()
    return parkourGrounded
end
fighter.IsSlidingLocally = function()
    return parkourSliding
end
local parkourMovement = Movement.new({
    controlsController = { ToggleInput = function() end },
    mechanicsController = {
        Jump = function()
            table.insert(parkourActions, "jump")
        end,
        JumpRequest = function()
            table.insert(parkourActions, "jump-request")
        end,
        Slide = function()
            parkourSliding = true
            table.insert(parkourActions, "slide")
        end,
        StopSliding = function()
            parkourSliding = false
        end,
        HighJump = function()
            parkourSliding = false
            table.insert(parkourActions, "high")
        end,
        DoubleJumpRequest = function()
            table.insert(parkourActions, "double-request")
        end,
    },
    getFighter = function()
        return fighter
    end,
    getSettings = function()
        return {}
    end,
    isActive = function()
        return true
    end,
    isTaskActive = function()
        return true
    end,
    isInCombat = function()
        return true
    end,
    isInputCaptured = function()
        return false
    end,
    userInputService = {},
    clock = function()
        return parkourNow
    end,
    spawn = function(fn)
        fn()
    end,
    taskParkourProbe = function()
        return { low = true, middle = false, high = false, landing = true }
    end,
})
parkourMovement:updateTaskCombat(Vector3.new(30, 0, 0))
assert(parkourActions[1] == "jump", "low parkour obstacles must use MechanicsController:Jump")
parkourNow = 1
parkourMovement.taskParkourProbe = function()
    return { low = true, middle = true, high = false, landing = true }
end
parkourMovement:updateTaskCombat(Vector3.new(30, 0, 0))
assert(
    parkourActions[#parkourActions] == "slide"
        and parkourMovement.taskMobilityPhase == "awaitingSlide",
    "mantle-height traversal must start through the native slide path"
)
parkourNow = 1.05
parkourMovement:updateTaskCombat(Vector3.new(30, 0, 0))
assert(
    parkourActions[#parkourActions] == "high",
    "mantle-height traversal must HighJump only after native sliding confirmation"
)
parkourNow = 2
parkourMovement.taskParkourProbe = function()
    return { low = false, middle = false, high = false, landing = false }
end
local actionsBeforeEdge = #parkourActions
parkourMovement:updateTaskCombat(Vector3.new(30, 0, 0))
parkourGrounded = false
parkourNow = 2.4
parkourMovement:updateTaskCombat(Vector3.new(30, 0, 0))
assert(
    #parkourActions == actionsBeforeEdge,
    "farm navigation must never jump or double-jump toward an unverified landing"
)

local infiniteHeld = false
local infiniteCalls = 0
local infiniteCaptured = false
local infiniteMovement = Movement.new({
    controlsController = { ToggleInput = function() end },
    mechanicsController = {
        DoubleJump = function()
            infiniteCalls += 1
        end,
    },
    getFighter = function()
        return fighter
    end,
    getSettings = function()
        return {}
    end,
    isActive = function()
        return true
    end,
    isInCombat = function()
        return true
    end,
    isInputCaptured = function()
        return infiniteCaptured
    end,
    userInputService = {
        IsKeyDown = function()
            return infiniteHeld
        end,
    },
    spawn = function(fn)
        fn()
    end,
})
infiniteHeld = true
infiniteMovement:updateInfiniteJump({ infiniteJump = true })
infiniteMovement:updateInfiniteJump({ infiniteJump = true })
assert(infiniteCalls == 1, "Infinite Jump must fire once per physical jump press, not every frame")
infiniteHeld = false
infiniteMovement:updateInfiniteJump({ infiniteJump = true })
infiniteHeld = true
infiniteCaptured = true
infiniteMovement:updateInfiniteJump({ infiniteJump = true })
assert(infiniteCalls == 1, "Infinite Jump must respect hub input capture")

local committedActions = {}
local committedNow = 0
local committedGrounded = true
local committedRoot =
    { Position = Vector3.new(0, 0, 0), AssemblyLinearVelocity = Vector3.new(0, 0, 0) }
local committedFighter = {
    Entity = { Humanoid = humanoid, RootPart = committedRoot },
    EquippedItem = { Info = { MaxDoubleJumps = 1 } },
    IsGrounded = function()
        return committedGrounded
    end,
}
local committedMovement = Movement.new({
    controlsController = { ToggleInput = function() end },
    mechanicsController = {
        JumpRequest = function()
            table.insert(committedActions, "jump")
        end,
        DoubleJumpRequest = function()
            table.insert(committedActions, "double")
        end,
    },
    getFighter = function()
        return committedFighter
    end,
    getSettings = function()
        return {}
    end,
    isActive = function()
        return true
    end,
    isTaskActive = function()
        return true
    end,
    isInCombat = function()
        return true
    end,
    isInputCaptured = function()
        return false
    end,
    userInputService = {},
    clock = function()
        return committedNow
    end,
    spawn = function(fn)
        fn()
    end,
    taskParkourProbe = function()
        return {
            low = false,
            middle = false,
            high = false,
            landing = true,
            jumpLanding = Vector3.new(8, 0, 0),
            jumpConfidence = 1,
        }
    end,
})
local committedDebug = committedMovement:updateTaskCombat(Vector3.new(30, 0, 0))
assert(
    committedActions[1] == "jump"
        and committedMovement.taskParkourCommit ~= nil
        and committedDebug.needsDoubleJump == true,
    "verified Baritone-style landing plans must commit one native jump"
)
committedGrounded = false
committedNow = 0.25
committedRoot.Position = Vector3.new(8, 1, 0)
committedRoot.AssemblyLinearVelocity = Vector3.new(0, 3, 0)
local missingTargetDebug = committedMovement:updateTaskCombat(nil)
assert(
    #committedActions == 1
        and committedMovement.taskParkourCommit ~= nil
        and missingTargetDebug.needsDoubleJump == true,
    "a dropped target must not cancel a committed gap or release its double-jump item"
)
committedNow = 0.5
committedRoot.Position = Vector3.new(8, 1, 0)
committedRoot.AssemblyLinearVelocity = Vector3.new(0, -2, 0)
committedMovement:updateTaskCombat(nil)
committedMovement:updateTaskCombat(nil)
assert(
    committedActions[2] == "double" and #committedActions == 2,
    "weapon-provided double jumps must use the native request once while descending"
)
committedGrounded = true
committedNow = 0.8
committedRoot.Position = Vector3.new(8, 0, 0)
committedMovement:updateTaskCombat(nil)
assert(
    committedMovement.taskParkourCommit == nil,
    "committed parkour must finish only on the verified landing"
)

local sensorNow = 0.1
local groundProbes, parkourProbes, unverifiedJumps = 0, 0, 0
local sensorRoot = { Position = Vector3.zero }
local sensorHumanoid = {
    Health = 100,
    MaxHealth = 100,
    Move = function() end,
}
local sensorFighter = {
    Entity = { Humanoid = sensorHumanoid, RootPart = sensorRoot },
    IsGrounded = function()
        return true
    end,
}
local sensorMovement = Movement.new({
    controlsController = { ToggleInput = function() end },
    mechanicsController = {
        Jump = function()
            unverifiedJumps += 1
        end,
    },
    getFighter = function()
        return sensorFighter
    end,
    getSettings = function()
        return {}
    end,
    isActive = function()
        return true
    end,
    isTaskActive = function()
        return true
    end,
    isInCombat = function()
        return true
    end,
    isInputCaptured = function()
        return false
    end,
    userInputService = {},
    clock = function()
        return sensorNow
    end,
    spawn = function(fn)
        fn()
    end,
    taskGroundProbe = function(_origin, _direction, _fighter, targetPosition)
        groundProbes += 1
        return {
            clear = true,
            elevation = 0,
            exposed = true,
            projectedDistance = targetPosition.Magnitude,
            supported = true,
        }
    end,
    taskLineOfSightBlocked = function()
        return false
    end,
    taskObstacleProbe = function()
        return false
    end,
    taskParkourProbe = function()
        parkourProbes += 1
        return nil
    end,
})
local sensorTarget = { key = "sensor-target", engagementSeed = 2, position = Vector3.new(40, 0, 0) }
sensorMovement:updateTaskCombat(sensorTarget)
sensorNow = 0.15
sensorMovement:updateTaskCombat(sensorTarget)
sensorNow = 0.9
sensorMovement:updateTaskCombat(sensorTarget)
assert(
    groundProbes == 16 and parkourProbes == 2,
    "terrain observations must be cached instead of running full probe fans every render frame"
)
assert(
    unverifiedJumps == 0,
    "a missing parkour observation must never manufacture a stuck-recovery jump"
)

local movementSource = require("@lune/fs").readFile("games/rivals/libraries/Movement.lua")
local wallNoclipStart = assert(movementSource:find("function Movement:updateWallNoclip", 1, true))
local wallNoclipEnd =
    assert(movementSource:find("function Movement:updateInfiniteJump", wallNoclipStart, true))
local wallNoclipUpdate = movementSource:sub(wallNoclipStart, wallNoclipEnd - 1)
assert(
    wallNoclipUpdate:find("settings.wallNoclip ~= true then", 1, true)
        and not wallNoclipUpdate:find("isTaskInputCaptured", 1, true)
        and not wallNoclipUpdate:find("isInputCaptured", 1, true),
    "Wall Noclip must keep collision off while the menu has captured input"
)
local adapterSource = require("@lune/fs").readFile("games/rivals/Adapter.lua")
assert(
    adapterSource:find("isTaskInputCaptured = function()", 1, true)
        and adapterSource:find("menuVisible ~= true", 1, true),
    "Menu visibility must not count as task input capture for Wall Noclip"
)

print("rivals-task-movement-contracts-ok")
