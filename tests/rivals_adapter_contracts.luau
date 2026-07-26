local roblox = require("@lune/roblox")
CFrame = roblox.CFrame
Color3 = roblox.Color3
Enum = roblox.Enum
Vector2 = roblox.Vector2
Vector3 = roblox.Vector3

local Rivals = require("../games/rivals/Adapter")
local RivalsTargeting = require("../games/rivals/Targeting")
local RivalsProjectileAim = require("../games/rivals/ProjectileAim")
local RivalsShotPresentation = require("../games/rivals/ShotPresentation")
local RivalsWeaponPolicy = require("../games/rivals/WeaponPolicy")
local RivalsEffects = require("../games/rivals/Effects")
local RivalsMovement = require("../games/rivals/Movement")
local RivalsCombatState = require("../games/rivals/CombatState")

assert(Rivals.match({ gameId = 6035872082, placeId = 0 }) == 100)
assert(Rivals.match({ gameId = 0, placeId = 17625359962 }) == 200)
assert(Rivals.match({ gameId = 0, placeId = 0 }) == 0)
assert(Rivals.cosmetics == false)
assert(
    table.find(Rivals.capabilities, "silentAim")
        and table.find(Rivals.capabilities, "shotAim")
        and table.find(Rivals.capabilities, "triggerBot")
        and table.find(Rivals.capabilities, "humanAim")
        and table.find(Rivals.capabilities, "aimSmoothness")
        and table.find(Rivals.capabilities, "headshotRate")
        and table.find(Rivals.capabilities, "missRate")
)
assert(not table.find(Rivals.capabilities, "wallbang"), "RIVALS must not advertise unverified hit forgery")

local readinessCamera = {}
local readinessDuel = {}
local readinessFighter = {}
local readinessMechanics = {}
assert(
    Rivals.controllersReady(readinessCamera, readinessFighter, {}) == false,
    "RIVALS must not require game controllers before the game has loaded either module"
)
assert(
    Rivals.controllersReady(readinessCamera, readinessFighter, { readinessCamera }) == false,
    "RIVALS must wait for both controller modules instead of racing partial game startup"
)
assert(
    Rivals.controllersReady(
        readinessCamera,
        readinessFighter,
        { readinessCamera, readinessDuel, readinessFighter, readinessMechanics },
        readinessMechanics,
        readinessDuel
    ) == true,
    "RIVALS may require controllers only after the game's own bootstrap loaded all required modules"
)

local function player(teamId, environmentId)
    return {
        GetAttribute = function(_self, name)
            if name == "TeamID" then
                return teamId
            end
            return name == "EnvironmentID" and environmentId or nil
        end,
    }
end

local function character(health, protected)
    return {
        FindFirstChildOfClass = function(_self, className)
            if className == "Humanoid" then
                return {
                    Health = health,
                    MaxHealth = 150,
                }
            end
            if className == "ForceField" and protected then
                return {}
            end
            return nil
        end,
    }
end

local localPlayer = player("Blue", "MatchA")
local enemyPlayer = player("Red", "MatchA")
local teammate = player("Blue", "MatchA")
assert(Rivals.isOpponent(localPlayer, enemyPlayer, character(150)) == true)
assert(Rivals.isOpponent(localPlayer, teammate, character(150)) == false)
assert(Rivals.isOpponent(localPlayer, enemyPlayer, character(0)) == false)
assert(Rivals.isOpponent(localPlayer, localPlayer, character(150)) == false)
local protectedFfaCharacter = character(150, true)
assert(
    Rivals.isOpponent(player(nil), player(nil), protectedFfaCharacter) == true,
    "FFA ESP must continue showing a spawn-protected opponent"
)
assert(
    Rivals.isTargetable(player(nil), player(nil), protectedFfaCharacter) == false,
    "Camera Aim, Human Aim, Trigger Bot, and backstab targeting must exclude spawn-protected players"
)
assert(
    Rivals.isOpponent(localPlayer, player("Red", "MatchB"), character(150)) == false,
    "RIVALS ESP and aim must exclude players assigned to another EnvironmentID"
)
assert(
    Rivals.isOpponent(player(nil, nil), player(nil, "MatchB"), character(150)) == false,
    "RIVALS lobby observations must exclude players already assigned to a match"
)
assert(
    Rivals.isOpponent(player(nil), player(nil), character(150)) == true,
    "FFA players without TeamID must remain eligible"
)

local closestCandidate = {
    position = Vector3.new(4, 0, 0),
    screenDistance = 80,
    visible = true,
}
local cursorCandidate = {
    position = Vector3.new(20, 0, 0),
    screenDistance = 5,
    visible = true,
}
assert(
    RivalsTargeting.closestObservation(
        { cursorCandidate, closestCandidate },
        Vector3.zero,
        { maxScreenDistance = 180 }
    ) == closestCandidate,
    "Human Aim must prioritize physical distance over cursor distance"
)
assert(
    RivalsTargeting.closestObservation(
        { cursorCandidate, closestCandidate },
        Vector3.zero,
        { maxScreenDistance = 40 }
    ) == cursorCandidate,
    "Human Aim must still respect the configured camera FOV"
)
assert(
    RivalsTargeting.closestObservation(
        {
            {
                position = Vector3.new(24, 0, 0),
                screenDistance = 5000,
                visible = true,
            },
            {
                position = Vector3.new(10, 0, 0),
                screenDistance = 9000,
                visible = true,
            },
        },
        Vector3.zero,
        { maxDistance = 26.75 }
    ).position == Vector3.new(10, 0, 0),
    "Gunblade target acquisition must choose closest world distance without a viewport FOV gate"
)
local protectedClosestCandidate = {
    character = protectedFfaCharacter,
    player = enemyPlayer,
    position = Vector3.new(1, 0, 0),
    screenDistance = 4,
    visible = true,
}
cursorCandidate.character = character(150)
cursorCandidate.player = enemyPlayer
assert(
    RivalsTargeting.closestObservation(
        { cursorCandidate, protectedClosestCandidate },
        Vector3.zero,
        {
            isEligible = function(candidatePlayer, candidateCharacter)
                return Rivals.isTargetable(localPlayer, candidatePlayer, candidateCharacter)
            end,
            maxScreenDistance = 180,
        }
    ) == cursorCandidate,
    "Human Aim must skip a physically closer opponent while their spawn protection is active"
)

local aimRoot = {
    CFrame = CFrame.new(Vector3.zero),
    Position = Vector3.zero,
    Size = Vector3.new(2, 2, 1),
}
local aimHead = {
    CFrame = CFrame.new(Vector3.new(0, 2, 0)),
    Name = "Head",
    Position = Vector3.new(0, 2, 0),
    Size = Vector3.new(1.2, 1.2, 1.2),
}
local aimCharacter = {
    FindFirstChild = function(_self, name)
        return ({ Head = aimHead, HumanoidRootPart = aimRoot })[name]
    end,
}
local baseAimObservation = {
    character = aimCharacter,
    part = aimRoot,
    position = aimRoot.Position,
}
local headAim = RivalsTargeting.applyAimRates(baseAimObservation, {
    headshotRate = 100,
    missRate = 0,
}, function()
    return 0
end)
assert(
    headAim.position == aimHead.Position and headAim.part == aimHead and not headAim.intentionalMiss,
    "A 100% headshot rate must aim at the live Head part"
)
do
local lowCameraOrigin = Vector3.new(0, -2, 8)
local bodyOccluder = {
    GetAttribute = function()
        return nil
    end,
    IsDescendantOf = function(_self, value)
        return value == aimCharacter
    end,
    Name = "UpperTorso",
}
local criticalHeadHitbox = {
    GetAttribute = function(_self, name)
        return name == "IsCritical" and true or nil
    end,
    IsDescendantOf = function(_self, value)
        return value == aimCharacter
    end,
    Name = "HitboxHead",
}
local crownPoint = aimHead.CFrame:PointToWorldSpace(
    Vector3.new(0, aimHead.Size.Y * 0.45, 0)
)
local crownAim = RivalsTargeting.applyAimRates(baseAimObservation, {
    headshotRate = 100,
    missRate = 0,
}, function()
    return 0
end, {
    origin = lowCameraOrigin,
    raycast = function(raycastOrigin, displacement)
        local point = raycastOrigin + displacement
        return {
            Instance = point == aimHead.Position and bodyOccluder or criticalHeadHitbox,
        }
    end,
})
assert(
    crownAim.position == crownPoint and crownAim.part == aimHead,
    "Head aim must choose the highest exposed crown point when the center is body-occluded"
)
local centerAim = RivalsTargeting.applyAimRates(baseAimObservation, {
    headshotRate = 100,
    missRate = 0,
}, function()
    return 0
end, {
    origin = lowCameraOrigin,
    raycast = function()
        return { Instance = criticalHeadHitbox }
    end,
})
assert(
    centerAim.position == aimHead.Position and centerAim.part == aimHead,
    "Head aim must preserve the normal center point when critical geometry is visible"
)
local blockedHeadAim = RivalsTargeting.applyAimRates({
    character = aimCharacter,
    part = aimHead,
    position = aimHead.Position,
}, {
    headshotRate = 100,
    missRate = 0,
}, function()
    return 0
end, {
    origin = lowCameraOrigin,
    raycast = function()
        return { Instance = bodyOccluder }
    end,
})
assert(
    blockedHeadAim.position == aimRoot.Position and blockedHeadAim.part == aimRoot,
    "Head aim must fall back to a visible body point when no bounded head candidate is exposed"
)
local obscuredBodyPosition, obscuredBodyPart = RivalsTargeting.visibleBodyPoint({
    character = aimCharacter,
    part = aimHead,
    position = aimHead.Position,
}, lowCameraOrigin, function()
    return { Instance = criticalHeadHitbox }
end)
assert(
    obscuredBodyPosition == nil and obscuredBodyPart == nil,
    "Body aim must not treat a first-hit Head or critical hitbox as a visible body candidate"
)
end
local missedAim = RivalsTargeting.applyAimRates(baseAimObservation, {
    headshotRate = 100,
    missRate = 100,
}, function()
    return 0
end)
assert(
    missedAim.intentionalMiss == true
        and missedAim.position == Vector3.new(3.5, 0, 0)
        and missedAim.part == aimRoot,
    "Miss rate must take priority and produce a stable point outside the target body"
)
assert(
    RivalsTargeting.applyAimRates({
        character = aimCharacter,
        part = aimHead,
        position = aimHead.Position,
    }, {
        headshotRate = 0,
        missRate = 0,
    }, function()
        error("Zero rates must not consume random samples")
    end, {
        origin = Vector3.new(0, 0, 8),
        raycast = function()
            return { Instance = aimRoot }
        end,
    }).part == aimRoot,
    "A 0% headshot rate must not inherit Hydroxide's raw Head observation when a visible body candidate exists"
)
assert(
    RivalsTargeting.applyAimRates({
        character = aimCharacter,
        part = aimHead,
        position = aimHead.Position,
    }, {
        headshotRate = 50,
        missRate = 0,
    }, function()
        return 0.49
    end).part == aimHead,
    "A 50% headshot rate must choose Head below its deterministic probability threshold"
)
assert(
    RivalsTargeting.applyAimRates({
        character = aimCharacter,
        part = aimHead,
        position = aimHead.Position,
    }, {
        headshotRate = 50,
        missRate = 0,
    }, function()
        return 0.5
    end, {
        origin = Vector3.new(0, 0, 8),
        raycast = function()
            return { Instance = aimRoot }
        end,
    }).part == aimRoot,
    "A 50% headshot rate must choose a visible body candidate at or above its deterministic probability threshold"
)

assert(RivalsWeaponPolicy.itemName({ Info = { DisplayName = "Energy Rifle" }, Name = "Internal" }) == "Energy Rifle")
assert(RivalsWeaponPolicy.itemName({ Info = { Name = "Handgun" } }) == "Handgun")
assert(RivalsWeaponPolicy.itemName(nil) == nil)
for _, utilityName in ipairs({
    "Medkit",
    "Subspace Tripmine",
    "Warpstone",
    "Jump Pad",
    "War Horn",
    "Grappler",
    "Flashbang",
    "Grenade",
    "Molotov",
    "Satchel",
    "Smoke Grenade",
}) do
    local policy = RivalsWeaponPolicy.automationPolicy({
        Info = { DisplayName = utilityName },
    })
    assert(
        policy.cameraAim == false and policy.silentAim == false and policy.triggerBot == false,
        ("%s must opt out of Camera Aim, Silent Aim, and Trigger Bot"):format(utilityName)
    )
end
assert(
    RivalsWeaponPolicy.automationPolicy({
        Info = { DisplayName = "Burst Rifle" },
    }).cameraAim == true,
    "Ordinary weapons must preserve existing automation behavior"
)
do
local riotShield = {
    Info = {
        DisplayName = "Riot Shield",
        MaxAbsorption = 100,
    },
    Get = function(_self, field)
        assert(field == "Ammo", "Shield labels must read the live replicated Ammo field")
        return 52.75
    end,
}
assert(
    RivalsWeaponPolicy.itemLabel(riotShield) == "Riot Shield (52/100)",
    "Riot Shield weapon text must truncate fractional Ammo in its current/max durability label"
)
assert(
    RivalsWeaponPolicy.itemLabel({
        Info = {
            DisplayName = "Riot Shield",
            MaxAbsorption = 100,
        },
    }) == "Riot Shield",
    "Riot Shield weapon text must stay unchanged when current durability is unavailable"
)
assert(
    RivalsWeaponPolicy.itemLabel({
        Info = { DisplayName = "Burst Rifle" },
        Data = { Ammo = 18 },
    }) == "Burst Rifle",
    "Ordinary weapon labels must not gain an ammo suffix"
)
end

local scopedItem = {
    Data = { IsAiming = true },
    Info = { AimScopePercent = 0.5 },
}
local scopeCamera = {
    _fov_weapons_spring = {
        Value = 0,
        Target = -50,
    },
}
assert(RivalsWeaponPolicy.adsSettled(scopeCamera, scopedItem) == false)
scopeCamera._fov_weapons_spring.Value = -49.75
assert(RivalsWeaponPolicy.adsSettled(scopeCamera, scopedItem) == true)
scopedItem.Data.IsAiming = false
assert(RivalsWeaponPolicy.adsSettled(scopeCamera, scopedItem) == true)

do
local sniper = {
    Info = {
        AimScopePercent = 0.5,
        DisplayName = "Sniper",
        ShootSpread = 15,
    },
    Data = {
        IsAiming = false,
    },
}
local sniperTarget = {
    part = {
        Name = "Torso",
        Size = Vector3.new(2, 2, 1),
    },
}
assert(
    RivalsWeaponPolicy.sniperTriggerReady(scopeCamera, sniper, sniperTarget, 30, false) == false,
    "Sniper Trigger Bot must wait for a far unscoped target outside the 50% radial hit cutoff"
)
assert(
    RivalsWeaponPolicy.sniperTriggerReady(scopeCamera, sniper, sniperTarget, 6, false) == true,
    "Sniper Trigger Bot must allow a close unscoped target inside the 50% radial hit cutoff"
)
assert(
    RivalsWeaponPolicy.sniperTriggerReady(scopeCamera, sniper, sniperTarget, 9, false) == false,
    "Sniper Trigger Bot must keep the standing no-scope cone conservative"
)
assert(
    RivalsWeaponPolicy.sniperTriggerReady(scopeCamera, sniper, sniperTarget, 9, true) == true,
    "Sniper Trigger Bot must use the native crouching spread reduction"
)
sniper.Data.IsAiming = true
sniper.fullyAiming = false
sniper.IsFullyAiming = function(self)
    return self.fullyAiming
end
scopeCamera._fov_weapons_spring.Value = -49.75
assert(
    RivalsWeaponPolicy.sniperTriggerReady(scopeCamera, sniper, sniperTarget, 30, false) == false,
    "Sniper Trigger Bot must wait until the native item reports full ADS"
)
sniper.fullyAiming = true
assert(
    RivalsWeaponPolicy.sniperTriggerReady(scopeCamera, sniper, sniperTarget, 30, false) == true,
    "Sniper Trigger Bot must allow a spread-free shot after native ADS settles"
)
assert(
    RivalsWeaponPolicy.sniperTriggerReady(
        scopeCamera,
        { Data = { IsAiming = false }, Info = { DisplayName = "Sniper", ShootSpread = 15 } },
        { part = {} },
        6,
        false
    ) == false,
    "Sniper Trigger Bot must fail closed when the selected hit area cannot be measured"
)
end

assert(
    RivalsWeaponPolicy.holdToFire({
        Info = {
            InputSpammingEnabled = { StartShooting = 0 },
            InternalUseCooldown = 0.25,
        },
    }) == true,
    "Flamethrower-style continuous weapons must hold primary fire"
)
assert(
    RivalsWeaponPolicy.holdToFire({
        Info = {
            InputSpammingEnabled = { StartShooting = 0 },
            ShootCooldown = 0.07,
        },
    }) == true,
    "Fast automatic weapons must hold primary fire"
)
assert(
    RivalsWeaponPolicy.holdToFire({
        Info = {
            InputSpammingEnabled = { StartShooting = false },
            ShootCooldown = 0.125,
        },
    }) == false,
    "Tap-fire weapons must not be inferred as automatic from cooldown alone"
)
assert(
    RivalsWeaponPolicy.holdToFire({
        Info = {
            InputSpammingEnabled = { StartShooting = 0 },
            IsProjectile = true,
            ShootCooldown = 0.1,
        },
    }) == false,
    "Trajectory weapons must keep deliberate per-shot trigger timing"
)

local bow = {
    Info = {
        ChargeLevelDamageMultipliers = { 1, 1.25, 1.5, 2 },
        ChargeLevelTimestamps = { 0, 0.3, 1, 1.8 },
        ChargeReleaseCooldown = 1,
        CriticalDamage = 60,
        ShootDamage = 30,
        ShootCooldown = 0.25,
    },
}
assert(RivalsWeaponPolicy.bowChargeTime(bow, { health = 40, part = { Name = "Torso" } }) == 1)
assert(RivalsWeaponPolicy.bowChargeTime(bow, { health = 70, part = { Name = "Head" } }) == 0.3)
assert(RivalsWeaponPolicy.bowChargeTime(bow, { health = 200, part = { Name = "Torso" } }) == 1.8)
assert(RivalsWeaponPolicy.bowQuickShotLethal(bow, { health = 30, part = { Name = "Torso" } }) == true)
assert(RivalsWeaponPolicy.bowQuickShotLethal(bow, { health = 60, part = { Name = "Head" } }) == true)
assert(RivalsWeaponPolicy.bowQuickShotLethal(bow, { health = 31, part = { Name = "Torso" } }) == false)
local similarCooldownBow = {
    Info = table.clone(bow.Info),
}
similarCooldownBow.Info.ChargeReleaseCooldown = 0.3
assert(
    RivalsWeaponPolicy.bowQuickShotLethal(similarCooldownBow, { health = 30, part = { Name = "Torso" } }) == false,
    "Bow should keep secondary fire when its uncharged release is similarly fast"
)
local revolver
do
revolver = {
    Data = {
        Ammo = 6,
    },
    Info = {
        CriticalDamage = 40,
        MaxAmmo = 6,
        QuickShotCooldown = 0.15,
        QuickShotSpread = 10,
        DamageFallOffEndDist = 200,
        DamageFallOffMultiplier = 0.25,
        DamageFallOffStartDist = 75,
        ShootCooldown = 0.4,
        ShootDamage = 30,
        ShootSpread = 0.5,
    },
    Name = "Revolver",
    _reload_cancel_cooldown = 0,
    _reload_cancel_expiration = 0,
    _reload_cooldown = 0,
    _shoot_cooldown = 0,
    IsEquipping = false,
}
local closeRevolverTarget = {
    health = 100,
    part = {
        Name = "Torso",
        Size = Vector3.new(2, 2, 1),
    },
}
local closeRevolverAction =
    RivalsWeaponPolicy.revolverTriggerAction(revolver, closeRevolverTarget, 4, 10)
assert(
    closeRevolverAction
        and closeRevolverAction.kind == "fan"
        and closeRevolverAction.cooldown == 0.15,
    "Revolver Trigger Bot must fan only when the target survives one shot and fits inside the quick-shot spread"
)
local lethalRevolverAction = RivalsWeaponPolicy.revolverTriggerAction(revolver, {
    health = 30,
    part = closeRevolverTarget.part,
}, 4, 10)
assert(
    lethalRevolverAction
        and lethalRevolverAction.kind == "precise"
        and lethalRevolverAction.cooldown == 0.4,
    "Revolver Trigger Bot must prefer one precise shot when it is already lethal"
)
local rangedRevolverAction =
    RivalsWeaponPolicy.revolverTriggerAction(revolver, closeRevolverTarget, 30, 10)
assert(
    rangedRevolverAction and rangedRevolverAction.kind == "precise",
    "Revolver Trigger Bot must use the smaller normal-shot cone when the full fan cone is unsafe"
)
local narrowRevolverTarget = {
    health = 100,
    part = {
        Name = "Torso",
        Size = Vector3.new(0.5, 0.5, 1),
    },
}
assert(
    RivalsWeaponPolicy.revolverTriggerAction(revolver, narrowRevolverTarget, 30, 10) == nil,
    "Revolver Trigger Bot must decline a shot when the selected hit area cannot contain the full precise cone"
)
revolver.IsEquipping = true
assert(
    RivalsWeaponPolicy.revolverTriggerAction(revolver, closeRevolverTarget, 4, 10) == nil,
    "Revolver Trigger Bot must honor the live boolean IsEquipping gate"
)
revolver.IsEquipping = false
local farRevolverTarget = {
    health = 10,
    part = closeRevolverTarget.part,
}
assert(
    math.abs(RivalsWeaponPolicy.damageAtDistance(revolver, farRevolverTarget, 200) - 7.5) < 1e-6,
    "Revolver damage must honor the live DamageFallOff fields"
)
assert(
    RivalsWeaponPolicy.triggerDamageReady(revolver, farRevolverTarget, 200) == false,
    "Revolver Trigger Bot must recognize severe falloff from the live DamageFallOff fields"
)
revolver._shoot_cooldown = 11
assert(
    RivalsWeaponPolicy.revolverTriggerAction(revolver, closeRevolverTarget, 4, 10) == nil,
    "Revolver Trigger Bot must wait for the live gun cooldown"
)
revolver._shoot_cooldown = 0
revolver._reload_cooldown = 11
revolver._reload_cancel_cooldown = 11
revolver._reload_cancel_expiration = 0
assert(
    RivalsWeaponPolicy.revolverTriggerAction(revolver, closeRevolverTarget, 4, 10) == nil,
    "Revolver Trigger Bot must not shoot through a non-cancellable reload"
)
revolver._reload_cooldown = 0
revolver._reload_cancel_cooldown = 0
revolver.Data.Ammo = 0
assert(
    RivalsWeaponPolicy.revolverTriggerAction(revolver, closeRevolverTarget, 4, 10) == nil,
    "Revolver Trigger Bot must not invent ammo"
)
revolver.Data.Ammo = 6
revolver._is_revolver_quick_shooting = 11
assert(
    RivalsWeaponPolicy.revolverTriggerAction(revolver, closeRevolverTarget, 30, 10) == nil,
    "Revolver Trigger Bot must wait rather than request a precise shot during the live fan-fire lock"
)
local lockedCloseAction =
    RivalsWeaponPolicy.revolverTriggerAction(revolver, closeRevolverTarget, 4, 10)
assert(
    lockedCloseAction and lockedCloseAction.kind == "fan",
    "Revolver Trigger Bot may continue an already-locked fan sequence only at reliable close range"
)
revolver._is_revolver_quick_shooting = nil
end
local shorty = {
    Info = {
        CriticalDamage = 112.5,
        RaycastDamageDropoffEndDistance = 25,
        RaycastDamageDropoffMultiplier = 0.333,
        RaycastDamageDropoffStartDistance = 10,
        ShootDamage = 75,
    },
}
assert(
    type(RivalsWeaponPolicy.damageAtDistance) == "function"
        and type(RivalsWeaponPolicy.triggerDamageReady) == "function",
    "Trigger Bot must expose a range-aware damage decision"
)
assert(RivalsWeaponPolicy.damageAtDistance(shorty, { part = { Name = "Torso" } }, 10) == 75)
assert(math.abs(RivalsWeaponPolicy.damageAtDistance(shorty, { part = { Name = "Torso" } }, 25) - 24.975) < 1e-6)
assert(
    RivalsWeaponPolicy.triggerDamageReady(shorty, { health = 150, part = { Name = "Torso" } }, 20) == false,
    "Trigger Bot must wait instead of wasting a severe-falloff body shot"
)
assert(
    RivalsWeaponPolicy.triggerDamageReady(
        {
            Name = "Burst Rifle",
            Info = table.clone(shorty.Info),
        },
        { health = 150, part = { Name = "Torso" } },
        20
    ) == true,
    "Burst Rifle Trigger Bot must keep taking accurate ranged bursts through damage falloff"
)
assert(
    RivalsWeaponPolicy.triggerDamageReady(shorty, { health = 40, part = { Name = "Torso" } }, 20) == true,
    "Trigger Bot must take a reduced-damage shot when it is still lethal"
)
assert(
    RivalsWeaponPolicy.triggerDamageReady(shorty, { health = 60, part = { Name = "Head" } }, 20) == true,
    "Trigger Bot must use critical damage when evaluating a lethal falloff shot"
)
assert(
    RivalsWeaponPolicy.triggerDamageReady(shorty, { health = 150, part = { Name = "Torso" } }, 12) == true,
    "Trigger Bot must accept near-full damage inside the useful falloff edge"
)
assert(
    RivalsWeaponPolicy.triggerDamageReady({ Info = { ShootDamage = 12 } }, { health = 150 }, 200) == true,
    "Weapons without falloff metadata must keep normal Trigger Bot behavior"
)
local gunbladeMode = "blade"
local gunblade
do
gunblade = {
    Info = {
        BladeCooldown = 0.5,
        BladeModeMobileInputSettings = {
            Aim = false,
            Inspect = false,
            Shoot = false,
        },
        BladeReach = 8,
        DashCooldown = 1.5,
        DashDuration = 0.1875,
        DashSpeed = 100,
        DisplayName = "Gunblade",
        MobileInputSettings = {
            Aim = true,
            Inspect = false,
            Shoot = false,
        },
        ShootCooldown = 0.75,
        TransitionCooldown = 0.6,
    },
}
function gunblade:GetMobileInputSettings()
    if gunbladeMode == "blade" then
        return self.Info.BladeModeMobileInputSettings
    end
    return self.Info.MobileInputSettings
end
function gunblade:CanQuickAttack()
    return self.quickAttackReady ~= false
end
assert(
    RivalsWeaponPolicy.gunbladeMode(gunblade) == "blade"
        and RivalsWeaponPolicy.gunbladeDashRange(gunblade) == 26.75,
    "Gunblade policy must use its live input mode and configured dash travel plus blade reach"
)
local gunbladeTarget = {}
local gunbladeState, gunbladeAction = RivalsWeaponPolicy.gunbladeTriggerAction(
    nil,
    gunblade,
    gunbladeTarget,
    20,
    10
)
assert(
    gunbladeState.phase == "strike"
        and gunbladeAction.kind == "dash"
        and gunbladeAction.cooldown == 1.5,
    "Gunblade Trigger Bot must dash first when Blade mode is inside the confirmed combo range"
)
gunblade.quickAttackReady = false
local waitingState, waitingAction = RivalsWeaponPolicy.gunbladeTriggerAction(
    gunbladeState,
    gunblade,
    gunbladeTarget,
    7,
    10 + 1 / 120
)
assert(
    waitingState == gunbladeState and waitingAction == nil,
    "Gunblade Trigger Bot must wait until the live item allows its blade quick attack"
)
gunblade.quickAttackReady = true
gunbladeState, gunbladeAction = RivalsWeaponPolicy.gunbladeTriggerAction(
    gunbladeState,
    gunblade,
    gunbladeTarget,
    7,
    10 + 1 / 60
)
assert(
    gunbladeState.phase == "awaitGun"
        and gunbladeAction.kind == "strike"
        and gunbladeAction.cooldown == 0.5,
    "Gunblade Trigger Bot must strike on the first frame that its dash reaches blade range"
)
local stuckBladeResult = { expectedState = gunbladeState }
stuckBladeResult.state, stuckBladeResult.action = RivalsWeaponPolicy.gunbladeTriggerAction(
    gunbladeState,
    gunblade,
    gunbladeTarget,
    7,
    10.7875
)
gunbladeMode = "gun"
waitingState, waitingAction = RivalsWeaponPolicy.gunbladeTriggerAction(
    gunbladeState,
    gunblade,
    gunbladeTarget,
    7,
    10.2
)
assert(
    waitingState == gunbladeState and waitingAction == nil,
    "Gunblade Trigger Bot must respect the configured transition cooldown before shooting"
)
gunbladeState, gunbladeAction = RivalsWeaponPolicy.gunbladeTriggerAction(
    gunbladeState,
    gunblade,
    gunbladeTarget,
    7,
    10.7875
)
assert(
    gunbladeState.phase == "awaitBlade"
        and gunbladeAction.kind == "shoot"
        and gunbladeAction.cooldown == 0.75,
    "Gunblade Trigger Bot must shoot only after the live item transitions back to Gun mode"
)
local stuckGunResult = { expectedState = gunbladeState }
stuckGunResult.state, stuckGunResult.action = RivalsWeaponPolicy.gunbladeTriggerAction(
    gunbladeState,
    gunblade,
    gunbladeTarget,
    7,
    11.5375
)
assert(
    stuckBladeResult.state == stuckBladeResult.expectedState
        and stuckBladeResult.action == nil
        and stuckGunResult.state == stuckGunResult.expectedState
        and stuckGunResult.action == nil,
    ("Gunblade Trigger Bot must wait for observed mode transitions (stuck Blade=%s, stuck Gun=%s)"):format(
        stuckBladeResult.action and stuckBladeResult.action.kind or "none",
        stuckGunResult.action and stuckGunResult.action.kind or "none"
    )
)
gunbladeMode = "blade"
gunbladeState, gunbladeAction = RivalsWeaponPolicy.gunbladeTriggerAction(
    gunbladeState,
    gunblade,
    gunbladeTarget,
    7,
    11.5375
)
assert(
    gunbladeState.phase == "strike" and gunbladeAction.kind == "dash",
    "Gunblade Trigger Bot must restart the dash-strike cycle after Blade mode returns"
)
local resetState, resetAction = RivalsWeaponPolicy.gunbladeTriggerAction(
    gunbladeState,
    gunblade,
    {},
    30,
    12
)
assert(
    resetState == nil and resetAction == nil,
    "Gunblade Trigger Bot must reset when the target changes and leaves the confirmed combo range"
)
end
gunbladeMode = "gun"
assert(RivalsProjectileAim.isSplashProjectile({
    Info = {
        DamageType = "Splash",
        IsProjectile = true,
        ProjectileSpeed = 100,
        ShootExplosionRadius = 16,
    },
}) == true)
assert(RivalsProjectileAim.isSplashProjectile({
    Info = {
        DamageType = "Bullet",
        IsProjectile = false,
        ProjectileSpeed = 300,
    },
}) == false)

local origin = Vector3.new(0, 2, 0)
local targetPosition = Vector3.new(10, 5, -20)
local rotation = RivalsTargeting.rotationToward(origin, targetPosition)
local rotationFrame = CFrame.Angles(0, rotation.Y, 0) * CFrame.Angles(rotation.X, 0, 0)
assert(
    rotationFrame.LookVector:Dot((targetPosition - origin).Unit) > 0.999,
    "Camera rotation must align with the selected target direction"
)
local cameraByte0 = utf8.char(0)
local cameraByte1 = utf8.char(1)
local cameraByte2 = utf8.char(2)
local cameraByte3 = utf8.char(3)
local cameraByte4 = utf8.char(4)
local cameraByte5 = utf8.char(5)
local originalCameraData = {
    [cameraByte0] = {
        [cameraByte0] = origin.X,
        [cameraByte1] = origin.Y,
        [cameraByte2] = origin.Z,
        [cameraByte3] = 0,
        [cameraByte4] = 0,
        [cameraByte5] = 0,
    },
    [cameraByte1] = {
        [cameraByte0] = origin.X + 0.1,
        [cameraByte1] = origin.Y,
        [cameraByte2] = origin.Z,
        [cameraByte3] = 0,
        [cameraByte4] = 0,
        [cameraByte5] = 0,
    },
}
local originalRay = {
    Distance = 999,
    Position = origin + Vector3.xAxis * 999,
}
local function corridorRaycast(rayOrigin, rayDirection)
    local bestDistance = math.huge
    local best
    for _, plane in ipairs({
        { height = 0, normal = Vector3.yAxis },
        { height = 2, normal = -Vector3.yAxis },
    }) do
        if math.abs(rayDirection.Y) > 1e-6 then
            local scale = (plane.height - rayOrigin.Y) / rayDirection.Y
            if scale > 1e-5 and scale <= 1 and rayDirection.Magnitude * scale < bestDistance then
                bestDistance = rayDirection.Magnitude * scale
                best = {
                    Normal = plane.normal,
                    Position = rayOrigin + rayDirection * scale,
                }
            end
        end
    end
    return best
end
local ricochetTarget = Vector3.new(10, 1, 0)
local ricochetDirection = (Vector3.new(10, -3, 0) - Vector3.new(0, 1, 0)).Unit
local ricochet = RivalsProjectileAim.traceRicochet(
    Vector3.new(0, 1, 0),
    ricochetDirection,
    ricochetTarget,
    corridorRaycast,
    2,
    math.rad(7.5),
    100
)
assert(
    ricochet and ricochet.bounces == 2,
    "Energy Rifle tracing must verify the same two-reflection path used by the game"
)
local solvedRicochet = RivalsProjectileAim.solveRicochet(
    Vector3.new(0, 1, 0),
    ricochetTarget,
    corridorRaycast,
    100
)
assert(
    solvedRicochet and solvedRicochet.bounces >= 1 and solvedRicochet.bounces <= 2,
    "Energy Rifle aiming must derive and verify a bounded reflected path from nearby surfaces"
)

local function floorRaycast(rayOrigin, rayDirection)
    if rayDirection.Y >= -1e-6 then
        return nil
    end
    local scale = -rayOrigin.Y / rayDirection.Y
    if scale <= 1e-5 or scale > 1 then
        return nil
    end
    return {
        Normal = Vector3.yAxis,
        Position = rayOrigin + rayDirection * scale,
    }
end
local splashTarget = {
    part = {
        AssemblyLinearVelocity = Vector3.new(5, 0, 0),
    },
    position = Vector3.new(10, 3, 0),
}
local splashAim = RivalsProjectileAim.solveSplashAim(
    Vector3.new(0, 3, 0),
    splashTarget,
    {
        ProjectileGravity = 0,
        ProjectileLifetime = 5,
        ProjectileSpeed = 100,
        ShootExplosionRadius = 16,
    },
    floorRaycast,
    196.2
)
assert(
    splashAim
        and splashAim.impact.Y == 0
        and splashAim.predictedPosition.X > splashTarget.position.X
        and (splashAim.impact - splashAim.predictedPosition).Magnitude <= 16,
    "Splash aiming must lead the player and verify the nearest environment impact inside blast radius"
)
local latencySplashAim = RivalsProjectileAim.solveSplashAim(
    Vector3.new(0, 3, 0),
    splashTarget,
    {
        ProjectileGravity = 0,
        ProjectileLifetime = 5,
        ProjectileSpeed = 100,
        ShootExplosionRadius = 16,
    },
    floorRaycast,
    196.2,
    0.1
)
local earlyWallX = 404.5
local function earlyWallRaycast(rayOrigin, rayDirection)
    if math.abs(rayDirection.X) <= 1e-6 then
        return nil
    end
    local scale = (earlyWallX - rayOrigin.X) / rayDirection.X
    if scale <= 1e-5 or scale > 1 then
        return nil
    end
    return {
        Normal = -Vector3.xAxis,
        Position = rayOrigin + rayDirection * scale,
    }
end
local unsafeEarlyImpact = RivalsProjectileAim.solveSplashAim(
    Vector3.zero,
    {
        part = {
            AssemblyLinearVelocity = Vector3.new(30, 0, 0),
        },
        position = Vector3.new(300, 0, 0),
    },
    {
        ProjectileGravity = 0,
        ProjectileLifetime = 5,
        ProjectileRaycastRadius = 1,
        ProjectileSpeed = 100,
        ShootExplosionRadius = 16,
    },
    earlyWallRaycast,
    196.2,
    0.035
)
assert(
    unsafeEarlyImpact == nil,
    "RPG prediction must reject an early path collision outside the target's blast radius at actual impact time"
)
do
local function solidWallRaycast(rayOrigin, rayDirection)
    local nearestScale = math.huge
    local nearestNormal
    for _, surface in ipairs({
        { axis = "X", normal = -Vector3.xAxis, position = 8 },
        { axis = "X", normal = Vector3.xAxis, position = 8.5 },
        { axis = "Y", normal = Vector3.yAxis, position = 0 },
    }) do
        local originCoordinate = surface.axis == "X" and rayOrigin.X or rayOrigin.Y
        local directionCoordinate = surface.axis == "X" and rayDirection.X or rayDirection.Y
        if math.abs(directionCoordinate) > 1e-6 then
            local scale = (surface.position - originCoordinate) / directionCoordinate
            if scale > 1e-5 and scale <= 1 and scale < nearestScale then
                nearestScale = scale
                nearestNormal = surface.normal
            end
        end
    end
    if nearestNormal then
        return {
            Normal = nearestNormal,
            Position = rayOrigin + rayDirection * nearestScale,
        }
    end
    return nil
end
local wallOccludedSplash = RivalsProjectileAim.solveSplashAim(
    Vector3.new(0, 3, 0),
    {
        part = {
            AssemblyLinearVelocity = Vector3.zero,
        },
        position = Vector3.new(10, 3, 0),
    },
    {
        ProjectileGravity = 0,
        ProjectileLifetime = 5,
        ProjectileSpeed = 100,
        ShootExplosionRadius = 16,
    },
    solidWallRaycast,
    196.2
)
assert(
    wallOccludedSplash == nil,
    "RPG prediction must reject a blast-radius impact when a solid wall blocks the impact from the target"
)
end
assert(
    latencySplashAim
        and latencySplashAim.predictedPosition.X > splashAim.predictedPosition.X + 0.4,
    "RPG prediction must add observed network latency to moving-target lead"
)
do
local daggerInfo = {
    ProjectileGravity = 0.25,
    ProjectileLifetime = 5,
    ProjectileSpawnOffset = CFrame.new(0, -1, -2)
        * CFrame.Angles(math.rad(4), 0, 0),
    ProjectileSpeed = 300,
}
local daggerOrigin = Vector3.new(0, 3, 0)
local daggerAim = RivalsProjectileAim.solveProjectileAim(
    daggerOrigin,
    {
        part = {
            AssemblyLinearVelocity = Vector3.new(0, 0, 12),
        },
        position = Vector3.new(60, 3, 0),
    },
    daggerInfo,
    196.2
)
local daggerReference = math.abs(daggerAim.direction:Dot(Vector3.yAxis)) < 0.999
        and Vector3.yAxis
    or Vector3.xAxis
local daggerRight = daggerAim.direction:Cross(daggerReference).Unit
local daggerUp = daggerRight:Cross(daggerAim.direction).Unit
local daggerLaunchFrame = CFrame.fromMatrix(
    daggerOrigin,
    daggerRight,
    daggerUp,
    -daggerAim.direction
) * daggerInfo.ProjectileSpawnOffset
local daggerImpact = daggerLaunchFrame.Position
    + daggerLaunchFrame.LookVector
        * (daggerInfo.ProjectileSpeed * daggerAim.flightTime)
    + Vector3.new(0, -196.2 * daggerInfo.ProjectileGravity, 0)
        * (0.5 * daggerAim.flightTime * daggerAim.flightTime)
local daggerSpawnCompensation = math.deg(math.acos(math.clamp(
    daggerAim.direction:Dot(daggerAim.projectileDirection),
    -1,
    1
)))
assert(
    daggerAim
        and daggerAim.predictedPosition.Z > 0
        and daggerAim.projectileDirection.Y > 0
        and daggerAim.flightTime > 0
        and daggerSpawnCompensation > 3
        and daggerLaunchFrame.LookVector:Dot(daggerAim.projectileDirection) > 0.99999
        and (daggerImpact - daggerAim.predictedPosition).Magnitude < 0.05,
    ("Dagger aiming must compensate for its rotated native projectile spawn frame (error %.4f, compensation %.4f)"):format(
        (daggerImpact - daggerAim.predictedPosition).Magnitude,
        daggerSpawnCompensation
    )
)
end
do
local bowCameraOrigin = Vector3.new(0, 5, 0)
local bowInfo = {
    ProjectileGravity = 0.25,
    ProjectileLifetime = 5,
    ProjectileSpawnOffset = CFrame.new(0, -1, -2),
    ProjectileSpeed = 300,
}
local bowAim = RivalsProjectileAim.solveProjectileAim(
    bowCameraOrigin,
    {
        part = {
            AssemblyLinearVelocity = Vector3.new(0, 0, 12),
        },
        position = Vector3.new(60, 5, 0),
    },
    bowInfo,
    196.2
)
local bowReference = math.abs(bowAim.direction:Dot(Vector3.yAxis)) < 0.999
        and Vector3.yAxis
    or Vector3.xAxis
local bowRight = bowAim.direction:Cross(bowReference).Unit
local bowUp = bowRight:Cross(bowAim.direction).Unit
local bowLaunchFrame = CFrame.fromMatrix(
    bowCameraOrigin,
    bowRight,
    bowUp,
    -bowAim.direction
)
local expectedBowLaunchOrigin =
    (bowLaunchFrame * bowInfo.ProjectileSpawnOffset).Position
local bowImpact = bowAim.launchOrigin
    + bowAim.direction * (bowInfo.ProjectileSpeed * bowAim.flightTime)
    + Vector3.new(0, -196.2 * bowInfo.ProjectileGravity, 0)
        * (0.5 * bowAim.flightTime * bowAim.flightTime)
assert(
    (bowAim.launchOrigin - expectedBowLaunchOrigin).Magnitude < 0.01
        and (bowAim.launchOrigin - bowCameraOrigin).Magnitude > 1
        and (bowImpact - bowAim.predictedPosition).Magnitude < 0.05,
    "Bow prediction must solve from its native camera-space projectile spawn offset"
)
local bowPresentationDelay = 1 / 60
local bowDelayedVelocity = Vector3.new(0, 0, 30)
local bowDelayedTarget = Vector3.new(120, 5, 0)
local bowDelayedAim = RivalsProjectileAim.solveProjectileAim(
    bowCameraOrigin,
    {
        part = {
            AssemblyLinearVelocity = bowDelayedVelocity,
        },
        position = bowDelayedTarget,
    },
    bowInfo,
    196.2,
    bowPresentationDelay
)
local bowDelayedImpact = bowDelayedAim.launchOrigin
    + bowDelayedAim.projectileDirection
        * (bowInfo.ProjectileSpeed * bowDelayedAim.flightTime)
    + Vector3.new(0, -196.2 * bowInfo.ProjectileGravity, 0)
        * (0.5 * bowDelayedAim.flightTime * bowDelayedAim.flightTime)
local bowDelayedExpected = bowDelayedTarget
    + bowDelayedVelocity * (bowPresentationDelay + bowDelayedAim.flightTime)
assert(
    (bowDelayedImpact - bowDelayedExpected).Magnitude < 0.05,
    "Bow prediction must include the Silent Aim presentation frame before projectile flight"
)
end

local smoothedRotation = RivalsTargeting.smoothRotation(
    Vector2.zero,
    Vector2.new(0.5, math.pi - 0.1),
    100,
    1 / 60
)
assert(
    smoothedRotation.X > 0
        and smoothedRotation.X < 0.5
        and smoothedRotation.Y > 0
        and smoothedRotation.Y < math.pi - 0.1,
    "Maximum Camera Aim smoothness must move toward the target without snapping"
)
assert(
    RivalsTargeting.smoothRotation(Vector2.zero, Vector2.new(0.5, 1), 0, 1 / 60)
        == Vector2.new(0.5, 1),
    "Zero Camera Aim smoothness must preserve instant rotation"
)

assert(
    type(RivalsTargeting.humanRotation) == "function",
    "Human Aim must provide motion-responsive curved tracking"
)
local humanAimState = { curveSign = 1 }
local humanStartTarget = Vector2.new(0, 0.35)
local humanStart = RivalsTargeting.humanRotation(
    Vector2.zero,
    humanStartTarget,
    70,
    1 / 60,
    humanAimState
)
local fastHumanTarget = Vector2.new(0, 0.5)
local fixedSpeedFollow = RivalsTargeting.smoothRotation(humanStart, fastHumanTarget, 70, 1 / 60)
local adaptiveFollow = RivalsTargeting.humanRotation(
    humanStart,
    fastHumanTarget,
    70,
    1 / 60,
    humanAimState
)
assert(
    (fastHumanTarget - adaptiveFollow).Magnitude < (fastHumanTarget - fixedSpeedFollow).Magnitude,
    "Human Aim must accelerate to reduce trailing error when the target moves quickly"
)
assert(adaptiveFollow ~= fastHumanTarget, "Human Aim must not snap perfectly onto a moving target")
assert(
    math.abs(adaptiveFollow.X) > 0 and math.abs(adaptiveFollow.X) <= math.rad(0.5),
    "Human Aim must follow a subtle curved path that remains close to the target"
)

local knifeTargetRoot = {
    CFrame = CFrame.lookAt(Vector3.new(5, 0, 0), Vector3.new(6, 0, 0)),
    Position = Vector3.new(5, 0, 0),
}
local knifeObservation = {
    character = {
        FindFirstChild = function(_self, name)
            return name == "HumanoidRootPart" and knifeTargetRoot or nil
        end,
    },
    health = 150,
    position = knifeTargetRoot.Position,
}
local knifeInfo = {
    AttackReach = 6,
    HeavyAttackReach = 7,
    CriticalDamage = 150,
}
assert(RivalsWeaponPolicy.backstabReady(Vector3.new(0, 0, 0), knifeObservation, knifeInfo) == true)
assert(RivalsWeaponPolicy.backstabReady(Vector3.new(10, 0, 0), knifeObservation, knifeInfo) == false)
local knifeApproach = RivalsWeaponPolicy.backstabPlan(
    Vector3.new(10, 0, 0),
    knifeObservation,
    knifeInfo
)
assert(
    knifeApproach
        and knifeApproach.ready == false
        and knifeApproach.aimPosition == knifeApproach.approachPosition
        and knifeApproach.movePosition == knifeApproach.approachPosition
        and #knifeApproach.path == 3
        and knifeApproach.approachPosition.X < knifeTargetRoot.Position.X,
    "Knife backstab planning must use the nearest lethal rear position"
)
assert(
    RivalsWeaponPolicy.backstabReady(Vector3.new(3, 0, 6), knifeObservation, knifeInfo) == true,
    "Knife backstab readiness must accept a lenient rear angle inside heavy-attack reach"
)
assert(
    RivalsWeaponPolicy.backstabReady(Vector3.new(5, 0, 6), knifeObservation, knifeInfo) == true,
    "Knife backstab readiness must accept the server's lenient side-plane window"
)
assert(
    RivalsWeaponPolicy.backstabReady(Vector3.new(-1.5, 0, 0), knifeObservation, knifeInfo) == true,
    "Knife backstab readiness must use the live 7-stud heavy-attack reach"
)
knifeObservation.health = 151
assert(
    RivalsWeaponPolicy.backstabReady(Vector3.new(0, 0, 0), knifeObservation, knifeInfo) == false,
    "Knife Camera Aim must not turn for a backstab that cannot eliminate the target"
)
knifeObservation.health = 150
assert(
    RivalsWeaponPolicy.backstabReady(Vector3.new(-2.1, 0, 0), knifeObservation, knifeInfo) == false,
    "Knife backstab readiness must reject targets beyond heavy-attack reach"
)
knifeObservation.fighter = {
    Entity = {
        RootPart = {
            Position = Vector3.new(0, 0, 0),
        },
    },
    IsGrounded = function(self)
        return self._grounded
    end,
    _grounded = false,
}
knifeObservation.item = { Info = knifeInfo }
knifeObservation.aimSettled = true
assert(
    RivalsWeaponPolicy.backstabTriggerReady(
        knifeObservation.fighter,
        knifeObservation.item,
        knifeObservation
    ) == false,
    "Knife Trigger Bot must reject a stale rear window while the fighter is airborne"
)
knifeObservation.fighter._grounded = true
knifeObservation.fighter.Entity.RootPart.Position = Vector3.new(0, 8, 0)
assert(
    RivalsWeaponPolicy.backstabTriggerReady(
        knifeObservation.fighter,
        knifeObservation.item,
        knifeObservation
    ) == false,
    "Knife Trigger Bot must revalidate current vertical reach instead of trusting aligned geometry"
)
knifeObservation.fighter.Entity.RootPart.Position = Vector3.new(10, 0, 0)
assert(
    RivalsWeaponPolicy.backstabTriggerReady(
        knifeObservation.fighter,
        knifeObservation.item,
        knifeObservation
    ) == false,
    "Knife Trigger Bot must revalidate current reach and rear geometry"
)
knifeObservation.fighter.Entity.RootPart.Position = Vector3.new(0, 0, 0)
assert(
    RivalsWeaponPolicy.backstabTriggerReady(
        knifeObservation.fighter,
        knifeObservation.item,
        knifeObservation
    ) == true,
    "Knife Trigger Bot must permit current grounded lethal rear geometry"
)

local slingshotAim = RivalsProjectileAim.solveSlingshot(
    Vector3.new(0, 5, 0),
    {
        part = {
            AssemblyLinearVelocity = Vector3.zero,
        },
        position = Vector3.new(10, 5, 0),
    },
    {
        ProjectileBounceRestitution = 1,
        ProjectileGravity = 0,
        ProjectileLifetime = 3,
        ProjectileMaxHits = 3,
        ProjectileSpeed = 10,
    },
    floorRaycast,
    196.2
)
assert(
    slingshotAim and slingshotAim.bounces >= 1 and #slingshotAim.path >= 3,
    "Slingshot aiming must simulate and verify its physical wall bounce before aligning"
)

local projectedSegments = RivalsProjectileAim.projectTrajectory({
    WorldToViewportPoint = function(_self, point)
        return Vector3.new(point.X, point.Y, 1), true
    end,
}, {
    Vector3.new(10, 20, 0),
    Vector3.new(30, 40, 0),
    Vector3.new(50, 60, 0),
})
assert(
    #projectedSegments == 2
        and projectedSegments[1].from == Vector2.new(10, 20)
        and projectedSegments[2].to == Vector2.new(50, 60),
    "Bounce ESP must project every verified wall segment"
)

local cameraHarness = {
    bound = {},
    boundCount = 0,
    rotationDeltaDisconnected = false,
    unbound = {},
    unboundCount = 0,
}
local rotationCalls = 0
local cameraModule = {
    Rotation = Vector2.zero,
    RotationDeltaApplied = {
        Connect = function(_signal, callback)
            cameraHarness.rotationDeltaCallback = callback
            return {
                Disconnect = function()
                    cameraHarness.rotationDeltaDisconnected = true
                    cameraHarness.rotationDeltaCallback = nil
                end,
            }
        end,
    },
    SetRotation = function(self, value)
        rotationCalls += 1
        self.Rotation = value
    end,
}
local targetItem = { Info = { Name = "Rifle" } }
local targetShield = {
    Info = {
        Name = "Riot Shield",
        MaxAbsorption = 100,
    },
    Get = function(_self, field)
        return field == "Ammo" and 52 or nil
    end,
}
local localItem = { Name = "Burst Rifle", Info = { DisplayName = "Burst Rifle" } }
local crouching = false
local sliding = false
local grounded = true
local canSlide = true
local originalMoveVector = Vector3.zAxis
local fighterModule = {
    LocalFighter = {
        Data = {
            EnvironmentID = "PracticeA",
            IsInDuel = true,
            IsInShootingRange = true,
            IsSpectating = false,
        },
        Entity = {
            Humanoid = {
                Health = 150,
            },
        },
        EquippedItem = localItem,
        CanSlide = function()
            return canSlide
        end,
        IsCrouching = function()
            return crouching
        end,
        IsSliding = function()
            return sliding
        end,
        IsGrounded = function()
            return grounded
        end,
        GetCameraData = function()
            cameraHarness.cameraDataFrameAtCall = cameraHarness.camera.CFrame
            cameraHarness.cameraDataRotationAtCall = cameraModule.Rotation
            local cameraData = table.clone(originalCameraData)
            for _, key in ipairs({ cameraByte0, cameraByte1 }) do
                local record = table.clone(cameraData[key])
                record[cameraByte3] = cameraModule.Rotation.X
                record[cameraByte4] = cameraModule.Rotation.Y
                cameraData[key] = record
            end
            local direction = (
                CFrame.Angles(0, cameraModule.Rotation.Y, 0)
                * CFrame.Angles(cameraModule.Rotation.X, 0, 0)
            ).LookVector
            local ray = table.clone(originalRay)
            ray.Position = origin + direction * ray.Distance
            return cameraData, ray
        end,
        GetMoveVector = function()
            return originalMoveVector
        end,
    },
    _player_to_fighter = {
        [enemyPlayer] = {
            EquippedItem = targetShield,
        },
    },
}
cameraModule._current_subject = fighterModule.LocalFighter
local cameraScript = {}
local duelScript = {}
local fighterScript = {}
local controlsScript = {}
local mechanicsScript = {}
local activeDuel = {
    Data = {
        Status = "RoundStarted",
    },
}
local loadoutOpen = false
local duelModule = {
    GetDuel = function()
        return fighterModule.LocalFighter.Data.IsInDuel == true
            and activeDuel
            or nil
    end,
}
local toggledInputs = {}
local wHeld = false
local controlsModule = {
    IsToggled = function(_self, input)
        return toggledInputs[input.Name] == true
    end,
    ToggleInput = function(_self, input, enabled)
        toggledInputs[input.Name] = enabled == true or nil
    end,
}
local slideCalls = 0
local highJumpCalls = 0
local stopSlideCalls = 0
local mechanicsModule = {
    IsSliding = false,
    Slide = function(self)
        slideCalls += 1
        self.IsSliding = true
    end,
    HighJump = function(self)
        highJumpCalls += 1
        self.IsSliding = false
    end,
    StopSliding = function(self)
        stopSlideCalls += 1
        self.IsSliding = false
    end,
}
local controllers = {}
function controllers:WaitForChild(name)
    if name == "CameraController" then
        return cameraScript
    end
    if name == "DuelController" then
        return duelScript
    end
    if name == "FighterController" then
        return fighterScript
    end
    return name == "MechanicsController" and mechanicsScript or controlsScript
end
local playerScripts = {}
function playerScripts:WaitForChild(name)
    assert(name == "Controllers")
    return controllers
end
localPlayer.PlayerScripts = playerScripts

local renderCallback
local disconnected = false
local RunService = {
    RenderStepped = {
        Connect = function(_signal, callback)
            renderCallback = callback
            return {
                Disconnect = function()
                    disconnected = true
                end,
            }
        end,
    },
    BindToRenderStep = function(_service, name, priority, callback)
        if not cameraHarness.bound[name] then
            cameraHarness.boundCount += 1
        end
        cameraHarness.bound[name] = {
            callback = callback,
            priority = priority,
        }
    end,
    UnbindFromRenderStep = function(_service, name)
        if cameraHarness.bound[name] then
            cameraHarness.boundCount -= 1
            cameraHarness.bound[name] = nil
        end
        if not cameraHarness.unbound[name] then
            cameraHarness.unboundCount += 1
            cameraHarness.unbound[name] = true
        end
    end,
}
local mousePosition = Vector2.new(640, 360)
local movementDirection = Vector3.zero
local UserInputService = {
    GetMouseLocation = function()
        return mousePosition
    end,
    IsKeyDown = function(_self, input)
        return input == Enum.KeyCode.W and wHeld
    end,
}
cameraHarness.camera = {
    CFrame = CFrame.new(origin),
    WorldToViewportPoint = function()
        return Vector3.new(640, 360, 1), true
    end,
}
local Workspace = {
    CurrentCamera = cameraHarness.camera,
}
function cameraHarness.frameForRotation(value)
    return CFrame.new(origin)
        * CFrame.Angles(0, value.Y, 0)
        * CFrame.Angles(value.X, 0, 0)
end
function cameraHarness.runCameraRenderFrame()
    local steps = {}
    for _, step in pairs(cameraHarness.bound) do
        table.insert(steps, step)
    end
    table.sort(steps, function(left, right)
        return left.priority < right.priority
    end)
    local cameraUpdated = false
    for _, step in ipairs(steps) do
        if not cameraUpdated and step.priority > Enum.RenderPriority.Camera.Value then
            cameraHarness.camera.CFrame =
                cameraHarness.frameForRotation(cameraModule.Rotation)
            cameraUpdated = true
        end
        step.callback()
    end
    if not cameraUpdated then
        cameraHarness.camera.CFrame =
            cameraHarness.frameForRotation(cameraModule.Rotation)
    end
end
local throwableAttributes = {
    DisplayName = "Smoke Grenade",
    EnvironmentID = "PracticeA",
}
local throwableModel = {
    Name = "Projectile",
    Parent = {},
    PrimaryPart = {
        Position = origin + Vector3.new(12, 0, 0),
    },
    GetAttribute = function(_self, name)
        return throwableAttributes[name]
    end,
    IsA = function()
        return false
    end,
}
local smokeObservation = RivalsEffects.throwableObservation(
    Workspace.CurrentCamera,
    throwableModel,
    "PracticeA"
)
assert(
    smokeObservation
        and smokeObservation.label == "SMOKE"
        and smokeObservation.tone == "smoke"
        and smokeObservation.onScreen == true,
    "RIVALS throwable discovery must classify replicated item metadata into a compact ESP marker"
)
assert(
    RivalsEffects.throwableObservation(Workspace.CurrentCamera, throwableModel, "OtherMatch") == nil,
    "Throwable ESP must exclude projectiles from another environment"
)
throwableAttributes.Exploded = true
assert(
    RivalsEffects.throwableObservation(Workspace.CurrentCamera, throwableModel, "PracticeA") == nil,
    "Throwable ESP must drop completed projectiles"
)
throwableAttributes.Exploded = nil

do
local utilityWorld = {
    Name = "Workspace",
}
local utilityEnvironment = {
    Name = "Match",
    Parent = utilityWorld,
    GetAttribute = function(_self, name)
        return name == "EnvironmentID" and "PracticeA" or nil
    end,
}
local tripmineAttributes = {
    HitboxDelay = 1,
    ObjectID = "mine-1",
    PlacedByUserID = 123,
    TeamID = "Red",
}
local tripminePart = {
    CFrame = CFrame.new(origin + Vector3.new(16, 0, 0)),
    Position = origin + Vector3.new(16, 0, 0),
    Size = Vector3.new(4, 3, 4),
}
local tripmineModel = {
    Name = "Object",
    Parent = utilityEnvironment,
    PrimaryPart = tripminePart,
    GetBoundingBox = function()
        return tripminePart.CFrame, tripminePart.Size
    end,
    GetAttribute = function(_self, name)
        return tripmineAttributes[name]
    end,
    HasTag = function(_self, tag)
        return tag == "SubspaceTripmine"
    end,
    IsA = function()
        return false
    end,
}
local tripmineCamera = {
    CFrame = Workspace.CurrentCamera.CFrame,
    WorldToViewportPoint = function(_self, position)
        return Vector3.new(640 + position.X * 10, 360 - position.Y * 10, position.Z + 50), true
    end,
}
local tripmineObservation = RivalsEffects.throwableObservation(
    tripmineCamera,
    tripmineModel,
    "PracticeA",
    utilityWorld
)
assert(
    tripmineObservation
        and tripmineObservation.label == "TRIPMINE"
        and tripmineObservation.tone == "danger"
        and tripmineObservation.markerStyle == "wireframeCube"
        and #tripmineObservation.wireframeCorners == 8
        and tripmineObservation.labelPosition.Y < tripmineObservation.screenPosition.Y,
    "Utility ESP must publish the live Tripmine bounds as a readable projected cube"
)
assert(
    RivalsEffects.throwableObservation(
        tripmineCamera,
        tripmineModel,
        "OtherMatch",
        utilityWorld
    ) == nil,
    "Tagged utility ESP must inherit EnvironmentID filtering from the replicated world hierarchy"
)

local jumpPadHitbox = {
    Name = "Hitbox",
    Parent = utilityEnvironment,
    Position = origin + Vector3.new(20, 0, 0),
    GetAttribute = function()
        return nil
    end,
    HasTag = function(_self, tag)
        return tag == "JumpPadHitbox"
    end,
    IsA = function(_self, className)
        return className == "BasePart"
    end,
}
local jumpPadObservation = RivalsEffects.throwableObservation(
    Workspace.CurrentCamera,
    jumpPadHitbox,
    "PracticeA",
    utilityWorld
)
assert(
    jumpPadObservation
        and jumpPadObservation.label == "JUMP PAD"
        and jumpPadObservation.tone == "accent",
    "Utility ESP must identify comparable persistent utility hitboxes from their live tag"
)

for displayName, expectedLabel in pairs({
    Elixir = "ELIXIR",
    Satchel = "SATCHEL",
    Warpstone = "WARPSTONE",
}) do
    throwableAttributes.DisplayName = displayName
    local observation = RivalsEffects.throwableObservation(
        Workspace.CurrentCamera,
        throwableModel,
        "PracticeA"
    )
    assert(
        observation and observation.label == expectedLabel,
        ("Utility ESP must classify the live %s throwable metadata"):format(displayName)
    )
end
throwableAttributes.DisplayName = "Smoke Grenade"

local viewModels = {
    Name = "ViewModels",
    Parent = utilityWorld,
}
local heldTripmine = {
    Name = "Subspace Tripmine",
    Parent = viewModels,
    PrimaryPart = {
        Position = origin + Vector3.new(8, 0, 0),
    },
    GetAttribute = function()
        return nil
    end,
    IsA = function()
        return false
    end,
}
assert(
    RivalsEffects.throwableObservation(
        Workspace.CurrentCamera,
        heldTripmine,
        "PracticeA",
        utilityWorld
    ) == nil,
    "Utility ESP must not turn a held weapon or first-person viewmodel into a world marker"
)

local requestedUtilityTags = {}
local effectsDiscovery = RivalsEffects.new({
    collectionService = {
        GetTagged = function(_self, tag)
            requestedUtilityTags[tag] = true
            return {}
        end,
    },
    localPlayer = {},
    projectileAim = {},
    workspace = {
        FindFirstChild = function()
            return nil
        end,
    },
})
effectsDiscovery:_collectThrowables()
assert(
    requestedUtilityTags.SubspaceTripmine and requestedUtilityTags.JumpPadHitbox,
    "Utility discovery must query the live persistent-utility tags alongside throwable tags"
)
end

local flashEffect = {
    Enabled = true,
    Name = "FlashbangColor",
    IsA = function(_self, className)
        return className == "ColorCorrectionEffect"
    end,
}
local smokeEffect = {
    Enabled = true,
    Name = "Cloud",
    IsA = function(_self, className)
        return className == "ParticleEmitter"
    end,
}
local smokeRoot = {
    Name = "Smoke Grenade",
    GetDescendants = function()
        return { smokeEffect }
    end,
    IsA = function()
        return false
    end,
}
local suppressedVisuals = {}
RivalsEffects.updateVisualSuppressions({
    noFlash = true,
    noSmoke = true,
}, {
    flashEffect,
    {
        instance = smokeRoot,
        kind = "smoke",
    },
}, suppressedVisuals)
assert(
    flashEffect.Enabled == false and smokeEffect.Enabled == false,
    "No Flash and No Smoke must suppress only their client-visible effect instances"
)
RivalsEffects.updateVisualSuppressions({}, {}, suppressedVisuals)
assert(
    flashEffect.Enabled == true and smokeEffect.Enabled == true,
    "Disabling visual suppression must restore each effect's original state"
)
assert(
    table.find(Rivals.capabilities, "noFlash") ~= nil
        and table.find(Rivals.capabilities, "noSmoke") ~= nil,
    "RIVALS must expose No Flash and No Smoke in the shared Visuals section"
)

local rangeRoot = {
    IsA = function(_self, className)
        return className == "BasePart"
    end,
}
local rangeTarget = {
    Name = "Dummy",
    GetAttribute = function(_self, name)
        return ({
            EnvironmentID = "PracticeA",
            Health = 1,
            MaxHealth = 1,
        })[name]
    end,
    FindFirstChild = function(_self, name)
        return name == "HumanoidRootPart" and rangeRoot or nil
    end,
    FindFirstChildOfClass = function(_self, className)
        if className == "Humanoid" then
            return {
                Health = math.huge,
                MaxHealth = math.huge,
            }
        end
        return nil
    end,
    IsA = function(_self, className)
        return className == "Model"
    end,
}
local targetMarker = {
    Name = "Target",
    GetAttribute = rangeTarget.GetAttribute,
    FindFirstChild = rangeTarget.FindFirstChild,
    FindFirstChildOfClass = function()
        return nil
    end,
    IsA = rangeTarget.IsA,
}
Workspace.ShootingRangeEntities = {
    GetChildren = function()
        return {
            targetMarker,
            rangeTarget,
        }
    end,
}
function Workspace:FindFirstChild(name)
    return self[name]
end
local Players = {
    LocalPlayer = localPlayer,
}
game = {
    GetService = function(_self, name)
        return ({
            Players = Players,
            RunService = RunService,
            UserInputService = UserInputService,
            Workspace = Workspace,
        })[name]
    end,
}

local target = {
    character = character(150),
    player = enemyPlayer,
    position = targetPosition,
    screenDistance = 40,
    visible = true,
}
local observations = {
    {
        character = target.character,
        player = enemyPlayer,
        position = targetPosition,
        screenDistance = 40,
        visible = true,
    },
}
local farObservation = {
    character = character(150),
    player = enemyPlayer,
    position = origin + Vector3.new(2001, 0, 0),
    screenDistance = 1,
    visible = true,
}
local rangeObservation = {
    character = rangeTarget,
    position = targetPosition,
    screenDistance = 40,
    visible = true,
}
local nearestOptions = {}
local smokeCloud = { Name = "SmokeCloud" }
local smokeClouds = { smokeCloud }
local targeting = {
    nearestObservation = function(values, options)
        table.insert(nearestOptions, options)
        for _, value in ipairs(values) do
            if not options.maxScreenDistance
                or value.screenDistance and value.screenDistance <= options.maxScreenDistance
            then
                return value
            end
        end
        return nil
    end,
    observePlayers = function(options)
        assert(options.isEligible(enemyPlayer, target.character) == true)
        assert(options.screenOrigin == mousePosition)
        assert(
            table.find(options.raycastIgnore or {}, smokeCloud) ~= nil,
            "Camera Aim, Human Aim, and Trigger Bot visibility must treat active SmokeCloud volumes as transparent"
        )
        return { farObservation, table.unpack(observations) }
    end,
    observeCharacter = function(value, options)
        assert(value == rangeTarget, "Non-humanoid Target markers must never reach ESP observation")
        assert(options.screenOrigin == mousePosition)
        return rangeObservation
    end,
}
local settings = {
    aimSmoothness = 0,
    bhop = false,
    fov = 180,
    fullScreenAim = false,
    headshotRate = 0,
    humanAim = false,
    missRate = 0,
    shotAim = false,
    silentAim = true,
    triggerBot = false,
    utilityEsp = true,
}
local state = {
    settings = settings,
}
local store = {
    Get = function()
        return state
    end,
    Patch = function(_self, patch)
        for key, value in pairs(patch) do
            state[key] = value
        end
    end,
}
local clicks = 0
local presses = 0
local releases = 0
local aimPresses = 0
local aimReleases = 0
local aimClicks = 0
local currentTime = 10
local ricochetSolves = 0
local slingshotSolves = 0
local trajectoryDestroyed = false
local trajectoryNodes = {}
local throwableObservation = {
    key = {},
    label = "GRENADE",
    onScreen = true,
    polygons = {},
    screenPosition = Vector2.new(700, 380),
    tone = "danger",
}
local throwableObserveCalls = 0
local loadedModuleChecks = 0
local hookImplementations = {}
local restoredHooks = {}
local triggerCameraCaptureEnabled = false
local triggerCameraDataAtClick
local triggerRayAtClick
local rendered
local inputCaptured = false
local environmentCast = function()
    return nil
end
local adapter = Rivals.new({
    aimPress = function()
        aimPresses += 1
    end,
    aimRelease = function()
        aimReleases += 1
    end,
    aimClick = function()
        aimClicks += 1
    end,
    clock = function()
        return currentTime
    end,
    itemClock = function()
        return currentTime
    end,
    getNetworkPing = function()
        return 0.035
    end,
    movementDirection = function()
        return movementDirection
    end,
    getLoadedModules = function()
        loadedModuleChecks += 1
        if loadedModuleChecks == 1 then
            return { cameraScript }
        end
        return { cameraScript, duelScript, fighterScript, mechanicsScript }
    end,
    hookFunction = function(targetFunction, replacement)
        hookImplementations[targetFunction] = replacement
        return targetFunction
    end,
    click = function()
        clicks += 1
        if triggerCameraCaptureEnabled then
            local cameraDataHook =
                hookImplementations[fighterModule.LocalFighter.GetCameraData]
            assert(cameraDataHook, "Trigger Bot must fire through the installed camera-data hook")
            triggerCameraDataAtClick, triggerRayAtClick =
                cameraDataHook(fighterModule.LocalFighter)
        end
    end,
    collectionService = {
        GetTagged = function(_self, tag)
            return tag == "SmokeCloud" and smokeClouds or {}
        end,
    },
    environmentRaycast = function()
        return environmentCast
    end,
    press = function()
        presses += 1
    end,
    random = function()
        return 0
    end,
    release = function()
        releases += 1
    end,
    isInputCaptured = function()
        return inputCaptured
    end,
    oh = {
        drawing = {
            createSurface = function()
                return {
                    create = function(_self, kind)
                        assert(kind == "Line")
                        local node = {
                            properties = {},
                        }
                        function node:set(properties)
                            self.properties = properties
                        end
                        table.insert(trajectoryNodes, node)
                        return node
                    end,
                    destroy = function()
                        trajectoryDestroyed = true
                    end,
                }
            end,
            supports = function(kind)
                return kind == "Line"
            end,
        },
        targeting = targeting,
    },
    observeThrowables = function(camera, environmentID)
        throwableObserveCalls += 1
        assert(camera == Workspace.CurrentCamera)
        assert(environmentID == "PracticeA")
        return { throwableObservation }
    end,
    render = function(value, position, utilities)
        rendered = {
            observations = value,
            position = position,
            utilities = utilities,
        }
    end,
    requireModule = function(module)
        assert(
            loadedModuleChecks >= 2,
            "RIVALS must never require a controller while the game's bootstrap is incomplete"
        )
        if module == cameraScript then
            return cameraModule
        end
        if module == fighterScript then
            return fighterModule
        end
        if module == duelScript then
            return duelModule
        end
        return module == mechanicsScript and mechanicsModule or controlsModule
    end,
    restoreFunction = function(targetFunction)
        restoredHooks[targetFunction] = true
        hookImplementations[targetFunction] = nil
    end,
    spawn = function(callback)
        callback()
    end,
    solveRicochet = function(solutionOrigin, solutionTarget)
        ricochetSolves += 1
        return {
            bounces = 1,
            direction = (solutionTarget - solutionOrigin).Unit,
            path = {
                solutionOrigin,
                solutionOrigin + (solutionTarget - solutionOrigin) * 0.5,
                solutionTarget,
            },
        }
    end,
    solveSlingshot = function(solutionOrigin, solutionTarget)
        slingshotSolves += 1
        return {
            bounces = 1,
            direction = (solutionTarget.position - solutionOrigin).Unit,
            path = {
                solutionOrigin,
                solutionOrigin + (solutionTarget.position - solutionOrigin) * 0.5,
                solutionTarget.position,
            },
        }
    end,
    rivalsTargeting = RivalsTargeting,
    projectileAim = RivalsProjectileAim,
    shotPresentation = RivalsShotPresentation,
    weaponPolicy = RivalsWeaponPolicy,
    effects = RivalsEffects,
    movement = RivalsMovement,
    combatState = RivalsCombatState,
    pickWeaponsPage = {
        IsOpen = function()
            return loadoutOpen
        end,
    },
    store = store,
    wait = function() end,
})

assert(loadedModuleChecks == 2, "RIVALS startup must yield until both game controllers are loaded")
assert(renderCallback, "RIVALS adapter must attach a resilient per-frame loop")
renderCallback()
assert(rendered.observations == state.observations and rendered.position == mousePosition)
assert(
    throwableObserveCalls == 1
        and #rendered.utilities == 1
        and rendered.utilities[1] == throwableObservation
        and state.utilityObservations.count == 1,
    "RIVALS must publish active-match throwable observations through Utility ESP"
)
assert(table.find(Rivals.capabilities, "utilityEsp") ~= nil)
assert(
    #rendered.observations == 2 and rendered.observations[2] == rangeObservation,
    "RIVALS observation pipeline must keep only the near player and range dummy"
)
assert(
    table.find(rendered.observations, farObservation) == nil,
    "RIVALS ESP and aim must exclude observations beyond 2,000 studs"
)
assert(state.activeWeapon == "Burst Rifle")
assert(state.status == "Shooting range · 2 dummies · 2 visible")
assert(observations[1].health == 150 and observations[1].maxHealth == 150)
assert(
    observations[1].weapon == "Riot Shield (52/100)",
    "RIVALS ESP must publish the live Riot Shield durability label"
)
fighterModule._player_to_fighter[enemyPlayer].EquippedItem = targetItem
assert(rangeObservation.player == rangeTarget)
assert(rangeObservation.health == 150 and rangeObservation.maxHealth == 150)
assert(
    rotationCalls == 1
        and cameraModule.Rotation == RivalsTargeting.rotationToward(origin, targetPosition)
        and nearestOptions[1].maxScreenDistance == 180,
    "Camera Aim must ignore a closer-to-crosshair target beyond the ESP distance cap"
)
assert(clicks == 0, "Camera Aim must not fire unless Trigger Bot is enabled")

local challengerPosition = targetPosition + Vector3.new(6, 0, 0)
local challenger = {
    character = character(150),
    player = enemyPlayer,
    position = challengerPosition,
    screenDistance = 10,
    visible = true,
}
table.insert(observations, 1, challenger)
renderCallback()
assert(
    cameraModule.Rotation == RivalsTargeting.rotationToward(origin, targetPosition),
    "RIVALS aim must retain its current valid target instead of switching to a closer observation"
)
observations[2].screenDistance = settings.fov + 1
renderCallback()
assert(
    cameraModule.Rotation == RivalsTargeting.rotationToward(origin, challengerPosition),
    "RIVALS aim must acquire a new target after the locked target leaves the configured FOV"
)
table.remove(observations, 1)
observations[1].screenDistance = 40
renderCallback()

do
    settings.silentAim = false
    settings.shotAim = true
    settings.triggerBot = true
    cameraModule.Rotation = Vector2.new(0.2, -0.4)
    cameraHarness.camera.CFrame =
        cameraHarness.frameForRotation(cameraModule.Rotation)
    local visibleRotation = cameraModule.Rotation
    local visibleFrame = cameraHarness.camera.CFrame
    local clicksBeforePresentedTarget = clicks
    triggerCameraCaptureEnabled = true
    renderCallback()
    assert(
        clicks == clicksBeforePresentedTarget,
        "Trigger Bot + Silent Aim must wait until the matching native camera frame is presented"
    )
    cameraHarness.runCameraRenderFrame()
    currentTime += 1
    renderCallback()
    triggerCameraCaptureEnabled = false
    assert(
        clicks == clicksBeforePresentedTarget + 1
            and triggerCameraDataAtClick ~= nil
            and triggerRayAtClick ~= nil,
        "Trigger Bot + Silent Aim must fire through GetCameraData after presentation is ready"
    )
    local triggerRecord = triggerCameraDataAtClick[cameraByte0]
    local triggerOrigin = Vector3.new(
        triggerRecord[cameraByte0],
        triggerRecord[cameraByte1],
        triggerRecord[cameraByte2]
    )
    local triggerRotation =
        RivalsTargeting.rotationToward(triggerOrigin, targetPosition)
    assert(
        triggerRecord[cameraByte3] == triggerRotation.X
            and triggerRecord[cameraByte4] == triggerRotation.Y
            and triggerRayAtClick.Position ~= originalRay.Position,
        "Trigger Bot + Silent Aim must present the matching target during synchronous GetCameraData"
    )
    assert(
        cameraHarness.boundCount == 2
            and cameraHarness.rotationDeltaCallback ~= nil,
        "RIVALS Silent Aim must split logical and rendered camera updates around the native camera step"
    )
    local preCameraBindings = 0
    local postCameraBindings = 0
    for _, binding in pairs(cameraHarness.bound) do
        if binding.priority == Enum.RenderPriority.Camera.Value - 1 then
            preCameraBindings += 1
        elseif binding.priority == Enum.RenderPriority.Camera.Value + 1 then
            postCameraBindings += 1
        end
    end
    assert(
        preCameraBindings == 1 and postCameraBindings == 1,
        "RIVALS Silent Aim must run at deterministic priorities around the native camera step"
    )
    cameraHarness.runCameraRenderFrame()
    local cameraDataHook =
        hookImplementations[fighterModule.LocalFighter.GetCameraData]
    assert(
        cameraDataHook,
        "RIVALS Silent Aim must hook the natural shot camera-data seam"
    )
    local hookEnvironment = getfenv(cameraDataHook)
    local previousProtectedCall = rawget(hookEnvironment, "pcall")
    local nativeProtectedCall = pcall
    hookEnvironment.pcall = function()
        error("the live ClientFighter VM rejects protected camera-data calls")
    end
    local silentCameraData, silentRay =
        cameraDataHook(fighterModule.LocalFighter)
    hookEnvironment.pcall = previousProtectedCall or nativeProtectedCall
    local silentRecord = silentCameraData[cameraByte0]
    local silentOrigin = Vector3.new(
        silentRecord[cameraByte0],
        silentRecord[cameraByte1],
        silentRecord[cameraByte2]
    )
    local silentRotation = RivalsTargeting.rotationToward(silentOrigin, targetPosition)
    assert(
        silentRecord[cameraByte3] == silentRotation.X
            and silentRecord[cameraByte4] == silentRotation.Y
            and silentRay.Position ~= originalRay.Position,
        "RIVALS Silent Aim must return a complete natural target-bound camera snapshot"
    )
    assert(
        cameraHarness.cameraDataRotationAtCall == silentRotation
            and cameraHarness.cameraDataFrameAtCall.LookVector:Dot(
                (
                    targetPosition
                    - cameraHarness.cameraDataFrameAtCall.Position
                ).Unit
            ) > 0.999,
        "RIVALS Silent Aim must expose the matching native logical and rendered target state only during camera-data generation"
    )
    assert(
        cameraModule.Rotation == silentRotation
            and cameraHarness.camera.CFrame.LookVector:Dot(
                visibleFrame.LookVector
            ) > 0.999,
        "RIVALS Silent Aim must retain trusted logical aim while preserving the rendered view"
    )
    local visibleDelta = Vector2.new(0.05, 0.1)
    cameraModule.Rotation += visibleDelta
    cameraHarness.rotationDeltaCallback(visibleDelta)
    cameraHarness.runCameraRenderFrame()
    local movedVisibleRotation = visibleRotation + visibleDelta
    assert(
        cameraModule.Rotation == silentRotation
            and cameraHarness.camera.CFrame.LookVector:Dot(
                cameraHarness.frameForRotation(movedVisibleRotation).LookVector
            ) > 0.999,
        "RIVALS Silent Aim must preserve native mouse movement in the masked rendered view"
    )
    settings.shotAim = false
    settings.triggerBot = false
    clicks = clicksBeforePresentedTarget
    renderCallback()
    cameraHarness.runCameraRenderFrame()
    assert(
        cameraModule.Rotation == movedVisibleRotation
            and cameraHarness.camera.CFrame.LookVector:Dot(
                cameraHarness.frameForRotation(movedVisibleRotation).LookVector
            ) > 0.999,
        "Disabling RIVALS Silent Aim must restore the latest visible camera rotation"
    )
    settings.silentAim = true
end

local closestRuntimePosition = origin + Vector3.new(3, 0, -4)
local closestRuntimeTarget = {
    character = character(150),
    player = enemyPlayer,
    position = closestRuntimePosition,
    screenDistance = 100,
    visible = true,
}
table.insert(observations, closestRuntimeTarget)
settings.humanAim = true
cameraModule.Rotation = Vector2.zero
local nearestCallsBeforeHumanAim = #nearestOptions
currentTime += 1
renderCallback(1 / 60)
local closestRotation = RivalsTargeting.rotationToward(origin, closestRuntimePosition)
assert(
    #nearestOptions == nearestCallsBeforeHumanAim,
    "Human Aim must bypass cursor-distance target ranking"
)
assert(
    (cameraModule.Rotation - closestRotation).Magnitude < closestRotation.Magnitude
        and cameraModule.Rotation ~= closestRotation,
    "Human Aim must smoothly move toward the physically closest eligible target"
)
table.remove(observations, assert(table.find(observations, closestRuntimeTarget)))
settings.humanAim = false

local runtimeAimRoot = {
    CFrame = CFrame.new(targetPosition),
    Position = targetPosition,
    Size = Vector3.new(2, 2, 1),
}
local runtimeAimHead = {
    Name = "Head",
    Position = targetPosition + Vector3.new(0, 2, 0),
}
target.character.FindFirstChild = function(_self, name)
    return ({ Head = runtimeAimHead, HumanoidRootPart = runtimeAimRoot })[name]
end
settings.headshotRate = 100
currentTime += 1
renderCallback()
assert(
    cameraModule.Rotation == RivalsTargeting.rotationToward(origin, runtimeAimHead.Position),
    "Camera Aim must apply the configured headshot rate to its live selected target"
)
settings.headshotRate = 0
currentTime += 0.01
renderCallback()
assert(
    cameraModule.Rotation == RivalsTargeting.rotationToward(origin, runtimeAimRoot.Position),
    "Camera Aim must invalidate a cached head plan immediately when Headshot Rate changes"
)
runtimeAimRoot.Position += Vector3.new(4, 0, 0)
currentTime += 0.01
renderCallback()
assert(
    cameraModule.Rotation == RivalsTargeting.rotationToward(origin, runtimeAimRoot.Position),
    "Camera Aim must refresh the selected body point instead of reusing the fresh raw Head position during a cached body plan"
)
runtimeAimRoot.Position = targetPosition
settings.missRate = 100
currentTime += 0.01
renderCallback()
assert(
    cameraModule.Rotation
        == RivalsTargeting.rotationToward(origin, targetPosition + Vector3.new(3.5, 0, 0)),
    "Camera Aim must invalidate a cached body plan immediately when Miss Rate changes"
)
settings.missRate = 0
settings.humanAim = true
cameraModule.Rotation = Vector2.zero
for _ = 1, 24 do
    currentTime += 1 / 60
    renderCallback(1 / 60)
end
assert(
    (cameraModule.Rotation - RivalsTargeting.rotationToward(origin, runtimeAimRoot.Position)).Magnitude
        < (cameraModule.Rotation - RivalsTargeting.rotationToward(origin, runtimeAimHead.Position)).Magnitude,
    "Human Aim with a 0% Headshot Rate must converge on the visible body candidate"
)
settings.headshotRate = 100
cameraModule.Rotation = Vector2.zero
for _ = 1, 24 do
    currentTime += 1 / 60
    renderCallback(1 / 60)
end
assert(
    (cameraModule.Rotation - RivalsTargeting.rotationToward(origin, runtimeAimHead.Position)).Magnitude
        < (cameraModule.Rotation - RivalsTargeting.rotationToward(origin, runtimeAimRoot.Position)).Magnitude,
    "Human Aim with a 100% Headshot Rate must converge on Head"
)
settings.humanAim = false
settings.headshotRate = 0

settings.humanAim = true
settings.headshotRate = 100
settings.aimSmoothness = 70
cameraModule.Rotation = Vector2.zero
currentTime += 1
renderCallback(1 / 60)
local humanHeadStart = cameraModule.Rotation
runtimeAimHead.Position += Vector3.new(8, 0, 0)
local movedHeadRotation = RivalsTargeting.rotationToward(origin, runtimeAimHead.Position)
local fixedHeadFollow = RivalsTargeting.smoothRotation(humanHeadStart, movedHeadRotation, 70, 1 / 60)
currentTime += 1 / 60
renderCallback(1 / 60)
assert(
    (movedHeadRotation - cameraModule.Rotation).Magnitude
        < (movedHeadRotation - fixedHeadFollow).Magnitude,
    "Human Aim must refresh the moving head position and speed up enough to keep it relatively tracked"
)
assert(cameraModule.Rotation ~= movedHeadRotation, "Human Aim must stay imperfect instead of hard-locking the head")
settings.humanAim = false
settings.headshotRate = 0
runtimeAimHead.Position = targetPosition + Vector3.new(0, 2, 0)

local clicksBeforeSmoothAim = clicks
settings.aimSmoothness = 100
settings.triggerBot = true
cameraModule.Rotation = Vector2.zero
currentTime += 1
renderCallback(1 / 60)
assert(
    clicks == clicksBeforeSmoothAim,
    "Trigger Bot must wait while smoothed Camera Aim is still converging"
)
local smoothFrames = 0
repeat
    smoothFrames += 1
    currentTime += 1 / 60
    renderCallback(1 / 60)
until clicks > clicksBeforeSmoothAim or smoothFrames == 300
assert(
    clicks == clicksBeforeSmoothAim + 1 and smoothFrames > 1,
    "Trigger Bot must fire after smoothed Camera Aim reaches the target"
)
clicks = clicksBeforeSmoothAim
settings.aimSmoothness = 0
settings.triggerBot = false
currentTime += 1

fighterModule.LocalFighter.Data.IsInShootingRange = false
fighterModule.LocalFighter.Data.IsSpectating = true
local duelRotationCalls = rotationCalls
renderCallback()
assert(
    rotationCalls == duelRotationCalls + 1,
    "An alive local camera subject must remain active when RIVALS reports IsSpectating during a duel"
)

activeDuel.Data.Status = "Voting"
local votingRotationCalls = rotationCalls
renderCallback()
assert(
    rotationCalls == votingRotationCalls,
    "Map and weapon voting must suspend Camera Aim before a duel round starts"
)

activeDuel.Data.Status = "RoundStarting"
local preRoundRotationCalls = rotationCalls
renderCallback()
assert(
    rotationCalls == preRoundRotationCalls,
    "The duel countdown must suspend Camera Aim until Status is RoundStarted"
)

activeDuel.Data.Status = "RoundStarted"
fighterModule.LocalFighter.Data.CanPickWeapons = true
loadoutOpen = true
local matchLoadoutRotationCalls = rotationCalls
renderCallback()
assert(
    rotationCalls == matchLoadoutRotationCalls,
    "Generic match loadout selection must suspend Camera Aim"
)

fighterModule.LocalFighter.Data.IsInDuel = false
fighterModule.LocalFighter.Data.IsInShootingRange = true
local rangeLoadoutRotationCalls = rotationCalls
renderCallback()
assert(
    rotationCalls == rangeLoadoutRotationCalls,
    "Practice-range loadout selection must suspend Camera Aim"
)

loadoutOpen = false
local rangeCombatRotationCalls = rotationCalls
renderCallback()
assert(
    rotationCalls == rangeCombatRotationCalls + 1,
    "Practice-range combat must resume after the picker closes even while weapon-pick permission remains true"
)

settings.silentAim = false
settings.triggerBot = true
fighterModule.LocalFighter.Data.CanPickWeapons = false
fighterModule.LocalFighter.Data.IsInShootingRange = false
fighterModule.LocalFighter.Data.IsInDuel = false
target.screenDistance = 4
observations[1].screenDistance = 4
rangeObservation.screenDistance = 4
local lobbyClicks = clicks
renderCallback()
assert(
    clicks == lobbyClicks,
    "Trigger Bot must not target players outside a match or the shooting range"
)
assert(#rendered.utilities == 0, "Throwable ESP must not render unrelated lobby projectiles")

fighterModule.LocalFighter.Data.IsInDuel = true
fighterModule.LocalFighter.Data.IsInShootingRange = true
target.screenDistance = 40
observations[1].screenDistance = 40
rangeObservation.screenDistance = 40
renderCallback()
assert(clicks == 0, "Trigger Bot must not fire at an enemy outside the crosshair radius")
assert(nearestOptions[#nearestOptions].maxScreenDistance == 8)

target.screenDistance = 4
observations[1].screenDistance = 4
rangeObservation.screenDistance = 4
renderCallback()
assert(clicks == 1, "Trigger Bot must use normal input only when a visible enemy crosses the reticle")

for _, utilityName in ipairs({
    "Medkit",
    "Subspace Tripmine",
    "Warpstone",
    "Jump Pad",
    "War Horn",
    "Grappler",
    "Flashbang",
    "Grenade",
    "Molotov",
    "Satchel",
    "Smoke Grenade",
}) do
    localItem.Name = utilityName
    localItem.Info = { DisplayName = utilityName }
    localItem.Data = {}
    settings.silentAim = true
    settings.shotAim = false
    currentTime += 1
    local cameraAimInputs = {
        aimClicks = aimClicks,
        aimPresses = aimPresses,
        aimReleases = aimReleases,
        clicks = clicks,
        presses = presses,
        releases = releases,
        rotations = rotationCalls,
    }
    renderCallback()
    assert(
        rotationCalls == cameraAimInputs.rotations
            and clicks == cameraAimInputs.clicks
            and presses == cameraAimInputs.presses
            and releases == cameraAimInputs.releases
            and aimClicks == cameraAimInputs.aimClicks
            and aimPresses == cameraAimInputs.aimPresses
            and aimReleases == cameraAimInputs.aimReleases,
        ("%s must not select a Camera Aim target or dispatch Trigger Bot input"):format(utilityName)
    )

    settings.silentAim = false
    settings.shotAim = true
    currentTime += 1
    renderCallback()
    cameraHarness.runCameraRenderFrame()
    assert(
        rotationCalls == cameraAimInputs.rotations
            and clicks == cameraAimInputs.clicks
            and presses == cameraAimInputs.presses
            and releases == cameraAimInputs.releases
            and aimClicks == cameraAimInputs.aimClicks
            and aimPresses == cameraAimInputs.aimPresses
            and aimReleases == cameraAimInputs.aimReleases,
        ("%s must not publish a Silent Aim target or dispatch Trigger Bot input"):format(utilityName)
    )
end
localItem.Name = "Burst Rifle"
localItem.Info = { DisplayName = "Burst Rifle" }
localItem.Data = {}
settings.silentAim = false
settings.shotAim = false

fighterModule._player_to_fighter[enemyPlayer].EquippedItem = {
    Name = "Katana",
    Data = { FOVOffset = 5 },
    Info = { DisplayName = "Katana" },
}
currentTime += 1
local deflectClicks = clicks
renderCallback()
assert(
    clicks == deflectClicks,
    "Trigger Bot must not fire while the target's Katana is actively deflecting"
)
fighterModule._player_to_fighter[enemyPlayer].EquippedItem.Data.FOVOffset = 0
currentTime += 1
renderCallback()
assert(
    clicks == deflectClicks + 1,
    "Trigger Bot must resume once the target's Katana deflection ends"
)
fighterModule._player_to_fighter[enemyPlayer].EquippedItem = targetItem
clicks = deflectClicks

localItem.Name = "RPG"
localItem.Info = {
    DamageType = "Splash",
    DisplayName = "RPG",
    IsProjectile = true,
    ProjectileGravity = 0,
    ProjectileLifetime = 5,
    ProjectileSpeed = 100,
    ShootExplosionRadius = 16,
}
settings.silentAim = true
currentTime += 1
local unsafeSplashClicks = clicks
local unsafeSplashRotations = rotationCalls
renderCallback()
assert(
    rotationCalls == unsafeSplashRotations,
    "Splash Camera Aim must not fall back to a direct player shot without a verified environment impact"
)
assert(
    clicks == unsafeSplashClicks,
    "Splash Trigger Bot must not fire when Camera Aim cannot verify an environment impact"
)

settings.silentAim = false
currentTime += 1
renderCallback()
assert(
    clicks == unsafeSplashClicks,
    "Splash Trigger Bot must independently require a verified environment impact"
)

environmentCast = floorRaycast
settings.silentAim = true
currentTime += 1
renderCallback()
assert(
    rotationCalls == unsafeSplashRotations + 1 and clicks == unsafeSplashClicks + 1,
    "Splash Camera Aim and Trigger Bot must use a verified environment impact"
)

do
environmentCast = function()
    return nil
end
local staleSplashClicks = clicks
local staleSplashRotations = rotationCalls
renderCallback()
assert(
    rotationCalls == staleSplashRotations and clicks == staleSplashClicks,
    "Splash Camera Aim and Trigger Bot must discard a cached impact when its environment geometry changes"
)
end

clicks = unsafeSplashClicks
environmentCast = function()
    return nil
end
localItem.Name = "Burst Rifle"
localItem.Info = { DisplayName = "Burst Rifle" }
settings.silentAim = false
localItem.Info.AimScopePercent = 0.5
localItem.Data = { IsAiming = true }
cameraModule._fov_weapons_spring = { Value = 0, Target = -50 }
currentTime += 1
renderCallback()
assert(clicks == 1, "Trigger Bot must wait while a scoped weapon is still entering ADS")
cameraModule._fov_weapons_spring.Value = -49.75
renderCallback()
assert(clicks == 2, "Trigger Bot must fire once the scoped weapon finishes entering ADS")

do
local previousPart = observations[1].part
localItem.Name = "Sniper"
localItem.Info = {
    AimScopePercent = 0.5,
    DisplayName = "Sniper",
    ShootSpread = 15,
}
localItem.Data = { IsAiming = false }
local fullyAiming = false
localItem.IsFullyAiming = function()
    return fullyAiming
end
observations[1].part = {
    Name = "Torso",
    Size = Vector3.new(2, 2, 1),
}
crouching = false
observations[1].position = origin + Vector3.new(0, 0, -30)
runtimeAimRoot.Position = observations[1].position
currentTime += 1
local sniperClicks = clicks
renderCallback()
assert(
    clicks == sniperClicks,
    "Adapter Trigger Bot must wait for an unreliable far unscoped Sniper shot"
)

observations[1].position = origin + Vector3.new(0, 0, -6)
runtimeAimRoot.Position = observations[1].position
settings.shotAim = true
currentTime += 1
renderCallback()
assert(
    clicks == sniperClicks,
    "Silent Aim Sniper Trigger Bot must wait for the matching presented target"
)
cameraHarness.runCameraRenderFrame()
currentTime += 1
renderCallback()
assert(
    clicks == sniperClicks + 1,
    "Silent Aim Sniper Trigger Bot must fire a reliable close unscoped shot after presentation"
)
settings.shotAim = false

localItem.Data.IsAiming = true
cameraModule._fov_weapons_spring = { Value = -49.75, Target = -50 }
currentTime += 1
renderCallback()
assert(
    clicks == sniperClicks + 1,
    "Adapter Trigger Bot must wait while native Sniper ADS is incomplete"
)
fullyAiming = true
currentTime += 1
renderCallback()
assert(
    clicks == sniperClicks + 2,
    "Adapter Trigger Bot must fire after native Sniper ADS settles"
)

localItem.Data.IsAiming = false
fullyAiming = false
observations[1].position = origin + Vector3.new(0, 0, -9)
runtimeAimRoot.Position = observations[1].position
crouching = false
currentTime += 1
renderCallback()
assert(
    clicks == sniperClicks + 2,
    "Adapter Trigger Bot must keep standing no-scopes inside the reliable spread range"
)
crouching = true
currentTime += 1
renderCallback()
assert(
    clicks == sniperClicks + 3,
    "Adapter Trigger Bot must extend reliable no-scope range while crouching"
)

crouching = false
localItem.IsFullyAiming = nil
observations[1].part = previousPart
observations[1].position = targetPosition
runtimeAimRoot.Position = targetPosition
end

localItem.Name = "Shorty"
localItem.Info = table.clone(shorty.Info)
localItem.Info.DisplayName = "Shorty"
localItem.Data = {}
observations[1].position = origin + Vector3.new(20, 0, 0)
currentTime += 1
local falloffClicks = clicks
renderCallback()
assert(
    clicks == falloffClicks,
    "Trigger Bot must wait when a high-falloff shot is neither near-full damage nor lethal"
)
target.character.FindFirstChildOfClass = function(_self, className)
    if className == "Humanoid" then
        return {
            Health = 40,
            MaxHealth = 150,
        }
    end
    return nil
end
currentTime += 1
renderCallback()
assert(clicks == falloffClicks + 1, "Trigger Bot must fire the same falloff shot once it becomes lethal")
observations[1].position = targetPosition

do
localItem.Name = "Gunblade"
localItem.Info = gunblade.Info
localItem.Data = {}
localItem.GetMobileInputSettings = gunblade.GetMobileInputSettings
localItem.CanQuickAttack = gunblade.CanQuickAttack
fighterModule.LocalFighter.Entity.RootPart = {
    Position = origin,
}
gunbladeMode = "blade"
settings.shotAim = true
settings.silentAim = false
local silentGunbladeAimClicks = aimClicks
renderCallback()
assert(
    aimClicks == silentGunbladeAimClicks,
    "Gunblade Trigger Bot + Silent Aim must wait for the matching presented target"
)
cameraHarness.runCameraRenderFrame()
currentTime += 1 / 60
renderCallback()
assert(
    aimClicks == silentGunbladeAimClicks + 1,
    "Gunblade Trigger Bot + Silent Aim must act only after the matching target is presented"
)
settings.triggerBot = false
renderCallback()
settings.shotAim = false
settings.triggerBot = true
currentTime += gunblade.Info.DashCooldown
currentTime += 1
local gunbladeAimClicks = aimClicks
local gunbladeClicks = clicks
renderCallback()
assert(
    aimClicks == gunbladeAimClicks + 1 and clicks == gunbladeClicks,
    "Gunblade Trigger Bot must dispatch the Blade-mode dash through secondary input"
)
fighterModule.LocalFighter.Entity.RootPart.Position = targetPosition - Vector3.xAxis * 7
currentTime += 1 / 60
renderCallback()
assert(
    clicks == gunbladeClicks + 1,
    "Gunblade Trigger Bot must slice on the first frame that the live dash enters blade reach"
)
gunbladeMode = "gun"
currentTime += 1 / 60
renderCallback()
assert(
    clicks == gunbladeClicks + 1,
    "Gunblade Trigger Bot must respect the live transition cooldown before shooting"
)
currentTime += gunblade.Info.TransitionCooldown
renderCallback()
assert(
    clicks == gunbladeClicks + 2,
    "Gunblade Trigger Bot must fire after the live item reports its Gun-mode transition"
)
gunbladeMode = "blade"
currentTime += 1 / 60
renderCallback()
assert(
    aimClicks == gunbladeAimClicks + 1,
    "Gunblade Trigger Bot must respect the dash cooldown before repeating"
)
currentTime += gunblade.Info.DashCooldown
renderCallback()
assert(
    aimClicks == gunbladeAimClicks + 2,
    "Gunblade Trigger Bot must repeat from Blade mode while the same target remains eligible"
)
fighterModule.LocalFighter.Entity.RootPart = nil
localItem.GetMobileInputSettings = nil
localItem.CanQuickAttack = nil
localItem.Name = "Shorty"
localItem.Info = table.clone(shorty.Info)
localItem.Info.DisplayName = "Shorty"
localItem.Data = {}
end

fighterModule.LocalFighter.Data.IsInShootingRange = false
settings.silentAim = true
settings.humanAim = true
settings.headshotRate = 100
settings.aimSmoothness = 100
cameraModule.Rotation = RivalsTargeting.rotationToward(origin, runtimeAimHead.Position)
    + Vector2.new(0, math.rad(4))
local humanShortyClicks = clicks
for _ = 1, 3 do
    currentTime += 0.125
    runtimeAimHead.Position += Vector3.new(0.1, 0, 0)
    renderCallback(1 / 60)
end
assert(
    clicks == humanShortyClicks + 3,
    "Human Aim Trigger Bot must keep firing Shorty while its imperfect tracking stays inside the reticle envelope"
)
fighterModule.LocalFighter.Data.IsInShootingRange = true
settings.silentAim = false
settings.humanAim = false
settings.headshotRate = 0
settings.aimSmoothness = 0
runtimeAimHead.Position = targetPosition + Vector3.new(0, 2, 0)

localItem.Name = "Bow"
localItem.Info = bow.Info
localItem.Info.DisplayName = "Bow"
localItem.Info.ChargeReleaseCooldown = 1
localItem.Data = {}
target.character.FindFirstChildOfClass = function(_self, className)
    if className == "Humanoid" then
        return {
            Health = 40,
            MaxHealth = 150,
        }
    end
    return nil
end
observations[1].part = { Name = "Torso" }
currentTime += 1
renderCallback()
assert(
    aimPresses == 1 and aimReleases == 0 and presses == 0,
    "Bow Trigger Bot must begin charging through the held aiming action"
)
currentTime += 0.9
renderCallback()
assert(aimReleases == 0, "Bow Trigger Bot must keep holding before the shortest lethal charge")
currentTime += 0.1
renderCallback()
assert(aimReleases == 1, "Bow Trigger Bot must release aiming at the shortest lethal body-shot charge")

target.character.FindFirstChildOfClass = function(_self, className)
    if className == "Humanoid" then
        return {
            Health = 30,
            MaxHealth = 150,
        }
    end
    return nil
end
currentTime += 1
local quickBowClicks = clicks
renderCallback()
assert(
    clicks == quickBowClicks + 1 and aimPresses == 1 and aimReleases == 1,
    "Bow Trigger Bot must tap primary fire when one faster uncharged shot is lethal"
)

do
    local practiceBowPresses = aimPresses
    local practiceBowClicks = clicks
    local practiceEnemyScreenDistance = observations[1].screenDistance
    local practiceDummyScreenDistance = rangeObservation.screenDistance
    observations[1].screenDistance = settings.fov + 1
    rangeObservation.screenDistance = 4
    rangeObservation.part = { Name = "Torso" }
    currentTime += 1
    renderCallback()
    assert(
        rangeObservation.health == 150 and rangeObservation.maxHealth == 150,
        "Infinite-health practice dummies must expose representative full player health"
    )
    assert(
        aimPresses == practiceBowPresses + 1 and clicks == practiceBowClicks,
        "Bow Trigger Bot must charge practice dummies through ADS instead of primary-clicking"
    )
    settings.triggerBot = false
    renderCallback()
    settings.triggerBot = true
    observations[1].screenDistance = practiceEnemyScreenDistance
    rangeObservation.screenDistance = practiceDummyScreenDistance
    rangeObservation.part = nil
end

do
localItem.Name = "Revolver"
localItem.Info = table.clone(revolver.Info)
localItem.Info.DisplayName = "Revolver"
localItem.Data = {
    Ammo = 6,
}
localItem._is_revolver_quick_shooting = nil
localItem._reload_cancel_cooldown = 0
localItem._reload_cancel_expiration = 0
localItem._reload_cooldown = 0
localItem._shoot_cooldown = 0
localItem.IsEquipping = revolver.IsEquipping
target.character.FindFirstChildOfClass = function(_self, className)
    if className == "Humanoid" then
        return {
            Health = 30,
            MaxHealth = 150,
        }
    end
    return nil
end
observations[1].part = {
    Name = "Torso",
    Size = Vector3.new(2, 2, 1),
}
observations[1].position = origin + Vector3.new(0, 0, -30)
currentTime += 1
local revolverInputCounts = {
    clicks = clicks,
    aimClicks = aimClicks,
    aimPresses = aimPresses,
    aimReleases = aimReleases,
}
renderCallback()
assert(
    clicks == revolverInputCounts.clicks + 1
        and aimClicks == revolverInputCounts.aimClicks
        and aimPresses == revolverInputCounts.aimPresses
        and aimReleases == revolverInputCounts.aimReleases,
    "Revolver precise fire must use normal primary without invoking the quick-shot StartAiming override"
)

target.character.FindFirstChildOfClass = function(_self, className)
    if className == "Humanoid" then
        return {
            Health = 100,
            MaxHealth = 150,
        }
    end
    return nil
end
observations[1].position = origin + Vector3.new(0, 0, -4)
currentTime += 1
revolverInputCounts.clicks = clicks
revolverInputCounts.aimClicks = aimClicks
revolverInputCounts.aimPresses = aimPresses
renderCallback()
assert(
    clicks == revolverInputCounts.clicks
        and aimClicks == revolverInputCounts.aimClicks + 1
        and aimPresses == revolverInputCounts.aimPresses,
    "Revolver fan fire must use the item-specific StartAiming quick-shot input"
)
observations[1].position = targetPosition
end

localItem.Name = "Flamethrower"
localItem.Info = {
    DisplayName = "Flamethrower",
    InputSpammingEnabled = { StartShooting = 0 },
    InternalUseCooldown = 0.25,
    MaxAmmo = 100,
}
localItem.Data = {}
currentTime += 1
local flamethrowerPresses = presses
local flamethrowerReleases = releases
local flamethrowerClicks = clicks
renderCallback()
assert(
    presses == flamethrowerPresses + 1 and clicks == flamethrowerClicks,
    "Flamethrower Trigger Bot must press primary fire once instead of clicking repeatedly"
)
currentTime += 0.05
renderCallback()
assert(
    presses == flamethrowerPresses + 1 and releases == flamethrowerReleases,
    "Flamethrower Trigger Bot must remain held without repeating the press"
)
target.screenDistance = 40
observations[1].screenDistance = 40
rangeObservation.screenDistance = 40
renderCallback()
assert(
    releases == flamethrowerReleases + 1,
    "Held automatic fire must release immediately when no target is inside the trigger radius"
)
target.screenDistance = 4
observations[1].screenDistance = 4
rangeObservation.screenDistance = 4

localItem.Name = "Slingshot"
localItem.Info = {
    DisplayName = "Slingshot",
    ProjectileGravity = 1,
    ProjectileLifetime = 5,
    ProjectileMaxHits = 3,
    ProjectileRaycastRadius = 0.375,
    ProjectileSpeed = 300,
    ShootCooldown = 0.1,
}
settings.silentAim = true
settings.triggerBot = false
currentTime += 1
renderCallback(1 / 60)
settings.humanAim = true
settings.aimSmoothness = 100
settings.triggerBot = true
local slingshotRotation = RivalsTargeting.rotationToward(origin, runtimeAimHead.Position)
cameraModule.Rotation = slingshotRotation + Vector2.new(0, math.rad(20))
local slingshotClicks = clicks
local slingshotFrames = 0
repeat
    slingshotFrames += 1
    currentTime += 1 / 60
    renderCallback(1 / 60)
until clicks > slingshotClicks or slingshotFrames == 180
assert(slingshotSolves >= 1, "Human Aim must calculate a verified Slingshot bounce immediately")
assert(
    clicks == slingshotClicks + 1 and slingshotFrames > 1 and slingshotFrames <= 30,
    ("Human Aim must release a verified Slingshot path promptly (took %d frames)"):format(
        slingshotFrames
    )
)
settings.humanAim = false
settings.aimSmoothness = 0

localItem.Name = "Energy Rifle"
localItem.Info = {
    DisplayName = "Energy Rifle",
}
observations[1].visible = false
rangeObservation.visible = false
settings.silentAim = true
currentTime += 1
local ricochetClicks = clicks
local ricochetRotations = rotationCalls
renderCallback()
assert(
    ricochetSolves == 1,
    ("Energy Rifle Camera Aim must request one cached ricochet solution (got %d)"):format(ricochetSolves)
)
assert(rotationCalls == ricochetRotations + 1, "A verified ricochet must rotate toward the bounce wall")
assert(
    clicks == ricochetClicks + 1,
    "Trigger Bot must fire through normal input when Camera Aim verifies an Energy Rifle bounce"
)
assert(
    #trajectoryNodes == 2
        and trajectoryNodes[1].properties.Visible
        and trajectoryNodes[2].properties.Visible,
    "Bounce ESP must draw every verified Energy Rifle wall segment"
)

local knifeRoot = {
    AssemblyLinearVelocity = Vector3.zero,
    CFrame = CFrame.lookAt(targetPosition, targetPosition + Vector3.xAxis),
    Position = targetPosition,
}
target.character.FindFirstChild = function(_self, name)
    return name == "HumanoidRootPart" and knifeRoot or nil
end
fighterModule.LocalFighter.Entity.RootPart = {
    AssemblyLinearVelocity = Vector3.zero,
    Position = targetPosition + Vector3.xAxis * 18.5,
}
localItem.Name = "Knife"
localItem.Info = {
    AttackReach = 6,
    HeavyAttackCooldown = 1.25,
    HeavyAttackReach = 7,
    CriticalDamage = 150,
    DisplayName = "Knife",
}
grounded = true
observations[1].visible = true
observations[1].screenDistance = settings.fov + 100
fighterModule.LocalFighter.Entity.RootPart.Position = targetPosition + Vector3.xAxis * 1.5
fighterModule.LocalFighter.Entity.RootPart.AssemblyLinearVelocity = -Vector3.xAxis * 60
currentTime += 2
local predictiveAimClicks = aimClicks
renderCallback(1 / 60)
assert(
    aimClicks == predictiveAimClicks,
    "Knife prediction may pre-turn the camera but must not fire using a future rear position"
)
fighterModule.LocalFighter.Entity.RootPart.Position = targetPosition - Vector3.xAxis * 0.5
currentTime += 1 / 60
renderCallback(1 / 60)
assert(
    aimClicks == predictiveAimClicks + 1,
    "Knife Trigger Bot must heavy-attack as soon as the current position enters the lenient rear window"
)

fighterModule.LocalFighter.Entity.RootPart.Position = targetPosition - Vector3.xAxis * 6.5
fighterModule.LocalFighter.Entity.RootPart.AssemblyLinearVelocity = Vector3.zero
currentTime += 2
local backstabClicks = clicks
local backstabAimClicks = aimClicks
local backstabRotations = rotationCalls
grounded = false
renderCallback()
assert(
    rotationCalls == backstabRotations + 1,
    "Knife Camera Aim must lock only from a lethal rear position"
)
assert(
    clicks == backstabClicks and aimClicks == backstabAimClicks,
    "Knife Trigger Bot must not backstab from a stale airborne rear window"
)
grounded = true
currentTime += 1 / 60
renderCallback()
assert(
    clicks == backstabClicks and aimClicks == backstabAimClicks + 1,
    "Knife Trigger Bot must use secondary fire from current grounded lethal rear geometry"
)

settings.bhop = true
wHeld = false
movementDirection = Vector3.xAxis
sliding = false
grounded = true
canSlide = true
localItem._testKnifeIsSlidingMethod = fighterModule.LocalFighter.IsSliding
fighterModule.LocalFighter.IsSliding = false
localItem._testKnifeHighJumpCalls = highJumpCalls
renderCallback()
fighterModule.LocalFighter.IsSliding = true
currentTime += 1 / 60
renderCallback()
currentTime += 1 / 60
renderCallback()
assert(
    not toggledInputs.Space and highJumpCalls == localItem._testKnifeHighJumpCalls,
    "RIVALS Bunny Hop must suppress high jumps while a Knife backstab is approaching or striking"
)
settings.bhop = false
movementDirection = Vector3.zero
renderCallback()
fighterModule.LocalFighter.IsSliding = localItem._testKnifeIsSlidingMethod
localItem._testKnifeHighJumpCalls = nil
localItem._testKnifeIsSlidingMethod = nil

target.character.FindFirstChildOfClass = function(_self, className)
    if className == "Humanoid" then
        return {
            Health = 151,
            MaxHealth = 151,
        }
    end
    return nil
end
currentTime += 1
local nonlethalClicks = clicks
local nonlethalRotations = rotationCalls
renderCallback()
assert(
    clicks == nonlethalClicks and rotationCalls == nonlethalRotations,
    "Knife must neither turn nor trigger when its backstab cannot eliminate the target"
)

do
localItem.Name = "Burst Rifle"
localItem.Info = { DisplayName = "Burst Rifle" }
settings.bhop = true
wHeld = false
movementDirection = Vector3.xAxis
sliding = false
grounded = true
canSlide = true
local mockedIsSlidingMethod = fighterModule.LocalFighter.IsSliding
fighterModule.LocalFighter.IsSliding = false
local bhopSlideCalls = slideCalls
local bhopHighJumpCalls = highJumpCalls
currentTime += 1
renderCallback()
assert(
    toggledInputs.LeftShift
        and toggledInputs.C
        and not toggledInputs.Space
        and fighterModule.LocalFighter:GetMoveVector() == originalMoveVector,
    "RIVALS Bunny Hop must start the shared automatic slide-jump loop without taking over movement"
)
assert(
    slideCalls == bhopSlideCalls + 1,
    "RIVALS Bunny Hop must invoke the live RIVALS slide mechanic from lateral movement"
)
fighterModule.LocalFighter.IsSliding = true
currentTime += 1 / 60
renderCallback()
currentTime += 1 / 60
renderCallback()
assert(
    toggledInputs.Space and highJumpCalls == bhopHighJumpCalls + 1,
    "RIVALS Bunny Hop must invoke the live high-jump mechanic after the confirmed slide frames"
)
settings.bhop = false
movementDirection = Vector3.zero
renderCallback()
fighterModule.LocalFighter.IsSliding = mockedIsSlidingMethod
assert(
    not toggledInputs.LeftShift and not toggledInputs.C and not toggledInputs.Space,
    "Disabling RIVALS Bunny Hop must clear every synthetic movement input"
)

mechanicsModule._successfulSlide = mechanicsModule.Slide
mechanicsModule.Slide = function(self)
    slideCalls += 1
    if slideCalls >= self._retryStart + 2 then
        self.IsSliding = true
    end
end
mechanicsModule._retryStart = slideCalls
mechanicsModule._retryJumpStart = highJumpCalls
settings.bhop = true
movementDirection = Vector3.xAxis
grounded = true
canSlide = true
fighterModule.LocalFighter.IsSliding = false
mechanicsModule.IsSliding = false
renderCallback()
currentTime += 1 / 60
renderCallback()
currentTime += 1 / 60
renderCallback()
currentTime += 1 / 60
renderCallback()
currentTime += 1 / 60
renderCallback()
currentTime += 1 / 60
renderCallback()
currentTime += 1 / 60
renderCallback()
assert(
    slideCalls == mechanicsModule._retryStart + 2
        and highJumpCalls == mechanicsModule._retryJumpStart + 1,
    "RIVALS Bunny Hop must retry and resume after a slide is rejected during native cooldown"
)
settings.bhop = false
movementDirection = Vector3.zero
renderCallback()
mechanicsModule.Slide = mechanicsModule._successfulSlide
mechanicsModule._successfulSlide = nil
mechanicsModule._retryStart = nil
mechanicsModule._retryJumpStart = nil

for _, direction in ipairs({
    -Vector3.zAxis,
    (Vector3.xAxis - Vector3.zAxis).Unit,
}) do
    local directionalSlideCalls = slideCalls
    settings.bhop = true
    movementDirection = direction
    grounded = true
    canSlide = true
    renderCallback()
    assert(
        slideCalls == directionalSlideCalls + 1,
        "RIVALS Bunny Hop must begin from backward and diagonal movement without requiring W"
    )
    settings.bhop = false
    movementDirection = Vector3.zero
    renderCallback()
end
end

do
inputCaptured = true
settings.silentAim = true
cameraModule.Rotation = Vector2.zero
local capturedClicks = clicks
local capturedPresses = presses
local capturedReleases = releases
local capturedAimPresses = aimPresses
local capturedAimReleases = aimReleases
local capturedAimClicks = aimClicks
renderCallback()
assert(cameraModule.Rotation == Vector2.zero, "The open menu must suppress camera control")
assert(
    clicks == capturedClicks
        and presses == capturedPresses
        and releases == capturedReleases
        and aimPresses == capturedAimPresses
        and aimReleases == capturedAimReleases
        and aimClicks == capturedAimClicks,
    "The open menu must suppress automated input"
)
end

inputCaptured = false
settings.silentAim = false
settings.shotAim = true
settings.humanAim = false
observations[1].screenDistance = 40
observations[1].visible = true
cameraModule.Rotation = Vector2.new(-0.1, 0.25)
cameraHarness.camera.CFrame =
    cameraHarness.frameForRotation(cameraModule.Rotation)
local stopVisibleRotation = cameraModule.Rotation
local stopVisibleFrame = cameraHarness.camera.CFrame
renderCallback()
cameraHarness.runCameraRenderFrame()
assert(
    cameraModule.Rotation ~= stopVisibleRotation,
    "The active-stop contract requires a live logical target rotation"
)
adapter.stop()
adapter.stop()
assert(
    cameraModule.Rotation == stopVisibleRotation
        and cameraHarness.camera.CFrame.LookVector:Dot(
            stopVisibleFrame.LookVector
        ) > 0.999999,
    "Stopping active RIVALS Silent Aim must restore the visible camera immediately"
)
assert(disconnected == true, "Stopping the adapter must disconnect its render loop")
assert(trajectoryDestroyed == true, "Stopping the adapter must destroy bounce ESP drawings")
assert(
    fighterModule.LocalFighter:GetMoveVector() == originalMoveVector,
    "Stopping the adapter must restore the fighter's original movement method"
)
assert(
    restoredHooks[fighterModule.LocalFighter.GetCameraData] == true,
    "Stopping the adapter must restore the natural camera-data function"
)
assert(
    cameraHarness.boundCount == 0
        and cameraHarness.unboundCount == 2
        and cameraHarness.rotationDeltaDisconnected,
    "Stopping the adapter must remove every Silent Aim camera binding"
)
assert(table.find(Rivals.capabilities, "knifeMovement") == nil)
assert(table.find(Rivals.capabilities, "bhop") ~= nil)
print("rivals-adapter-contracts-ok")
