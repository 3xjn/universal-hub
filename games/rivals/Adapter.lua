local Targeting = require("./libraries/Targeting")
local ProjectileAim = require("./libraries/ProjectileAim")
local Session = require("./Session")
local CameraAim = require("./features/CameraAim")
local SilentAim = require("./features/SilentAim")
local TeleportBehind = require("./features/TeleportBehind")
local TriggerBot = require("./features/TriggerBot")
local SkipBlocks = require("./features/SkipBlocks")
local AutoDeflect = require("./features/AutoDeflect")
local AutoCounter = require("./features/AutoCounter")
local NoScope = require("./features/NoScope")
local Pickup = require("./features/Pickup")
local SkinUnlock = require("./features/SkinUnlock")
local RedLightSafety = require("./features/RedLightSafety")
local TaskLoadout = require("./tasks/TaskLoadout")
local HookRuntime = require("./libraries/HookRuntime")
local WeaponPolicy = require("./libraries/WeaponPolicy")
local ItemInput = require("./libraries/ItemInput")
local Effects = require("./world/Effects")
local Movement = require("./libraries/Movement")
local TaskCamera = require("./tasks/TaskCamera")
local TaskLocomotion = require("./tasks/TaskLocomotion")
local TaskWeaponSwap = require("./tasks/TaskWeaponSwap")
local TaskSkillRuntime = require("./tasks/TaskSkillRuntime")
local TaskCounterPolicy = require("./tasks/TaskCounterPolicy")
local TaskPolicy = require("./tasks/TaskPolicy")
local CombatState = require("./libraries/CombatState")
local ModePolicy = require("./libraries/ModePolicy")
local GunGameRuntime = require("./features/GunGameRuntime")
local ObservationRuntime = require("./world/ObservationRuntime")
local AutoCounterRuntime = require("./features/AutoCounterRuntime")
local WorldPolicy = require("./world/WorldPolicy")
local TaskFarmRuntime = require("./tasks/TaskFarmRuntime")
local PracticeTaskDriver = require("./tasks/PracticeTaskDriver")

local Rivals = {}

local TRIGGER_INTERVAL = TriggerBot.INTERVAL
local TRIGGER_RADIUS = TriggerBot.RADIUS

function Rivals.playerTone(localPlayer, player, character)
    if player == localPlayer or not character then
        return nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health <= 0 then
        return nil
    end

    if localPlayer:GetAttribute("EnvironmentID") ~= player:GetAttribute("EnvironmentID") then
        return nil
    end

    local localTeam = localPlayer:GetAttribute("TeamID")
    local playerTeam = player:GetAttribute("TeamID")
    return localTeam ~= nil and playerTeam ~= nil and localTeam == playerTeam and "team" or "enemy"
end

function Rivals.isOpponent(localPlayer, player, character)
    return Rivals.playerTone(localPlayer, player, character) == "enemy"
end

function Rivals.capabilityContext(context)
    context = context or {}
    local duelController = context.duelController
    local player = context.player
    -- Capability discovery runs before Adapter.new and therefore before the
    -- native loading-screen readiness gate. The live path must never require a
    -- controller here; injected test/composition loaders are already isolated.
    if not duelController and type(context.requireModule) == "function" then
        local gameObject = context.game or game
        local players = gameObject:GetService("Players")
        player = player or players.LocalPlayer
        local controllers = player.PlayerScripts:WaitForChild("Controllers")
        duelController = context.requireModule(controllers:WaitForChild("DuelController"))
    end
    return {
        isGunGame = duelController ~= nil
                and ModePolicy.controllerIsGunGame(duelController, player)
            or false,
    }
end

function Rivals.capabilitiesFor(context, declaredCapabilities)
    context = context or {}
    -- Gun Game is joined after execute. Do not snapshot IsGunGame here or the
    -- Tools tab disappears for the rest of the session.
    local autoPickupAvailable = context.fireTouchInterestAvailable == true
    local hookFeaturesAvailable = context.hookFunctionAvailable == true
        and context.restoreFunctionAvailable == true
    local capabilities = {}
    for _, capability in ipairs(declaredCapabilities or {}) do
        local available = capability ~= "autoPickup" or autoPickupAvailable
        if
            capability == "shotAim"
            or capability == "alwaysScoped"
            or capability == "skipDeflect"
            or capability == "redLightSafety"
        then
            available = available and hookFeaturesAvailable
        end
        if available then
            table.insert(capabilities, capability)
        end
    end
    return capabilities
end

function Rivals.entityIsInvincible(entity)
    if type(entity) ~= "table" then
        return false
    end

    if type(entity.Get) == "function" then
        local succeeded, value = pcall(entity.Get, entity, "IsInvincible")
        if succeeded and value ~= nil then
            return value == true
        end
    end

    local data = entity.Data
    return type(data) == "table" and data.IsInvincible == true
end

function Rivals.lowestHealthObservation(observations, validate, nearest)
    local lowestHealth = math.huge
    local lowest = {}
    for _, observation in ipairs(observations or {}) do
        local accepted = validate(observation)
        local health = accepted and accepted.health
        if type(health) == "number" and health > 0 then
            if health < lowestHealth then
                lowestHealth = health
                lowest = { accepted }
            elseif health == lowestHealth then
                table.insert(lowest, accepted)
            end
        end
    end
    if #lowest == 0 then
        return nil
    end
    return nearest(lowest)
end

Rivals.pickupType = GunGameRuntime.pickupType
Rivals.shouldCollectPickup = GunGameRuntime.shouldCollect

function Rivals.isTargetable(localPlayer, player, character, fighter, isGunGame)
    if
        not Rivals.isOpponent(localPlayer, player, character)
        or character:FindFirstChildOfClass("ForceField") ~= nil
    then
        return false
    end

    return isGunGame ~= true or not Rivals.entityIsInvincible(fighter and fighter.Entity)
end

function Rivals.new(context)
    assert(context and context.oh, "RIVALS adapter requires Hydroxide")
    assert(context.store, "RIVALS adapter requires a reactive store")

    local clock = context.clock or os.clock
    local itemClock = context.itemClock or tick
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local ContextActionService = context.contextActionService
        or game:GetService("ContextActionService")
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
    local playerDataControllerModule
    local matchmakingControllerModule
    local shootingRangeControllerModule
    if context.taskFarmRuntime == nil then
        playerDataControllerModule = controllers:WaitForChild("PlayerDataController")
        matchmakingControllerModule = controllers:WaitForChild("MatchmakingController")
        shootingRangeControllerModule = controllers:WaitForChild("ShootingRangeController")
    end
    if context.requireModule == nil then
        if not game:IsLoaded() then
            game.Loaded:Wait()
        end
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        if character and not character:FindFirstChild("HumanoidRootPart") then
            character:WaitForChild("HumanoidRootPart", 15)
        end
        -- game:IsLoaded() and character readiness both precede RIVALS' own
        -- controller bootstrap. Requiring Camera/Fighter/Mechanics while its
        -- native LoadingScreen is enabled permanently poisons those modules.
        local playerGui = LocalPlayer:WaitForChild("PlayerGui")
        local loadingScreen = playerGui:FindFirstChild("LoadingScreen")
        local loadingDeadline = os.clock() + 3
        while loadingScreen == nil and os.clock() < loadingDeadline do
            RunService.Heartbeat:Wait()
            loadingScreen = playerGui:FindFirstChild("LoadingScreen")
        end
        while loadingScreen and loadingScreen.Parent ~= nil and loadingScreen.Enabled == true do
            RunService.Heartbeat:Wait()
        end
        RunService.Heartbeat:Wait()

        local loadedModules = getloadedmodules
        if type(loadedModules) == "function" then
            local playerModules = LocalPlayer.PlayerScripts:WaitForChild("Modules")
            local clientItem = playerModules
                :WaitForChild("ClientReplicatedClasses")
                :WaitForChild("ClientFighter")
                :WaitForChild("ClientItem")
            local equipment = playerModules:WaitForChild("UserInterface"):WaitForChild("Equipment")
            local requiredModules = {
                clientItem:WaitForChild("ClientViewModel"),
                clientItem.Parent:WaitForChild("FighterInterface"):WaitForChild("Keybinds"),
                equipment,
                equipment:WaitForChild("EquipmentState"),
            }
            local deadline = os.clock() + 15
            while true do
                local loaded = {}
                for _, module in ipairs(loadedModules()) do
                    loaded[module] = true
                end
                local ready = true
                for _, module in ipairs(requiredModules) do
                    if not loaded[module] then
                        ready = false
                        break
                    end
                end
                if ready then
                    break
                end
                if os.clock() >= deadline then
                    error("RIVALS native module bootstrap timed out", 0)
                end
                RunService.Heartbeat:Wait()
            end
        end
    end
    local PlayerDataController = context.playerDataController
    if context.taskFarmRuntime == nil then
        local modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
        PlayerDataController = PlayerDataController or loadModule(playerDataControllerModule)
        if context.requireModule == nil then
            local playerDataUtility = loadModule(modules:WaitForChild("PlayerDataUtility"))
            for _, name in ipairs({
                "GetSetting",
                "GetSettingChangedSignal",
                "SetSetting",
                "IsNosniyGamesTeamMember",
                "GetWeaponData",
                "HasGamepass",
                "GetStatistic",
                "GetDirectoryStatistic",
                "GetWeaponStatistic",
                "GetMapStatistic",
                "GetUnlockedWeapons",
                "AreTasksCompleted",
            }) do
                local method = playerDataUtility[name]
                if type(method) == "function" then
                    PlayerDataController[name] = function(controller, ...)
                        return method(playerDataUtility, controller, ...)
                    end
                end
            end
        end
    end
    local CameraController = loadModule(cameraControllerModule)
    local DuelController = loadModule(duelControllerModule)
    local FighterController = loadModule(fighterControllerModule)
    local ControlsController = loadModule(controlsControllerModule)
    local MechanicsController = loadModule(mechanicsControllerModule)
    local CosmeticLibrary = context.cosmeticLibrary
    local Equipment = context.equipment
    local EquipmentStateLibrary = context.equipmentStateLibrary
    local EquipCosmetic = context.equipCosmetic
    local ClientViewModelLibrary = context.clientViewModelLibrary
    local MatchmakingController
    local ShootingRangeController
    local TaskLibrary
    local RivalsConstants
    if context.taskFarmRuntime == nil then
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local modules = ReplicatedStorage:WaitForChild("Modules")
        CosmeticLibrary = CosmeticLibrary or loadModule(modules:WaitForChild("CosmeticLibrary"))
        local equipmentModule = LocalPlayer.PlayerScripts
            :WaitForChild("Modules")
            :WaitForChild("UserInterface")
            :WaitForChild("Equipment")
        Equipment = Equipment or loadModule(equipmentModule)
        EquipmentStateLibrary = EquipmentStateLibrary
            or loadModule(equipmentModule:WaitForChild("EquipmentState"))
        EquipCosmetic = EquipCosmetic
            or ReplicatedStorage:WaitForChild("Remotes")
                :WaitForChild("Data")
                :WaitForChild("EquipCosmetic")
        if context.requireModule == nil then
            local wrapController = loadModule(controllers:WaitForChild("WrapController"))
            local wrapGroups =
                LocalPlayer.PlayerScripts:WaitForChild("Modules"):WaitForChild("WrapGroupObjects")
            for _, module in ipairs(wrapGroups:GetChildren()) do
                if
                    module:IsA("ModuleScript")
                    and wrapController._wrap_group_classes[module.Name] == nil
                then
                    wrapController._wrap_group_classes[module.Name] = loadModule(module)
                end
            end
        end
        ClientViewModelLibrary = ClientViewModelLibrary
            or loadModule(
                LocalPlayer.PlayerScripts
                    :WaitForChild("Modules")
                    :WaitForChild("ClientReplicatedClasses")
                    :WaitForChild("ClientFighter")
                    :WaitForChild("ClientItem")
                    :WaitForChild("ClientViewModel")
            )
        MatchmakingController = context.matchmakingController
            or loadModule(matchmakingControllerModule)
        ShootingRangeController = context.shootingRangeController
            or loadModule(shootingRangeControllerModule)
        TaskLibrary = context.taskLibrary or loadModule(modules:WaitForChild("TaskLibrary"))
        RivalsConstants = context.rivalsConstants or loadModule(modules:WaitForChild("CONSTANTS"))
    end
    local function isGunGame()
        return ModePolicy.controllerIsGunGame(DuelController, LocalPlayer)
    end
    local PickWeaponsPage = context.pickWeaponsPage
        or loadModule(
            LocalPlayer.PlayerScripts
                :WaitForChild("Modules")
                :WaitForChild("Pages")
                :WaitForChild("PickWeapons")
        )
    assert(
        PickWeaponsPage and type(PickWeaponsPage.IsOpen) == "function",
        "RIVALS adapter requires the live Pick Weapons page"
    )
    local spawn = context.spawn or task.spawn
    local targeting = context.oh.targeting
    local store = context.store
    if context.teleportBootstrap ~= true and store:Get().settings.taskAutomationPaused ~= true then
        local state = store:Get()
        local settings = table.clone(state.settings)
        settings.taskAutomationPaused = true
        store:Patch({ settings = settings })
        if context.settingsChanged then
            context.settingsChanged(settings)
        end
    end
    local lastTaskPauseSetting = store:Get().settings.taskAutomationPaused == true
    local function persistCosmeticSetting(name, cosmetics)
        local state = store:Get()
        local updated = table.clone(state.settings)
        updated[name] = SkinUnlock.encodeRestore(cosmetics)
        store:Patch({ settings = updated })
        if type(context.settingsChanged) == "function" then
            context.settingsChanged(updated)
        end
    end
    local skinUnlock
    if
        CosmeticLibrary
        and type(Equipment) == "table"
        and type(Equipment.EquipmentState) == "table"
        and EquipmentStateLibrary
        and PlayerDataController
        and EquipCosmetic
        and ClientViewModelLibrary
    then
        skinUnlock = SkinUnlock.new({
            clientViewModelLibrary = ClientViewModelLibrary,
            cosmeticLibrary = CosmeticLibrary,
            equipmentState = Equipment.EquipmentState,
            equipmentStateLibrary = EquipmentStateLibrary,
            equipCosmetic = EquipCosmetic,
            fighterController = FighterController,
            onEquippedChanged = function(cosmetics)
                persistCosmeticSetting("unlockAllCosmeticsEquipped", cosmetics)
            end,
            onRestoreChanged = function(cosmetics)
                persistCosmeticSetting("unlockAllSkinsRestore", cosmetics)
            end,
            playerDataController = PlayerDataController,
        })
    end
    local session = Session.new()
    local stopped = false
    local trigger = {
        fireAmmo = nil,
        fireAmmoAt = 0,
        fireHeld = false,
        fireItem = nil,
        gunblade = nil,
        held = false,
        heldAt = 0,
        heldItem = nil,
        nextAt = 0,
    }
    local aimPlan
    local aimTargetKey
    local aimTargetWeapon
    local humanAimCharacter
    local humanAimState
    local renderDelta = 1 / 60
    local observations = {}
    local visualObservations = observations
    local taskFarmRuntime
    local taskEmergencyConnection
    local autoCounterInFlight = false
    local self = { autoCounterDebug = {}, taskDebug = {} }
    local getNetworkPing = context.getNetworkPing
        or function()
            return LocalPlayer:GetNetworkPing()
        end
    local random = context.random or math.random
    local effects = Effects.new({
        clock = clock,
        collectionService = CollectionService,
        lighting = Lighting,
        limn = context.limn,
        localPlayer = LocalPlayer,
        playerGui = context.playerGui,
        projectileAim = ProjectileAim,
        workspace = Workspace,
    })
    local observeThrowables = context.observeThrowables
        or function(camera, environmentID)
            return effects:observeThrowables(camera, environmentID)
        end

    local combatInput = ItemInput.new(function()
        return FighterController.LocalFighter
    end)
    local function startShooting()
        return combatInput:fire()
    end
    local function finishShooting()
        return combatInput:releaseFire()
    end
    local function startAiming()
        return combatInput:aim()
    end
    local function finishAiming()
        return combatInput:releaseAim()
    end

    local function releaseFire()
        if not trigger.fireHeld then
            return
        end
        combatInput:releaseFire()
        trigger.fireHeld = false
        trigger.fireItem = nil
        trigger.fireAmmo = nil
        trigger.fireAmmoAt = 0
    end

    local taskWeaponSwap = TaskWeaponSwap.new({
        clock = clock,
        equip = function(fighter, item)
            if type(fighter.EquipItem) == "function" then
                local succeeded, result = pcall(fighter.EquipItem, fighter, item)
                if succeeded and result ~= false then
                    return true
                end
            end
            return ItemInput.dispatch(fighter, ItemInput.equipAction(item))
        end,
        weaponPolicy = WeaponPolicy,
        release = function()
            releaseFire()
            if trigger.held then
                finishAiming()
                trigger.held = false
                trigger.heldItem = nil
            end
        end,
    })

    local taskSkillRuntime = TaskSkillRuntime.new({ localPlayer = LocalPlayer })
    local taskCounterPolicy = TaskCounterPolicy.new({ clock = clock })
    local taskSkillWasActive = false
    local nextCounterEquipAt = 0
    local function fighterFor(player)
        if player == LocalPlayer then
            return FighterController.LocalFighter
        end
        if type(FighterController.GetFighter) == "function" then
            local succeeded, fighter =
                pcall(FighterController.GetFighter, FighterController, player)
            if succeeded and fighter ~= nil then
                return fighter
            end
        end
        local fighters = FighterController._player_to_fighter
        return type(fighters) == "table" and fighters[player] or nil
    end

    local function equippedWeapon(player)
        local fighter = fighterFor(player)
        return fighter and WeaponPolicy.itemLabel(fighter.EquippedItem) or nil
    end

    local function isDeflecting(player)
        local fighter = fighterFor(player)
        return WeaponPolicy.isActivelyDeflecting(fighter and fighter.EquippedItem)
    end

    local function currentCameraSubject()
        if type(CameraController.GetCurrentSubject) == "function" then
            local succeeded, subject = pcall(CameraController.GetCurrentSubject, CameraController)
            if succeeded then
                return subject
            end
        end
        return CameraController._current_subject
    end

    local function localFighterIsActive()
        local fighter = FighterController.LocalFighter
        local entity = fighter and fighter.Entity
        local humanoid = entity and entity.Humanoid
        return fighter ~= nil
            and currentCameraSubject() == fighter
            and humanoid ~= nil
            and humanoid.Health > 0
    end

    local function localFighterIsTaskActive()
        local fighter = FighterController.LocalFighter
        local entity = fighter and fighter.Entity
        local humanoid = entity and entity.Humanoid
        return humanoid ~= nil and humanoid.Health > 0 and not PickWeaponsPage:IsOpen()
    end

    local function localFighterIsInCombat()
        local fighter = FighterController.LocalFighter
        return CombatState.isCombatEligible(
            fighter,
            DuelController:GetDuel(LocalPlayer),
            PickWeaponsPage:IsOpen()
        )
    end

    local function localFighterIsInRound()
        local fighter = FighterController.LocalFighter
        return CombatState.isRoundEligible(
            fighter,
            DuelController:GetDuel(LocalPlayer),
            PickWeaponsPage:IsOpen()
        )
    end

    local function localFighterRoot()
        local fighter = FighterController.LocalFighter
        local entity = fighter and fighter.Entity
        return entity and (entity.RootPart or entity.HumanoidRootPart)
    end
    local function localFighterHumanoid()
        local fighter = FighterController.LocalFighter
        local entity = fighter and fighter.Entity
        return entity and entity.Humanoid
    end
    local gameplayUtility
    local teleportPhysics
    local function localFighterCharacter()
        local fighter = FighterController.LocalFighter
        local entity = fighter and fighter.Entity
        return entity and entity.Character or LocalPlayer.Character
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
    local function teleportLibs()
        return {
            clock = clock,
            getRoot = localFighterRoot,
            getHumanoid = localFighterHumanoid,
            getCharacter = localFighterCharacter,
            isImmune = function()
                local fighter = FighterController.LocalFighter
                local entity = fighter and fighter.Entity
                return TeleportBehind.hasForceField(localFighterCharacter())
                    or Rivals.entityIsInvincible(entity)
            end,
            raycast = function(origin, displacement)
                if type(environmentRaycast) ~= "function" then
                    return nil
                end
                local cast = environmentRaycast()
                if type(cast) ~= "function" then
                    return nil
                end
                return cast(origin, displacement)
            end,
            weaponMode = function()
                local fighter = FighterController.LocalFighter
                local item = fighter and fighter.EquippedItem
                if WeaponPolicy.isBackstabKnife(item) then
                    return "knife"
                end
                if WeaponPolicy.isScoped(item) then
                    return "sniper"
                end
                return "barrage"
            end,
            killParts = function()
                return CollectionService:GetTagged(TeleportBehind.OOB_TAG)
            end,
            isOutOfBounds = function(position)
                if gameplayUtility == nil then
                    local modules = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")
                    local moduleScript = modules and modules:FindFirstChild("GameplayUtility")
                    if moduleScript then
                        local ok, result = pcall(loadModule, moduleScript)
                        gameplayUtility = ok and result or false
                    else
                        gameplayUtility = false
                    end
                end
                if
                    type(gameplayUtility) == "table"
                    and type(gameplayUtility.IsWithinOOBPart) == "function"
                then
                    return gameplayUtility:IsWithinOOBPart(position) ~= nil
                end
                return TeleportBehind.isOutOfBounds(position, {
                    kill = CollectionService:GetTagged(TeleportBehind.OOB_TAG),
                    safe = CollectionService:GetTagged(TeleportBehind.OOB_SAFE_TAG),
                })
            end,
        }
    end
    local function stopTeleportPhysics()
        if teleportPhysics then
            for _, connection in ipairs(teleportPhysics) do
                connection:Disconnect()
            end
            teleportPhysics = nil
        end
        TeleportBehind.release(session, {
            getRoot = localFighterRoot,
            getHumanoid = localFighterHumanoid,
        })
    end
    local function startTeleportPhysics()
        if teleportPhysics then
            return
        end
        local function holdAfterPhysics()
            if stopped then
                return
            end
            TeleportBehind.hold(session, {
                getRoot = localFighterRoot,
                getHumanoid = localFighterHumanoid,
            })
        end
        teleportPhysics = {
            RunService.Stepped:Connect(holdAfterPhysics),
            RunService.Heartbeat:Connect(holdAfterPhysics),
        }
    end

    local autoCounterRuntime = AutoCounterRuntime.new({ clock = clock })

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
        clock = clock,
        controlsController = ControlsController,
        getFighter = function()
            return FighterController.LocalFighter
        end,
        getSettings = function()
            return store:Get().settings
        end,
        isActive = localFighterIsActive,
        isTaskActive = localFighterIsTaskActive,
        isInCombat = localFighterIsInCombat,
        isInputCaptured = context.isInputCaptured,
        isTaskInputCaptured = function()
            return context.isInputCaptured() and store:Get().menuVisible ~= true
        end,
        mechanicsController = MechanicsController,
        movementDirection = context.movementDirection,
        taskObstacleProbe = function(origin, direction)
            if
                not Workspace.Raycast
                or typeof(origin) ~= "Vector3"
                or typeof(direction) ~= "Vector3"
            then
                return false
            end
            local params
            if RaycastParams and type(RaycastParams.new) == "function" then
                params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = LocalPlayer.Character
                        and { LocalPlayer.Character }
                    or {}
                params.IgnoreWater = true
            end
            local result =
                Workspace:Raycast(origin + Vector3.new(0, 2, 0), direction.Unit * 6, params)
            return result ~= nil
        end,
        taskParkourProbe = function(origin, direction)
            if
                not Workspace.Raycast
                or typeof(origin) ~= "Vector3"
                or typeof(direction) ~= "Vector3"
            then
                return nil
            end
            local params
            if RaycastParams and type(RaycastParams.new) == "function" then
                params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = LocalPlayer.Character
                        and { LocalPlayer.Character }
                    or {}
                params.IgnoreWater = true
            end
            local unit = direction.Magnitude > 0.01 and direction.Unit or Vector3.zero
            local function blocked(height, length)
                return Workspace:Raycast(origin + Vector3.new(0, height, 0), unit * length, params)
                    ~= nil
            end
            local function groundAt(distance)
                local castOrigin = origin + unit * distance + Vector3.new(0, 5, 0)
                local result = Workspace:Raycast(castOrigin, Vector3.new(0, -13, 0), params)
                return result and result.Normal.Y >= 0.55 and result or nil
            end
            local currentGround = groundAt(0)
            local nearGround = groundAt(3)
            local landing = groundAt(7)
            local result = {
                low = blocked(0.75, 4.5),
                middle = blocked(2.5, 4.5),
                high = blocked(4.5, 4.5),
                landing = landing ~= nil,
            }
            -- Baritone's MovementParkour evaluates bounded jump distances from
            -- shortest to longest, requiring body clearance, a walkable landing,
            -- and overshoot safety before it creates a movement.
            if currentGround and not nearGround then
                local rootHeight = math.clamp(origin.Y - currentGround.Position.Y, 2, 4)
                local fighter = FighterController.LocalFighter
                local humanoid = fighter and fighter.Entity and fighter.Entity.Humanoid
                local walkSpeed = humanoid and humanoid.WalkSpeed or 20
                local jumpPower = humanoid and humanoid.JumpPower or 50
                local gravity = Workspace.Gravity > 0 and Workspace.Gravity or 196.2
                local maxReach = math.clamp(walkSpeed * (2 * jumpPower / gravity) * 0.82, 6, 11)
                local lateral = Vector3.new(-unit.Z, 0, unit.X)
                local function landingPatch(distance, center)
                    if not center then
                        return false
                    end
                    for _, offset in ipairs({
                        lateral * 1.1,
                        lateral * -1.1,
                        unit * 0.9,
                        unit * -0.9,
                    }) do
                        local castOrigin = origin + unit * distance + offset + Vector3.new(0, 5, 0)
                        local patch = Workspace:Raycast(castOrigin, Vector3.new(0, -13, 0), params)
                        if
                            not patch
                            or patch.Normal.Y < 0.55
                            or math.abs(patch.Position.Y - center.Position.Y) > 0.75
                        then
                            return false
                        end
                    end
                    return true
                end
                for _, distance in ipairs({ 6, 8, 10 }) do
                    if distance > maxReach then
                        break
                    end
                    local candidate = groundAt(distance)
                    local overshoot = groundAt(distance + 2)
                    local verticalDelta = candidate
                        and candidate.Position.Y - currentGround.Position.Y
                    local clearTrajectory = not blocked(2.5, distance - 1)
                        and not blocked(4.5, distance - 1)
                    if Workspace.Blockcast and clearTrajectory then
                        local castFrame = CFrame.new(origin + Vector3.new(0, 1.2, 0))
                        clearTrajectory = Workspace:Blockcast(
                            castFrame,
                            Vector3.new(2.4, 4.6, 2.4),
                            unit * math.max(0, distance - 2),
                            params
                        ) == nil
                    end
                    local headClear = candidate
                        and Workspace:Raycast(
                                candidate.Position + Vector3.new(0, 0.35, 0),
                                Vector3.new(0, 5.5, 0),
                                params
                            )
                            == nil
                    if
                        candidate
                        and overshoot
                        and clearTrajectory
                        and headClear
                        and landingPatch(distance, candidate)
                        and verticalDelta >= -2.5
                        and verticalDelta <= 2
                    then
                        result.jumpLanding = candidate.Position + Vector3.new(0, rootHeight, 0)
                        result.jumpDistance = distance
                        result.jumpConfidence = 1
                        result.landing = true
                        break
                    end
                end
            end
            return result
        end,

        taskLineOfSightBlocked = function(origin, targetPosition)
            if
                not Workspace.Raycast
                or typeof(origin) ~= "Vector3"
                or typeof(targetPosition) ~= "Vector3"
            then
                return false
            end
            local displacement = targetPosition - (origin + Vector3.new(0, 2, 0))
            if displacement.Magnitude <= 4 then
                return false
            end
            local params
            if RaycastParams and type(RaycastParams.new) == "function" then
                params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = LocalPlayer.Character
                        and { LocalPlayer.Character }
                    or {}
                params.IgnoreWater = true
            end
            return Workspace:Raycast(
                origin + Vector3.new(0, 2, 0),
                displacement.Unit * (displacement.Magnitude - 3),
                params
            ) ~= nil
        end,
        shouldSuppressJump = function()
            return suppressBhopJump
        end,
        spawn = spawn,
        userInputService = UserInputService,
    })
    local taskLocomotion = TaskLocomotion.new()
    local redLightSafety
    if table.find(context.capabilities or {}, "redLightSafety") then
        local actionName = "UniversalHubRivalsRedLightSafety"
        redLightSafety = RedLightSafety.new({
            enabled = function()
                return not stopped and store:Get().settings.redLightSafety == true
            end,
            hookFunction = context.hookFunction,
            releaseAll = function()
                combatInput:releaseAll()
                trigger.fireHeld = false
                trigger.fireItem = nil
                trigger.held = false
                trigger.heldItem = nil
            end,
            restoreFunction = context.restoreFunction,
            setInputSink = function(enabled)
                if enabled then
                    ContextActionService:BindActionAtPriority(
                        actionName,
                        function()
                            return Enum.ContextActionResult.Sink
                        end,
                        false,
                        Enum.ContextActionPriority.High.Value + 200,
                        Enum.UserInputType.MouseButton1,
                        Enum.UserInputType.MouseButton2,
                        Enum.KeyCode.W,
                        Enum.KeyCode.A,
                        Enum.KeyCode.S,
                        Enum.KeyCode.D,
                        Enum.KeyCode.Space,
                        Enum.KeyCode.LeftShift,
                        Enum.KeyCode.C
                    )
                else
                    ContextActionService:UnbindAction(actionName)
                end
            end,
            stopMovement = function()
                movement:stopTaskCombat()
                movement:stop()
                local humanoid = localFighterHumanoid()
                if humanoid and type(humanoid.Move) == "function" then
                    humanoid:Move(Vector3.zero, false)
                end
            end,
        })
    end

    local function playerTone(player, character)
        return Rivals.playerTone(LocalPlayer, player, character)
    end

    local function isOpponent(player, character)
        return playerTone(player, character) == "enemy"
    end

    local function isTargetable(player, character)
        return Rivals.isTargetable(LocalPlayer, player, character, fighterFor(player), isGunGame())
    end

    local function taskOpponentFighter()
        local localEnvironment = LocalPlayer:GetAttribute("EnvironmentID")
        for _, player in ipairs(Players:GetPlayers()) do
            if
                player ~= LocalPlayer
                and player:GetAttribute("EnvironmentID") == localEnvironment
            then
                local fighter = fighterFor(player)
                if fighter then
                    return fighter, player
                end
            end
        end
        return nil, nil
    end

    local function counterLoadoutReady(fighter)
        local items = fighter and fighter.Items
        if type(items) ~= "table" or next(items) == nil then
            return false
        end
        if type(fighter.Get) == "function" then
            local succeeded, canPick = pcall(fighter.Get, fighter, "CanPickWeapons")
            if succeeded and canPick == true then
                return false
            end
        end
        return true
    end

    local gunGameRuntime = GunGameRuntime.new({
        clock = clock,
        fireTouchInterest = context.fireTouchInterest,
        getFighter = function()
            return FighterController.LocalFighter
        end,
        isActive = localFighterIsActive,
        isGunGame = isGunGame,
        isInCombat = localFighterIsInCombat,
        spawn = spawn,
        store = store,
        wait = context.wait,
        workspace = Workspace,
    })

    local function taskNavigationObservation()
        local fighter = FighterController.LocalFighter
        local entity = fighter and fighter.Entity
        local localRoot = entity and (entity.RootPart or entity.HumanoidRootPart)
        if not localRoot then
            return nil
        end
        local nearest
        local nearestDistance = math.huge
        for _, player in ipairs(Players:GetPlayers()) do
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if humanoid and humanoid.Health > 0 and root and isTargetable(player, character) then
                local distance = (root.Position - localRoot.Position).Magnitude
                if distance < nearestDistance then
                    nearestDistance = distance
                    nearest = {
                        character = character,
                        player = player,
                        part = root,
                        position = root.Position,
                        screenDistance = math.huge,
                        visible = false,
                    }
                end
            end
        end
        return nearest
    end

    local function selectTarget(maxScreenDistance, includeBlocked, ignoreAimFov, preferVisible)
        local settings = store:Get().settings
        local options = {
            includeBlocked = includeBlocked,
            isEligible = isTargetable,
            screenOrigin = UserInputService:GetMouseLocation(),
        }
        if maxScreenDistance then
            options.maxScreenDistance = maxScreenDistance
        elseif not ignoreAimFov then
            local shotOnly = settings.shotAim == true
            local fullScreenAim = shotOnly
                    and (settings.shotFullScreenAim == nil and settings.fullScreenAim or settings.shotFullScreenAim)
                or not shotOnly
                    and (settings.cameraFullScreenAim == nil and settings.fullScreenAim or settings.cameraFullScreenAim)
            if not fullScreenAim then
                options.maxScreenDistance = shotOnly and (settings.shotFov or settings.fov)
                    or (settings.cameraFov or settings.fov)
            end
        end
        local preferredVisible = false
        if preferVisible then
            for _, observation in ipairs(observations) do
                local screenDistance = observation.screenDistance
                if
                    observation.visible == true
                    and (options.maxScreenDistance == nil or type(screenDistance) == "number" and screenDistance <= options.maxScreenDistance)
                    and (
                        observation.player == observation.character
                        or isTargetable(observation.player, observation.character)
                    )
                then
                    preferredVisible = true
                    break
                end
            end
        end
        local function nearest(values)
            local eligible = {}
            for _, observation in ipairs(values) do
                if
                    (not preferredVisible or observation.visible == true)
                    and (
                        observation.player == observation.character
                        or isTargetable(observation.player, observation.character)
                    )
                then
                    table.insert(eligible, observation)
                end
            end
            if settings.humanAim then
                local camera = Workspace.CurrentCamera
                local cameraFrame = camera
                    and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
                return Targeting.closestObservation(
                    eligible,
                    cameraFrame and cameraFrame.Position,
                    options
                )
            end
            return targeting.nearestObservation(eligible, options)
        end
        local selected
        if isGunGame() then
            local fighter = FighterController.LocalFighter
            local item = fighter and fighter.EquippedItem
            local camera = Workspace.CurrentCamera
            local cameraFrame = camera
                and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
            local origin = cameraFrame and cameraFrame.Position
            local function accepted(observation)
                if not includeBlocked and observation.visible ~= true then
                    return nil
                end
                return nearest({ observation })
            end
            local function finishable(observation)
                local candidate = accepted(observation)
                local distance = candidate
                    and origin
                    and candidate.position
                    and (candidate.position - origin).Magnitude
                local damage = candidate and WeaponPolicy.finishingDamage(item, candidate, distance)
                return type(damage) == "number"
                        and type(candidate.health) == "number"
                        and damage >= candidate.health
                        and candidate
                    or nil
            end
            selected = Rivals.lowestHealthObservation(observations, finishable, nearest)
                or Rivals.lowestHealthObservation(observations, accepted, nearest)
                or nearest(observations)
            aimTargetKey = selected and (selected.character or selected.player or selected.part)
                or nil
        else
            selected, aimTargetKey =
                Targeting.selectObservation(observations, aimTargetKey, nearest)
        end
        return selected
    end

    local function selectBackstabTarget(localPosition, info, acquisitionDistance)
        local nearest
        local nearestDistance = math.huge
        local lowestHealth = math.huge
        for _, observation in ipairs(observations) do
            local character = observation.character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local plan =
                WeaponPolicy.backstabPlan(localPosition, observation, info, acquisitionDistance)
            if
                observation.visible
                and isTargetable(observation.player, character)
                and root
                and plan
            then
                local distance = (localPosition - root.Position).Magnitude
                local health = type(observation.health) == "number" and observation.health
                    or math.huge
                local preferred = isGunGame()
                        and (health < lowestHealth or health == lowestHealth and distance < nearestDistance)
                    or not isGunGame() and distance < nearestDistance
                if preferred then
                    nearest = table.clone(observation)
                    nearest.backstabPlan = plan
                    nearestDistance = distance
                    lowestHealth = health
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

    local function selectDualModeBladeTarget(fighter, item)
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
                local result = position
                    and gunbladeRaycast
                    and gunbladeRaycast(localRoot.Position, position - localRoot.Position)
                local instance = result and result.Instance
                local clear = not instance
                    or instance.IsDescendantOf and instance:IsDescendantOf(character)
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

    local function plannedAimTarget(target, item, rateOverrides)
        local now = clock()
        local settings = store:Get().settings
        local headshotRate = rateOverrides and rateOverrides.headshotRate or settings.headshotRate
        local missRate = rateOverrides and rateOverrides.missRate or settings.missRate
        local options = headAimOptions()
        if
            aimPlan
            and aimPlan.character == target.character
            and aimPlan.headshotRate == headshotRate
            and aimPlan.humanAim == settings.humanAim
            and aimPlan.item == item
            and aimPlan.missRate == missRate
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
        local aimSettings = settings
        if rateOverrides then
            aimSettings = table.clone(settings)
            aimSettings.headshotRate = headshotRate
            aimSettings.missRate = missRate
        end
        local planned = Targeting.applyAimRates(target, aimSettings, random, options)
        aimPlan = {
            character = target.character,
            expiresAt = now + math.max(TRIGGER_INTERVAL, cooldown or TRIGGER_INTERVAL),
            headshotRate = headshotRate,
            humanAim = settings.humanAim,
            item = item,
            missRate = missRate,
            target = planned,
        }
        return planned
    end

    local solveRicochet = context.solveRicochet or ProjectileAim.solveRicochet
    local solveSplashAim = context.solveSplashAim or ProjectileAim.solveSplashAim
    local solveBouncingProjectile = context.solveBouncingProjectile
        or ProjectileAim.solveBouncingProjectile

    local observationRuntime = ObservationRuntime.new({
        effects = effects,
        equippedWeapon = equippedWeapon,
        getFighter = function()
            return FighterController.LocalFighter
        end,
        getPlayerTone = playerTone,
        isOpponent = isOpponent,
        targeting = targeting,
        workspace = Workspace,
    })

    local function setAimRotation(rotation, instant, character, maximumHumanSmoothness)
        local applied = rotation
        local function commitCameraFrame(committedRotation)
            local camera = Workspace.CurrentCamera
            if not camera then
                return
            end

            -- SetRotation can be ignored while the native subject is frozen (for
            -- example while a modal menu is open).  This adapter owns the final
            -- task-combat render step, so also commit the requested orientation
            -- directly while preserving the native camera position.
            TaskCamera.commit(camera, committedRotation)
        end
        if instant then
            CameraController:SetRotation(rotation)
            commitCameraFrame(rotation)
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
        commitCameraFrame(applied)
        local pitchError = math.abs(rotation.X - applied.X)
        local yawError = math.abs((rotation.Y - applied.Y + math.pi) % (math.pi * 2) - math.pi)
        return math.max(pitchError, yawError) <= math.rad(0.5)
    end

    local function publishAutoCounterDebug(extra)
        local status = autoCounterRuntime:status()
        for key, value in pairs(extra or {}) do
            status[key] = value
        end
        self.autoCounterDebug = status
    end

    local function humanoidStateName(humanoid)
        if not humanoid or type(humanoid.GetState) ~= "function" then
            return nil
        end
        local succeeded, state = pcall(humanoid.GetState, humanoid)
        if not succeeded or state == nil then
            return nil
        end
        local nameSucceeded, name = pcall(function()
            return state.Name
        end)
        if nameSucceeded and type(name) == "string" then
            return name
        end
        return tostring(state):match("([^%.]+)$")
    end

    local function updateAutoCounterDetector(settings)
        local roundEligible = localFighterIsInRound()
        local fighter = FighterController.LocalFighter
        local entity = fighter and fighter.Entity
        local root = entity and (entity.RootPart or entity.HumanoidRootPart)
        local humanoid = entity and entity.Humanoid
        autoCounterRuntime:update({
            alive = humanoid ~= nil and humanoid.Health > 0,
            enabled = settings.autoCounter == true,
            epoch = entity,
            humanoidState = humanoidStateName(humanoid),
            now = clock(),
            position = root and root.Position,
            roundEligible = roundEligible,
        })
        publishAutoCounterDebug()
    end

    local function runAutoCounter(settings)
        return AutoCounter.fire(settings, {
            runtime = autoCounterRuntime,
            inFlight = autoCounterInFlight,
            inputCaptured = context.isInputCaptured(),
            fighterActive = localFighterIsActive(),
            inRound = localFighterIsInRound(),
            getFighter = function()
                return FighterController.LocalFighter
            end,
            selectTarget = selectTarget,
            camera = Workspace.CurrentCamera,
            headAimOptions = headAimOptions,
            isTargetable = isTargetable,
            targeting = Targeting,
            weaponPolicy = WeaponPolicy,
            itemClock = itemClock,
            isDeflecting = isDeflecting,
            localFighterIsCrouching = localFighterIsCrouching,
            cameraController = CameraController,
            releaseTrigger = function()
                releaseFire()
                if trigger.held then
                    finishAiming()
                    trigger.held = false
                    trigger.heldItem = nil
                end
            end,
            clearAimPlan = function()
                aimPlan = nil
            end,
            setInFlight = function(value)
                autoCounterInFlight = value
            end,
            setAimRotation = setAimRotation,
            interval = TRIGGER_INTERVAL,
            clock = clock,
            click = startShooting,
            commitCamera = TaskCamera.commit,
            publishDebug = publishAutoCounterDebug,
        })
    end

    local function stopAutoCounter(reason)
        autoCounterRuntime:disable(reason or "disabled")
        autoCounterInFlight = false
        publishAutoCounterDebug()
    end

    local cameraAim = CameraAim.new({
        targeting = Targeting,
        projectileAim = ProjectileAim,
        weaponPolicy = WeaponPolicy,
    })
    local function alignCamera(shotOnly, taskCombatActive)
        return cameraAim:align({
            shotOnly = shotOnly,
            taskCombatActive = taskCombatActive,
            settings = store:Get().settings,
            inputCaptured = context.isInputCaptured(),
            fighterActive = taskCombatActive == true and localFighterIsTaskActive()
                or localFighterIsActive(),
            inCombat = localFighterIsInCombat(),
            fighter = FighterController.LocalFighter,
            camera = Workspace.CurrentCamera,
            clock = clock,
            renderDelta = renderDelta,
            gravity = Workspace.Gravity,
            getNetworkPing = getNetworkPing,
            environmentRaycast = environmentRaycast,
            solveBouncingProjectile = solveBouncingProjectile,
            solveSplashAim = solveSplashAim,
            solveRicochet = solveRicochet,
            setAimRotation = setAimRotation,
            selectTarget = selectTarget,
            selectBackstabTarget = selectBackstabTarget,
            taskNavigationObservation = taskNavigationObservation,
            plannedAimTarget = plannedAimTarget,
            taskSkillRuntime = taskSkillRuntime,
            taskDebug = self.taskDebug,
            clearRetention = function(clearPlan)
                aimTargetKey = nil
                aimTargetWeapon = nil
                if clearPlan then
                    aimPlan = nil
                end
            end,
            rememberWeapon = function(item)
                if aimTargetWeapon ~= item then
                    aimTargetKey = nil
                    aimTargetWeapon = item
                end
            end,
            rememberTarget = function(target)
                aimTargetKey = target.character or target.player or target.part
            end,
            clearTargetKey = function()
                aimTargetKey = nil
            end,
        })
    end

    local hookRuntime = HookRuntime.new({
        capabilities = context.capabilities,
        hookFunction = context.hookFunction,
        restoreFunction = context.restoreFunction,
        skipBlocks = {
            getFighter = function()
                return FighterController.LocalFighter
            end,
            hookFunction = context.hookFunction,
            isEnabled = function()
                return not stopped and store:Get().settings.skipDeflect == true
            end,
            restoreFunction = context.restoreFunction,
            shouldBlock = function(item)
                local settings = store:Get().settings
                local target = settings.shotAim == true and session.presented or session.aligned
                if not target and settings.shotAim ~= true then
                    target = selectTarget(nil, true, true)
                end
                return SkipBlocks.shouldBlock(item, target, {
                    isDeflecting = isDeflecting,
                    fighterFor = fighterFor,
                    taskCounterPolicy = TaskCounterPolicy,
                })
            end,
        },
        scopedAccuracy = {
            getFighter = function()
                return FighterController.LocalFighter
            end,
            hookFunction = context.hookFunction,
            isEnabled = function()
                return not stopped and store:Get().settings.alwaysScoped == true
            end,
            restoreFunction = context.restoreFunction,
        },
        shotPresentation = {
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
        },
    })
    local shotPresentation = hookRuntime.presentation

    local function refreshHooks()
        hookRuntime:refresh()
    end

    local function triggerContext(alignedTarget, taskCombatActive)
        return {
            alignedTarget = alignedTarget,
            taskCombatActive = taskCombatActive,
            inputCaptured = context.isInputCaptured(),
            fighterActive = taskCombatActive == true and localFighterIsTaskActive()
                or localFighterIsActive(),
            inCombat = localFighterIsInCombat(),
            state = trigger,
            taskDebug = self.taskDebug,
            weaponPolicy = WeaponPolicy,
            projectileAim = ProjectileAim,
            targeting = Targeting,
            taskCounterPolicy = TaskCounterPolicy,
            interval = TRIGGER_INTERVAL,
            radius = TRIGGER_RADIUS,
            clock = clock,
            itemClock = itemClock,
            getFighter = function()
                return FighterController.LocalFighter
            end,
            selectDualModeBladeTarget = selectDualModeBladeTarget,
            selectTarget = selectTarget,
            isDeflecting = isDeflecting,
            isGunGame = isGunGame,
            localFighterIsCrouching = localFighterIsCrouching,
            fighterFor = fighterFor,
            targetRootPosition = targetRootPosition,
            releaseFire = releaseFire,
            clearAimPlan = function()
                aimPlan = nil
            end,
            camera = Workspace.CurrentCamera,
            cameraController = CameraController,
            gravity = Workspace.Gravity,
            raycast = type(environmentRaycast) == "function" and environmentRaycast() or nil,
            click = startShooting,
            aimClick = startAiming,
            aimPress = function()
                return combatInput:pressAim()
            end,
            aimRelease = finishAiming,
            press = function()
                return combatInput:pressFire()
            end,
        }
    end
    local function runTriggerBot(alignedTarget, taskCombatActive)
        TriggerBot.update(session, triggerContext(alignedTarget, taskCombatActive))
    end

    local function taskMovementPosition(alignedTarget)
        local position = targetRootPosition(alignedTarget)
        if typeof(position) == "Vector3" then
            return position
        end
        local fighter = FighterController.LocalFighter
        local entity = fighter and fighter.Entity
        local localRoot = entity and (entity.RootPart or entity.HumanoidRootPart)
        if not localRoot then
            return nil
        end
        local nearestPosition
        local nearestDistance = math.huge
        for _, player in ipairs(Players:GetPlayers()) do
            local character = player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if root and isTargetable(player, character) then
                local distance = (root.Position - localRoot.Position).Magnitude
                if distance < nearestDistance then
                    nearestDistance = distance
                    nearestPosition = root.Position
                end
            end
        end
        return nearestPosition
    end

    local renderConnection
    local renderBindingName = "UniversalHubRivalsFrame"
    local settingsSubscription
    local ensureTaskLoadoutPoll
    local function updateFrame(deltaTime)
        if stopped then
            return
        end
        local settings = store:Get().settings
        if skinUnlock then
            skinUnlock:step()
        end
        if redLightSafety then
            local duel = DuelController:GetDuel(LocalPlayer)
            redLightSafety:refresh(duel and duel.ChickenGame)
            if settings.redLightSafety ~= true then
                redLightSafety:setPaused(false)
            elseif redLightSafety:isPaused() then
                redLightSafety:holdStill()
                return
            end
        end
        if ensureTaskLoadoutPoll then
            ensureTaskLoadoutPoll()
        end
        local taskCombatActive = taskFarmRuntime and taskFarmRuntime:isCombatActive() == true
        if taskCombatActive ~= taskSkillWasActive then
            taskSkillRuntime:reset()
            taskSkillWasActive = taskCombatActive
        end
        if NoScope.shouldRefresh(settings) or settings.skipDeflect == true then
            refreshHooks()
        end
        if type(deltaTime) == "number" and deltaTime > 0 then
            renderDelta = deltaTime
        end

        updateAutoCounterDetector(settings)

        Pickup.update({ settings = settings }, gunGameRuntime)
        local overlayVisualsEnabled = settings.names == true
            or settings.health == true
            or settings.weapon == true
        local limnVisualsEnabled = settings.worldRenderer ~= "native"
            and (settings.boxes == true or settings.chams == true or overlayVisualsEnabled)
        local observationsEnabled = settings.silentAim == true
            or settings.shotAim == true
            or settings.triggerBot == true
            or settings.autoCounter == true
            or settings.teleportBehind == true
            or taskCombatActive
            or limnVisualsEnabled
            or overlayVisualsEnabled
        if observationsEnabled then
            observations, visualObservations = observationRuntime:update(
                UserInputService:GetMouseLocation(),
                settings.showTeammates == true,
                settings.showEnemies ~= false
            )
        elseif #observations > 0 or #visualObservations > 0 then
            observations = {}
            visualObservations = observations
        end
        local utilityObservations = {}
        local taskHazards = utilityObservations
        local fighter = FighterController.LocalFighter
        if
            (settings.utilityEsp == true or taskCombatActive)
            and localFighterIsInCombat()
            and Workspace.CurrentCamera
        then
            local data = fighter and fighter.Data
            local environmentID = type(data) == "table" and data.EnvironmentID
                or LocalPlayer:GetAttribute("EnvironmentID")
            taskHazards = observeThrowables(Workspace.CurrentCamera, environmentID)
            if settings.utilityEsp == true then
                utilityObservations = taskHazards
            end
        end
        if not settingsSubscription then
            effects:update(settings)
        end
        context.render(visualObservations, UserInputService:GetMouseLocation(), utilityObservations)

        local autoCounterActed = runAutoCounter(settings)
        local alignedTarget
        local aimEnabled = not autoCounterActed
            and (settings.silentAim == true or settings.shotAim == true or taskCombatActive)
        if aimEnabled then
            alignedTarget = alignCamera(false, taskCombatActive)
            if not alignedTarget and settings.shotAim then
                alignedTarget = alignCamera(true, taskCombatActive)
            end
        end
        local taskWeaponDistance
        local taskRoot = fighter
            and fighter.Entity
            and (fighter.Entity.RootPart or fighter.Entity.HumanoidRootPart)
        local taskTargetPosition = alignedTarget and targetRootPosition(alignedTarget)
        if taskRoot and taskTargetPosition then
            taskWeaponDistance = (taskTargetPosition - taskRoot.Position).Magnitude
        end
        movement:updateInfiniteJump(settings)
        movement:updateWallNoclip(settings)
        local taskTactical
        if taskCombatActive and alignedTarget and alignedTarget.player then
            local opponentFighter = fighterFor(alignedTarget.player)
            local opponentItem = opponentFighter and opponentFighter.EquippedItem
            taskTactical = {
                pushSniper = WeaponPolicy.isScoped(opponentItem),
                avoidSniperPeek = WeaponPolicy.isScoped(opponentItem)
                    and WeaponPolicy.isAiming(opponentItem),
            }
        end
        local counterSwitching = false
        if taskCombatActive and alignedTarget and alignedTarget.player then
            local opponentFighter = fighterFor(alignedTarget.player)
            local counterActive = counterLoadoutReady(opponentFighter)
                    and taskCounterPolicy:update(opponentFighter.EquippedItem)
                or false
            if
                counterActive
                and fighter
                and fighter.EquippedItem
                and not WeaponPolicy.isTrueDamage(fighter.EquippedItem)
                and clock() >= nextCounterEquipAt
            then
                local spray
                for key, value in pairs(fighter.Items or {}) do
                    local item = type(value) == "table" and value
                        or type(key) == "table" and key
                        or nil
                    if
                        item
                        and WeaponPolicy.isTrueDamage(item)
                        and (WeaponPolicy.ammo(item) or 0) > 0
                    then
                        spray = item
                        break
                    end
                end
                if spray then
                    releaseFire()
                    if taskWeaponSwap.equip(fighter, spray) then
                        nextCounterEquipAt = clock() + 0.75
                        counterSwitching = true
                        self.taskDebug.counterWeapon = WeaponPolicy.itemName(spray) or "Spray"
                    end
                end
            end
        end
        local taskWeaponSwapping = counterSwitching
            or taskWeaponSwap:update(taskCombatActive, fighter, alignedTarget, taskWeaponDistance)
        if taskWeaponSwapping then
            alignedTarget = nil
        end
        session.settings = settings
        session.aligned = alignedTarget
        session.active = taskCombatActive == true and localFighterIsTaskActive()
            or localFighterIsActive()
        session.inCombat = localFighterIsInCombat()
        session.inRound = localFighterIsInRound()
        session.inputCaptured = context.isInputCaptured()
        session.taskCombat = taskCombatActive == true
        if settings.teleportBehind == true then
            local libs = teleportLibs()
            libs.selectTarget = function()
                return selectTarget(nil, true, true)
            end
            TeleportBehind.update(session, libs)
            startTeleportPhysics()
            local lookTarget = session.presented or alignedTarget
            local movedRoot = localFighterRoot()
            local lookPoint = movedRoot and TeleportBehind.aimPoint(movedRoot.Position, lookTarget)
            if movedRoot and typeof(lookPoint) == "Vector3" then
                setAimRotation(
                    Targeting.rotationToward(movedRoot.Position, lookPoint),
                    true,
                    lookTarget and lookTarget.character
                )
                session.cameraOrigin = movedRoot.Position
                if alignedTarget then
                    alignedTarget.position = lookPoint
                    alignedTarget.aimSettled = true
                    session.aligned = alignedTarget
                end
            end
        elseif settingsSubscription then
            stopTeleportPhysics()
        end
        local camera = Workspace.CurrentCamera
        local cameraFrame = camera
            and (camera.GetRenderCFrame and camera:GetRenderCFrame() or camera.CFrame)
        local movedRoot = localFighterRoot()
        session.cameraOrigin = cameraFrame and cameraFrame.Position
            or movedRoot and movedRoot.Position
            or nil
        if session.teleportEngaged == true and movedRoot then
            session.cameraOrigin = movedRoot.Position
        end
        if settings.shotAim == true or not settingsSubscription then
            SilentAim.update(session, shotPresentation, {
                targeting = Targeting,
                maxDistance = ProjectileAim.MAX_DISTANCE,
            })
        end
        local triggerTarget = alignedTarget
        if settings.shotAim == true then
            triggerTarget = session.presented
        end
        if taskCombatActive then
            local movementTarget = taskMovementPosition(alignedTarget)
            local locomotionPlan
            if taskRoot and typeof(movementTarget) == "Vector3" then
                local routeClear = true
                if type(environmentRaycast) == "function" then
                    local cast = environmentRaycast()
                    local offset = movementTarget - taskRoot.Position
                    if type(cast) == "function" and offset.Magnitude > 1 then
                        routeClear = cast(
                            taskRoot.Position,
                            offset.Unit * math.min(offset.Magnitude, 6)
                        ) == nil
                    end
                end
                locomotionPlan = taskLocomotion:plan({
                    clear = routeClear,
                    grounded = localFighterIsTaskActive(),
                    now = clock(),
                    position = taskRoot.Position,
                    targetPosition = movementTarget,
                })
            end
            movement:updateTaskCombat(movementTarget, taskHazards, taskTactical, locomotionPlan)
            self.taskDebug.parkour = movement.taskParkourCommit and "committed" or "grounded-route"
        else
            movement:stopTaskCombat()
        end
        if settings.bhop == true then
            suppressBhopJump = WeaponPolicy.isBackstabKnife(fighter and fighter.EquippedItem)
                and alignedTarget ~= nil
                and alignedTarget.knifePath ~= nil
            movement:update(settings)
        elseif not settingsSubscription then
            suppressBhopJump = false
            movement:stop()
        end
        if aimEnabled then
            local trajectory = alignedTarget
                and (
                    (alignedTarget.ricochet and alignedTarget.ricochet.path)
                    or (alignedTarget.slingshot and alignedTarget.slingshot.path)
                    or alignedTarget.knifePath
                )
            effects:renderTrajectory(trajectory)
        elseif not settingsSubscription then
            effects:renderTrajectory(nil)
        end
        local targetDeflecting = settings.skipDeflect == true
                and triggerTarget
                and triggerTarget.player
                and isDeflecting(triggerTarget.player)
            or false
        combatInput:setDeflecting(targetDeflecting)
        if settings.skipDeflect == true then
            local equipped = fighter and fighter.EquippedItem
            SkipBlocks.update(equipped, triggerTarget, {
                isDeflecting = isDeflecting,
                fighterFor = fighterFor,
                taskCounterPolicy = TaskCounterPolicy,
                fireHeld = trigger.fireHeld,
                releaseFire = function()
                    finishShooting()
                    trigger.fireHeld = false
                    trigger.fireItem = nil
                end,
            })
        end
        local autoDeflectActed = false
        if settings.autoDeflect == true then
            local entity = fighter and fighter.Entity
            local humanoid = entity and entity.Humanoid
            local ours = entity and entity.Character or LocalPlayer.Character
            local opponents = {}
            local map = FighterController._player_to_fighter
            if type(map) == "table" then
                for player, opponentFighter in pairs(map) do
                    local character = player and player.Character
                    if
                        player ~= LocalPlayer
                        and opponentFighter
                        and character
                        and isTargetable(player, character)
                    then
                        opponents[#opponents + 1] = {
                            player = player,
                            character = character,
                            EquippedItem = opponentFighter.EquippedItem,
                        }
                    end
                end
            end
            autoDeflectActed = AutoDeflect.update(settings, {
                inputCaptured = context.isInputCaptured(),
                fighterActive = localFighterIsActive(),
                inCombat = localFighterIsInCombat(),
                getFighter = function()
                    return FighterController.LocalFighter
                end,
                weaponPolicy = WeaponPolicy,
                itemClock = itemClock,
                health = humanoid and humanoid.Health,
                character = ours,
                opponents = opponents,
                hasLine = function(origin, point, opponentCharacter)
                    local cast = type(environmentRaycast) == "function" and environmentRaycast()
                    if
                        type(cast) ~= "function"
                        or typeof(origin) ~= "Vector3"
                        or typeof(point) ~= "Vector3"
                    then
                        return true
                    end
                    local delta = point - origin
                    local distance = delta.Magnitude
                    if distance < 1 then
                        return true
                    end
                    local result = cast(origin, delta.Unit, distance)
                    if not result or not result.Instance then
                        return true
                    end
                    if ours and result.Instance:IsDescendantOf(ours) then
                        return true
                    end
                    if opponentCharacter and result.Instance:IsDescendantOf(opponentCharacter) then
                        return true
                    end
                    return false
                end,
                aimClick = startAiming,
                taskDebug = self.taskDebug,
            })
        end
        if
            not autoCounterActed
            and not autoDeflectActed
            and (
                settings.triggerBot == true
                or taskCombatActive
                or trigger.held
                or trigger.fireHeld
                or not settingsSubscription
            )
        then
            runTriggerBot(triggerTarget, taskCombatActive)
        end
    end

    local reconcileFrameLifecycle
    local reconcileTaskEmergency
    local function taskStatusChanged(status)
        if reconcileTaskEmergency then
            reconcileTaskEmergency(status)
        end
    end
    local function taskActivityChanged(_, status)
        taskStatusChanged(status)
        if reconcileFrameLifecycle then
            reconcileFrameLifecycle(store:Get())
        end
    end
    local practiceTaskDriver = context.practiceTaskDriver
    if practiceTaskDriver == nil and context.taskFarmRuntime == nil then
        practiceTaskDriver = PracticeTaskDriver.new({
            getFighter = function()
                return FighterController.LocalFighter
            end,
            actions = {
                enterRange = function()
                    local result = ShootingRangeController:Enter()
                    return result ~= false
                end,
                slide = function()
                    local fighter = FighterController.LocalFighter
                    if
                        not fighter
                        or type(fighter.CanSlide) ~= "function"
                        or fighter:CanSlide() ~= true
                    then
                        return false
                    end
                    MechanicsController:Slide()
                    return true
                end,
                equip = function(name)
                    local fighter = FighterController.LocalFighter
                    if
                        not fighter
                        or type(fighter.GetItem) ~= "function"
                        or type(fighter.EquipItem) ~= "function"
                    then
                        return false
                    end
                    local item = fighter:GetItem(name)
                    if not item then
                        return false
                    end
                    local result = fighter:EquipItem(item)
                    return result ~= false
                end,
                secondary = function()
                    startAiming()
                    return true
                end,
                primary = function()
                    startShooting()
                    return true
                end,
                releaseAll = function()
                    if trigger.held then
                        finishAiming()
                        trigger.held = false
                    end
                    releaseFire()
                end,
            },
        })
    end
    taskFarmRuntime = context.taskFarmRuntime
        or TaskFarmRuntime.new({
            constants = RivalsConstants,
            duelController = DuelController,
            fighterController = FighterController,
            localPlayer = LocalPlayer,
            matchmakingController = MatchmakingController,
            playerDataController = PlayerDataController,
            practiceDriver = practiceTaskDriver,
            taskLibrary = TaskLibrary,
            paused = store:Get().settings.taskAutomationPaused == true,
            onActivityChanged = taskActivityChanged,
            onStatusChanged = taskStatusChanged,
            onManualDuel = function()
                local state = store:Get()
                if state.settings.taskAutomationPaused == true then
                    return
                end
                local settings = table.clone(state.settings)
                settings.taskAutomationPaused = true
                store:Patch({ settings = settings })
                if type(context.settingsChanged) == "function" then
                    context.settingsChanged(settings)
                end
            end,
        })
    if type(taskFarmRuntime.setActivityChanged) == "function" then
        taskFarmRuntime:setActivityChanged(taskActivityChanged)
    end
    if type(taskFarmRuntime.setStatusChanged) == "function" then
        taskFarmRuntime:setStatusChanged(taskStatusChanged)
    end
    local function currentTaskStatus()
        if type(taskFarmRuntime.status) == "function" then
            return taskFarmRuntime:status()
        end
        return { state = "idle", paused = false, task = nil }
    end
    taskStatusChanged(currentTaskStatus())
    self.taskFarmRuntime = taskFarmRuntime

    local loadoutOpenConnection
    local loadoutVisibleConnection
    local taskLoadout = TaskLoadout.new({
        clock = clock,
        constants = RivalsConstants,
        getOpponentFighter = taskOpponentFighter,
        getStatus = currentTaskStatus,
        page = PickWeaponsPage,
        taskCounterPolicy = TaskCounterPolicy,
        taskDebug = self.taskDebug,
        taskPolicy = TaskPolicy,
    })
    local function stopLoadoutPoll()
        taskLoadout:stop()
    end
    ensureTaskLoadoutPoll = function()
        taskLoadout:poll()
    end

    reconcileTaskEmergency = function(status)
        status = status or currentTaskStatus()
        local armed = status.task ~= nil
            and status.paused ~= true
            and status.state ~= "idle"
            and status.state ~= "stopped"
        if not armed then
            if taskEmergencyConnection then
                taskEmergencyConnection:Disconnect()
                taskEmergencyConnection = nil
            end
            return
        end
        if taskEmergencyConnection then
            return
        end
        taskEmergencyConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then
                return
            end
            local keyCode = input and input.KeyCode
            local pressedName = keyCode and keyCode.Name
            local currentState = store:Get()
            local settings = currentState.settings or {}
            if pressedName ~= (settings.taskAutomationEmergencyKey or "End") then
                return
            end
            local updated = table.clone(settings)
            updated.taskAutomationPaused = true
            store:Patch({ settings = updated })
            if type(context.settingsChanged) == "function" then
                context.settingsChanged(updated)
            end
        end)
    end
    reconcileTaskEmergency(currentTaskStatus())

    local function frameWorkEnabled(state)
        local settings = state.settings or {}
        local playerVisuals = settings.boxes == true
            or settings.chams == true
            or settings.names == true
            or settings.health == true
            or settings.weapon == true
        local playerFrame = playerVisuals
            and (settings.worldRenderer ~= "native" or state.menuVisible ~= false)
        return taskFarmRuntime:isCombatActive() == true
            or PickWeaponsPage:IsOpen()
            or settings.silentAim == true
            or settings.shotAim == true
            or settings.triggerBot == true
            or settings.autoCounter == true
            or settings.alwaysScoped == true
            or settings.bhop == true
            or settings.infiniteJump == true
            or settings.wallNoclip == true
            or settings.teleportBehind == true
            or settings.autoPickup == true
            or settings.utilityEsp == true
            or settings.fovCircle == true
            or playerFrame
    end

    local function connectFrame()
        if renderConnection then
            return
        end
        if
            context.requireModule == nil
            and type(RunService.BindToRenderStep) == "function"
            and type(RunService.UnbindFromRenderStep) == "function"
        then
            local priority = Enum.RenderPriority.Last.Value
            RunService:BindToRenderStep(renderBindingName, priority, updateFrame)
            renderConnection = {
                Disconnect = function()
                    RunService:UnbindFromRenderStep(renderBindingName)
                end,
            }
        else
            renderConnection = RunService.RenderStepped:Connect(updateFrame)
        end
    end

    local function disconnectFrame()
        if renderConnection then
            renderConnection:Disconnect()
            renderConnection = nil
        end
    end

    reconcileFrameLifecycle = function(state)
        if stopped then
            return
        end
        local settings = state.settings or {}
        local pausedSetting = settings.taskAutomationPaused == true
        if pausedSetting ~= lastTaskPauseSetting then
            local wasPaused = lastTaskPauseSetting
            lastTaskPauseSetting = pausedSetting
            if type(context.settingsChanged) == "function" then
                context.settingsChanged(settings)
            end
            -- Starting the farm closes the hub once. Subsequent manual menu
            -- opens are respected while farming remains active.
            if wasPaused and not pausedSetting and state.menuVisible ~= false then
                store:Patch({ menuVisible = false })
                return
            end
        end
        if type(taskFarmRuntime.status) == "function" then
            local taskStatus = taskFarmRuntime:status()
            if settings.taskAutomationPaused == true and not taskStatus.paused then
                taskFarmRuntime:pause("user")
            elseif settings.taskAutomationPaused ~= true and taskStatus.paused then
                taskFarmRuntime:resume()
            end
        end
        if skinUnlock then
            skinUnlock:update(settings)
        end
        effects:update(settings)
        refreshHooks()
        if settings.autoCounter ~= true then
            stopAutoCounter("disabled")
        end
        if frameWorkEnabled(state) then
            connectFrame()
            return
        end
        disconnectFrame()
        stopTeleportPhysics()
        context.render({}, UserInputService:GetMouseLocation(), {})
        movement:stop()
        movement:stopWallNoclip()
        effects:renderTrajectory(nil)
        shotPresentation:clear()
        runTriggerBot(nil, false)
    end

    local function loadoutVisibilityChanged()
        if stopped then
            return
        end
        if PickWeaponsPage:IsOpen() then
            if ensureTaskLoadoutPoll then
                ensureTaskLoadoutPoll()
            end
        elseif taskLoadout.wasOpen then
            stopLoadoutPoll()
            self.taskDebug.loadoutStage = "closed"
        end
        reconcileFrameLifecycle(store:Get())
    end
    if PickWeaponsPage.OpenChanged and type(PickWeaponsPage.OpenChanged.Connect) == "function" then
        loadoutOpenConnection = PickWeaponsPage.OpenChanged:Connect(loadoutVisibilityChanged)
    end
    if
        PickWeaponsPage.PageFrame
        and type(PickWeaponsPage.PageFrame.GetPropertyChangedSignal) == "function"
    then
        loadoutVisibleConnection = PickWeaponsPage.PageFrame
            :GetPropertyChangedSignal("Visible")
            :Connect(loadoutVisibilityChanged)
    end

    if type(store.Subscribe) == "function" then
        settingsSubscription = store:Subscribe(reconcileFrameLifecycle)
        reconcileFrameLifecycle(store:Get())
    else
        connectFrame()
    end

    function self.stop()
        if stopped then
            return
        end
        stopped = true
        if redLightSafety then
            redLightSafety:stop()
        end
        if skinUnlock then
            skinUnlock:stop()
        end
        if taskEmergencyConnection then
            taskEmergencyConnection:Disconnect()
            taskEmergencyConnection = nil
        end
        stopLoadoutPoll()
        if loadoutOpenConnection then
            loadoutOpenConnection:Disconnect()
            loadoutOpenConnection = nil
        end
        if loadoutVisibleConnection then
            loadoutVisibleConnection:Disconnect()
            loadoutVisibleConnection = nil
        end
        taskFarmRuntime:stop()
        gunGameRuntime:stop()
        hookRuntime:stop()
        autoCounterRuntime:stop()
        if trigger.held then
            finishAiming()
            trigger.held = false
        end
        releaseFire()
        movement:stop()
        movement:stopWallNoclip()
        effects:stop()
        if settingsSubscription then
            settingsSubscription()
            settingsSubscription = nil
        end
        stopTeleportPhysics()
        disconnectFrame()
    end

    self.capabilities = context.capabilities or {}
    self.autoCounterRuntime = autoCounterRuntime
    self.isOpponent = isOpponent
    self.selectTarget = selectTarget
    self.worldPolicy = WorldPolicy.new({
        getLocalFighter = function()
            return FighterController.LocalFighter
        end,
        getWeapon = equippedWeapon,
        getFighter = fighterFor,
        isOpponent = isOpponent,
        getPlayerTone = playerTone,
        localPlayer = LocalPlayer,
        workspace = Workspace,
    })

    return self
end

return Rivals
