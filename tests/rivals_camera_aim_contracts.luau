local roblox = require("@lune/roblox")
Vector2 = roblox.Vector2
Vector3 = roblox.Vector3
CFrame = roblox.CFrame

local CameraAim = require("../games/rivals/features/CameraAim")
local Definition = require("../games/rivals/Definition")
local ProjectileAim = require("../games/rivals/libraries/ProjectileAim")
local Targeting = require("../games/rivals/libraries/Targeting")
local WeaponPolicy = require("../games/rivals/libraries/WeaponPolicy")

assert(table.find(Definition.sources, "games/rivals/features/CameraAim"))
assert(table.find(Definition.sources, "games/rivals/Session"))

local humanRadius = CameraAim.humanAimRadius(60)
assert(humanRadius > 200, "Aim Assist must acquire well beyond its old narrow magnetism radius")
local centerStrength = CameraAim.humanAimStrengthScale({ screenDistance = 0 }, 60)
local middleStrength = CameraAim.humanAimStrengthScale({ screenDistance = humanRadius * 0.5 }, 60)
local edgeStrength = CameraAim.humanAimStrengthScale({ screenDistance = humanRadius }, 60)
assert(
    centerStrength == 1 and middleStrength < centerStrength and edgeStrength < middleStrength,
    "Aim Assist strength must fall smoothly with screen distance"
)
assert(edgeStrength >= 0.2, "far Aim Assist must stay helpful without retaining full magnetism")

assert(
    CameraAim.enabled({ silentAim = true, shotAim = false }, false, false) == true,
    "Camera Aim runs when silentAim is on and Silent Aim is off"
)
assert(
    CameraAim.enabled({ silentAim = true, shotAim = true }, false, false) == false,
    "Camera Aim must not rotate the camera while Silent Aim is on"
)
assert(
    CameraAim.enabled({ silentAim = false, shotAim = true }, true, false) == true,
    "The Silent Aim planning pass is shotOnly"
)
assert(
    CameraAim.enabled({ silentAim = false, shotAim = false }, false, true) == true,
    "Task combat may aim without the Camera Aim setting"
)
assert(
    CameraAim.enabled({ silentAim = false, shotAim = true }, false, true) == true,
    "Task combat must visibly aim even when the user has Silent Aim enabled"
)
assert(
    CameraAim.enabled({ silentAim = false, shotAim = false }, false, false) == false,
    "Neither setting nor task combat means no aim plan"
)

assert(
    CameraAim.shouldClearRetention({ silentAim = true, shotAim = true }, false, false, true, true)
        == false,
    "Silent Aim must keep the retained target while Camera Aim is gated off"
)
assert(
    CameraAim.shouldClearRetention({ silentAim = false, shotAim = false }, false, false, true, true)
        == true,
    "Both aim features off must drop retention"
)
assert(
    CameraAim.shouldClearRetention({ silentAim = true, shotAim = false }, false, true, true, true)
        == true,
    "Input capture outside task combat must drop retention"
)

local softRotation = Vector2.zero
local softTarget = Vector2.new(0.5, 1)
for _ = 1, 60 do
    softRotation = Targeting.smoothRotation(softRotation, softTarget, 100, 1 / 60)
end
assert(
    (softTarget - softRotation).Magnitude < math.rad(1),
    "Maximum Camera Aim smoothness must stay soft without taking seconds to become useful"
)

local origin = Vector3.new(0, 2, 0)
local targetPosition = Vector3.new(10, 2, -4)
local target = {
    character = { Name = "dummy" },
    position = targetPosition,
    visible = true,
    health = 80,
    distance = 10,
}
local item = { Info = { ShootDamage = 24 } }
local rotations = {}
local instantRotations = {}
local retentionClears = 0
local remembered = {}

local function context(overrides)
    local ctx = {
        shotOnly = false,
        taskCombatActive = false,
        settings = { silentAim = true, shotAim = false },
        inputCaptured = false,
        fighterActive = true,
        inCombat = true,
        fighter = {
            EquippedItem = item,
            Entity = { RootPart = { Position = origin } },
        },
        camera = {
            CFrame = CFrame.new(origin),
        },
        clock = function()
            return 1
        end,
        renderDelta = 1 / 60,
        gravity = 196.2,
        getNetworkPing = function()
            return 0
        end,
        environmentRaycast = function()
            return function()
                return nil
            end
        end,
        solveBouncingProjectile = function()
            return nil
        end,
        solveSplashAim = function()
            return nil
        end,
        solveRicochet = function()
            return nil
        end,
        setAimRotation = function(rotation, instant)
            table.insert(rotations, rotation)
            table.insert(instantRotations, instant)
            return true
        end,
        selectTarget = function()
            return target
        end,
        selectBackstabTarget = function()
            return nil
        end,
        taskNavigationObservation = function()
            return nil
        end,
        plannedAimTarget = function(selected)
            return selected
        end,
        taskDebug = {},
        clearRetention = function()
            retentionClears += 1
        end,
        rememberWeapon = function(equipped)
            remembered.weapon = equipped
        end,
        rememberTarget = function(selected)
            remembered.target = selected
        end,
        clearTargetKey = function()
            remembered.target = nil
        end,
    }
    for key, value in pairs(overrides or {}) do
        ctx[key] = value
    end
    return ctx
end

local cameraAim = CameraAim.new({
    targeting = Targeting,
    projectileAim = ProjectileAim,
    weaponPolicy = WeaponPolicy,
})
assert(cameraAim:align(context({
    settings = { silentAim = false, shotAim = false },
})) == nil and retentionClears == 1, "A disabled Camera Aim must not invent a plan")

local aligned = cameraAim:align(context())
assert(
    aligned
        and aligned.position == targetPosition
        and aligned.aimSettled == true
        and aligned.visible == true
        and remembered.weapon == item
        and remembered.target == target
        and #rotations == 1
        and rotations[1] == Targeting.rotationToward(origin, targetPosition),
    "Camera Aim must settle on the selected target without picking another"
)

local projectileMaximumError
local projectileTarget = table.clone(target)
projectileTarget.part = { AssemblyLinearVelocity = Vector3.new(0, 0, 12) }
local projectileItem = {
    Name = "Daggers",
    Info = {
        IsProjectile = true,
        ProjectileGravity = 0.25,
        ProjectileLifetime = 5,
        ProjectileMaxHits = 1,
        ProjectileSpeed = 300,
        ShootDamage = 20,
    },
}
local projectileAligned = cameraAim:align(context({
    fighter = {
        EquippedItem = projectileItem,
        Entity = { RootPart = { Position = origin } },
    },
    selectTarget = function()
        return projectileTarget
    end,
    setAimRotation = function(_rotation, _instant, _character, _maximumSmoothness, maximumError)
        projectileMaximumError = maximumError
        return true
    end,
}))
assert(
    projectileAligned
        and projectileAligned.projectileAim
        and projectileMaximumError == math.rad(0.2),
    "Direct projectiles must settle more precisely than hitscan before Trigger Bot fires"
)
local flickSettings = {
    silentAim = true,
    shotAim = false,
    flickProjectiles = true,
}
assert(CameraAim.flickProjectiles(flickSettings, projectileItem) == true)
assert(
    CameraAim.flickProjectiles(flickSettings, {
        Name = "charged-projectile",
        Info = projectileItem.Info,
        _is_charging = false,
    }, true) == false
        and CameraAim.flickProjectiles(flickSettings, {
            Name = "charged-projectile",
            Info = projectileItem.Info,
            _is_charging = true,
        }, true) == true,
    "Bow flicking must be limited to its charged right-click release"
)
local flickRotations = 0
local flickAligned = cameraAim:align(context({
    settings = flickSettings,
    fighter = {
        EquippedItem = projectileItem,
        Entity = { RootPart = { Position = origin } },
    },
    selectTarget = function()
        return projectileTarget
    end,
    setAimRotation = function()
        flickRotations += 1
        return false
    end,
}))
assert(
    flickAligned
        and flickAligned.projectileAim
        and flickAligned.aimSettled == true
        and flickRotations == 0,
    "Flick Projectiles must solve the shot without continuously moving Camera Aim"
)
local clippedProjectile = cameraAim:align(context({
    fighter = {
        EquippedItem = projectileItem,
        Entity = { RootPart = { Position = origin } },
    },
    environmentRaycast = function()
        return function(rayOrigin, ray)
            return { Position = rayOrigin + ray * 0.5 }
        end
    end,
    selectTarget = function()
        return projectileTarget
    end,
}))
assert(
    clippedProjectile and clippedProjectile.projectileAim == nil,
    "Camera Aim must not stage a direct projectile path clipped by native spawn offset cover"
)

local silentRotations = #rotations
local silentAligned = cameraAim:align(context({
    shotOnly = true,
    settings = { silentAim = false, shotAim = true },
}))
assert(
    silentAligned and silentAligned.aimSettled == true and #rotations == silentRotations,
    "The Silent Aim planning pass must not move the camera"
)

local blocked = {
    character = { Name = "blocked" },
    position = Vector3.new(-20, 2, 8),
    visible = false,
}
local rotationsBeforeBlocked = #rotations
local blockedInclude
local blockedAligned = cameraAim:align(context({
    selectTarget = function(_radius, includeBlocked)
        blockedInclude = includeBlocked
        return blocked
    end,
}))
assert(
    blockedAligned == nil
        and blockedInclude == false
        and #rotations == rotationsBeforeBlocked
        and remembered.target == nil,
    "Camera Aim must drop a target without line of sight instead of tracking through a wall"
)
local taskRotationsBeforeBlocked = #rotations
local blockedTaskAligned = cameraAim:align(context({
    taskCombatActive = true,
    settings = { silentAim = false, shotAim = false },
    selectTarget = function()
        return blocked
    end,
}))
assert(
    blockedTaskAligned
        and blockedTaskAligned.navigationOnly == true
        and blockedTaskAligned.aimSettled == false
        and #rotations == taskRotationsBeforeBlocked,
    "Task navigation may retain a blocked opponent for locomotion but must never rotate the camera through a wall"
)

local offScreen = {
    character = { Name = "behind" },
    position = Vector3.new(-20, 2, 8),
    visible = false,
    offscreen = true,
    health = 80,
    distance = 22,
}
local offScreenSelects = {}
local offScreenAligned = cameraAim:align(context({
    selectTarget = function(_radius, includeBlocked, ignoreAimFov, preferVisible)
        table.insert(offScreenSelects, {
            includeBlocked = includeBlocked,
            ignoreAimFov = ignoreAimFov,
            preferVisible = preferVisible,
        })
        return offScreen
    end,
}))
assert(
    offScreenAligned
        and offScreenAligned.position == offScreen.position
        and offScreenAligned.aimSettled == true
        and #offScreenSelects == 1
        and offScreenSelects[1].includeBlocked == false
        and offScreenSelects[1].ignoreAimFov == false
        and offScreenSelects[1].preferVisible == true
        and instantRotations[#instantRotations] == false
        and rotations[#rotations] == Targeting.rotationToward(origin, offScreen.position),
    "360 Camera Aim may turn toward an off-screen target only after a clear world ray"
)
local rotationsBeforeTaskOffscreen = #rotations
local taskOffscreenAligned = cameraAim:align(context({
    taskCombatActive = true,
    settings = { silentAim = false, shotAim = false },
    selectTarget = function()
        return offScreen
    end,
}))
assert(
    taskOffscreenAligned
        and taskOffscreenAligned.navigationOnly == false
        and taskOffscreenAligned.aimSettled == true
        and #rotations == rotationsBeforeTaskOffscreen + 1
        and instantRotations[#instantRotations] == false,
    "Task combat may smoothly acquire an off-screen target only after a clear world ray"
)

local rotationsBeforeObstruction = #rotations
local obstructedAligned = cameraAim:align(context({
    environmentRaycast = function()
        return function()
            return { Instance = { Name = "Wall" } }
        end
    end,
    selectTarget = function()
        return offScreen
    end,
}))
assert(
    obstructedAligned == nil and #rotations == rotationsBeforeObstruction,
    "360 Camera Aim must reject an off-screen target when the world ray hits a wall"
)
local taskObstructedAligned = cameraAim:align(context({
    taskCombatActive = true,
    settings = { silentAim = false, shotAim = false },
    environmentRaycast = function()
        return function()
            return { Instance = { Name = "Wall" } }
        end
    end,
    selectTarget = function()
        return offScreen
    end,
}))
assert(
    taskObstructedAligned
        and taskObstructedAligned.navigationOnly == true
        and taskObstructedAligned.aimSettled == false
        and #rotations == rotationsBeforeObstruction,
    "Task combat must retain an obstructed off-screen target only for navigation"
)

print("rivals-camera-aim-contracts-ok")
