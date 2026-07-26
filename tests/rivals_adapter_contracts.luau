local roblox = require("@lune/roblox")
CFrame = roblox.CFrame
Color3 = roblox.Color3
Enum = roblox.Enum
Vector2 = roblox.Vector2
Vector3 = roblox.Vector3

local Rivals = require("../games/Rivals")

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
        { readinessCamera, readinessFighter, readinessMechanics },
        readinessMechanics
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
    Rivals.closestObservation(
        { cursorCandidate, closestCandidate },
        Vector3.zero,
        { maxScreenDistance = 180 }
    ) == closestCandidate,
    "Human Aim must prioritize physical distance over cursor distance"
)
assert(
    Rivals.closestObservation(
        { cursorCandidate, closestCandidate },
        Vector3.zero,
        { maxScreenDistance = 40 }
    ) == cursorCandidate,
    "Human Aim must still respect the configured camera FOV"
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
    Rivals.closestObservation(
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
    Name = "Head",
    Position = Vector3.new(0, 2, 0),
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
local headAim = Rivals.applyAimRates(baseAimObservation, {
    headshotRate = 100,
    missRate = 0,
}, function()
    return 0
end)
assert(
    headAim.position == aimHead.Position and headAim.part == aimHead and not headAim.intentionalMiss,
    "A 100% headshot rate must aim at the live Head part"
)
local missedAim = Rivals.applyAimRates(baseAimObservation, {
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
    Rivals.applyAimRates(baseAimObservation, {
        headshotRate = 0,
        missRate = 0,
    }, function()
        error("Zero rates must not consume random samples")
    end) == baseAimObservation,
    "Zero accuracy rates must preserve existing targeting behavior"
)

assert(Rivals.itemName({ Info = { DisplayName = "Energy Rifle" }, Name = "Internal" }) == "Energy Rifle")
assert(Rivals.itemName({ Info = { Name = "Handgun" } }) == "Handgun")
assert(Rivals.itemName(nil) == nil)

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
assert(Rivals.adsSettled(scopeCamera, scopedItem) == false)
scopeCamera._fov_weapons_spring.Value = -49.75
assert(Rivals.adsSettled(scopeCamera, scopedItem) == true)
scopedItem.Data.IsAiming = false
assert(Rivals.adsSettled(scopeCamera, scopedItem) == true)

assert(
    Rivals.holdToFire({
        Info = {
            InputSpammingEnabled = { StartShooting = 0 },
            InternalUseCooldown = 0.25,
        },
    }) == true,
    "Flamethrower-style continuous weapons must hold primary fire"
)
assert(
    Rivals.holdToFire({
        Info = {
            InputSpammingEnabled = { StartShooting = 0 },
            ShootCooldown = 0.07,
        },
    }) == true,
    "Fast automatic weapons must hold primary fire"
)
assert(
    Rivals.holdToFire({
        Info = {
            InputSpammingEnabled = { StartShooting = false },
            ShootCooldown = 0.125,
        },
    }) == false,
    "Tap-fire weapons must not be inferred as automatic from cooldown alone"
)
assert(
    Rivals.holdToFire({
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
assert(Rivals.bowChargeTime(bow, { health = 40, part = { Name = "Torso" } }) == 1)
assert(Rivals.bowChargeTime(bow, { health = 70, part = { Name = "Head" } }) == 0.3)
assert(Rivals.bowChargeTime(bow, { health = 200, part = { Name = "Torso" } }) == 1.8)
assert(Rivals.bowQuickShotLethal(bow, { health = 30, part = { Name = "Torso" } }) == true)
assert(Rivals.bowQuickShotLethal(bow, { health = 60, part = { Name = "Head" } }) == true)
assert(Rivals.bowQuickShotLethal(bow, { health = 31, part = { Name = "Torso" } }) == false)
local similarCooldownBow = {
    Info = table.clone(bow.Info),
}
similarCooldownBow.Info.ChargeReleaseCooldown = 0.3
assert(
    Rivals.bowQuickShotLethal(similarCooldownBow, { health = 30, part = { Name = "Torso" } }) == false,
    "Bow should keep secondary fire when its uncharged release is similarly fast"
)
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
    type(Rivals.damageAtDistance) == "function"
        and type(Rivals.triggerDamageReady) == "function",
    "Trigger Bot must expose a range-aware damage decision"
)
assert(Rivals.damageAtDistance(shorty, { part = { Name = "Torso" } }, 10) == 75)
assert(math.abs(Rivals.damageAtDistance(shorty, { part = { Name = "Torso" } }, 25) - 24.975) < 1e-6)
assert(
    Rivals.triggerDamageReady(shorty, { health = 150, part = { Name = "Torso" } }, 20) == false,
    "Trigger Bot must wait instead of wasting a severe-falloff body shot"
)
assert(
    Rivals.triggerDamageReady(shorty, { health = 40, part = { Name = "Torso" } }, 20) == true,
    "Trigger Bot must take a reduced-damage shot when it is still lethal"
)
assert(
    Rivals.triggerDamageReady(shorty, { health = 60, part = { Name = "Head" } }, 20) == true,
    "Trigger Bot must use critical damage when evaluating a lethal falloff shot"
)
assert(
    Rivals.triggerDamageReady(shorty, { health = 150, part = { Name = "Torso" } }, 12) == true,
    "Trigger Bot must accept near-full damage inside the useful falloff edge"
)
assert(
    Rivals.triggerDamageReady({ Info = { ShootDamage = 12 } }, { health = 150 }, 200) == true,
    "Weapons without falloff metadata must keep normal Trigger Bot behavior"
)
assert(Rivals.isSplashProjectile({
    Info = {
        DamageType = "Splash",
        IsProjectile = true,
        ProjectileSpeed = 100,
        ShootExplosionRadius = 16,
    },
}) == true)
assert(Rivals.isSplashProjectile({
    Info = {
        DamageType = "Bullet",
        IsProjectile = false,
        ProjectileSpeed = 300,
    },
}) == false)

local origin = Vector3.new(0, 2, 0)
local targetPosition = Vector3.new(10, 5, -20)
local rotation = Rivals.rotationToward(origin, targetPosition)
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
local ricochet = Rivals.traceRicochet(
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
local solvedRicochet = Rivals.solveRicochet(
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
local splashAim = Rivals.solveSplashAim(
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
local latencySplashAim = Rivals.solveSplashAim(
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
local unsafeEarlyImpact = Rivals.solveSplashAim(
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
assert(
    latencySplashAim
        and latencySplashAim.predictedPosition.X > splashAim.predictedPosition.X + 0.4,
    "RPG prediction must add observed network latency to moving-target lead"
)
local daggerAim = Rivals.solveProjectileAim(
    Vector3.new(0, 3, 0),
    {
        part = {
            AssemblyLinearVelocity = Vector3.new(0, 0, 12),
        },
        position = Vector3.new(60, 3, 0),
    },
    {
        ProjectileGravity = 0.25,
        ProjectileLifetime = 5,
        ProjectileSpeed = 300,
    },
    196.2
)
assert(
    daggerAim
        and daggerAim.predictedPosition.Z > 0
        and daggerAim.direction.Y > 0
        and daggerAim.flightTime > 0,
    "Dagger aiming must lead target movement and compensate for its measured projectile gravity"
)

local smoothedRotation = Rivals.smoothRotation(
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
    Rivals.smoothRotation(Vector2.zero, Vector2.new(0.5, 1), 0, 1 / 60)
        == Vector2.new(0.5, 1),
    "Zero Camera Aim smoothness must preserve instant rotation"
)

assert(
    type(Rivals.humanRotation) == "function",
    "Human Aim must provide motion-responsive curved tracking"
)
local humanAimState = { curveSign = 1 }
local humanStartTarget = Vector2.new(0, 0.35)
local humanStart = Rivals.humanRotation(
    Vector2.zero,
    humanStartTarget,
    70,
    1 / 60,
    humanAimState
)
local fastHumanTarget = Vector2.new(0, 0.5)
local fixedSpeedFollow = Rivals.smoothRotation(humanStart, fastHumanTarget, 70, 1 / 60)
local adaptiveFollow = Rivals.humanRotation(
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
assert(Rivals.backstabReady(Vector3.new(0, 0, 0), knifeObservation, knifeInfo) == true)
assert(Rivals.backstabReady(Vector3.new(10, 0, 0), knifeObservation, knifeInfo) == false)
local knifeApproach = Rivals.backstabPlan(
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
    Rivals.backstabReady(Vector3.new(3, 0, 6), knifeObservation, knifeInfo) == true,
    "Knife backstab readiness must accept a lenient rear angle inside heavy-attack reach"
)
assert(
    Rivals.backstabReady(Vector3.new(5, 0, 6), knifeObservation, knifeInfo) == true,
    "Knife backstab readiness must accept the server's lenient side-plane window"
)
assert(
    Rivals.backstabReady(Vector3.new(-1.5, 0, 0), knifeObservation, knifeInfo) == true,
    "Knife backstab readiness must use the live 7-stud heavy-attack reach"
)
knifeObservation.health = 151
assert(
    Rivals.backstabReady(Vector3.new(0, 0, 0), knifeObservation, knifeInfo) == false,
    "Knife Camera Aim must not turn for a backstab that cannot eliminate the target"
)
knifeObservation.health = 150
assert(
    Rivals.backstabReady(Vector3.new(-2.1, 0, 0), knifeObservation, knifeInfo) == false,
    "Knife backstab readiness must reject targets beyond heavy-attack reach"
)

local slingshotAim = Rivals.solveSlingshot(
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

local projectedSegments = Rivals.projectTrajectory({
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

local rotationCalls = 0
local cameraModule = {
    Rotation = Vector2.zero,
    SetRotation = function(self, value)
        rotationCalls += 1
        self.Rotation = value
    end,
}
local targetItem = { Info = { Name = "Rifle" } }
local localItem = { Name = "Burst Rifle", Info = { DisplayName = "Burst Rifle" } }
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
        IsSliding = function()
            return sliding
        end,
        IsGrounded = function()
            return grounded
        end,
        GetCameraData = function()
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
            EquippedItem = targetItem,
        },
    },
}
cameraModule._current_subject = fighterModule.LocalFighter
local cameraScript = {}
local fighterScript = {}
local controlsScript = {}
local mechanicsScript = {}
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
local Workspace = {
    CurrentCamera = {
        CFrame = CFrame.new(origin),
        WorldToViewportPoint = function()
            return Vector3.new(640, 360, 1), true
        end,
    },
}
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
local smokeObservation = Rivals.throwableObservation(
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
    Rivals.throwableObservation(Workspace.CurrentCamera, throwableModel, "OtherMatch") == nil,
    "Throwable ESP must exclude projectiles from another environment"
)
throwableAttributes.Exploded = true
assert(
    Rivals.throwableObservation(Workspace.CurrentCamera, throwableModel, "PracticeA") == nil,
    "Throwable ESP must drop completed projectiles"
)
throwableAttributes.Exploded = nil

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
Rivals.updateVisualSuppressions({
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
Rivals.updateVisualSuppressions({}, {}, suppressedVisuals)
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
                Health = 150,
                MaxHealth = 150,
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
        return { cameraScript, fighterScript, mechanicsScript }
    end,
    hookFunction = function(targetFunction, replacement)
        hookImplementations[targetFunction] = replacement
        return targetFunction
    end,
    click = function()
        clicks += 1
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
assert(observations[1].weapon == "Rifle")
assert(rangeObservation.player == rangeTarget)
assert(rangeObservation.health == 150 and rangeObservation.maxHealth == 150)
assert(
    rotationCalls == 1
        and cameraModule.Rotation == Rivals.rotationToward(origin, targetPosition)
        and nearestOptions[1].maxScreenDistance == 180,
    "Camera Aim must ignore a closer-to-crosshair target beyond the ESP distance cap"
)
assert(clicks == 0, "Camera Aim must not fire unless Trigger Bot is enabled")

local visibleRotation = cameraModule.Rotation
settings.silentAim = false
settings.shotAim = true
local cameraDataHook = hookImplementations[fighterModule.LocalFighter.GetCameraData]
assert(cameraDataHook, "RIVALS Silent Aim must hook the natural shot camera-data seam")
local silentCameraData, silentRay = cameraDataHook(fighterModule.LocalFighter)
local silentRecord = silentCameraData[cameraByte0]
local silentOrigin = Vector3.new(
    silentRecord[cameraByte0],
    silentRecord[cameraByte1],
    silentRecord[cameraByte2]
)
local silentRotation = Rivals.rotationToward(silentOrigin, targetPosition)
assert(
    silentRecord[cameraByte3] == silentRotation.X
        and silentRecord[cameraByte4] == silentRotation.Y
        and silentRay.Position ~= originalRay.Position,
    "RIVALS Silent Aim must redirect only the natural shot trajectory"
)
assert(
    cameraModule.Rotation == visibleRotation,
    "RIVALS Silent Aim must leave the visible camera rotation unchanged"
)
settings.shotAim = false
settings.silentAim = true

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
local closestRotation = Rivals.rotationToward(origin, closestRuntimePosition)
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
    cameraModule.Rotation == Rivals.rotationToward(origin, runtimeAimHead.Position),
    "Camera Aim must apply the configured headshot rate to its live selected target"
)
settings.headshotRate = 0
settings.missRate = 100
currentTime += 1
renderCallback()
assert(
    cameraModule.Rotation
        == Rivals.rotationToward(origin, targetPosition + Vector3.new(3.5, 0, 0)),
    "Camera Aim must turn toward the intentional miss point for a configured miss"
)
settings.missRate = 0

settings.humanAim = true
settings.aimSmoothness = 70
cameraModule.Rotation = Vector2.zero
currentTime += 1
renderCallback(1 / 60)
local humanHeadStart = cameraModule.Rotation
runtimeAimHead.Position += Vector3.new(8, 0, 0)
local movedHeadRotation = Rivals.rotationToward(origin, runtimeAimHead.Position)
local fixedHeadFollow = Rivals.smoothRotation(humanHeadStart, movedHeadRotation, 70, 1 / 60)
currentTime += 1 / 60
renderCallback(1 / 60)
assert(
    (movedHeadRotation - cameraModule.Rotation).Magnitude
        < (movedHeadRotation - fixedHeadFollow).Magnitude,
    "Human Aim must refresh the moving head position and speed up enough to keep it relatively tracked"
)
assert(cameraModule.Rotation ~= movedHeadRotation, "Human Aim must stay imperfect instead of hard-locking the head")
settings.humanAim = false
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

settings.silentAim = false
settings.triggerBot = true
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

fighterModule.LocalFighter.Data.IsInShootingRange = false
settings.silentAim = true
settings.humanAim = true
settings.aimSmoothness = 100
cameraModule.Rotation = Rivals.rotationToward(origin, runtimeAimHead.Position)
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
local slingshotRotation = Rivals.rotationToward(origin, runtimeAimHead.Position)
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
renderCallback()
assert(
    rotationCalls == backstabRotations + 1,
    "Knife Camera Aim must lock only from a lethal rear position"
)
assert(
    clicks == backstabClicks and aimClicks == backstabAimClicks + 1,
    "Knife Trigger Bot must use secondary fire for the live heavy/backstab attack"
)

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

adapter.stop()
adapter.stop()
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
assert(table.find(Rivals.capabilities, "knifeMovement") == nil)
assert(table.find(Rivals.capabilities, "bhop") ~= nil)
print("rivals-adapter-contracts-ok")
