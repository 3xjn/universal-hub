local Rivals = {
    id = "rivals",
    label = "RIVALS",
    manifest = {
        gameIds = { 6035872082 },
        placeIds = { 17625359962 },
    },
    capabilities = {
        "silentAim",
        "shotAim",
        "triggerBot",
        "scopedAccuracy",
        "humanAim",
        "bhop",
        "aimSmoothness",
        "headshotRate",
        "missRate",
        "boxes",
        "chams",
        "names",
        "health",
        "weapon",
        "utilityEsp",
        "noFlash",
        "noSmoke",
    },
    optionLabels = {
        humanAim = "Human Aim",
        scopedAccuracy = "Scoped Accuracy",
        silentAim = "Camera Aim",
        shotAim = "Silent Aim",
    },
    exclusiveOptions = {
        shotAim = { "silentAim", "humanAim" },
        silentAim = { "shotAim" },
    },
    cosmetics = false,
}

local TRIGGER_INTERVAL = 0.1
local TRIGGER_RADIUS = 8
local MAX_OBSERVATION_DISTANCE = 2000
local PRACTICE_DUMMY_HEALTH = 150
local RICOCHET_CACHE_INTERVAL = 0.15
local SPLASH_CACHE_INTERVAL = 0.1
local SLINGSHOT_CACHE_INTERVAL = 0.2
local SLINGSHOT_HUMAN_AIM_MAX_SMOOTHNESS = 65

local function contains(list, value)
    for _, candidate in ipairs(list or {}) do
        if candidate == value then
            return true
        end
    end
    return false
end

function Rivals.match(context)
    if contains(Rivals.manifest.placeIds, context.placeId) then
        return 200
    end
    if contains(Rivals.manifest.gameIds, context.gameId) then
        return 100
    end
    return 0
end

function Rivals.controllersReady(
    cameraController,
    fighterController,
    loadedModules,
    mechanicsController,
    duelController
)
    local cameraReady = false
    local duelReady = duelController == nil
    local fighterReady = false
    local mechanicsReady = mechanicsController == nil
    for _, module in ipairs(loadedModules or {}) do
        cameraReady = cameraReady or module == cameraController
        duelReady = duelReady or module == duelController
        fighterReady = fighterReady or module == fighterController
        mechanicsReady = mechanicsReady or module == mechanicsController
    end
    return cameraReady and duelReady and fighterReady and mechanicsReady
end

function Rivals.isOpponent(localPlayer, player, character)
    if player == localPlayer or not character then
        return false
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health <= 0 then
        return false
    end

    if localPlayer:GetAttribute("EnvironmentID") ~= player:GetAttribute("EnvironmentID") then
        return false
    end

    local localTeam = localPlayer:GetAttribute("TeamID")
    local playerTeam = player:GetAttribute("TeamID")
    return localTeam == nil or playerTeam == nil or localTeam ~= playerTeam
end

function Rivals.isTargetable(localPlayer, player, character)
    return Rivals.isOpponent(localPlayer, player, character)
        and character:FindFirstChildOfClass("ForceField") == nil
end

function Rivals.new(context)
    assert(context and context.oh, "RIVALS adapter requires Hydroxide")
    assert(context.store, "RIVALS adapter requires a reactive store")
    assert(context.press and context.release, "RIVALS adapter requires held input support")
    assert(context.aimClick, "RIVALS adapter requires secondary click support")
    assert(context.aimPress and context.aimRelease, "RIVALS adapter requires held aiming support")
    assert(context.hookFunction, "RIVALS adapter requires hookfunction")
    assert(context.restoreFunction, "RIVALS adapter requires restorefunction")
    assert(context.rivalsTargeting, "RIVALS adapter requires its targeting module")
    assert(context.projectileAim, "RIVALS adapter requires its projectile aim module")
    assert(context.shotPresentation, "RIVALS adapter requires its shot presentation module")
    assert(context.scopedAccuracy, "RIVALS adapter requires its scoped-accuracy module")
    assert(context.weaponPolicy, "RIVALS adapter requires its weapon policy module")
    assert(context.effects, "RIVALS adapter requires its effects module")
    assert(context.movement, "RIVALS adapter requires its movement module")
    assert(context.combatState, "RIVALS adapter requires its combat-state module")

    local clock = context.clock or os.clock
    local itemClock = context.itemClock or tick
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace = game:GetService("Workspace")
    local Lighting = context.lighting or game:GetService("Lighting")
    local CollectionService = context.collectionService or game:GetService("CollectionService")
    local LocalPlayer = Players.LocalPlayer
    local loadModule: (any) -> any = context.requireModule or require
    local controllers = LocalPlayer.PlayerScripts:WaitForChild("Controllers")
    local cameraControllerModule = controllers:WaitForChild("CameraController")
    local duelControllerModule = controllers:WaitForChild("DuelController")
    local fighterControllerModule = controllers:WaitForChild("FighterController")
    local controlsControllerModule = controllers:WaitForChild("ControlsController")
    local mechanicsControllerModule = controllers:WaitForChild("MechanicsController")
    if context.getLoadedModules then
        local deadline = clock() + 30
        repeat
            local succeeded, loadedModules = pcall(context.getLoadedModules)
            if succeeded
                and Rivals.controllersReady(
                    cameraControllerModule,
                    fighterControllerModule,
                    loadedModules,
                    mechanicsControllerModule,
                    duelControllerModule
                )
            then
                break
            end
            if clock() >= deadline then
                error("RIVALS did not initialize its client controllers within 30 seconds")
            end
            (context.wait or task.wait)(0.1)
        until false
    end
    local CameraController = loadModule(cameraControllerModule)
    local DuelController = loadModule(duelControllerModule)
    local FighterController = loadModule(fighterControllerModule)
    local ControlsController = loadModule(controlsControllerModule)
    local MechanicsController = loadModule(mechanicsControllerModule)
    local PickWeaponsPage = context.pickWeaponsPage or loadModule(
        LocalPlayer.PlayerScripts:WaitForChild("Modules")
            :WaitForChild("Pages")
            :WaitForChild("PickWeapons")
    )
    assert(
        PickWeaponsPage and type(PickWeaponsPage.IsOpen) == "function",
        "RIVALS adapter requires the live Pick Weapons page"
    )
    local spawn = context.spawn or task.spawn
    local Targeting = context.rivalsTargeting
    local ProjectileAim = context.projectileAim
    local ShotPresentation = context.shotPresentation
    local ScopedAccuracy = context.scopedAccuracy
    local WeaponPolicy = context.weaponPolicy
    local Effects = context.effects
    local Movement = context.movement
    local CombatState = context.combatState
    local targeting = context.oh.targeting
    local store = context.store
    local stopped = false
    local nextTriggerAt = 0
    local triggerHeld = false
    local triggerHeldAt = 0
    local triggerHeldItem
    local gunbladeComboState
    local fireHeld = false
    local fireHeldItem
    local ricochetCache
    local splashCache
    local slingshotCache
    local aimPlan
    local aimTargetKey
    local aimTargetWeapon
    local humanAimCharacter
    local humanAimState
    local renderDelta = 1 / 60
    local observations = {}
    local self = {}
    local getNetworkPing = context.getNetworkPing or function()
        return LocalPlayer:GetNetworkPing()
    end
    local random = context.random or math.random
    local effects = Effects.new({
        clock = clock,
        collectionService = CollectionService,
        drawing = context.oh.drawing,
        lighting = Lighting,
        localPlayer = LocalPlayer,
        playerGui = context.playerGui,
        projectileAim = ProjectileAim,
        workspace = Workspace,
    })
    local observeThrowables = context.observeThrowables or function(camera, environmentID)
        return effects:observeThrowables(camera, environmentID)
    end

    local function releaseFire()
        if not fireHeld then
            return
        end
        context.release()
        fireHeld = false
        fireHeldItem = nil
    end

    local function fighterFor(player)
        if player == LocalPlayer then
            return FighterController.LocalFighter
        end
        local fighters = FighterController._player_to_fighter
        return type(fighters) == "table" and fighters[player] or nil
    end

    local function equippedWeapon(player)
        local fighter = fighterFor(player)
        return fighter and WeaponPolicy.itemLabel(fighter.EquippedItem) or nil
    end

    local function isKatanaDeflecting(player)
        local fighter = fighterFor(player)
        local item = fighter and fighter.EquippedItem
        local data = item and item.Data
        return WeaponPolicy.itemName(item) == "Katana"
            and type(data) == "table"
            and data.FOVOffset == 5
    end

    local function localFighterIsActive()
        local fighter = FighterController.LocalFighter
        local entity = fighter and fighter.Entity
        local humanoid = entity and entity.Humanoid
        return fighter ~= nil
            and CameraController._current_subject == fighter
            and humanoid ~= nil
            and humanoid.Health > 0
    end

    local function localFighterIsInCombat()
        local fighter = FighterController.LocalFighter
        return CombatState.isCombatEligible(
            fighter,
            DuelController:GetDuel(LocalPlayer),
            PickWeaponsPage:IsOpen()
        )
    end

    local function localFighterIsCrouching(fighter)
        local isCrouching = fighter and fighter.IsCrouching
        if type(isCrouching) == "function" then
            local succeeded, crouching = pcall(isCrouching, fighter)
            if succeeded then
                return crouching == true
            end
        end
        local data = fighter and fighter.Data
        return type(data) == "table" and data.IsCrouching == true
    end

    local suppressBhopJump = false
    local movement = Movement.new({
        controlsController = ControlsController,
        getFighter = function()
            return FighterController.LocalFighter
        end,
        getSettings = function()
            return store:Get().settings
        end,
        isActive = localFighterIsActive,
        isInCombat = localFighterIsInCombat,
        isInputCaptured = context.isInputCaptured,
        mechanicsController = MechanicsController,
        movementDirection = context.movementDirection,
        shouldSuppressJump = function()
            return suppressBhopJump
        end,
        spawn = spawn,
        userInputService = UserInputService,
    })

    local function isOpponent(player, character)
        return Rivals.isOpponent(LocalPlayer, player, character)
    end

    local function isTargetable(player, character)
        return Rivals.isTargetable(LocalPlayer, player, character)
    end

    local function selectTarget(maxScreenDistance, includeBlocked)
        local settings = store:Get().settings
        local options = {
            includeBlocked = includeBlocked,
            isEligible = isTargetable,
            screenOrigin = UserInputService:GetMouseLocation(),
        }
        if maxScreenDistance then
            options.maxScreenDistance = maxScreenDistance
        elseif not settings.fullScreenAim then
            options.maxScreenDistance = settings.fov
        end
        local function nearest(values)
            if settings.humanAim then
                local camera = Workspace.CurrentCamera
                local cameraFrame = camera
                    and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
                return Targeting.closestObservation(
                    values,
                    cameraFrame and cameraFrame.Position,
                    options
                )
            end
            return targeting.nearestObservation(values, options)
        end
        local selected
        selected, aimTargetKey = Targeting.selectObservation(
            observations,
            aimTargetKey,
            nearest
        )
        return selected
    end

    local function selectBackstabTarget(localPosition, info, acquisitionDistance)
        local nearest
        local nearestDistance = math.huge
        for _, observation in ipairs(observations) do
            local character = observation.character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local plan = WeaponPolicy.backstabPlan(
                localPosition,
                observation,
                info,
                acquisitionDistance
            )
            if observation.visible
                and isTargetable(observation.player, character)
                and root
                and plan
            then
                local distance = (localPosition - root.Position).Magnitude
                if distance < nearestDistance then
                    nearest = table.clone(observation)
                    nearest.backstabPlan = plan
                    nearestDistance = distance
                end
            end
        end
        return nearest
    end

    local function targetRootPosition(target)
        local character = target and target.character
        local root = character
            and character.FindFirstChild
            and character:FindFirstChild("HumanoidRootPart")
        return root and root.Position or target and target.position
    end

    local function selectGunbladeTarget(fighter, item)
        local entity = fighter and fighter.Entity
        local localRoot = entity and entity.RootPart
        local comboRange = WeaponPolicy.gunbladeDashRange(item)
        if not localRoot or type(comboRange) ~= "number" then
            return nil
        end

        local candidates = table.clone(observations)
        local gunbladeRaycast = context.gunbladeRaycast
        if not gunbladeRaycast and RaycastParams and type(RaycastParams.new) == "function" then
            local raycastParams = RaycastParams.new()
            raycastParams.FilterType = Enum.RaycastFilterType.Exclude
            raycastParams.IgnoreWater = true
            local excluded = effects:smokeRaycastIgnore()
            if LocalPlayer.Character then
                table.insert(excluded, LocalPlayer.Character)
            end
            raycastParams.FilterDescendantsInstances = excluded
            gunbladeRaycast = function(raycastOrigin, displacement)
                return Workspace:Raycast(raycastOrigin, displacement, raycastParams)
            end
        end
        if type(Players.GetPlayers) == "function" then
            for _, player in ipairs(Players:GetPlayers()) do
                local character = player.Character
                local position = targetRootPosition({ character = character })
                local result = position and gunbladeRaycast
                    and gunbladeRaycast(localRoot.Position, position - localRoot.Position)
                local instance = result and result.Instance
                local clear = not instance
                    or instance.IsDescendantOf
                        and instance:IsDescendantOf(character)
                if position and clear and isTargetable(player, character) then
                    table.insert(candidates, {
                        character = character,
                        player = player,
                        position = position,
                        visible = true,
                    })
                end
            end
        end
        return Targeting.closestObservation(candidates, localRoot.Position, {
            isEligible = isTargetable,
            maxDistance = comboRange,
            resolvePosition = targetRootPosition,
        })
    end

    local function headAimOptions()
        local camera = Workspace.CurrentCamera
        local cameraFrame = camera
            and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
        local origin = cameraFrame and cameraFrame.Position
        if not origin then
            return nil
        end
        if context.headRaycast then
            return {
                origin = origin,
                raycast = context.headRaycast,
            }
        end
        if not RaycastParams or type(RaycastParams.new) ~= "function" then
            return { origin = origin }
        end

        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        raycastParams.IgnoreWater = true
        local excluded = effects:smokeRaycastIgnore()
        if LocalPlayer.Character then
            table.insert(excluded, LocalPlayer.Character)
        end
        raycastParams.FilterDescendantsInstances = excluded
        return {
            origin = origin,
            raycast = function(raycastOrigin, displacement)
                return Workspace:Raycast(raycastOrigin, displacement, raycastParams)
            end,
        }
    end

    local function updatePreferredHead(target, result, options)
        result.preferHead = true
        local position, head = Targeting.visibleHeadPoint(
            target,
            options and options.origin,
            options and options.raycast
        )
        if position then
            result.part = head
            result.position = position
        else
            result.part = target.part
            result.position = target.position
        end
        return result
    end

    local function plannedAimTarget(target, item)
        local now = clock()
        local settings = store:Get().settings
        local options = headAimOptions()
        if aimPlan
            and aimPlan.character == target.character
            and aimPlan.headshotRate == settings.headshotRate
            and aimPlan.humanAim == settings.humanAim
            and aimPlan.item == item
            and aimPlan.missRate == settings.missRate
            and now < aimPlan.expiresAt
        then
            local refreshed = table.clone(target)
            refreshed.intentionalMiss = aimPlan.target.intentionalMiss
            refreshed.part = aimPlan.target.part
            refreshed.preferHead = aimPlan.target.preferHead
            if refreshed.intentionalMiss then
                local character = target.character
                local root = character
                    and character.FindFirstChild
                    and character:FindFirstChild("HumanoidRootPart")
                if root then
                    local width = root.Size and root.Size.X or 2
                    refreshed.part = root
                    refreshed.position = target.position
                        + root.CFrame.RightVector * (width * 0.5 + 2.5)
                end
            elseif refreshed.preferHead then
                updatePreferredHead(target, refreshed, options)
            else
                local bodyPosition, bodyPart = Targeting.visibleBodyPoint(
                    target,
                    options and options.origin,
                    options and options.raycast
                )
                if bodyPosition and bodyPart then
                    refreshed.part = bodyPart
                    refreshed.position = bodyPosition
                elseif refreshed.part and refreshed.part.Position then
                    refreshed.position = refreshed.part.Position
                end
            end
            return refreshed
        end

        local info = item and item.Info
        local cooldown = type(info) == "table"
                and (info.ShootCooldown or info.AttackCooldown or info.ChargeReleaseCooldown)
            or TRIGGER_INTERVAL
        local planned = Targeting.applyAimRates(target, settings, random, options)
        aimPlan = {
            character = target.character,
            expiresAt = now + math.max(TRIGGER_INTERVAL, cooldown or TRIGGER_INTERVAL),
            headshotRate = settings.headshotRate,
            humanAim = settings.humanAim,
            item = item,
            missRate = settings.missRate,
            target = planned,
        }
        return planned
    end

    local function ricochetRaycast()
        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        raycastParams.IgnoreWater = true

        local excluded = {}
        if LocalPlayer.Character then
            table.insert(excluded, LocalPlayer.Character)
        end
        for _, observation in ipairs(observations) do
            if observation.character then
                table.insert(excluded, observation.character)
            end
        end
        raycastParams.FilterDescendantsInstances = excluded

        return function(origin, displacement)
            return Workspace:Raycast(origin, displacement, raycastParams)
        end
    end
    local environmentRaycast = context.environmentRaycast or ricochetRaycast
    local solveRicochet = context.solveRicochet or ProjectileAim.solveRicochet
    local solveSplashAim = context.solveSplashAim or ProjectileAim.solveSplashAim
    local solveSlingshot = context.solveSlingshot or ProjectileAim.solveSlingshot

    local function updateObservations()
        local screenOrigin = UserInputService:GetMouseLocation()
        observations = targeting.observePlayers({
            isEligible = isOpponent,
            raycastIgnore = effects:smokeRaycastIgnore(),
            screenOrigin = screenOrigin,
        })

        local fighter = FighterController.LocalFighter
        local data = fighter and fighter.Data
        local camera = Workspace.CurrentCamera
        local rangeEntities = Workspace:FindFirstChild("ShootingRangeEntities")
        if type(data) == "table" and data.IsInShootingRange and camera and rangeEntities then
            for _, entity in ipairs(rangeEntities:GetChildren()) do
                local humanoid = entity:FindFirstChildOfClass("Humanoid")
                local environmentID = entity:GetAttribute("EnvironmentID")
                local root = entity:FindFirstChild("HumanoidRootPart")
                local onScreen = false
                if root then
                    local _viewportPoint
                    _viewportPoint, onScreen = camera:WorldToViewportPoint(root.Position)
                end
                if entity:IsA("Model")
                    and humanoid
                    and humanoid.Health > 0
                    and (data.EnvironmentID == nil or environmentID == data.EnvironmentID)
                    and onScreen
                then
                    local observation = targeting.observeCharacter(entity, {
                        screenOrigin = screenOrigin,
                    })
                    if observation then
                        local health = humanoid.Health
                        local maxHealth = humanoid.MaxHealth
                        if health == math.huge or maxHealth == math.huge then
                            health = PRACTICE_DUMMY_HEALTH
                            maxHealth = PRACTICE_DUMMY_HEALTH
                        end
                        observation.player = entity
                        observation.health = health
                        observation.maxHealth = maxHealth
                        table.insert(observations, observation)
                    end
                end
            end
        end

        local cameraFrame = camera
            and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
        local cameraPosition = cameraFrame and cameraFrame.Position
        local nearby = {}
        if cameraPosition then
            for _, observation in ipairs(observations) do
                if observation.position
                    and (observation.position - cameraPosition).Magnitude <= MAX_OBSERVATION_DISTANCE
                then
                    table.insert(nearby, observation)
                end
            end
        end
        observations = nearby

        local visibleCount = 0
        for _, observation in ipairs(observations) do
            if observation.player ~= observation.character then
                local character = observation.character
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                observation.health = humanoid and humanoid.Health or 0
                observation.maxHealth = humanoid and humanoid.MaxHealth or 100
                observation.weapon = equippedWeapon(observation.player)
            end
            if observation.visible then
                visibleCount += 1
            end
        end
        return visibleCount
    end

    local function statusText(enemyCount, visibleCount)
        local fighter = FighterController.LocalFighter
        local data = fighter and fighter.Data
        local phase = "Lobby"
        if type(data) == "table" then
            if data.IsInShootingRange then
                return ("Shooting range · %d dummies · %d visible"):format(enemyCount, visibleCount)
            elseif data.IsInDuel then
                phase = "Duel"
            elseif data.IsSpectating ~= true then
                phase = "Active"
            end
        end
        return ("%s · %d enemies · %d visible"):format(phase, enemyCount, visibleCount)
    end

    local function setAimRotation(rotation, instant, character, maximumHumanSmoothness)
        local applied = rotation
        if instant then
            CameraController:SetRotation(rotation)
            return true
        end
        local settings = store:Get().settings
        local smoothness = settings.aimSmoothness
        if settings.humanAim then
            smoothness = math.max(smoothness, 55)
            if maximumHumanSmoothness then
                smoothness = math.min(smoothness, maximumHumanSmoothness)
            end
            if humanAimCharacter ~= character then
                humanAimCharacter = character
                humanAimState = {
                    curveSign = random() < 0.5 and -1 or 1,
                }
            end
            applied = Targeting.humanRotation(
                CameraController.Rotation,
                rotation,
                smoothness,
                renderDelta,
                humanAimState
            )
        else
            humanAimCharacter = nil
            humanAimState = nil
            applied = Targeting.smoothRotation(
                CameraController.Rotation,
                rotation,
                smoothness,
                renderDelta
            )
        end
        CameraController:SetRotation(applied)
        local pitchError = math.abs(rotation.X - applied.X)
        local yawError = math.abs((rotation.Y - applied.Y + math.pi) % (math.pi * 2) - math.pi)
        return math.max(pitchError, yawError) <= math.rad(0.5)
    end

    local function alignCamera(shotOnly)
        local settings = store:Get().settings
        local enabled = shotOnly and settings.shotAim
            or (settings.silentAim and not settings.shotAim)
        if not enabled
            or context.isInputCaptured()
            or not localFighterIsActive()
            or not localFighterIsInCombat()
        then
            if not settings.silentAim
                and not settings.shotAim
                or context.isInputCaptured()
                or not localFighterIsActive()
                or not localFighterIsInCombat()
            then
                aimTargetKey = nil
                aimTargetWeapon = nil
            end
            return nil
        end
        local function settleAim(rotation, instant, character, maximumSmoothness)
            if shotOnly then
                return true
            end
            return setAimRotation(
                rotation,
                instant,
                character,
                maximumSmoothness
            )
        end

        local fighter = FighterController.LocalFighter
        local item = fighter and fighter.EquippedItem
        local automationPolicy = WeaponPolicy.automationPolicy(item)
        local aimMode = shotOnly and "silentAim" or "cameraAim"
        if automationPolicy[aimMode] ~= true then
            aimTargetKey = nil
            aimTargetWeapon = nil
            aimPlan = nil
            return nil
        end
        local weaponName = WeaponPolicy.itemName(item)
        local energyRifle = weaponName == "Energy Rifle"
        local knife = weaponName == "Knife"
        local slingshot = weaponName == "Slingshot"
        local splashProjectile = ProjectileAim.isSplashProjectile(item)
        local entity = fighter and fighter.Entity
        local localRoot = entity and entity.RootPart
        local target
        if knife then
            aimTargetKey = nil
            aimTargetWeapon = nil
            target = localRoot and selectBackstabTarget(localRoot.Position, item.Info)
        else
            if aimTargetWeapon ~= item then
                aimTargetKey = nil
                aimTargetWeapon = item
            end
            target = selectTarget(nil, energyRifle or slingshot or splashProjectile)
        end
        local camera = Workspace.CurrentCamera
        if not target or not camera then
            if not target then
                aimTargetKey = nil
            end
            return nil
        end
        if not knife then
            aimTargetKey = target.character or target.player or target.part
        end

        local cameraFrame = camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame
        local origin = cameraFrame.Position
        local now = clock()
        if knife then
            local plan = target.backstabPlan
            local aimSettled = settleAim(
                Targeting.rotationToward(origin, plan.aimPosition),
                true,
                target.character
            )
            local aligned = {}
            for key, value in pairs(target) do
                aligned[key] = value
            end
            aligned.position = plan.aimPosition
            aligned.aimSettled = aimSettled
            aligned.backstab = plan.ready
            aligned.knifePath = plan.path
            return aligned
        end
        target = plannedAimTarget(target, item)

        if slingshot and target.position then
            local cacheValid = slingshotCache
                and slingshotCache.target == target.character
                and now < slingshotCache.expiresAt
                and (slingshotCache.origin - origin).Magnitude <= 0.5
                and (slingshotCache.targetPosition - target.position).Magnitude <= 0.5
            if not cacheValid then
                slingshotCache = {
                    expiresAt = now + SLINGSHOT_CACHE_INTERVAL,
                    origin = origin,
                    solution = solveSlingshot(
                        origin,
                        target,
                        item.Info,
                        environmentRaycast(),
                        Workspace.Gravity,
                        getNetworkPing()
                    ),
                    target = target.character,
                    targetPosition = target.position,
                }
            end

            if slingshotCache.solution then
                local aimSettled = settleAim(
                    Targeting.rotationToward(origin, origin + slingshotCache.solution.direction),
                    false,
                    target.character,
                    SLINGSHOT_HUMAN_AIM_MAX_SMOOTHNESS
                )
                local aligned = {}
                for key, value in pairs(target) do
                    aligned[key] = value
                end
                aligned.aimSettled = aimSettled
                aligned.slingshot = slingshotCache.solution
                aligned.visible = true
                return aligned
            end
        else
            slingshotCache = nil
        end

        if splashProjectile and target.position then
            local raycast = environmentRaycast()
            local cacheValid = splashCache
                and splashCache.target == target.character
                and splashCache.item == item
                and now < splashCache.expiresAt
                and (splashCache.origin - origin).Magnitude <= 0.5
                and (splashCache.targetPosition - target.position).Magnitude <= 0.5
                and (
                    not splashCache.solution
                    or ProjectileAim.isSplashSolutionCurrent(
                        origin,
                        splashCache.solution,
                        item.Info,
                        raycast,
                        Workspace.Gravity
                    )
                )
            if not cacheValid then
                splashCache = {
                    expiresAt = now + SPLASH_CACHE_INTERVAL,
                    item = item,
                    origin = origin,
                    solution = solveSplashAim(
                        origin,
                        target,
                        item.Info,
                        raycast,
                        Workspace.Gravity
                    ),
                    target = target.character,
                    targetPosition = target.position,
                }
            end

            if splashCache.solution then
                local aimSettled = settleAim(
                    Targeting.rotationToward(origin, origin + splashCache.solution.direction),
                    false,
                    target.character
                )
                local aligned = {}
                for key, value in pairs(target) do
                    aligned[key] = value
                end
                aligned.aimSettled = aimSettled
                aligned.splashImpact = splashCache.solution
                aligned.visible = true
                return aligned
            end
        else
            splashCache = nil
        end
        if splashProjectile then
            return nil
        end

        if target.visible and ProjectileAim.isDirectProjectile(item) then
            local solution = ProjectileAim.solveProjectileAim(
                origin,
                target,
                item.Info,
                Workspace.Gravity,
                shotOnly and renderDelta or 0
            )
            if solution then
                local aimSettled = settleAim(
                    Targeting.rotationToward(origin, origin + solution.direction),
                    false,
                    target.character
                )
                local aligned = {}
                for key, value in pairs(target) do
                    aligned[key] = value
                end
                aligned.aimSettled = aimSettled
                aligned.projectileAim = solution
                aligned.visible = true
                return aligned
            end
        end

        if target.visible then
            local aimSettled = settleAim(
                Targeting.rotationToward(origin, target.position),
                false,
                target.character
            )
            ricochetCache = nil
            local aligned = table.clone(target)
            aligned.aimSettled = aimSettled
            return aligned
        end
        if not energyRifle or not target.position then
            return nil
        end

        local cacheValid = ricochetCache
            and ricochetCache.target == target.character
            and now < ricochetCache.expiresAt
            and (ricochetCache.origin - origin).Magnitude <= 0.5
            and (ricochetCache.targetPosition - target.position).Magnitude <= 0.5
        if not cacheValid then
            ricochetCache = {
                direction = solveRicochet(origin, target.position, environmentRaycast()),
                expiresAt = now + RICOCHET_CACHE_INTERVAL,
                origin = origin,
                target = target.character,
                targetPosition = target.position,
            }
        end

        local solution = ricochetCache.direction
        if not solution then
            return nil
        end

        local aimSettled = settleAim(
            Targeting.rotationToward(origin, origin + solution.direction),
            false,
            target.character
        )
        local aligned = {}
        for key, value in pairs(target) do
            aligned[key] = value
        end
        aligned.aimSettled = aimSettled
        aligned.ricochet = solution
        aligned.visible = true
        return aligned
    end

    local function silentAimPoint(aligned, origin, distance)
        local solution = aligned
            and (aligned.slingshot
                or aligned.splashImpact
                or aligned.projectileAim
                or aligned.ricochet)
        if solution and typeof(solution.direction) == "Vector3" then
            return origin + solution.direction.Unit * distance
        end
        return aligned and aligned.position
    end

    local shotPresentation = ShotPresentation.new({
        cameraController = CameraController,
        getFighter = function()
            return FighterController.LocalFighter
        end,
        hookFunction = context.hookFunction,
        isEnabled = function()
            return not stopped and store:Get().settings.shotAim == true
        end,
        isInputCaptured = context.isInputCaptured,
        restoreFunction = context.restoreFunction,
        runService = RunService,
        workspace = Workspace,
    })
    local scopedAccuracy = ScopedAccuracy.new({
        getFighter = function()
            return FighterController.LocalFighter
        end,
        hookFunction = context.hookFunction,
        isEnabled = function()
            return not stopped and store:Get().settings.scopedAccuracy == true
        end,
        restoreFunction = context.restoreFunction,
    })
    scopedAccuracy:refreshHook()

    local function updateShotAimPresentation(aligned)
        local camera = Workspace.CurrentCamera
        local cameraFrame = camera
            and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
        local origin = cameraFrame and cameraFrame.Position
        local point = origin
            and silentAimPoint(aligned, origin, ProjectileAim.MAX_DISTANCE)
        if not point then
            shotPresentation:clear()
            return nil
        end
        shotPresentation:update(Targeting.rotationToward(origin, point), aligned)
        return shotPresentation:getPresentedTarget()
    end

    local function installCameraDataHook()
        shotPresentation:refreshHook()
    end

    local function runTriggerBot(alignedTarget)
        local settings = store:Get().settings
        if not settings.triggerBot
            or context.isInputCaptured()
            or not localFighterIsActive()
            or not localFighterIsInCombat()
        then
            gunbladeComboState = nil
            releaseFire()
            if triggerHeld then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
            end
            return
        end
        local fighter = FighterController.LocalFighter
        local item = fighter and fighter.EquippedItem
        if WeaponPolicy.automationPolicy(item).triggerBot ~= true then
            gunbladeComboState = nil
            aimPlan = nil
            releaseFire()
            if triggerHeld then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
            end
            return
        end
        local gunblade = WeaponPolicy.itemName(item) == "Gunblade"
        if not gunblade and alignedTarget and alignedTarget.aimSettled == false then
            local humanReticleReady = settings.humanAim
                and (alignedTarget.screenDistance or math.huge) <= TRIGGER_RADIUS
                and not alignedTarget.ricochet
                and not alignedTarget.slingshot
                and not alignedTarget.splashImpact
                and not alignedTarget.projectileAim
            if not humanReticleReady then
                releaseFire()
                return
            end
        end

        local target
        if gunblade then
            if settings.shotAim then
                target = alignedTarget
            else
                target = selectGunbladeTarget(fighter, item)
            end
        else
            target = alignedTarget
            if not target and not settings.shotAim then
                target = selectTarget(TRIGGER_RADIUS)
            end
        end
        if not target or not target.visible then
            gunbladeComboState = nil
            releaseFire()
            if triggerHeld then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
                nextTriggerAt = clock() + TRIGGER_INTERVAL
            end
            return
        end
        if not gunblade
            and not alignedTarget
            and (target.screenDistance or math.huge) > TRIGGER_RADIUS
        then
            gunbladeComboState = nil
            releaseFire()
            return
        end
        if isKatanaDeflecting(target.player) then
            gunbladeComboState = nil
            releaseFire()
            if triggerHeld then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
            end
            return
        end

        if gunblade then
            releaseFire()
            if triggerHeld then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
            end

            local entity = fighter and fighter.Entity
            local localRoot = entity and entity.RootPart
            local localPosition = localRoot and localRoot.Position
            local targetPosition = targetRootPosition(target)
            local targetDistance = localPosition
                and targetPosition
                and (targetPosition - localPosition).Magnitude
            local action
            gunbladeComboState, action = WeaponPolicy.gunbladeTriggerAction(
                gunbladeComboState,
                item,
                target.character or target.player or target,
                targetDistance,
                clock()
            )
            if not action then
                return
            end

            local camera = Workspace.CurrentCamera
            local cameraFrame = camera
                and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
            local cameraPosition = cameraFrame and cameraFrame.Position
            local cameraOffset = cameraPosition
                and targetPosition
                and targetPosition - cameraPosition
            local visibleFrame = camera and camera.CFrame
            local visibleRotation = CameraController.Rotation
            if cameraOffset and cameraOffset.Magnitude > 1e-3 then
                CameraController:SetRotation(
                    Targeting.rotationToward(cameraPosition, targetPosition)
                )
                camera.CFrame = CFrame.lookAt(cameraPosition, targetPosition)
            end
            if action.kind == "dash" then
                context.aimClick()
            else
                context.click()
            end
            if visibleFrame then
                camera.CFrame = visibleFrame
            end
            if visibleRotation then
                CameraController:SetRotation(visibleRotation)
            end
            aimPlan = nil
            return
        end
        gunbladeComboState = nil
        if ProjectileAim.isSplashProjectile(item)
            and not (alignedTarget and alignedTarget.splashImpact)
        then
            releaseFire()
            return
        end
        if WeaponPolicy.itemName(item) == "Knife" then
            releaseFire()
            if not WeaponPolicy.backstabTriggerReady(fighter, item, alignedTarget) then
                return
            end
            if triggerHeld then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
            end
            if clock() < nextTriggerAt then
                return
            end
            nextTriggerAt = clock() + (item.Info.HeavyAttackCooldown or TRIGGER_INTERVAL)
            context.aimClick()
            return
        end
        local camera = Workspace.CurrentCamera
        local cameraFrame = camera
            and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
        local targetDistance = cameraFrame
            and target.position
            and (target.position - cameraFrame.Position).Magnitude
        if targetDistance and not WeaponPolicy.triggerDamageReady(item, target, targetDistance) then
            releaseFire()
            return
        end
        local sniperCrouching = WeaponPolicy.itemName(item) == "Sniper"
            and localFighterIsCrouching(fighter)
        if not WeaponPolicy.sniperTriggerReady(
            CameraController,
            item,
            target,
            targetDistance,
            sniperCrouching,
            settings.scopedAccuracy == true
        ) then
            releaseFire()
            return
        end
        if item and item.Name == "Revolver" then
            releaseFire()
            local action =
                WeaponPolicy.revolverTriggerAction(item, target, targetDistance, itemClock())
            if triggerHeld then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
            end
            if not action or clock() < nextTriggerAt then
                return
            end
            nextTriggerAt = clock() + action.cooldown
            if action.kind == "fan" then
                context.aimClick()
            else
                context.click()
            end
            aimPlan = nil
            return
        end
        if item and item.Name == "Bow" and type(item.Info) == "table" then
            releaseFire()
            if not triggerHeld then
                if clock() < nextTriggerAt then
                    return
                end
                if WeaponPolicy.bowQuickShotLethal(item, target) then
                    nextTriggerAt = clock() + (item.Info.ShootCooldown or TRIGGER_INTERVAL)
                    context.click()
                    aimPlan = nil
                    return
                end
                triggerHeld = true
                triggerHeldAt = clock()
                triggerHeldItem = item
                context.aimPress()
                return
            end
            if triggerHeldItem ~= item then
                context.aimRelease()
                triggerHeld = false
                triggerHeldItem = nil
                nextTriggerAt = clock() + TRIGGER_INTERVAL
                return
            end
            if clock() - triggerHeldAt + 1e-3 < WeaponPolicy.bowChargeTime(item, target) then
                return
            end

            context.aimRelease()
            triggerHeld = false
            triggerHeldItem = nil
            nextTriggerAt = clock() + (item.Info.ChargeReleaseCooldown or TRIGGER_INTERVAL)
            aimPlan = nil
            return
        end

        if triggerHeld then
            context.aimRelease()
            triggerHeld = false
            triggerHeldItem = nil
        end
        if WeaponPolicy.holdToFire(item) then
            if not WeaponPolicy.adsSettled(CameraController, item) then
                releaseFire()
                return
            end
            if fireHeld and fireHeldItem == item then
                return
            end
            releaseFire()
            if clock() < nextTriggerAt then
                return
            end
            fireHeld = true
            fireHeldItem = item
            context.press()
            aimPlan = nil
            return
        end

        releaseFire()
        if clock() < nextTriggerAt or not WeaponPolicy.adsSettled(CameraController, item) then
            return
        end

        nextTriggerAt = clock() + TRIGGER_INTERVAL
        context.click()
        aimPlan = nil
    end

    local renderConnection = RunService.RenderStepped:Connect(function(deltaTime)
        if stopped then
            return
        end
        installCameraDataHook()
        scopedAccuracy:refreshHook()
        if type(deltaTime) == "number" and deltaTime > 0 then
            renderDelta = deltaTime
        end

        local visibleCount = updateObservations()
        local activeWeapon = equippedWeapon(LocalPlayer)
        local settings = store:Get().settings
        local utilityObservations = {}
        local fighter = FighterController.LocalFighter
        local data = fighter and fighter.Data
        if (settings.utilityEsp or settings.noSmoke)
            and localFighterIsInCombat()
            and Workspace.CurrentCamera
        then
            local environmentID = type(data) == "table" and data.EnvironmentID
                or LocalPlayer:GetAttribute("EnvironmentID")
            local observedUtilities = observeThrowables(Workspace.CurrentCamera, environmentID)
            if settings.utilityEsp then
                utilityObservations = observedUtilities
            end
        end
        effects:update(settings)
        store:Patch({
            activeWeapon = activeWeapon,
            activeWeaponKind = activeWeapon and "Item" or nil,
            observations = observations,
            utilityObservations = {
                count = #utilityObservations,
            },
            status = statusText(#observations, visibleCount),
        })
        context.render(observations, UserInputService:GetMouseLocation(), utilityObservations)
        local alignedTarget = alignCamera()
        if not alignedTarget and settings.shotAim then
            alignedTarget = alignCamera(true)
        end
        local triggerTarget = alignedTarget
        if settings.shotAim then
            triggerTarget = updateShotAimPresentation(alignedTarget)
        else
            shotPresentation:clear()
        end
        suppressBhopJump = WeaponPolicy.itemName(fighter and fighter.EquippedItem) == "Knife"
            and alignedTarget ~= nil
            and alignedTarget.knifePath ~= nil
        movement:update()
        local trajectory = alignedTarget
            and ((alignedTarget.ricochet and alignedTarget.ricochet.path)
                or (alignedTarget.slingshot and alignedTarget.slingshot.path)
                or alignedTarget.knifePath)
        effects:renderTrajectory(trajectory)
        runTriggerBot(triggerTarget)
    end)

    function self.stop()
        if stopped then
            return
        end
        stopped = true
        scopedAccuracy:stop()
        shotPresentation:stop()
        if triggerHeld then
            context.aimRelease()
            triggerHeld = false
        end
        releaseFire()
        movement:stop()
        effects:stop()
        renderConnection:Disconnect()
    end

    self.capabilities = Rivals.capabilities
    self.isOpponent = isOpponent
    self.selectTarget = selectTarget

    function self:cycleSkin() end
    function self:setWear() end
    function self:toggleStatTrak() end
    function self:resetSkin() end
    function self:cycleGlove() end
    function self:setGloveWear() end
    function self:setGloveColor() end
    function self:resetGlove() end

    return self
end

return Rivals
