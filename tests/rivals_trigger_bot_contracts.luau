local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
CFrame = roblox.CFrame
Vector3 = roblox.Vector3

local Definition = require("../games/rivals/Definition")
local Session = require("../games/rivals/Session")
local TriggerBot = require("../games/rivals/features/TriggerBot")

assert(table.find(Definition.sources, "games/rivals/features/TriggerBot"))
assert(TriggerBot.INTERVAL == 0)
assert(TriggerBot.delaySeconds({ triggerDelay = 40 }) == 0.04)
assert(TriggerBot.delaySeconds({ triggerDelay = 0 }) == 0)
assert(TriggerBot.delaySeconds({ triggerDelay = 999 }) == 0.25)
local delayState = {}
assert(TriggerBot.delayReady(delayState, 10, 0.04, "a") == false)
assert(TriggerBot.delayReady(delayState, 10.04, 0.04, "a") == true)
local lossState = {}
assert(TriggerBot.delayReady(lossState, 10, 0.2, "a") == false)
TriggerBot.delayLost(lossState, 10.05)
assert(
    TriggerBot.delayReady(lossState, 10.1, 0.2, "a") == false and lossState.armedAt == 10,
    "A brief target loss must retain dwell progress"
)
TriggerBot.delayLost(lossState, 10.2)
assert(
    TriggerBot.delayReady(lossState, 10.4, 0.2, "a") == false and lossState.armedAt == 10.4,
    "A target loss beyond the grace period must restart dwell"
)
assert(
    TriggerBot.delayReady(delayState, 10.05, 0.04, "b") == false,
    "A new target must restart the delay"
)
local changedDelayState = {}
assert(TriggerBot.delayReady(changedDelayState, 20, 0.04, "a") == false)
assert(TriggerBot.delayReady(changedDelayState, 20.04, 0.04, "a") == true)
assert(
    TriggerBot.delayReady(changedDelayState, 20.05, 0.2, "a") == false
        and changedDelayState.armedAt == 20.05,
    "Changing Trigger Delay while locked onto a target must restart the first-shot wait"
)
assert(TriggerBot.weaponReady({ _shoot_cooldown = 2 }, 1) == false)
assert(TriggerBot.weaponReady({ _shoot_cooldown = 1 }, 1) == true)
assert(TriggerBot.fireDelay({ Info = { ShootCooldown = 0.05 } }, 0.1) == 0.05)
assert(TriggerBot.fireDelay({ Info = { InternalUseCooldown = 0.25 } }, 0) == 0.25)
local stuck = { nextAt = 1786837540 }
assert(
    TriggerBot.hubReady(stuck, 20) == true and stuck.nextAt == 0,
    "A tick-valued nextAt must not block hub-clock weapons"
)
assert(TriggerBot.hubReady({ nextAt = 21 }, 20) == false, "A real hub delay must still wait")
local assault = { Info = { ShootCooldown = 0.1 }, _shoot_cooldown = 1 }
assert(
    TriggerBot.holdDropped(assault, 1.05, 0) == false,
    "A working AR hold must not restart while the native cooldown is still producing shots"
)
assault._shoot_cooldown = 1
assert(
    TriggerBot.holdDropped(assault, 1.2, 0) == true,
    "A dropped AR hold may repress only after the native cooldown has stayed expired"
)
assert(
    TriggerBot.holdDropped({ Info = { ShootCooldown = 0.1 } }, 2, 0) == false,
    "Hold recovery must not treat a missing native cooldown as a dropped press"
)
assert(
    TriggerBot.holdDropped({ Info = { InternalUseCooldown = 0.25 }, _shoot_cooldown = 0 }, 2, 0)
        == false,
    "A stream weapon with an unset shoot cooldown must keep holding"
)

local session = Session.new()
session.settings = { shotAim = true, triggerBot = true }
session.aligned = { id = "aligned", visible = true }
session.presented = nil
assert(
    TriggerBot.target(session, session.aligned) == nil,
    "Silent Aim Trigger Bot must not fall back to aligned when presented is missing"
)

session.presented = { id = "presented", visible = true }
assert(TriggerBot.target(session, session.aligned).id == "presented")

session.settings.shotAim = false
assert(TriggerBot.target(session, session.aligned).id == "aligned")

local released = 0
local clicked = 0
local state = {
    fireHeld = false,
    held = false,
    nextAt = 0,
}
local ctx = {
    alignedTarget = session.aligned,
    taskCombatActive = false,
    inputCaptured = false,
    fighterActive = true,
    inCombat = true,
    state = state,
    taskDebug = {},
    weaponPolicy = {
        automationPolicy = function()
            return { triggerBot = true }
        end,
        isDualModeBlade = function()
            return false
        end,
        isSplashProjectile = function()
            return false
        end,
        isBackstabKnife = function()
            return false
        end,
        isScoped = function()
            return false
        end,
        isFanFirearm = function()
            return false
        end,
        isChargedBow = function()
            return false
        end,
        holdToFire = function()
            return false
        end,
        repeatShootingInput = function()
            return false
        end,
        ammo = function()
            return nil
        end,
        triggerDamageReady = function()
            return true
        end,
        sniperTriggerReady = function()
            return true
        end,
        adsSettled = function()
            return true
        end,
    },
    projectileAim = {
        isSplashProjectile = function()
            return false
        end,
    },
    targeting = {},
    taskCounterPolicy = {
        shouldForceSpray = function()
            return false
        end,
    },
    clock = function()
        return 1
    end,
    itemClock = function()
        return 1
    end,
    getFighter = function()
        return { EquippedItem = { Info = { ShootCooldown = 0.1 } } }
    end,
    selectTarget = function()
        error("Silent Aim must not reselect")
    end,
    selectCrosshairTarget = function()
        return nil
    end,
    isDeflecting = function()
        return false
    end,
    isGunGame = function()
        return false
    end,
    localFighterIsCrouching = function()
        return false
    end,
    fighterFor = function()
        return nil
    end,
    targetRootPosition = function()
        return nil
    end,
    releaseFire = function()
        released += 1
    end,
    clearAimPlan = function() end,
    camera = {
        CFrame = CFrame.new(0, 0, 0),
    },
    cameraController = {},
    click = function()
        clicked += 1
    end,
    aimClick = function() end,
    aimPress = function() end,
    aimRelease = function() end,
    press = function() end,
}

session.settings.shotAim = true
session.presented = nil
TriggerBot.update(session, ctx)
assert(clicked == 0 and released >= 1, "Missing presented target must not fire")

local wall = { Name = "Wall" }
local blocked = {
    visible = true,
    position = { X = 0, Y = 0, Z = 10 },
    character = {},
}
assert(TriggerBot.pathReady(blocked, { Info = { ShootCooldown = 0.1 } }, {
    weaponPolicy = ctx.weaponPolicy,
    projectileAim = ctx.projectileAim,
    targeting = {
        visibleHeadPoint = function()
            return nil
        end,
        visibleBodyPoint = function()
            return nil
        end,
    },
    camera = {
        CFrame = CFrame.new(0, 0, 0),
    },
    raycast = function()
        return { Instance = wall }
    end,
}) == false, "On-screen hitscan must not fire when the bullet path is blocked")

local offScreen = {
    visible = false,
    projectileAim = { direction = true },
}
assert(TriggerBot.pathReady(offScreen, { Info = { IsProjectile = true, ProjectileSpeed = 120 } }, {
    weaponPolicy = ctx.weaponPolicy,
    projectileAim = {
        isSplashProjectile = function()
            return false
        end,
        isDirectProjectile = function()
            return true
        end,
    },
}) == true, "A solved projectile path must fire even when the target is off screen")

local onScreenArc = {
    visible = true,
    position = { X = 0, Y = 0, Z = 20 },
}
assert(
    TriggerBot.pathReady(onScreenArc, { Info = { IsProjectile = true, ProjectileSpeed = 120 } }, {
        weaponPolicy = ctx.weaponPolicy,
        projectileAim = {
            isSplashProjectile = function()
                return false
            end,
            isDirectProjectile = function()
                return true
            end,
            solveProjectileAim = function()
                return { direction = Vector3.new(0, 0, -1) }
            end,
        },
        camera = ctx.camera,
    }) == false,
    "An on-screen projectile must not fire without a solved bullet path"
)

local adapter = fs.readFile("games/rivals/Adapter.lua")
assert(adapter:find("raycast = type(environmentRaycast)", 1, true))
local source = fs.readFile("games/rivals/features/TriggerBot.lua")
assert(source:find("TriggerBot.pathReady", 1, true))
assert(source:find("TriggerBot.shouldHoldForDeflect", 1, true))
assert(source:find("TriggerBot.weaponReady", 1, true))
assert(source:find("TriggerBot.holdDropped", 1, true))
assert(source:find("TriggerBot.hubReady", 1, true))
assert(
    not source:find("state.nextAt = type(nativeReadyAt)", 1, true),
    "Click fire must not copy tick() _shoot_cooldown onto the os.clock nextAt gate"
)
assert(source:find("ctx.selectCrosshairTarget()", 1, true))
assert(not source:find("not target.visible", 1, true))
assert(
    not source:find("0.35", 1, true),
    "Hold-to-fire must not restart after an ammo-replica stall"
)
assert(
    source:find("local ammo = WeaponPolicy.ammo(item)", 1, true)
        and source:find("ammo == 0", 1, true),
    "Trigger Bot must release an empty weapon so native reload can start"
)
session.settings.shotAim = false
session.aligned = nil
ctx.alignedTarget = nil
local crosshairQueries = 0
ctx.selectCrosshairTarget = function()
    crosshairQueries += 1
    return nil
end
TriggerBot.update(session, ctx)
assert(crosshairQueries == 1, "No-aim Trigger Bot must query the native crosshair hit")

session.settings.shotAim = false
session.aligned = { visible = true, position = Vector3.new(0, 0, 10), aimSettled = true }
ctx.alignedTarget = session.aligned
ctx.targeting.visibleHeadPoint = function()
    return Vector3.new(0, 0, 10)
end
ctx.raycast = function()
    return nil
end
clicked = 0
state.nextAt = 0

local retainedCharacter = {}
session.settings.humanAim = true
session.settings.aimSmoothness = 80
session.aligned = {
    aimSettled = false,
    character = retainedCharacter,
    position = Vector3.new(0, 0, 10),
    visible = true,
}
ctx.alignedTarget = session.aligned
ctx.selectCrosshairTarget = function()
    return {
        character = retainedCharacter,
        position = Vector3.new(0, 0, 10),
        visible = true,
    }
end
TriggerBot.update(session, ctx)
assert(
    clicked == 0 and ctx.taskDebug.triggerStage == "aim-settling",
    "Trigger Bot must wait for the configured head plan instead of firing on the target body"
)

session.aligned.aimSettled = false
ctx.selectCrosshairTarget = function()
    return {
        character = {},
        position = Vector3.new(0, 0, 10),
        visible = true,
    }
end
TriggerBot.update(session, ctx)
assert(
    clicked == 0 and ctx.taskDebug.triggerStage == "aim-settling",
    "Smoothed Camera Aim must not fire until its retained target rotation settles"
)

session.aligned.projectileAim = { direction = Vector3.new(0, 0, -1) }
ctx.selectCrosshairTarget = function()
    return {
        character = retainedCharacter,
        position = Vector3.new(0, 0, 10),
        visible = true,
    }
end
TriggerBot.update(session, ctx)
assert(
    clicked == 0 and ctx.taskDebug.triggerStage == "aim-settling",
    "A smoothed projectile solution must wait for its solved lead rotation to settle"
)

local chargedBow = { Info = { ShootCooldown = 0.25 } }
local aimReleases = 0
ctx.getFighter = function()
    return { EquippedItem = chargedBow }
end
ctx.weaponPolicy.isChargedBow = function(candidate)
    return candidate == chargedBow
end
ctx.aimRelease = function()
    aimReleases += 1
end
state.held = true
state.heldItem = chargedBow
session.aligned.aimSettled = false
ctx.alignedTarget = session.aligned
TriggerBot.update(session, ctx)
assert(
    state.held == true
        and aimReleases == 0
        and ctx.taskDebug.triggerStage == "aim-settling",
    "A charging Bow must hold through projectile re-alignment instead of releasing a miss"
)
local disownedAims = 0
local manualAimPresses = 0
ctx.isAimInputHeld = function()
    return true
end
ctx.disownAim = function()
    disownedAims += 1
end
ctx.aimPress = function()
    manualAimPresses += 1
end
session.aligned.aimSettled = true
state.nextAt = 0
TriggerBot.update(session, ctx)
assert(
    state.held == false
        and state.heldItem == nil
        and disownedAims == 1
        and manualAimPresses == 0
        and aimReleases == 0
        and ctx.taskDebug.triggerStage == "manual-aim",
    "Trigger Bot must transfer Bow aim ownership without releasing held right-click input"
)
ctx.isAimInputHeld = nil
ctx.disownAim = nil
state.held = false
state.heldItem = nil
ctx.getFighter = function()
    return { EquippedItem = { Info = { ShootCooldown = 0.1 } } }
end
ctx.weaponPolicy.isChargedBow = function()
    return false
end
ctx.aimRelease = function() end

session.settings.humanAim = false
session.aligned = { visible = true, position = Vector3.new(0, 0, 10), aimSettled = true }
ctx.alignedTarget = session.aligned
ctx.selectCrosshairTarget = function()
    return nil
end
state.nextAt = 0
session.settings.triggerDelay = 40
clicked = 0
state.nextAt = 0
state.armedAt = nil
state.armedKey = nil
ctx.clock = function()
    return 1
end
TriggerBot.update(session, ctx)
assert(
    clicked == 0 and ctx.taskDebug.triggerStage == "delay",
    "A delayed trigger must wait before the first shot"
)
ctx.clock = function()
    return 1.04
end
TriggerBot.update(session, ctx)
assert(clicked == 1, "A delayed trigger must fire once the wait elapses")
session.settings.triggerDelay = 0
state.armedAt = nil
state.armedKey = nil
clicked = 0
state.nextAt = 0
ctx.clock = function()
    return 1
end
TriggerBot.update(session, ctx)
assert(clicked == 1, "A ready semi must fire on the first ready frame")
TriggerBot.update(session, ctx)
assert(clicked == 2, "A ready semi must not wait on a 0.1s hub interval")

local pistol = { Info = { ShootCooldown = 0.28 }, _shoot_cooldown = 1786837540 }
local pistolNow = 20
ctx.weaponPolicy.holdToFire = function()
    return false
end
ctx.getFighter = function()
    return { EquippedItem = pistol }
end
ctx.clock = function()
    return pistolNow
end
ctx.itemClock = function()
    return 1786837539
end
clicked = 0
state.nextAt = 0
TriggerBot.update(session, ctx)
assert(clicked == 0, "A cooling semi must wait on the item tick clock")
ctx.itemClock = function()
    return 1786837540
end
TriggerBot.update(session, ctx)
assert(clicked == 1, "A ready semi must fire once the item tick clock is ready")
assert(
    state.nextAt == 0 or state.nextAt <= pistolNow,
    "A click must not store tick() _shoot_cooldown on the os.clock nextAt gate"
)
pistol._shoot_cooldown = 1786837540.28
TriggerBot.update(session, ctx)
assert(clicked == 1, "A just-fired semi must wait for the native tick cooldown")
ctx.itemClock = function()
    return 1786837540.28
end
TriggerBot.update(session, ctx)
assert(clicked == 2, "The next semi shot must not be blocked by a tick-valued nextAt")

local now = 10
local presses = 0
local fireReleases = 0
local rifle = { Info = { ShootCooldown = 0.1 }, _shoot_cooldown = now + 0.1 }
ctx.weaponPolicy.holdToFire = function()
    return true
end
ctx.weaponPolicy.repeatShootingInput = function()
    return true
end
ctx.weaponPolicy.ammo = function()
    return 20
end
ctx.getFighter = function()
    return { EquippedItem = rifle }
end
ctx.clock = function()
    return now
end
ctx.itemClock = function()
    return now
end
ctx.press = function()
    presses += 1
    state.fireHeld = true
end
ctx.releaseFire = function()
    if state.fireHeld then
        fireReleases += 1
        state.fireHeld = false
    end
end
state.fireHeld = false
state.fireItem = nil
state.nextAt = 0
TriggerBot.update(session, ctx)
assert(presses == 1 and fireReleases == 0, "An AR must begin its native hold")
now = 10.01
TriggerBot.update(session, ctx)
now = 10.02
TriggerBot.update(session, ctx)
assert(
    presses == 3 and fireReleases == 0,
    "An AR hold must repeat StartShooting without release gaps so native cooldown controls cadence"
)

ctx.alignedTarget = nil
state.fireLostAt = nil
now = 10.47
TriggerBot.update(session, ctx)
assert(
    fireReleases == 0,
    "An AR must keep its native hold through a one-frame presented-target gap"
)
now = 10.58
TriggerBot.update(session, ctx)
assert(fireReleases == 1, "An AR must release after the target grace period expires")
ctx.alignedTarget = session.aligned
local emptyReleases = fireReleases
state.fireHeld = true
state.fireItem = rifle
ctx.weaponPolicy.ammo = function()
    return 0
end
TriggerBot.update(session, ctx)
assert(
    fireReleases == emptyReleases + 1 and ctx.taskDebug.triggerStage == "empty",
    "Trigger Bot must release an empty weapon so reload can start"
)
ctx.weaponPolicy.ammo = function()
    return 20
end

assert(TriggerBot.shouldHoldForDeflect({ player = {} }, rifle, {
    isDeflecting = function()
        return true
    end,
    taskCounterPolicy = {
        shouldForceSpray = function()
            return false
        end,
    },
}) == true)
assert(TriggerBot.shouldHoldForDeflect({ player = {} }, rifle, {
    isDeflecting = function()
        return true
    end,
    fighterFor = function()
        return { EquippedItem = {} }
    end,
    taskCounterPolicy = {
        shouldForceSpray = function()
            return true
        end,
    },
}) == false, "True-damage spray may still fire through a deflector")

ctx.isDeflecting = function()
    return true
end
ctx.fighterFor = function()
    return { EquippedItem = { Info = { DeflectDuration = 1, DeflectCooldown = 4 } } }
end
ctx.raycast = function()
    return { Instance = wall }
end
ctx.targeting.visibleHeadPoint = function()
    return Vector3.new(0, 0, 10)
end
session.aligned =
    { visible = true, player = {}, position = Vector3.new(0, 0, 10), aimSettled = true }
ctx.alignedTarget = session.aligned
state.fireHeld = true
state.nextAt = 0
local deflectReleases = fireReleases
local deflectPresses = presses
TriggerBot.update(session, ctx)
assert(
    fireReleases == deflectReleases + 1 and presses == deflectPresses,
    "A hold must release when the target is deflecting even if the blade blocks line of sight"
)
assert(ctx.taskDebug.triggerStage == "target-deflecting")

print("rivals-trigger-bot-contracts-ok")
