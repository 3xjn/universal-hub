local roblox = require("@lune/roblox")
CFrame = roblox.CFrame
Color3 = roblox.Color3
Vector2 = roblox.Vector2
Vector3 = roblox.Vector3

local Rivals = require("../games/Rivals")

assert(Rivals.match({ gameId = 6035872082, placeId = 0 }) == 100)
assert(Rivals.match({ gameId = 0, placeId = 17625359962 }) == 200)
assert(Rivals.match({ gameId = 0, placeId = 0 }) == 0)
assert(Rivals.cosmetics == false)
assert(
    table.find(Rivals.capabilities, "silentAim")
        and table.find(Rivals.capabilities, "triggerBot")
        and table.find(Rivals.capabilities, "humanAim")
        and table.find(Rivals.capabilities, "aimSmoothness")
        and table.find(Rivals.capabilities, "headshotRate")
        and table.find(Rivals.capabilities, "missRate")
)
assert(not table.find(Rivals.capabilities, "wallbang"), "RIVALS must not advertise unverified hit forgery")

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

local function character(health)
    return {
        FindFirstChildOfClass = function(_self, className)
            if className == "Humanoid" then
                return {
                    Health = health,
                    MaxHealth = 150,
                }
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
local controllers = {}
function controllers:WaitForChild(name)
    return name == "CameraController" and cameraScript or fighterScript
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
local UserInputService = {
    GetMouseLocation = function()
        return mousePosition
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
local rangeObservation = {
    character = rangeTarget,
    position = targetPosition,
    screenDistance = 40,
    visible = true,
}
local nearestOptions = {}
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
        return observations
    end,
    observeCharacter = function(value, options)
        assert(value == rangeTarget, "Non-humanoid Target markers must never reach ESP observation")
        assert(options.screenOrigin == mousePosition)
        return rangeObservation
    end,
}
local settings = {
    aimSmoothness = 0,
    fov = 180,
    fullScreenAim = false,
    headshotRate = 0,
    humanAim = false,
    missRate = 0,
    silentAim = true,
    triggerBot = false,
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
local trajectoryDestroyed = false
local trajectoryNodes = {}
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
    click = function()
        clicks += 1
    end,
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
    render = function(value, position)
        rendered = {
            observations = value,
            position = position,
        }
    end,
    requireModule = function(module)
        return module == cameraScript and cameraModule or fighterModule
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
    store = store,
})

assert(renderCallback, "RIVALS adapter must attach a resilient per-frame loop")
renderCallback()
assert(rendered.observations == state.observations and rendered.position == mousePosition)
assert(#rendered.observations == 2 and rendered.observations[2] == rangeObservation)
assert(state.activeWeapon == "Burst Rifle")
assert(state.status == "Shooting range · 2 dummies · 2 visible")
assert(observations[1].health == 150 and observations[1].maxHealth == 150)
assert(observations[1].weapon == "Rifle")
assert(rangeObservation.player == rangeTarget)
assert(rangeObservation.health == 150 and rangeObservation.maxHealth == 150)
assert(
    rotationCalls == 1
        and cameraModule.Rotation ~= Vector2.zero
        and nearestOptions[1].maxScreenDistance == 180,
    "Camera Aim must use the configured FOV and the game's public camera rotation seam"
)
assert(clicks == 0, "Camera Aim must not fire unless Trigger Bot is enabled")

local closestRuntimePosition = origin + Vector3.new(3, 0, -4)
local closestRuntimeTarget = {
    character = {},
    player = nil,
    position = closestRuntimePosition,
    screenDistance = 100,
    visible = true,
}
closestRuntimeTarget.player = closestRuntimeTarget.character
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
fighterModule.LocalFighter.Data.IsInShootingRange = true

settings.silentAim = false
settings.triggerBot = true
renderCallback()
assert(clicks == 0, "Trigger Bot must not fire at an enemy outside the crosshair radius")
assert(nearestOptions[#nearestOptions].maxScreenDistance == 8)

target.screenDistance = 4
observations[1].screenDistance = 4
rangeObservation.screenDistance = 4
renderCallback()
assert(clicks == 1, "Trigger Bot must use normal input only when a visible enemy crosses the reticle")

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
    CFrame = CFrame.lookAt(targetPosition, targetPosition + Vector3.xAxis),
    Position = targetPosition,
}
target.character.FindFirstChild = function(_self, name)
    return name == "HumanoidRootPart" and knifeRoot or nil
end
fighterModule.LocalFighter.Entity.RootPart = {
    Position = targetPosition - Vector3.xAxis * 6.5,
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
currentTime += 1
local backstabClicks = clicks
local backstabAimClicks = aimClicks
local backstabRotations = rotationCalls
renderCallback()
assert(
    rotationCalls == backstabRotations + 1,
    "Knife Camera Aim must lock an already-close lethal rear target outside ordinary camera FOV"
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

inputCaptured = true
settings.silentAim = true
cameraModule.Rotation = Vector2.zero
renderCallback()
assert(cameraModule.Rotation == Vector2.zero, "The open menu must suppress camera control")
assert(
    clicks == 4
        and presses == 0
        and releases == 0
        and aimPresses == 1
        and aimReleases == 1
        and aimClicks == 1,
    "The open menu must suppress automated input"
)

adapter.stop()
adapter.stop()
assert(disconnected == true, "Stopping the adapter must disconnect its render loop")
assert(trajectoryDestroyed == true, "Stopping the adapter must destroy bounce ESP drawings")
print("rivals-adapter-contracts-ok")
