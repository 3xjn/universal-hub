local buildId = [[610c86b0]]
local shared = {
    ["changelog.json"] = [[{
  "current": "0.3.0",
  "releases": [
    {
      "version": "0.3.0",
      "channel": "beta",
      "date": "2026-08-15",
      "title": "Warp",
      "added": [
        {
          "tab": "Rage",
          "name": "Warp",
          "note": "hops around your opponent"
        }
      ],
      "changed": [],
      "fixed": [
        {
          "tab": "Combat",
          "name": "Trigger Bot",
          "note": "uses line of sight, not just who's on screen"
        },
        {
          "tab": "Movement",
          "name": "Wall Noclip",
          "note": "stays put when the menu opens"
        }
      ]
    },
    {
      "version": "0.2.0",
      "channel": "beta",
      "date": "2026-08-15",
      "title": "New menu",
      "added": [
        {
          "tab": "Hub",
          "name": "New menu",
          "note": "the live hub menu"
        },
        {
          "tab": "Settings",
          "name": "Task farming",
          "note": "can run matches and pause"
        },
        {
          "tab": "Movement",
          "name": "Infinite Jump",
          "note": "keeps you in the air"
        },
        {
          "tab": "Movement",
          "name": "Wall Noclip",
          "note": "walks through map walls"
        },
        {
          "tab": "Visuals",
          "name": "Highlight ESP",
          "note": "draws players with native highlights"
        }
      ],
      "changed": [],
      "fixed": []
    }
  ]
}
]],
    ["games/Catalog.lua"] = [[return {
    "games/counterblox/Definition",
    "games/rivals/Definition",
    "games/town/Definition",
    "games/bloxstrike/Definition",
    "games/duelinggrounds/Definition",
    "games/hoodrivals/Definition",
    "games/stealanegg/Definition",
}
]],
    ["games/Compatibility.lua"] = [[local Compatibility = {}

local DEFAULTS = {
    aimSmoothness = 0,
    autoPickup = false,
    bhop = false,
    boxes = true,
    bombTimer = true,
    chams = true,
    chamsExcludeAccessories = false,
    chamsPerPart = false,
    cameraFov = 180,
    cameraFullScreenAim = false,
    cameraTargetMode = "radius",
    fov = 180,
    fovCircle = true,
    -- Legacy shared palette remains for config migration; relationship-specific
    -- values take precedence when customized.
    espFillAlpha = -1,
    espFillColor = "",
    espHealthHighColor = "",
    espHealthLowColor = "",
    espNameColor = "",
    espOutlineColor = "",
    espWeaponColor = "",
    espEnemyOutlineColor = "",
    espEnemyFillColor = "",
    espEnemyFillAlpha = -1,
    espEnemyNameColor = "",
    espEnemyWeaponColor = "",
    espEnemyHealthLowColor = "",
    espEnemyHealthHighColor = "",
    espTeammateOutlineColor = "",
    espTeammateFillColor = "",
    espTeammateFillAlpha = -1,
    espTeammateNameColor = "",
    espTeammateWeaponColor = "",
    espTeammateHealthLowColor = "",
    espTeammateHealthHighColor = "",
    fullScreenAim = false,
    gloveColorOverride = false,
    gloveOverride = false,
    headshotRate = 0,
    health = true,
    humanAim = false,
    knifeAura = false,
    maximumFov = 500,
    menuKey = "RightShift",
    microStep = false,
    minimumFov = 40,
    missRate = 0,
    names = true,
    noFlash = false,
    noRecoil = false,
    noSmoke = false,
    noSpread = false,
    noWeaponSlow = false,
    rapidFire = false,
    alwaysScoped = false,
    shotFov = 180,
    shotFullScreenAim = false,
    shotTargetMode = "radius",
    shotAim = false,
    showEnemies = true,
    showTeammates = false,
    silentAim = false,
    skinOverrides = {},
    spinBot = false,
    triggerBot = false,
    utilityEsp = true,
    wallbang = false,
    weapon = true,
    worldRenderer = "limn",
}

local INITIAL_STATE = {
    activeWeapon = nil,
    activeWeaponKind = nil,
    cosmeticWeapon = nil,
    cosmetics = {
        maximumWear = 1,
        minimumWear = 0,
        skin = "Stock",
        skinCount = 1,
        skinIndex = 1,
        statTrak = false,
        supportsStatTrak = false,
        wear = 0,
        weapon = nil,
    },
    cosmeticMode = "weapon",
    cosmeticsOpen = false,
    error = nil,
    menuVisible = true,
    observations = {},
    plotCopy = {
        active = false,
        confirmedProgress = 0,
        context = "",
        phase = "Ready",
        state = "idle",
    },
    bombObservation = {
        visible = false,
    },
    utilityObservations = {},
    gloves = {
        maximumWear = 1,
        minimumWear = 0,
        skin = "Game equipped",
        skinCount = 1,
        skinIndex = 0,
        wear = 0,
        weapon = "Gloves",
    },
}

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, child in pairs(value) do
        result[copy(key)] = copy(child)
    end
    return result
end

local function merge(base, additions)
    local result = copy(base)
    for key, value in pairs(additions or {}) do
        if type(value) == "table" and type(result[key]) == "table" then
            result[key] = merge(result[key], value)
        else
            result[key] = copy(value)
        end
    end
    return result
end

function Compatibility.Compose(definition)
    assert(type(definition) == "table", "Compatibility composition requires a game definition")
    local result = copy(definition)
    result.defaults = merge(DEFAULTS, definition.defaults)
    result.initialState = merge(INITIAL_STATE, definition.initialState)
    return result
end

function Compatibility.Defaults()
    return copy(DEFAULTS)
end

function Compatibility.InitialState()
    return copy(INITIAL_STATE)
end

return Compatibility
]],
    ["games/Counterblox.lua"] = [[local Counterblox = {}

local KNIFE_AURA_INTERVAL = 0.06
local KNIFE_EXTRA_REACH = 3
local KNIFE_FALLBACK_RANGE = 7
local KNIFE_HIT_TOLERANCE = 1.5
local KNIFE_MICRO_STEP = 0.75
local BHOP_AIR_ACCELERATION = 10
local BHOP_SPEED_MULTIPLIER = 1.35
local RAPID_FIRE_INTERVAL = 0.04
local SPIN_SPEED = math.rad(1440)
local THIRD_PERSON_DISTANCE = 8
local MOVEMENT_RENDER_STEP = "UniversalHubCounterbloxMovement"
local MOVEMENT_RENDER_PRIORITY = 2000
local BOMB_MARKER_MAX_DISTANCE = 350
local BOMB_MARKER_THROUGH_WALL_DISTANCE = 160
local UTILITY_MAX_DISTANCE = 500
local MAX_ZONE_QUADS = 48

function Counterblox.cosmeticLabel(skin)
    local base, pattern = string.match(skin, "^(.-)_PATTERN_(%d+)$")
    if base then
        return ("%s (Pattern %s)"):format(base, pattern)
    end
    return skin
end

function Counterblox.bombTimeRemaining(data, serverTime)
    data = type(data) == "table" and data or {}
    serverTime = type(serverTime) == "number" and serverTime or 0
    local plantedAt = type(data.Time) == "number" and data.Time or serverTime
    local duration = type(data.TimeUntilExplode) == "number" and data.TimeUntilExplode or 40
    return math.max(plantedAt + math.max(duration, 0.1) - serverTime, 0)
end

function Counterblox.bombPresentation(distance)
    distance = math.max(type(distance) == "number" and distance or math.huge, 0)
    local visible = distance <= BOMB_MARKER_MAX_DISTANCE
    local closeness = 1 - math.clamp(distance / BOMB_MARKER_MAX_DISTANCE, 0, 1)
    return {
        alwaysOnTop = visible and distance <= BOMB_MARKER_THROUGH_WALL_DISTANCE,
        height = math.round(20 + 10 * closeness),
        textSize = math.round(12 + 4 * closeness),
        visible = visible,
        width = math.round(60 + 44 * closeness),
    }
end

function Counterblox.utilityLabel(name)
    local normalized = string.lower(tostring(name or ""))
    if string.find(normalized, "incendiary", 1, true) then
        return "INCENDIARY", "danger"
    elseif string.find(normalized, "molotov", 1, true) then
        return "MOLOTOV", "danger"
    elseif string.find(normalized, "flash", 1, true) then
        return "FLASH", "accent"
    elseif string.find(normalized, "smoke", 1, true) then
        return "SMOKE", "smoke"
    elseif string.find(normalized, "decoy", 1, true) then
        return "DECOY", "accent"
    elseif string.find(normalized, "he grenade", 1, true)
        or string.find(normalized, "explosive", 1, true)
    then
        return "HE", "danger"
    end
    return "GRENADE", "accent"
end

function Counterblox.planMeleeAttack(cameraPosition, attackerPosition, target, range)
    local offset = target and target.position and target.position - cameraPosition
    local plan = {
        distance = offset and offset.Magnitude or math.huge,
        heavy = false,
        inRange = false,
    }
    plan.inRange = plan.distance <= math.max(range or 0, 0) + KNIFE_HIT_TOLERANCE

    local character = target and target.character
    local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
    local behind = targetRoot and attackerPosition - targetRoot.Position
    if behind and behind.Magnitude > 0.001 then
        local dot = math.clamp(targetRoot.CFrame.LookVector:Dot(behind.Unit), -1, 1)
        plan.heavy = math.deg(math.acos(dot)) > 100
    end
    return plan
end

local function targetVisible(target)
    if target.visible ~= nil then
        return target.visible == true
    end
    if type(target.visibility) == "table" then
        return target.visibility.visible == true
    end
    return false
end

function Counterblox.nearestMeleeTarget(origin, observations)
    local nearest
    local nearestDistance = math.huge
    for _, observation in ipairs(observations or {}) do
        if targetVisible(observation) and observation.position then
            local distance = (observation.position - origin).Magnitude
            if distance < nearestDistance then
                nearest = observation
                nearestDistance = distance
            end
        end
    end
    return nearest
end

local function materialName(material)
    if material and material.Name then
        return material.Name
    end
    return tostring(material or "Plastic")
end

local function reachesTarget(instance, target)
    if instance == target.part then
        return true
    end

    local character = target.character
    if not character or not instance or type(instance.IsDescendantOf) ~= "function" then
        return false
    end
    local success, isDescendant = pcall(instance.IsDescendantOf, instance, character)
    return success and isDescendant == true
end

function Counterblox.classifyWeapon(equipped)
    if not equipped or equipped.IsDestroyed then
        return nil
    end
    if equipped.Bullet then
        return "Gun"
    end
    if type(equipped.shoot) == "function" and equipped.Properties and equipped.Properties.Range then
        return "Knife"
    end
    return nil
end

function Counterblox.applyAimRates(observation, settings, random)
    if not observation or not observation.position then
        return observation
    end

    local result = table.clone(observation)
    result.aimRatesApplied = true
    random = random or math.random
    local character = observation.character
    if character then
        for _, partName in ipairs({ "UpperTorso", "Torso", "LowerTorso", "HumanoidRootPart" }) do
            local body = character:FindFirstChild(partName)
            if body then
                result.part = body
                result.position = body.Position
                break
            end
        end
    end

    local missRate = math.clamp(settings.missRate or 0, 0, 100)
    if missRate > 0 and random() * 100 < missRate then
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root then
            local width = root.Size and root.Size.X or 2
            result.intentionalMiss = true
            result.part = root
            result.position = root.Position + root.CFrame.RightVector * (width * 0.5 + 2.5)
        end
        return result
    end

    local headshotRate = math.clamp(settings.headshotRate or 0, 0, 100)
    if headshotRate > 0 and random() * 100 < headshotRate then
        local head = character and character:FindFirstChild("Head")
        if head then
            result.intentionalMiss = false
            result.part = head
            result.position = head.Position
        end
    end
    return result
end

function Counterblox.redirectBullet(originalResult, target, bullet, api)
    if not target or not originalResult or not originalResult.Origin then
        return originalResult, false
    end

    local offset = target.position - originalResult.Origin
    if offset.Magnitude <= 0.001 then
        return originalResult, false
    end

    local direction = offset.Unit
    local range = bullet.Properties.Range or 500
    local penetration = bullet.Properties.Penetration or 0
    local ignore = api.getIgnore()
    local first = api.cast(originalResult.Origin, direction * range, nil, ignore)
    local hits = {}

    local accepted = false
    if first and first.instance and reachesTarget(first.instance, target) then
        table.insert(hits, {
            Distance = (first.position - originalResult.Origin).Magnitude,
            Exit = false,
            Instance = first.instance,
            Material = materialName(first.material),
            Normal = first.normal or Vector3.new(0, 0, 0),
            Position = first.position,
        })
        accepted = true
    elseif first and first.instance then
        local castHits = api.castThrough(
            first.position + direction * -0.001,
            direction * range,
            penetration,
            ignore
        ) or {}
        local lastPosition = originalResult.Origin
        for index, hit in ipairs(castHits) do
            if hit.instance then
                table.insert(hits, {
                    Distance = (hit.position - lastPosition).Magnitude,
                    Exit = index % 2 == 0,
                    Instance = hit.instance,
                    Material = materialName(hit.material),
                    Normal = hit.normal or Vector3.new(0, 0, 0),
                    Position = hit.position,
                })
                lastPosition = hit.position
                if reachesTarget(hit.instance, target) then
                    accepted = true
                    break
                end
            end
        end
    end

    if not accepted then
        return originalResult, false
    end

    return {
        Direction = direction,
        Distance = offset.Magnitude,
        Hits = hits,
        Origin = originalResult.Origin,
    }, true
end

function Counterblox.new(context)
    assert(context and context.oh, "Counterblox adapter requires Hydroxide")
    assert(context.store, "Counterblox adapter requires a reactive store")

    local Players = game:GetService("Players")
    local HttpService = game:GetService("HttpService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace = game:GetService("Workspace")
    local CollectionService = game:GetService("CollectionService")
    local LocalPlayer = Players.LocalPlayer

    local loadModule: (any) -> any = context.requireModule or require
    local Bullet = loadModule(ReplicatedStorage.Components.Weapon.Classes.Bullet)
    local Melee = loadModule(ReplicatedStorage.Components.Melee)
    local CameraController = loadModule(ReplicatedStorage.Controllers.CameraController)
    local SpectateController = loadModule(ReplicatedStorage.Controllers.SpectateController)
    local CrosshairSettings =
        loadModule(ReplicatedStorage.Interface.Screens.Gameplay.Middle.Crosshair.Settings)
    local GetRayIgnore = loadModule(ReplicatedStorage.Components.Common.GetRayIgnore)
    local GameRaycast = loadModule(ReplicatedStorage.Shared.Raycast)
    local CharacterClass = loadModule(ReplicatedStorage.Classes.Character)
    local FlashEffect = loadModule(ReplicatedStorage.Components.Common.VFXLibary.FlashEffect)
    local VoxelSmoke = loadModule(ReplicatedStorage.Components.Common.VFXLibary.CreateVoxelSmoke)
    local WeaponComponentScript = ReplicatedStorage.Classes.WeaponComponent
    local WeaponComponent = loadModule(WeaponComponentScript)
    local Viewmodel = loadModule(WeaponComponentScript.Classes.Viewmodel)
    local Skins = loadModule(ReplicatedStorage.Database.Components.Libraries.Skins)

    local click = assert(context.click, "Counterblox adapter requires a click function")
    local press = assert(context.press, "Counterblox adapter requires a press function")
    local heavyClick = assert(context.aimClick, "Counterblox adapter requires a right-click function")
    local cancelThread = context.cancelThread or task.cancel
    local gcObjects = context.gcObjects or function()
        return {}
    end
    local hookFunction = assert(context.hookFunction, "Counterblox adapter requires hookfunction")
    local restoreFunction = assert(context.restoreFunction, "Counterblox adapter requires restorefunction")
    local setThirdPerson = context.setThirdPerson or function() end
    local isJumpHeld = context.isJumpHeld or function()
        return UserInputService:IsKeyDown(Enum.KeyCode.Space)
    end
    local movementDirection = context.movementDirection
    local random = context.random or math.random
    local store = context.store
    local targeting = context.oh.targeting
    local stopped = false
    local hooks: { [string]: any } = {}
    local observations = {}
    local visualObservations = observations
    local activeWeaponKind
    local currentTarget
    local meleeTarget
    local meleeRange = KNIFE_FALLBACK_RANGE
    local nextAuraAt = 0
    local nextRapidFireAt = 0
    local nextTriggerAt = 0
    local noFlashApplied = false
    local noSmokeApplied = false
    local followRecoil = CrosshairSettings["Follow Recoil"]
    local bhopRoot
    local bhopMomentum
    local bhopSpeedLimit
    local spinRoot
    local spinJoint
    local spinJointC0
    local spinAngle = 0
    local lastEquippedName
    local lastCosmeticKey
    local lastGloveKey
    local cosmeticCatalogCache = {}
    local cosmeticOverrideCache = {}
    local cosmeticWeaponCache
    local gloveCatalogCache
    local selectedCosmeticWeapon
    local trackedComponents = setmetatable({}, { __mode = "k" })
    local characterTransparency = setmetatable({}, { __mode = "k" })
    local viewmodelTransparency = setmetatable({}, { __mode = "k" })
    local bombAttribute
    local bombData

    local self = {}

    local function restoreTransparency(cache)
        for part, value in pairs(cache) do
            if part.Parent then
                part.LocalTransparencyModifier = value
            end
            cache[part] = nil
        end
    end

    local function updateThirdPersonPresentation(active)
        if not active then
            restoreTransparency(characterTransparency)
            restoreTransparency(viewmodelTransparency)
            return
        end

        local character = LocalPlayer.Character
        if character then
            for _, descendant in ipairs(character:GetDescendants()) do
                if descendant:IsA("BasePart") then
                    if characterTransparency[descendant] == nil then
                        characterTransparency[descendant] = descendant.LocalTransparencyModifier
                    end
                    descendant.LocalTransparencyModifier = 0
                end
            end
        end

        local camera = Workspace.CurrentCamera
        local activeWeapon = store:Get().activeWeapon
        if camera and activeWeapon then
            for _, child in ipairs(camera:GetChildren()) do
                if child:IsA("Model") and child.Name == activeWeapon then
                    for _, descendant in ipairs(child:GetDescendants()) do
                        if descendant:IsA("BasePart") then
                            if viewmodelTransparency[descendant] == nil then
                                viewmodelTransparency[descendant] = descendant.LocalTransparencyModifier
                            end
                            descendant.LocalTransparencyModifier = 1
                        end
                    end
                end
            end
        end
    end

    local function spectatedPlayer()
        if SpectateController and type(SpectateController.GetPlayer) == "function" then
            local success, player = pcall(SpectateController.GetPlayer)
            if success and player then
                return player
            end
        end

        local camera = Workspace.CurrentCamera
        local subject = camera and camera.CameraSubject
        if not subject then
            return nil
        end
        return Players:GetPlayerFromCharacter(subject)
            or subject.Parent and Players:GetPlayerFromCharacter(subject.Parent)
    end

    local function isSpectatedCharacter(character)
        local player = spectatedPlayer()
        if player and player.Character == character then
            return true
        end

        local camera = Workspace.CurrentCamera
        local subject = camera and camera.CameraSubject
        return subject ~= nil
            and (subject == character or subject.Parent == character or subject:IsDescendantOf(character))
    end

    local function spectatorRaycastIgnore()
        local player = spectatedPlayer()
        local character = player and player.Character
        if character and character ~= LocalPlayer.Character then
            return { character }
        end
        return {}
    end

    local function attribute(instance, name)
        if not instance or type(instance.GetAttribute) ~= "function" then
            return nil
        end
        local succeeded, value = pcall(instance.GetAttribute, instance, name)
        return succeeded and value or nil
    end

    local function playerTone(player, character)
        if player == LocalPlayer or not character or attribute(character, "Dead") == true then
            return nil
        end
        if isSpectatedCharacter(character) then
            return nil
        end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health <= 0 then
            return nil
        end

        local referencePlayer = spectatedPlayer() or LocalPlayer
        local localTeam = attribute(referencePlayer, "Team")
        local playerTeam = attribute(player, "Team")
        local gameMode = attribute(Workspace, "Gamemode")
        local serverGameMode = attribute(Workspace, "ServerGamemode")
        local isDeathmatch = (type(gameMode) == "string" and gameMode:lower() == "deathmatch")
            or (type(serverGameMode) == "string" and serverGameMode:lower() == "deathmatch")
        return not isDeathmatch
            and localTeam ~= nil
            and playerTeam ~= nil
            and localTeam == playerTeam
            and "team"
            or "enemy"
    end

    local function isOpponent(player, character)
        return playerTone(player, character) == "enemy"
    end

    local function selectTarget(includeBlocked)
        local settings = store:Get().settings
        local options = {
            includeBlocked = includeBlocked == true,
            isEligible = isOpponent,
            raycastIgnore = spectatorRaycastIgnore(),
            screenOrigin = UserInputService:GetMouseLocation(),
        }
        if not settings.fullScreenAim then
            options.maxScreenDistance = settings.fov
        end
        return targeting.nearestPlayer(options)
    end

    local meleeNameHints = {
        "bayonet",
        "bowie",
        "butterfly",
        "dagger",
        "falchion",
        "flip",
        "gut",
        "huntsman",
        "karambit",
        "knife",
        "kukri",
        "navaja",
        "nomad",
        "paracord",
        "shadow",
        "skeleton",
        "stiletto",
        "survival",
        "talon",
        "ursus",
    }

    local function weaponClassFromAsset(asset)
        if type(asset.GetAttribute) == "function" then
            for _, attributeName in ipairs({ "Class", "WeaponClass", "Type" }) do
                local value = asset:GetAttribute(attributeName)
                if type(value) == "string" then
                    return value
                end
            end
        end
        if type(asset.FindFirstChild) == "function" then
            for _, childName in ipairs({ "Class", "WeaponClass", "Type" }) do
                local child = asset:FindFirstChild(childName)
                if child and type(child.Value) == "string" then
                    return child.Value
                end
            end
        end

        local name = asset.Name:lower()
        if name:find("glove", 1, true) or name:find("hand wrap", 1, true) then
            return "Glove"
        end
        for _, hint in ipairs(meleeNameHints) do
            if name:find(hint, 1, true) then
                return "Melee"
            end
        end
        return nil
    end

    local function weaponClass(weaponName)
        for _, asset in ipairs(ReplicatedStorage.Assets.Weapons:GetChildren()) do
            if asset.Name == weaponName then
                return weaponClassFromAsset(asset)
            end
        end
        return weaponClassFromAsset({ Name = weaponName })
    end

    local function cosmeticWeapons()
        if cosmeticWeaponCache then
            return cosmeticWeaponCache
        end

        local weapons = {}
        for _, asset in ipairs(ReplicatedStorage.Assets.Weapons:GetChildren()) do
            local class = weaponClassFromAsset(asset)
            local isBaseMelee = asset.Name == "T Knife" or asset.Name == "CT Knife"
            if class ~= "Glove" and (class ~= "Melee" or isBaseMelee) then
                table.insert(weapons, asset.Name)
            end
        end
        table.sort(weapons)
        cosmeticWeaponCache = weapons
        return weapons
    end

    local function currentCosmeticWeapon()
        return selectedCosmeticWeapon or store:Get().activeWeapon or lastEquippedName
    end

    local function cosmeticCatalog(weaponName)
        local cached = cosmeticCatalogCache[weaponName]
        if cached then
            return cached
        end

        local weaponNames = { weaponName }
        if weaponClass(weaponName) == "Melee" then
            local alternatives = {}
            for _, weapon in ipairs(ReplicatedStorage.Assets.Weapons:GetChildren()) do
                if weapon.Name ~= weaponName and weaponClassFromAsset(weapon) == "Melee" then
                    table.insert(alternatives, weapon.Name)
                end
            end
            table.sort(alternatives)
            for _, alternative in ipairs(alternatives) do
                table.insert(weaponNames, alternative)
            end
        end

        local catalog = {}
        for _, cosmeticWeapon in ipairs(weaponNames) do
            table.insert(catalog, {
                floatRange = { min = 0, max = 1 },
                skin = "Stock",
                supportsStatTrak = false,
                weapon = cosmeticWeapon,
            })
            for _, source in ipairs(Skins.GetAllSkinsForWeapon(cosmeticWeapon) or {}) do
                local sourceWeapon = source.weapon or source.name
                if source.skin ~= "Stock"
                    and (type(sourceWeapon) ~= "string" or sourceWeapon == cosmeticWeapon)
                then
                    local schema = table.clone(source)
                    schema.weapon = cosmeticWeapon
                    table.insert(catalog, schema)
                end
            end
        end
        cosmeticCatalogCache[weaponName] = catalog
        return catalog
    end

    local function cosmeticSchema(weaponName, skin, cosmeticWeapon)
        for index, schema in ipairs(cosmeticCatalog(weaponName)) do
            if schema.skin == skin and (not cosmeticWeapon or schema.weapon == cosmeticWeapon) then
                return schema, index
            end
        end
        return cosmeticCatalog(weaponName)[1], 1
    end

    local function cosmeticOverride(weaponName)
        local settings = store:Get().settings
        local overrides = settings.skinOverrides
        local override = overrides and overrides[weaponName]
        local cached = cosmeticOverrideCache[weaponName]
        if cached and cached.source == override then
            return cached.value or nil
        end

        local validOverride
        if type(override) == "table" then
            for _, schema in ipairs(cosmeticCatalog(weaponName)) do
                if schema.skin == override.skin
                    and (not override.weapon or schema.weapon == override.weapon)
                then
                    validOverride = override
                    break
                end
            end
        end
        cosmeticOverrideCache[weaponName] = {
            source = override,
            value = validOverride or false,
        }
        return validOverride
    end

    local function gloveCatalog()
        if gloveCatalogCache then
            return gloveCatalogCache
        end

        local gloveNames = {}
        for _, weapon in ipairs(ReplicatedStorage.Assets.Weapons:GetChildren()) do
            if weaponClassFromAsset(weapon) == "Glove" then
                table.insert(gloveNames, weapon.Name)
            end
        end
        table.sort(gloveNames)

        local catalog = {}
        for _, gloveName in ipairs(gloveNames) do
            table.insert(catalog, {
                floatRange = { min = 0, max = 1 },
                skin = "Stock",
                weapon = gloveName,
            })
            for _, source in ipairs(Skins.GetAllSkinsForWeapon(gloveName) or {}) do
                if source.skin ~= "Stock" then
                    local schema = table.clone(source)
                    schema.weapon = gloveName
                    table.insert(catalog, schema)
                end
            end
        end
        gloveCatalogCache = catalog
        return catalog
    end

    local function gloveOverride()
        local override = store:Get().settings.gloveOverride
        return type(override) == "table" and override or nil
    end

    local function gloveColorOverride()
        local override = store:Get().settings.gloveColorOverride
        return type(override) == "table" and override or nil
    end

    local function applyGloveColor(viewmodel)
        local override = gloveColorOverride()
        local model = override and viewmodel.Model
        if not model then
            return
        end

        local color = Color3.new(override.r, override.g, override.b)
        for _, descendant in ipairs(model:GetDescendants()) do
            if descendant:IsA("BasePart")
                and string.find(string.lower(descendant.Name), "glove", 1, true)
            then
                descendant.Color = color
                if descendant:IsA("MeshPart") then
                    descendant.TextureID = ""
                end
                for _, appearance in ipairs(descendant:GetDescendants()) do
                    if appearance:IsA("SurfaceAppearance")
                        or appearance:IsA("Texture")
                        or appearance:IsA("Decal")
                    then
                        appearance:Destroy()
                    end
                end
            end
        end
    end

    local function gloveSchema(weaponName, skin)
        for index, schema in ipairs(gloveCatalog()) do
            if schema.weapon == weaponName and schema.skin == skin then
                return schema, index
            end
        end
        return nil, 0
    end

    local function publishGloves()
        local override = gloveOverride()
        local schema, index
        if override then
            schema, index = gloveSchema(override.weapon, override.skin)
        end
        local range = schema and schema.floatRange or { min = 0, max = 1 }
        local catalog = gloveCatalog()
        local key = override
                and table.concat({
                    override.weapon,
                    override.skin,
                    tostring(override.wear),
                    tostring(#catalog),
                }, "|")
            or ("game|" .. tostring(#catalog))
        if key == lastGloveKey then
            return
        end
        lastGloveKey = key
        store:Patch({
            gloves = {
                maximumWear = range.max or 1,
                minimumWear = range.min or 0,
                skin = override and override.skin or "Game equipped",
                skinCount = #catalog,
                skinIndex = index,
                wear = override and override.wear or 0,
                weapon = override and override.weapon or "Gloves",
            },
        })
    end

    local function publishCosmetics(weaponName)
        if not weaponName then
            return
        end

        local override = cosmeticOverride(weaponName) or {
            skin = "Stock",
            statTrak = false,
            wear = 0,
            weapon = weaponName,
        }
        local key = table.concat({
            weaponName,
            override.weapon or weaponName,
            override.skin,
            tostring(override.wear),
            tostring(override.statTrak),
        }, "|")
        if key == lastCosmeticKey then
            return
        end
        local schema, index = cosmeticSchema(weaponName, override.skin, override.weapon)
        local range = schema.floatRange or { min = 0, max = 1 }
        local catalog = cosmeticCatalog(weaponName)
        lastCosmeticKey = key
        store:Patch({
            cosmetics = {
                maximumWear = range.max or 1,
                minimumWear = range.min or 0,
                skin = override.skin,
                skinLabel = Counterblox.cosmeticLabel(override.skin),
                skinCount = #catalog,
                skinIndex = index,
                statTrak = override.statTrak == true,
                supportsStatTrak = schema.supportsStatTrak == true,
                wear = override.wear or range.min or 0,
                weapon = override.weapon or weaponName,
            },
        })
    end

    local function applyCosmeticToComponent(component, weaponName, override)
        local oldViewmodel = component.Viewmodel
        local wasEquipped = oldViewmodel
            and (oldViewmodel.IsEquipped == true or store:Get().activeWeapon == weaponName)
        component.Skin = override.skin
        component.Float = override.wear
        component.StatTrack = override.statTrak
        local success, replacement = pcall(Viewmodel.new, component, override.weapon or weaponName, component.Skin)
        if success then
            if oldViewmodel then
                oldViewmodel:destroy()
            end
            component.Viewmodel = replacement
            if wasEquipped then
                replacement:equip(true)
            end
        end
    end

    local function trackExistingComponents()
        local success, objects = pcall(gcObjects)
        if not success or type(objects) ~= "table" then
            return
        end

        for _, component in ipairs(objects) do
            if type(component) == "table"
                and rawget(component, "Player") == LocalPlayer
                and rawget(component, "IsDestroyed") ~= true
            then
                local name = rawget(component, "Name")
                local viewmodel = rawget(component, "Viewmodel")
                if type(name) == "string"
                    and type(viewmodel) == "table"
                    and type(rawget(viewmodel, "destroy")) == "function"
                then
                    trackedComponents[component] = name
                end
            end
        end
    end

    local function refreshCosmetic(weaponName, override)
        for component, componentWeapon in pairs(trackedComponents) do
            if component.IsDestroyed then
                trackedComponents[component] = nil
            elseif component.Player == LocalPlayer and componentWeapon == weaponName then
                applyCosmeticToComponent(component, weaponName, override)
            end
        end
    end

    local function refreshGloves()
        for component, componentWeapon in pairs(trackedComponents) do
            if component.IsDestroyed then
                trackedComponents[component] = nil
            elseif component.Player == LocalPlayer then
                local override = cosmeticOverride(componentWeapon) or {
                    skin = component.Skin,
                    statTrak = component.StatTrack,
                    wear = component.Float,
                    weapon = componentWeapon,
                }
                applyCosmeticToComponent(component, componentWeapon, override)
            end
        end
    end

    local function setCosmetic(weaponName, schema, wear, statTrak)
        if not weaponName then
            return
        end
        local range = schema.floatRange or { min = 0, max = 1 }
        local override = {
            skin = schema.skin,
            statTrak = schema.supportsStatTrak == true and statTrak == true,
            wear = math.clamp(wear or range.min or 0, range.min or 0, range.max or 1),
            weapon = schema.weapon or weaponName,
        }
        local settings = store:Get().settings
        settings.skinOverrides[weaponName] = override
        lastCosmeticKey = nil
        refreshCosmetic(weaponName, override)
        publishCosmetics(weaponName)
        if context.settingsChanged then
            context.settingsChanged(settings)
        end
    end

    local function setGlove(schema, wear)
        local range = schema.floatRange or { min = 0, max = 1 }
        local settings = store:Get().settings
        settings.gloveOverride = {
            skin = schema.skin,
            wear = math.clamp(wear or range.min or 0, range.min or 0, range.max or 1),
            weapon = schema.weapon,
        }
        lastGloveKey = nil
        refreshGloves()
        publishGloves()
        if context.settingsChanged then
            context.settingsChanged(settings)
        end
    end

    local function directedBulletRaycast(bullet, spread)
        local settings = store:Get().settings
        local result = hooks.bulletOriginal(bullet, settings.noSpread and 0 or spread)
        local target = currentTarget
        currentTarget = nil
        if not settings.silentAim and not target then
            return result
        end

        local wallbangActive = settings.silentAim and settings.wallbang
        target = target or selectTarget(wallbangActive)
        if not target or not result or not result.Origin then
            store:Patch({ lastShot = "No target" })
            return result
        end

        if not targetVisible(target) and not wallbangActive then
            return result
        end
        if not target.aimRatesApplied then
            target = Counterblox.applyAimRates(target, settings, random)
        end
        if target.intentionalMiss then
            local offset = target.position - result.Origin
            if offset.Magnitude > 0.001 then
                store:Patch({
                    lastShot = "Intentional miss",
                    target = target.player,
                })
                return {
                    Direction = offset.Unit,
                    Distance = offset.Magnitude,
                    Hits = {},
                    Origin = result.Origin,
                }
            end
            return result
        end

        local redirected, accepted = Counterblox.redirectBullet(result, target, bullet, {
            cast = GameRaycast.cast,
            castThrough = GameRaycast.castThrough,
            getIgnore = GetRayIgnore,
        })

        store:Patch({
            lastShot = accepted and "Retargeted" or "No accepted hit path",
            target = target.player,
        })
        return accepted and redirected or result
    end

    hooks.bulletTarget = Bullet._performRaycast
    hooks.bulletOriginal = hookFunction(hooks.bulletTarget, function(bullet, spread)
        activeWeaponKind = "Gun"
        if stopped then
            return hooks.bulletOriginal(bullet, spread)
        end
        return directedBulletRaycast(bullet, spread)
    end)

    hooks.spreadTarget = Bullet.getTrueSpread
    hooks.spreadOriginal = hookFunction(hooks.spreadTarget, function(bullet)
        if not stopped and store:Get().settings.noSpread then
            return 0
        end
        return hooks.spreadOriginal(bullet)
    end)

    hooks.spreadUpdateTarget = Bullet._updateShotSpread
    hooks.spreadUpdateOriginal = hookFunction(hooks.spreadUpdateTarget, function(bullet, ...)
        if not stopped and store:Get().settings.noSpread then
            return nil
        end
        return hooks.spreadUpdateOriginal(bullet, ...)
    end)

    hooks.recoilTarget = CameraController.weaponKick
    hooks.recoilOriginal = hookFunction(hooks.recoilTarget, function(...)
        if not stopped and store:Get().settings.noRecoil then
            return nil
        end
        return hooks.recoilOriginal(...)
    end)

    hooks.weaponRecoilTarget = CameraController.setWeaponRecoil
    hooks.weaponRecoilOriginal = hookFunction(hooks.weaponRecoilTarget, function(...)
        if not stopped and store:Get().settings.noRecoil then
            return nil
        end
        return hooks.weaponRecoilOriginal(...)
    end)

    hooks.cameraUpdateTarget = CameraController.updateCamera
    hooks.cameraUpdateOriginal = hookFunction(hooks.cameraUpdateTarget, function(cameraFrame)
        local packed = table.pack(pcall(hooks.cameraUpdateOriginal, cameraFrame))
        if packed[1] and not stopped and store:Get().settings.spinBot then
            local camera = Workspace.CurrentCamera
            if camera then
                camera.CFrame = camera.CFrame * CFrame.new(0, 0, THIRD_PERSON_DISTANCE)
            end
            updateThirdPersonPresentation(true)
        end
        if not packed[1] then
            error(packed[2], 0)
        end
        return table.unpack(packed, 2, packed.n)
    end)

    hooks.flashTarget = FlashEffect.Flash
    hooks.flashOriginal = hookFunction(hooks.flashTarget, function(...)
        if not stopped and store:Get().settings.noFlash then
            return false
        end
        return hooks.flashOriginal(...)
    end)

    hooks.smokeTarget = VoxelSmoke.Create
    hooks.smokeOriginal = hookFunction(hooks.smokeTarget, function(...)
        if not stopped and store:Get().settings.noSmoke then
            return nil
        end
        return hooks.smokeOriginal(...)
    end)

    hooks.speedTarget = CharacterClass.GetMaxSpeed
    hooks.speedOriginal = hookFunction(hooks.speedTarget, function(character)
        local speed = hooks.speedOriginal(character)
        local settings = store:Get().settings
        if stopped
            or not (settings.noWeaponSlow or settings.spinBot)
            or type(speed) ~= "number"
            or speed <= 0
        then
            return speed
        end

        local stance = settings.spinBot and 1 or (character.IsWalking and 0.52 or 1)
        if not settings.spinBot and character.IsCrouching and not character.IsJumping then
            stance = 0.34
        end
        local climb = character.IsClimbing and 0.5 or 1
        return math.max(speed, 20 * stance * climb)
    end)

    hooks.viewmodelConstructTarget = Viewmodel.construct
    hooks.viewmodelConstructOriginal = hookFunction(
        hooks.viewmodelConstructTarget,
        function(viewmodel, character, ...)
            local isLocal = not stopped and viewmodel.Player == LocalPlayer
            local override = isLocal and gloveOverride()
            local colorOverride = isLocal and gloveColorOverride()
            if (not override and not colorOverride) or not character then
                return hooks.viewmodelConstructOriginal(viewmodel, character, ...)
            end

            local previousGloves
            if override then
                previousGloves = character:GetAttribute("EquippedGloves")
                local encoded = HttpService:JSONEncode({
                    Float = override.wear,
                    Name = override.weapon,
                    Skin = override.skin,
                })
                character:SetAttribute("EquippedGloves", encoded)
            end
            local packed = table.pack(pcall(hooks.viewmodelConstructOriginal, viewmodel, character, ...))
            if override then
                character:SetAttribute("EquippedGloves", previousGloves)
            end
            if not packed[1] then
                error(packed[2], 0)
            end
            applyGloveColor(viewmodel)
            return table.unpack(packed, 2, packed.n)
        end
    )

    hooks.weaponComponentTarget = WeaponComponent.new
    hooks.weaponComponentOriginal = hookFunction(
        hooks.weaponComponentTarget,
        function(player, identifier, id, slot, name, skin, wear, statTrak, nameTag, owner, charm, stickers)
            local componentWeapon = name
            local override = player == LocalPlayer and cosmeticOverride(name)
            local changesWeapon = override and override.weapon and override.weapon ~= name
            if override and not changesWeapon then
                skin = override.skin
                wear = override.wear
                statTrak = override.statTrak
            end
            local component = hooks.weaponComponentOriginal(
                player,
                identifier,
                id,
                slot,
                name,
                skin,
                wear,
                statTrak,
                nameTag,
                owner,
                charm,
                stickers
            )
            if player == LocalPlayer then
                trackedComponents[component] = componentWeapon
                if changesWeapon then
                    applyCosmeticToComponent(component, componentWeapon, override)
                end
            end
            return component
        end
    )
    trackExistingComponents()

    hooks.workspaceRaycastTarget = Workspace.Raycast
    hooks.workspaceRaycastOriginal = hookFunction(hooks.workspaceRaycastTarget, function(workspaceInstance, origin, direction, params)
        if workspaceInstance == Workspace and meleeTarget then
            local offset = meleeTarget.position - origin
            if offset.Magnitude <= direction.Magnitude + 2 then
                return {
                    Distance = offset.Magnitude,
                    Instance = meleeTarget.part,
                    Material = meleeTarget.part.Material,
                    Normal = -offset.Unit,
                    Position = meleeTarget.position,
                }
            end
        end
        return hooks.workspaceRaycastOriginal(workspaceInstance, origin, direction, params)
    end)

    hooks.spherecastTarget = Workspace.Spherecast
    hooks.spherecastOriginal = hookFunction(hooks.spherecastTarget, function(workspaceInstance, origin, radius, direction, params)
        if workspaceInstance == Workspace and meleeTarget then
            local offset = meleeTarget.position - origin
            if offset.Magnitude <= direction.Magnitude + radius + 2 then
                return {
                    Distance = offset.Magnitude,
                    Instance = meleeTarget.part,
                    Material = meleeTarget.part.Material,
                    Normal = -offset.Unit,
                    Position = meleeTarget.position,
                }
            end
        end
        return hooks.spherecastOriginal(workspaceInstance, origin, radius, direction, params)
    end)

    hooks.meleeTarget = Melee.shoot
    hooks.meleeOriginal = hookFunction(hooks.meleeTarget, function(melee, heavy)
        activeWeaponKind = "Knife"
        local settings = store:Get().settings
        meleeRange = melee.Properties and melee.Properties.Range or meleeRange
        local camera
        local cameraCFrame
        if not stopped and settings.knifeAura then
            local selected = currentTarget or selectTarget(false)
            currentTarget = nil
            if selected and targetVisible(selected) then
                camera = Workspace.CurrentCamera
                local origin = camera and camera.CFrame.Position
                local range = meleeRange
                local offset = origin and selected.position - origin
                if offset and offset.Magnitude > 0.001 and offset.Magnitude <= range + 2 then
                    meleeTarget = selected
                    cameraCFrame = camera.CFrame
                    camera.CFrame = CFrame.lookAt(origin, selected.position)
                end
            end
        end

        local packed = table.pack(pcall(hooks.meleeOriginal, melee, heavy))
        meleeTarget = nil
        if cameraCFrame then
            camera.CFrame = cameraCFrame
        end
        if not packed[1] then
            error(packed[2], 0)
        end
        return table.unpack(packed, 2, packed.n)
    end)

    local function equippedWeapon(player)
        local encoded = player:GetAttribute("CurrentEquipped")
        if type(encoded) ~= "string" then
            return nil, nil
        end
        local success, value = pcall(game:GetService("HttpService").JSONDecode, game:GetService("HttpService"), encoded)
        if success and type(value) == "table" then
            local kind
            for _, fieldName in ipairs({
                "Type",
                "Class",
                "Category",
                "ItemType",
                "WeaponType",
                "Component",
                "Name",
            }) do
                local field = value[fieldName]
                if type(field) == "string" then
                    local normalized = string.lower(field)
                    if string.find(normalized, "knife", 1, true)
                        or string.find(normalized, "melee", 1, true)
                    then
                        kind = "Knife"
                        break
                    elseif string.find(normalized, "gun", 1, true)
                        or string.find(normalized, "firearm", 1, true)
                        or normalized == "primary"
                        or normalized == "secondary"
                    then
                        kind = "Gun"
                        break
                    end
                end
            end
            return value.Name, kind
        end
        return nil, nil
    end

    local function updateObservations(settings)
        local includeEnemies = settings.showEnemies ~= false
        local includeTeammates = settings.showTeammates == true
        local eligibility = isOpponent
        if includeTeammates then
            eligibility = function(player, character)
                return playerTone(player, character) ~= nil
            end
        end
        local observed = targeting.observePlayers({
            isEligible = eligibility,
            raycastIgnore = spectatorRaycastIgnore(),
            screenOrigin = UserInputService:GetMouseLocation(),
        })

        local visibleCount = 0
        local opponents = includeTeammates and {} or observed
        local allies = {}
        for _, observation in ipairs(observed) do
            local humanoid = observation.character and observation.character:FindFirstChildOfClass("Humanoid")
            observation.health = humanoid and humanoid.Health or 0
            observation.maxHealth = humanoid and humanoid.MaxHealth or 100
            observation.weapon = equippedWeapon(observation.player)
            observation.tone = playerTone(observation.player, observation.character)
            if observation.tone == "team" then
                table.insert(allies, observation)
            elseif observation.tone == "enemy" then
                if includeTeammates then
                    table.insert(opponents, observation)
                end
                if observation.visible then
                    visibleCount = visibleCount + 1
                end
            end
        end
        observations = opponents
        if includeTeammates and includeEnemies then
            local combined = {}
            for _, observation in ipairs(opponents) do
                table.insert(combined, observation)
            end
            for _, observation in ipairs(allies) do
                table.insert(combined, observation)
            end
            visualObservations = combined
        elseif includeTeammates then
            visualObservations = allies
        elseif includeEnemies then
            visualObservations = observed
        else
            visualObservations = {}
        end
        return visibleCount
    end

    local function tagged(tagName)
        if not CollectionService or type(CollectionService.GetTagged) ~= "function" then
            return {}
        end
        local success, instances = pcall(CollectionService.GetTagged, CollectionService, tagName)
        return success and instances or {}
    end

    local function projectPosition(camera, position)
        local point, onScreen = camera:WorldToViewportPoint(position)
        return Vector2.new(point.X, point.Y), onScreen == true and point.Z > 0
    end

    local function projectTop(camera, part)
        local half = part.Size * 0.5
        local points = {}
        for _, offset in ipairs({
            Vector3.new(-half.X, half.Y + 0.04, -half.Z),
            Vector3.new(half.X, half.Y + 0.04, -half.Z),
            Vector3.new(half.X, half.Y + 0.04, half.Z),
            Vector3.new(-half.X, half.Y + 0.04, half.Z),
        }) do
            local screen, onScreen = projectPosition(camera, part.CFrame:PointToWorldSpace(offset))
            if not onScreen then
                return nil
            end
            table.insert(points, screen)
        end
        return points
    end

    local function activeVoxels(folder, requireEnabledEmitter)
        local parts = {}
        local hasEnabledEmitter = false
        for _, descendant in ipairs(folder:GetDescendants()) do
            if descendant:IsA("BasePart") then
                table.insert(parts, descendant)
            elseif descendant:IsA("ParticleEmitter") and descendant.Enabled then
                hasEnabledEmitter = true
            end
        end
        return (not requireEnabledEmitter or hasEnabledEmitter) and parts or {}
    end

    local function zoneObservation(camera, folder, label, tone, requireEnabledEmitter)
        local parts = activeVoxels(folder, requireEnabledEmitter)
        if #parts == 0 then
            return nil
        end
        local center = Vector3.new(0, 0, 0)
        for _, part in ipairs(parts) do
            center += part.Position
        end
        center /= #parts
        local distance = (camera.CFrame.Position - center).Magnitude
        if distance > UTILITY_MAX_DISTANCE then
            return nil
        end

        local polygons = {}
        local stride = math.max(1, math.ceil(#parts / MAX_ZONE_QUADS))
        for index = 1, #parts, stride do
            local polygon = projectTop(camera, parts[index])
            if polygon then
                table.insert(polygons, polygon)
            end
        end
        local screenPosition, onScreen = projectPosition(camera, center + Vector3.new(0, 1.5, 0))
        return {
            key = folder,
            label = label,
            onScreen = onScreen,
            polygons = polygons,
            screenPosition = screenPosition,
            tone = tone,
        }
    end

    local function updateWorldObservations(settings)
        local camera = Workspace.CurrentCamera
        local utilities = {}
        local bombObservation = {
            visible = false,
        }
        if not camera then
            return bombObservation, utilities
        end

        if settings.bombTimer then
            for _, model in ipairs(tagged("Bomb")) do
                local primaryPart = model.PrimaryPart
                local encoded = model:GetAttribute("BombPlanted")
                if primaryPart and type(encoded) == "string"
                    and model:GetAttribute("Defused") ~= true
                    and model:GetAttribute("Exploded") ~= true
                then
                    if encoded ~= bombAttribute then
                        local success, decoded = pcall(HttpService.JSONDecode, HttpService, encoded)
                        bombAttribute = encoded
                        bombData = success and decoded or nil
                    end
                    local remaining = Counterblox.bombTimeRemaining(
                        bombData,
                        Workspace:GetServerTimeNow()
                    )
                    local distance = (camera.CFrame.Position - primaryPart.Position).Magnitude
                    local presentation = Counterblox.bombPresentation(distance)
                    bombObservation = {
                        adornee = primaryPart,
                        presentation = presentation,
                        remaining = remaining,
                        visible = remaining > 0 and presentation.visible,
                    }
                    break
                end
            end
        end

        if not settings.utilityEsp then
            return bombObservation, utilities
        end
        for _, model in ipairs(tagged("Grenade")) do
            local primaryPart = model.PrimaryPart
            if primaryPart and model:GetAttribute("SimulationFinished") ~= true then
                local distance = (camera.CFrame.Position - primaryPart.Position).Magnitude
                if distance <= UTILITY_MAX_DISTANCE then
                    local label, tone = Counterblox.utilityLabel(model:GetAttribute("GrenadeName"))
                    local screenPosition, onScreen = projectPosition(camera, primaryPart.Position)
                    table.insert(utilities, {
                        key = model,
                        label = label,
                        onScreen = onScreen,
                        polygons = {},
                        screenPosition = screenPosition,
                        tone = tone,
                    })
                end
            end
        end

        local debris = Workspace:FindFirstChild("Debris")
        if debris then
            for _, child in ipairs(debris:GetChildren()) do
                local observation
                if string.sub(child.Name, 1, 10) == "VoxelFire_" then
                    observation = zoneObservation(camera, child, "FIRE ZONE", "danger", true)
                elseif string.sub(child.Name, 1, 11) == "VoxelSmoke_" then
                    observation = zoneObservation(camera, child, "SMOKE", "smoke", false)
                end
                if observation then
                    table.insert(utilities, observation)
                end
            end
        end
        return bombObservation, utilities
    end

    local function equippedGunComponent()
        local activeWeapon = store:Get().activeWeapon
        if not activeWeapon then
            return nil
        end

        for component, componentWeapon in pairs(trackedComponents) do
            if component.IsDestroyed then
                trackedComponents[component] = nil
            elseif component.Player == LocalPlayer
                and componentWeapon == activeWeapon
                and component.Bullet
                and component.Bullet.Properties
            then
                return component
            end
        end
        return nil
    end

    local function equippedGunBullet()
        local component = equippedGunComponent()
        return component and component.Bullet or nil
    end

    local function penetrationAccepted(target)
        local camera = Workspace.CurrentCamera
        local bullet = equippedGunBullet()
        if not camera or not bullet then
            return false
        end

        local _, accepted = Counterblox.redirectBullet({ Origin = camera.CFrame.Position }, target, bullet, {
            cast = GameRaycast.cast,
            castThrough = GameRaycast.castThrough,
            getIgnore = GetRayIgnore,
        })
        return accepted
    end

    local function runTriggerBot()
        local settings = store:Get().settings
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not settings.triggerBot
            or not character
            or character:GetAttribute("Dead") == true
            or (humanoid and humanoid.Health <= 0)
            or activeWeaponKind ~= "Gun"
            or os.clock() < nextTriggerAt
        then
            return
        end

        local target = selectTarget(settings.silentAim and settings.wallbang)
        if not target then
            return
        end
        if not targetVisible(target) and not (settings.silentAim and settings.wallbang) then
            return
        end
        if not penetrationAccepted(target) then
            return
        end

        currentTarget = Counterblox.applyAimRates(target, settings, random)
        nextTriggerAt = os.clock() + 0.1
        click()
    end

    local function localCharacter()
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not character
            or character:GetAttribute("Dead") == true
            or (humanoid and humanoid.Health <= 0)
        then
            return nil, nil, nil
        end
        return character, humanoid, character:FindFirstChild("HumanoidRootPart")
    end

    local function runRapidFire()
        local settings = store:Get().settings
        if not settings.rapidFire
            or activeWeaponKind ~= "Gun"
            or context.isInputCaptured()
            or os.clock() < nextRapidFireAt
        then
            return
        end

        local weapon = equippedGunComponent()
        local fireHeld = context.isFireHeld
            and context.isFireHeld()
            or weapon and weapon.IsFireHeld
        if not weapon
            or weapon.IsDestroyed
            or not weapon.IsEquipped
            or not fireHeld
            or weapon.IsReloading
            or (type(weapon.Rounds) == "number" and weapon.Rounds <= 0)
        then
            return
        end

        if weapon.ShootDelayThread then
            cancelThread(weapon.ShootDelayThread)
        end
        weapon.ShootDelayThread = nil
        weapon.IsShooting = false
        weapon.NextShotDue = nil
        nextRapidFireAt = os.clock() + RAPID_FIRE_INTERVAL
        press()
    end

    local function runKnifeAura()
        local settings = store:Get().settings
        if not settings.knifeAura
            or activeWeaponKind ~= "Knife"
            or os.clock() < nextAuraAt
        then
            return
        end

        local _, humanoid, root = localCharacter()
        if not root then
            return true
        end

        local camera = Workspace.CurrentCamera
        if not camera then
            return true
        end
        local target = Counterblox.nearestMeleeTarget(root.CFrame.Position, observations)
        if not target then
            return true
        end
        local plan = Counterblox.planMeleeAttack(
            camera.CFrame.Position,
            root.CFrame.Position,
            target,
            meleeRange
        )
        local targetRoot = target.character and target.character:FindFirstChild("HumanoidRootPart")
        local offset = (targetRoot and targetRoot.Position or target.position) - root.CFrame.Position
        local distance = plan.distance
        local attackRange = meleeRange + KNIFE_HIT_TOLERANCE
        if not plan.inRange then
            if not settings.microStep or distance > attackRange + KNIFE_EXTRA_REACH then
                return true
            end

            local horizontal = Vector3.new(offset.X, 0, offset.Z)
            if horizontal.Magnitude <= 0.001
                or not humanoid.FloorMaterial
                or humanoid.FloorMaterial.Name == "Air"
            then
                return true
            end
            local stepDistance = math.min(KNIFE_MICRO_STEP, distance - attackRange)
            root.CFrame = root.CFrame + horizontal.Unit * stepDistance
            return true
        end

        currentTarget = target
        nextAuraAt = os.clock() + KNIFE_AURA_INTERVAL
        store:Patch({
            lastShot = plan.heavy and "Auto backstab" or "Knife Aura",
            target = target.player,
        })
        if plan.heavy then
            heavyClick()
        else
            click()
        end
        return true
    end

    local function restoreSpinMotion()
        if spinJoint and spinJointC0 then
            pcall(function()
                spinJoint.C0 = spinJointC0
            end)
        end
        spinRoot = nil
        spinJoint = nil
        spinJointC0 = nil
        spinAngle = 0
    end

    local function restoreSpin()
        restoreSpinMotion()
        updateThirdPersonPresentation(false)
        setThirdPerson(false)
    end

    local function runMovement(deltaTime)
        local settings = store:Get().settings
        local character, humanoid, root = localCharacter()
        if not humanoid or not root then
            bhopRoot = nil
            bhopMomentum = nil
            bhopSpeedLimit = nil
            restoreSpin()
            return
        end
        if bhopRoot ~= root then
            bhopRoot = root
            bhopMomentum = nil
            bhopSpeedLimit = nil
        end

        local alive = humanoid.Health > 0 and character:GetAttribute("Dead") ~= true
        if settings.spinBot and alive then
            if spinRoot ~= root then
                restoreSpinMotion()
                spinRoot = root
                for _, descendant in ipairs(character:GetDescendants()) do
                    if descendant:IsA("Motor6D")
                        and (descendant.Part0 == root or descendant.Part1 == root)
                    then
                        spinJoint = descendant
                        spinJointC0 = descendant.C0
                        break
                    end
                end
            end
            setThirdPerson(true)
            updateThirdPersonPresentation(true)
            if spinJoint and spinJointC0 then
                spinAngle = (spinAngle + SPIN_SPEED * deltaTime) % (math.pi * 2)
                spinJoint.C0 = spinJointC0 * CFrame.Angles(0, spinAngle, 0)
            end
            local camera = Workspace.CurrentCamera
            if camera then
                local rotation = camera.CFrame.Rotation
                local focus = root.Position + Vector3.new(0, 2, 0)
                camera.CFrame = CFrame.new(focus - camera.CFrame.LookVector * THIRD_PERSON_DISTANCE) * rotation
            end
        else
            restoreSpin()
        end

        if settings.bhop and isJumpHeld() then
            local velocity = root.AssemblyLinearVelocity
            local moveDirection = movementDirection and movementDirection() or humanoid.MoveDirection
            if not bhopMomentum then
                bhopMomentum = Vector3.new(velocity.X, 0, velocity.Z)
                bhopSpeedLimit = math.max(
                    bhopMomentum.Magnitude,
                    humanoid.WalkSpeed * BHOP_SPEED_MULTIPLIER
                )
            end
            if moveDirection.Magnitude > 0.001 then
                local direction = moveDirection.Unit
                local acceleration = math.min(
                    math.max(humanoid.WalkSpeed - bhopMomentum:Dot(direction), 0),
                    humanoid.WalkSpeed * BHOP_AIR_ACCELERATION * (deltaTime or 0)
                )
                local steered = bhopMomentum + direction * acceleration
                if steered.Magnitude > bhopSpeedLimit then
                    steered = steered.Unit * bhopSpeedLimit
                end
                bhopMomentum = steered
            end
            root.AssemblyLinearVelocity =
                Vector3.new(bhopMomentum.X, velocity.Y, bhopMomentum.Z)
            if humanoid.FloorMaterial and humanoid.FloorMaterial.Name ~= "Air" then
                humanoid.Jump = true
            end
        else
            bhopMomentum = nil
            bhopSpeedLimit = nil
        end
    end

    local function updateSuppressions(settings)
        if settings.noRecoil then
            CrosshairSettings["Follow Recoil"] = false
        else
            CrosshairSettings["Follow Recoil"] = followRecoil
        end
        if settings.noFlash and not noFlashApplied then
            FlashEffect.CancelFlash()
        end
        if settings.noSmoke and not noSmokeApplied then
            VoxelSmoke.DestroyAll()
        end
        noFlashApplied = settings.noFlash == true
        noSmokeApplied = settings.noSmoke == true
    end

    local movementConnection
    local movementBound = type(RunService.BindToRenderStep) == "function"
    if movementBound then
        RunService:BindToRenderStep(MOVEMENT_RENDER_STEP, MOVEMENT_RENDER_PRIORITY, runMovement)
    else
        movementConnection = RunService.RenderStepped:Connect(runMovement)
    end

    local renderConnection = RunService.RenderStepped:Connect(function()
        if stopped then
            return
        end

        local settings = store:Get().settings
        updateSuppressions(settings)
        local activeWeapon, equippedKind = equippedWeapon(LocalPlayer)
        if activeWeapon ~= lastEquippedName then
            lastEquippedName = activeWeapon
            activeWeaponKind = equippedKind
        end
        if not selectedCosmeticWeapon and activeWeapon then
            selectedCosmeticWeapon = activeWeapon
        end
        local cosmeticWeapon = currentCosmeticWeapon()
        publishCosmetics(cosmeticWeapon)
        publishGloves()
        local limnVisualsEnabled = settings.worldRenderer ~= "native"
            and (settings.boxes == true
                or settings.chams == true
                or settings.names == true
                or settings.health == true
                or settings.weapon == true)
        local observationsEnabled = settings.silentAim == true
            or settings.triggerBot == true
            or settings.knifeAura == true
            or limnVisualsEnabled
        local visibleCount = 0
        if observationsEnabled then
            visibleCount = updateObservations(settings)
        elseif #observations > 0 or #visualObservations > 0 then
            observations = {}
            visualObservations = observations
        end
        local bombObservation, utilityObservations = updateWorldObservations(settings)
        store:Patch({
            activeWeapon = activeWeapon,
            activeWeaponKind = activeWeaponKind,
            bombObservation = bombObservation,
            cosmeticWeapon = cosmeticWeapon,
            observations = observations,
            utilityObservations = {
                count = #utilityObservations,
            },
            status = ("%d enemies · %d visible"):format(#observations, visibleCount),
        })
        context.render(visualObservations, UserInputService:GetMouseLocation(), utilityObservations)
        runRapidFire()
        if not runKnifeAura() then
            runTriggerBot()
        end
    end)

    function self.stop()
        if stopped then
            return
        end
        stopped = true
        renderConnection:Disconnect()
        if movementBound then
            RunService:UnbindFromRenderStep(MOVEMENT_RENDER_STEP)
        elseif movementConnection then
            movementConnection:Disconnect()
        end
        CrosshairSettings["Follow Recoil"] = followRecoil
        restoreSpin()
        restoreFunction(hooks.meleeTarget)
        restoreFunction(hooks.spherecastTarget)
        restoreFunction(hooks.workspaceRaycastTarget)
        restoreFunction(hooks.speedTarget)
        restoreFunction(hooks.viewmodelConstructTarget)
        restoreFunction(hooks.weaponComponentTarget)
        restoreFunction(hooks.smokeTarget)
        restoreFunction(hooks.flashTarget)
        restoreFunction(hooks.cameraUpdateTarget)
        restoreFunction(hooks.weaponRecoilTarget)
        restoreFunction(hooks.recoilTarget)
        restoreFunction(hooks.spreadUpdateTarget)
        restoreFunction(hooks.spreadTarget)
        restoreFunction(hooks.bulletTarget)
    end

    function self:weaponPreviewKey(state)
        local weaponName = currentCosmeticWeapon()
        local override = weaponName and cosmeticOverride(weaponName)
        return table.concat({
            "weapon",
            tostring(weaponName),
            tostring(override and override.weapon),
            tostring(override and override.skin),
            tostring(override and override.wear),
            tostring(override and override.statTrak),
        }, "|")
    end
    function self:weaponPreviewSubject(state)
        local weaponName = currentCosmeticWeapon()
        if not weaponName then
            return nil
        end
        local override = cosmeticOverride(weaponName) or {
            weapon = weaponName,
            skin = "Stock",
            wear = 0,
            statTrak = false,
        }
        local success, weapon = pcall(
            Skins.GetCharacterModel,
            override.weapon or weaponName,
            override.skin or "Stock",
            override.wear or 0,
            override.statTrak == true
        )
        if not success or typeof(weapon) ~= "Instance" or not weapon:IsA("Model") then
            return nil
        end
        weapon.Name = "UniversalHubWeaponPreview"
        return weapon
    end

    self.capabilities = context.capabilities or {}
    self.classify = Counterblox.classifyWeapon
    self.isOpponent = isOpponent
    self.selectTarget = selectTarget
    self.worldPolicy = {
        isPlayerEligible = isOpponent,
        getPlayerTone = playerTone,
        getWeapon = function(player)
            return equippedWeapon(player)
        end,
        connectPlayerChanged = function(player, invalidate)
            local connections = {
                player:GetAttributeChangedSignal("CurrentEquipped"):Connect(invalidate),
                player:GetAttributeChangedSignal("Team"):Connect(invalidate),
            }
            return function()
                for _, connection in ipairs(connections) do
                    connection:Disconnect()
                end
            end
        end,
        connectCharacterChanged = function(_player, character, invalidate)
            return character:GetAttributeChangedSignal("Dead"):Connect(invalidate)
        end,
        subscribeChanged = function(invalidate)
            local connections = {
                Workspace:GetAttributeChangedSignal("Gamemode"):Connect(invalidate),
                Workspace:GetAttributeChangedSignal("ServerGamemode"):Connect(invalidate),
                LocalPlayer:GetAttributeChangedSignal("Team"):Connect(invalidate),
            }
            local cameraConnection
            local function bindCamera()
                if cameraConnection then
                    cameraConnection:Disconnect()
                end
                local camera = Workspace.CurrentCamera
                cameraConnection = camera and camera:GetPropertyChangedSignal("CameraSubject"):Connect(invalidate)
                    or nil
                invalidate()
            end
            table.insert(connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera))
            bindCamera()
            return function()
                if cameraConnection then
                    cameraConnection:Disconnect()
                end
                for _, connection in ipairs(connections) do
                    connection:Disconnect()
                end
            end
        end,
    }
    function self:cycleCosmeticWeapon(direction)
        local weapons = cosmeticWeapons()
        if #weapons == 0 then
            return
        end
        local index = table.find(weapons, currentCosmeticWeapon())
        if not index then
            index = direction > 0 and 0 or 1
        end
        selectedCosmeticWeapon = weapons[((index - 1 + direction) % #weapons) + 1]
        lastCosmeticKey = nil
        publishCosmetics(selectedCosmeticWeapon)
        store:Patch({ cosmeticWeapon = selectedCosmeticWeapon })
    end
    function self:cycleSkin(direction)
        local weaponName = currentCosmeticWeapon()
        if not weaponName then
            return
        end
        local catalog = cosmeticCatalog(weaponName)
        local current = cosmeticOverride(weaponName)
        local _, index = cosmeticSchema(
            weaponName,
            current and current.skin or "Stock",
            current and current.weapon or weaponName
        )
        local nextIndex = ((index - 1 + direction) % #catalog) + 1
        local schema = catalog[nextIndex]
        local range = schema.floatRange or { min = 0, max = 1 }
        setCosmetic(weaponName, schema, range.min, false)
    end
    function self:setWear(alpha)
        local weaponName = currentCosmeticWeapon()
        local current = weaponName and cosmeticOverride(weaponName)
        if not weaponName or not current then
            return
        end
        local schema = cosmeticSchema(weaponName, current.skin, current.weapon)
        local range = schema.floatRange or { min = 0, max = 1 }
        setCosmetic(
            weaponName,
            schema,
            (range.min or 0) + ((range.max or 1) - (range.min or 0)) * math.clamp(alpha, 0, 1),
            current.statTrak
        )
    end
    function self:toggleStatTrak()
        local weaponName = currentCosmeticWeapon()
        local current = weaponName and cosmeticOverride(weaponName)
        if not weaponName or not current then
            return
        end
        local schema = cosmeticSchema(weaponName, current.skin, current.weapon)
        if schema.supportsStatTrak then
            setCosmetic(weaponName, schema, current.wear, not current.statTrak)
        end
    end
    function self:resetSkin()
        local weaponName = currentCosmeticWeapon()
        if weaponName then
            setCosmetic(weaponName, cosmeticCatalog(weaponName)[1], 0, false)
        end
    end
    function self:cycleGlove(direction)
        local catalog = gloveCatalog()
        if #catalog == 0 then
            return
        end
        local current = gloveOverride()
        local _, index = current and gloveSchema(current.weapon, current.skin) or nil, 0
        if current then
            _, index = gloveSchema(current.weapon, current.skin)
        end
        local nextIndex = ((index - 1 + direction) % #catalog) + 1
        local schema = catalog[nextIndex]
        local range = schema.floatRange or { min = 0, max = 1 }
        setGlove(schema, range.min)
    end
    function self:setGloveWear(alpha)
        local current = gloveOverride()
        if not current then
            return
        end
        local schema = gloveSchema(current.weapon, current.skin)
        if not schema then
            return
        end
        local range = schema.floatRange or { min = 0, max = 1 }
        setGlove(
            schema,
            (range.min or 0) + ((range.max or 1) - (range.min or 0)) * math.clamp(alpha, 0, 1)
        )
    end
    function self:setGloveColor(color)
        local settings = store:Get().settings
        if type(color) == "table" then
            settings.gloveColorOverride = {
                b = math.clamp(color.b or 0, 0, 1),
                g = math.clamp(color.g or 0, 0, 1),
                r = math.clamp(color.r or 0, 0, 1),
            }
        else
            settings.gloveColorOverride = false
        end
        refreshGloves()
        if context.settingsChanged then
            context.settingsChanged(settings)
        end
    end
    function self:resetGlove()
        local settings = store:Get().settings
        settings.gloveOverride = false
        settings.gloveColorOverride = false
        lastGloveKey = nil
        refreshGloves()
        publishGloves()
        if context.settingsChanged then
            context.settingsChanged(settings)
        end
    end
    return self
end

return Counterblox
]],
    ["games/bloxstrike/Definition.lua"] = [[return {
    composition = "games/bloxstrike/Composition",
    defaults = {},
    features = {
        capabilities = {
            "silentAim", "triggerBot", "wallbang", "knifeAura", "microStep",
            "spinBot", "bhop", "rapidFire", "bombTimer", "utilityEsp",
            "headshotRate", "missRate", "noSpread", "noRecoil", "noFlash",
            "noSmoke", "noWeaponSlow", "boxes", "chams", "chamsExcludeAccessories",
            "chamsPerPart", "showTeammates", "worldRenderer", "names", "health", "weapon",
        },
    },
    hydroxide = { "targeting" },
    id = "bloxstrike",
    initialState = {},
    label = "Bloxstrike",
    manifest = {
        gameIds = { 7633926880 },
        placeIds = { 114234929420007 },
    },
    module = "games/Bloxstrike",
    presentation = "games/bloxstrike/Presentation",
    sources = {
        "games/Bloxstrike",
        "games/Counterblox",
        "games/bloxstrike/Preview",
        "games/bloxstrike/Composition",
        "games/bloxstrike/Presentation",
    },
}
]],
    ["games/counterblox/Definition.lua"] = [[return {
    composition = "games/counterblox/Composition",
    defaults = {},
    features = {
        capabilities = {
            "silentAim",
            "triggerBot",
            "wallbang",
            "knifeAura",
            "microStep",
            "spinBot",
            "bhop",
            "rapidFire",
            "bombTimer",
            "utilityEsp",
            "headshotRate",
            "missRate",
            "noSpread",
            "noRecoil",
            "noFlash",
            "noSmoke",
            "noWeaponSlow",
            "boxes",
            "chams",
            "showEnemies",
            "showTeammates",
            "names",
            "health",
            "weapon",
        },
    },
    hydroxide = {
        "targeting",
    },
    id = "counterblox",
    initialState = {},
    label = "Counterblox",
    manifest = {
        gameIds = { 115797356 },
        placeIds = { 301549746 },
    },
    module = "games/Counterblox",
    presentation = "games/counterblox/Presentation",
    sources = {
        "games/Counterblox",
        "games/counterblox/Composition",
        "games/counterblox/Presentation",
    },
}
]],
    ["games/duelinggrounds/Definition.lua"] = [[return {
    defaults = {
        autoFight = false,
        autoMovement = false,
        botSkill = 85,
        combatStyle = "offensive",
        showWins = false,
        teleportBehind = false,
        noclip = false,
    },
    features = {
        capabilities = {
            "boxes",
            "chams",
            "chamsExcludeAccessories",
            "chamsPerPart",
            "showEnemies",
            "worldRenderer",
            "names",
            "health",
            "showWins",
            "autoFight",
            "autoMovement",
            "botSkill",
            "combatStyle",
            "teleportBehind",
            "noclip",
        },
        cosmetics = false,
    },
    hydroxide = { "targeting" },
    id = "duelinggrounds",
    initialState = {},
    label = "Dueling Grounds ⚔️",
    manifest = {
        gameIds = { 9051406594 },
        placeIds = { 94217045453265 },
    },
    module = "games/duelinggrounds/Adapter",
    presentation = "games/duelinggrounds/Presentation",
    sources = {
        "games/duelinggrounds/Adapter",
        "games/duelinggrounds/Presentation",
        "games/duelinggrounds/features/AutoMovement",
        "games/duelinggrounds/features/CombatPipeline",
        "games/duelinggrounds/features/CombatRuntime",
        "games/duelinggrounds/features/Noclip",
        "games/duelinggrounds/features/TeleportBehind",
        "games/duelinggrounds/features/WinTitles",
        "games/duelinggrounds/features/combat/Attacks",
        "games/duelinggrounds/features/combat/Combos",
        "games/duelinggrounds/features/combat/DefensiveStyle",
        "games/duelinggrounds/features/combat/DynamicStyle",
        "games/duelinggrounds/features/combat/EnemyPolicy",
        "games/duelinggrounds/features/combat/EnemyObserver",
        "games/duelinggrounds/features/combat/FlashyStyle",
        "games/duelinggrounds/features/combat/JumpAttackPolicy",
        "games/duelinggrounds/features/combat/OffensiveStyle",
        "games/duelinggrounds/features/combat/Skill",
        "games/duelinggrounds/features/combat/Styles",
        "games/duelinggrounds/features/combat/UltimatePolicy",
        "games/duelinggrounds/features/combat/defense/Planner",
        "games/duelinggrounds/features/combat/defense/Executor",
        "games/duelinggrounds/features/combat/offense/Executor",
        "games/duelinggrounds/recording/Persistence",
        "games/duelinggrounds/recording/Runtime",
        "games/duelinggrounds/recording/Sampler",
    },
}
]],
    ["games/hoodrivals/Definition.lua"] = [[return {
    defaults = {
        autoReload = false,
        fastReload = false,
        noScope = false,
        rapidFireDelay = 40,
    },
    features = {
        capabilities = {
            "silentAim",
            "triggerBot",
            "rapidFire",
            "rapidFireDelay",
            "headshotRate",
            "missRate",
            "boxes",
            "chams",
            "showEnemies",
            "showTeammates",
            "names",
            "health",
            "weapon",
        },
    },
    hydroxide = {
        "closure",
        "targeting",
    },
    id = "hoodrivals",
    initialState = {},
    label = "Hood Rivals",
    manifest = {
        gameIds = { 10648640958 },
        placeIds = { 77463332823746, 113272123504853 },
    },
    module = "games/hoodrivals/Adapter",
    presentation = "games/hoodrivals/Presentation",
    sources = {
        "games/hoodrivals/Adapter",
        "games/hoodrivals/Firearm",
        "games/hoodrivals/Presentation",
        "games/hoodrivals/Targeting",
        "games/hoodrivals/WeaponPolicy",
        "games/hoodrivals/features/AutoReload",
        "games/hoodrivals/features/FastReload",
        "games/hoodrivals/features/NoScope",
        "games/hoodrivals/features/RapidFire",
        "games/hoodrivals/features/SilentAim",
        "games/hoodrivals/features/TriggerBot",
    },
}
]],
    ["games/rivals/Definition.lua"] = [[return {
    defaults = {
        aimAssistStrength = 60,
        autoCounter = false,
        redLightSafety = false,
        taskAutomationEnabled = false,
        taskAutomationEmergencyKey = "End",
        infiniteJump = false,
        wallNoclip = false,
        teleportBehind = false,
        skipDeflect = false,
        autoDeflect = false,
        rapidFire = false,
        fireRate = 200,
        flickProjectiles = false,
        quickReload = false,
        meleeReach = false,
        meleeReachScale = 200,
        unlockAllSkins = false,
        unlockAllSkinsRestore = {},
        unlockAllCosmeticsEquipped = {},
        triggerDelay = 0,
    },
    features = {
        capabilities = {
            "silentAim",
            "shotAim",
            "target360",
            "triggerBot",
            "triggerDelay",
            "rapidFire",
            "fireRate",
            "flickProjectiles",
            "quickReload",
            "meleeReach",
            "meleeReachScale",
            "skipDeflect",
            "autoDeflect",
            "autoCounter",
            "redLightSafety",
            "autoPickup",
            "alwaysScoped",
            "humanAim",
            "bhop",
            "infiniteJump",
            "wallNoclip",
            "teleportBehind",
            "aimSmoothness",
            "aimAssistStrength",
            "headshotRate",
            "missRate",
            "boxes",
            "chams",
            "chamsExcludeAccessories",
            "chamsPerPart",
            "showEnemies",
            "showTeammates",
            "worldRenderer",
            "names",
            "health",
            "weapon",
            "utilityEsp",
            "noFlash",
            "noSmoke",
            "unlockAllSkins",
            "taskAutomationEnabled",
            "taskAutomationEmergencyKey",
        },
        cosmetics = false,
        exclusiveOptions = {
            shotAim = { "silentAim", "humanAim" },
            silentAim = { "shotAim" },
        },
        optionLabels = {
            humanAim = "Aim Assist",
            alwaysScoped = "Always Scoped",
            skipDeflect = "Katana Stop",
            autoDeflect = "Auto Katana",
            triggerDelay = "Delay",
            rapidFire = "Rapid Fire",
            fireRate = "Fire Rate",
            flickProjectiles = "Flick Projectiles",
            quickReload = "Quick Reload",
            meleeReach = "Melee Reach",
            meleeReachScale = "Reach",
            autoCounter = "Auto Counter",
            redLightSafety = "Red Light Safety",
            teleportBehind = "Warp",
            silentAim = "Camera Aim",
            shotAim = "Silent Aim",
            taskAutomationEnabled = "Task Farming",
            taskAutomationEmergencyKey = "Emergency Stop",
        },
    },
    hydroxide = {
        "targeting",
    },
    id = "rivals",
    initialState = {},
    label = "RIVALS",
    manifest = {
        gameIds = { 6035872082 },
        placeIds = { 17625359962 },
    },
    module = "games/rivals/Adapter",
    presentation = "games/rivals/Presentation",
    sources = {
        "games/rivals/Adapter",
        "games/rivals/Session",
        "games/rivals/Presentation",
        "games/rivals/features/CameraAim",
        "games/rivals/features/SilentAim",
        "games/rivals/features/ShotPresentation",
        "games/rivals/features/TeleportBehind",
        "games/rivals/features/TriggerBot",
        "games/rivals/features/RapidFire",
        "games/rivals/features/QuickReload",
        "games/rivals/features/MeleeReach",
        "games/rivals/features/SkipBlocks",
        "games/rivals/features/AutoDeflect",
        "games/rivals/features/AutoCounter",
        "games/rivals/features/NoScope",
        "games/rivals/features/Pickup",
        "games/rivals/features/SkinUnlock",
        "games/rivals/features/RedLightSafety",
        "games/rivals/features/ScopedAccuracy",
        "games/rivals/features/AutoCounterRuntime",
        "games/rivals/features/GunGameRuntime",
        "games/rivals/libraries/HookRuntime",
        "games/rivals/libraries/ItemPolicy",
        "games/rivals/libraries/ItemInput",
        "games/rivals/libraries/WeaponPolicy",
        "games/rivals/libraries/Targeting",
        "games/rivals/libraries/ProjectileAim",
        "games/rivals/libraries/CombatState",
        "games/rivals/libraries/ModePolicy",
        "games/rivals/libraries/Movement",
        "games/rivals/tasks/TaskPolicy",
        "games/rivals/tasks/TaskFarmRuntime",
        "games/rivals/tasks/PracticeTaskDriver",
        "games/rivals/tasks/TaskCamera",
        "games/rivals/tasks/TaskLocomotion",
        "games/rivals/tasks/TaskWeaponSwap",
        "games/rivals/tasks/TaskSkillRuntime",
        "games/rivals/tasks/TaskCounterPolicy",
        "games/rivals/tasks/TaskLoadout",
        "games/rivals/world/Effects",
        "games/rivals/world/UtilityPolicy",
        "games/rivals/world/VisualSuppression",
        "games/rivals/world/TrajectoryRenderer",
        "games/rivals/world/ObservationRuntime",
        "games/rivals/world/WorldPolicy",
    },
}
]],
    ["games/stealanegg/Definition.lua"] = [[return {
    defaults = {
        antiHit = false,
        antiTrap = false,
        autoBlossom = false,
        autoFarm = false,
        autoFarmEternal = true,
        autoFarmIndex = false,
        autoFarmSecret = true,
        autoFarmServerHopping = true,
        autoOpenEggs = false,
        idleTreadmill = true,
        eggEsp = false,
        eggRadar = true,
        eggEspMinimumRarity = 1,
        eggEspMinimumSize = 0.5,
        hitAura = false,
        hitAuraIgnoreFriends = true,
        instantPrompts = false,
        lagSafeMovement = false,
        serverHop = false,
        serverHopAttempts = 0,
        serverHopMaxPing = 120,
        serverHopPingGuard = false,
        serverHopTargetPopulation = 6,
        trapEsp = false,
    },
    features = {
        capabilities = {
            "antiHit",
            "antiTrap",
            "autoBlossom",
            "autoFarm",
            "autoFarmEternal",
            "autoFarmIndex",
            "autoFarmSecret",
            "autoFarmServerHopping",
            "autoOpenEggs",
            "idleTreadmill",
            "eggEsp",
            "eggRadar",
            "eggEspMinimumRarity",
            "eggEspMinimumSize",
            "hitAura",
            "hitAuraIgnoreFriends",
            "instantPrompts",
            "lagSafeMovement",
            "serverHop",
            "serverHopMaxPing",
            "serverHopTargetPopulation",
            "trapEsp",
        },
        cosmetics = false,
    },
    hydroxide = {},
    id = "stealanegg",
    initialState = {},
    label = "Steal An Egg",
    manifest = {
        gameIds = { 10563114921 },
        placeIds = { 107778070777162 },
    },
    module = "games/stealanegg/Adapter",
    presentation = "games/stealanegg/Presentation",
    sources = {
        "games/stealanegg/Adapter",
        "games/stealanegg/Presentation",
        "games/stealanegg/features/AntiHit",
        "games/stealanegg/features/AntiTrap",
        "games/stealanegg/features/AutoBlossom",
        "games/stealanegg/features/AutoFarm",
        "games/stealanegg/features/AutoOpenEggs",
        "games/stealanegg/features/HighlightEsp",
        "games/stealanegg/features/HitAura",
        "games/stealanegg/features/InstantPrompts",
        "games/stealanegg/features/LagSafeMovement",
        "games/stealanegg/features/ServerHop",
        "games/stealanegg/features/WalkNavigator",
    },
}
]],
    ["games/town/Definition.lua"] = [[return {
    composition = "games/town/Composition",
    defaults = {},
    features = {
        capabilities = {
            "plotCopy",
        },
        cosmetics = false,
    },
    hydroxide = {},
    id = "town",
    initialState = {},
    label = "Town",
    manifest = {
        gameIds = { 1718755273 },
        placeIds = { 4991214437 },
    },
    module = "games/Town",
    presentation = "games/town/Presentation",
    sources = {
        "games/Town",
        "games/town/Canonical",
        "games/town/CheckpointStore",
        "games/town/Composition",
        "games/town/CopyEngine",
        "games/town/CopyPlan",
        "games/town/ExecutionPlan",
        "games/town/Presentation",
    },
}
]],
    ["hub.lua"] = [[local environment = assert(getgenv, "<UH> ~ Your executor is not supported")()
local configuration = environment.UniversalHubConfig or {}
local sourceBaseUrl = assert(
    configuration.SourceBaseUrl,
    "Set UniversalHubConfig.SourceBaseUrl to the raw universal-hub source root"
)
type HttpGame = typeof(game) & {
    HttpGet: (self: typeof(game), url: string, noCache: boolean?) -> string,
}
local httpGame = game :: HttpGame
local fetchSource = type(configuration.Fetch) == "function" and configuration.Fetch
    or function(url)
        return httpGame:HttpGet(url, true)
    end

local bootTiming = configuration.BootTiming or { mode = "remote", startedAt = os.clock() }
configuration.BootTiming = bootTiming
bootTiming.hubStartedAt = os.clock()

local phaseStartedAt = os.clock()
local menuSource = fetchSource(sourceBaseUrl .. "ui/dist/Menu.lua")
bootTiming.menuSeconds = os.clock() - phaseStartedAt
local previousSession = environment.UniversalHubSession
if type(previousSession) == "table" and type(previousSession.stop) == "function" then
    pcall(previousSession.stop, previousSession)
    if environment.UniversalHubSession == previousSession then
        environment.UniversalHubSession = nil
    end
end
phaseStartedAt = os.clock()
local menuChunk, menuError = loadstring(menuSource, "ui/dist/Menu.lua")
bootTiming.menuCompileSeconds = os.clock() - phaseStartedAt
phaseStartedAt = os.clock()
local Menu = assert(menuChunk, menuError)()
bootTiming.menuExecuteSeconds = os.clock() - phaseStartedAt
assert(
    type(Menu) == "table" and type(Menu.mountUniversalHubMenu) == "function",
    "Universal Hub requires the compiled Prism menu"
)

phaseStartedAt = os.clock()
local limnSource = fetchSource(sourceBaseUrl .. "vendor/Limn.lua")
local limnChunk, limnError = loadstring(limnSource, "vendor/Limn.lua")
local Limn = assert(limnChunk, limnError)()
assert(type(Limn) == "table" and type(Limn.new) == "function", "Universal Hub requires Limn")
bootTiming.limnSeconds = os.clock() - phaseStartedAt

local hydroxideCommit = "38778f8a78762d48fba916cade6eb93399e7c404"
local hydroxideSourceBaseUrl = ("https://raw.githubusercontent.com/3xjn/hydroxide/%s/"):format(
    hydroxideCommit
)
phaseStartedAt = os.clock()
local hydroxideSources = {}
for _, path in ipairs({
    "modules/Helpers.lua",
    "modules/Closure.lua",
    "modules/Lifecycle.lua",
    "modules/Targeting.lua",
}) do
    hydroxideSources[path] = fetchSource(hydroxideSourceBaseUrl .. path)
end
bootTiming.hydroxideSeconds = os.clock() - phaseStartedAt
local helpersChunk, helpersError =
    loadstring(hydroxideSources["modules/Helpers.lua"], "hydroxide/modules/Helpers.lua")
local Helpers = assert(helpersChunk, helpersError)()
assert(
    type(Helpers) == "table" and type(Helpers.load) == "function",
    "Universal Hub requires Hydroxide Helpers.load"
)

local sources = {}
local function validModulePath(path)
    return type(path) == "string"
        and path ~= ""
        and path:match("^[%w_/%-]+$") ~= nil
        and not path:find("//", 1, true)
end

local function fetch(path)
    if sources[path] == nil then
        sources[path] = fetchSource(sourceBaseUrl .. path)
    end
    return sources[path]
end

local function execute(path)
    local chunk, compileError = loadstring(fetch(path), path)
    return assert(chunk, compileError)()
end

local Registry = execute("modules/Registry.lua")
local Sources = execute("modules/Sources.lua")
local Compatibility = execute("games/Compatibility.lua")
local catalog = execute("games/Catalog.lua")
assert(type(catalog) == "table", "Universal Hub catalog must be a table")
local registry = Registry.new()
local definitions = {}
local seenDefinitions = {}
for _, definitionPath in ipairs(catalog) do
    assert(validModulePath(definitionPath), "Invalid game definition path")
    assert(
        not seenDefinitions[definitionPath],
        "Duplicate game definition path: " .. definitionPath
    )
    seenDefinitions[definitionPath] = true

    local definition = Compatibility.Compose(execute(definitionPath .. ".lua"))
    Registry.Validate(definition)
    registry:Register(definition)
    table.insert(definitions, definition)
end

local inventory = Sources.new({
    catalog = catalog,
    definitions = definitions,
})
local selectedDefinition = registry:Resolve({
    gameId = game.GameId,
    placeId = game.PlaceId,
})
assert(
    selectedDefinition,
    ("Universal Hub does not support game %s / place %s"):format(
        tostring(game.GameId),
        tostring(game.PlaceId)
    )
)
local allowedImports = inventory:Allow(selectedDefinition.id)
phaseStartedAt = os.clock()
for _, modulePath in ipairs(inventory:All()) do
    if allowedImports[modulePath] then
        fetch(modulePath .. ".lua")
    end
end
bootTiming.inventorySeconds = os.clock() - phaseStartedAt
environment.UniversalHubConfig = configuration
local importCache = {}
local nativeRequire = require
local function resolveImport(path, importer)
    if path:sub(1, 1) ~= "." then
        return path
    end
    local resolved = {}
    for segment in (importer:match("^(.*)/") or ""):gmatch("[^/]+") do
        table.insert(resolved, segment)
    end
    for segment in path:gmatch("[^/]+") do
        if segment == ".." then
            assert(#resolved > 0, "Hub module path escapes source root: " .. path)
            table.remove(resolved)
        elseif segment ~= "." and segment ~= "" then
            table.insert(resolved, segment)
        end
    end
    return table.concat(resolved, "/")
end
local function import(path, importer)
    path = resolveImport(path, importer or "")
    assert(
        type(path) == "string" and path:match("^[%w_/%-]+$") ~= nil and not path:find("//", 1, true),
        "Invalid hub module path"
    )
    assert(
        allowedImports[path],
        "Hub module is outside selected game source scope: " .. tostring(path)
    )
    if importCache[path] ~= nil then
        return importCache[path]
    end
    local file = path .. ".lua"
    local chunk, compileError =
        loadstring(assert(sources[file], "Unknown hub module: " .. path), file)
    assert(chunk, compileError)
    local chunkEnvironment = getfenv(chunk)
    local moduleEnvironment = {
        require = function(target)
            if type(target) == "string" then
                return import(target, path)
            end
            return nativeRequire(target)
        end,
    }
    setmetatable(moduleEnvironment, { __index = chunkEnvironment })
    setfenv(chunk, moduleEnvironment)
    local result = chunk()
    importCache[path] = result
    return result
end
configuration.Import = import
local hydroxideCache = {}
configuration.HydroxideImport = function(path)
    assert(
        path == "modules/Closure" or path == "modules/Lifecycle" or path == "modules/Targeting",
        "Unknown Hydroxide helper module: " .. tostring(path)
    )
    if hydroxideCache[path] ~= nil then
        return hydroxideCache[path]
    end
    local file = path .. ".lua"
    local chunk, compileError = loadstring(
        assert(hydroxideSources[file], "Unknown Hydroxide source: " .. path),
        "hydroxide/" .. file
    )
    local result = assert(chunk, compileError)()
    hydroxideCache[path] = assert(result, "Hydroxide helper module returned nil: " .. path)
    return hydroxideCache[path]
end
configuration.HydroxideHelpers = Helpers
configuration.Limn = Limn
configuration.Menu = Menu
configuration.ChangelogSource = fetchSource(sourceBaseUrl .. "changelog.json")

local initSource = fetchSource(sourceBaseUrl .. "init.lua")
local initChunk, initError = loadstring(initSource, "init.lua")
bootTiming.hubSeconds = os.clock() - bootTiming.hubStartedAt
bootTiming.preInitSeconds = os.clock() - bootTiming.startedAt
return assert(initChunk, initError)()
]],
    ["init.lua"] = [[local environment = assert(getgenv, "<UH> ~ Your executor is not supported")()
local configuration = environment.UniversalHubConfig or {}
local root = configuration.LocalRoot or "universal-hub/local"
local cache = {}

local function import(path)
    if cache[path] ~= nil then
        return cache[path]
    end

    local result
    if configuration.Import then
        result = configuration.Import(path)
    else
        local source = readfile(root .. "/" .. path .. ".lua")
        local chunk, compileError = loadstring(source, path .. ".lua")
        result = assert(chunk, compileError)()
    end
    cache[path] = result
    return result
end

local function copyData(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, child in pairs(value) do
        copy[copyData(key)] = copyData(child)
    end
    return copy
end

local function extend(target, additions)
    for key, value in pairs(additions or {}) do
        assert(target[key] == nil, "Composition must not replace shared context: " .. tostring(key))
        target[key] = value
    end
    return target
end

local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Store = import("modules/Store")
local Config = import("modules/Config")
local Changelog = import("modules/Changelog")
local WhatsNew = import("ui/WhatsNew")
local InputCapture = import("modules/InputCapture")
local MenuToggle = import("modules/MenuToggle")
local Registry = import("modules/Registry")
local Logger = import("modules/Logger")
local Session = import("modules/Session")
local DrawingRenderer = import("ui/esp/DrawingRenderer")
local VisualPolicy = import("ui/esp/VisualPolicy")
local HighlightRenderer = import("ui/esp/HighlightRenderer")
local WorldRenderer = import("ui/esp/WorldRenderer")
local HubMenu = import("ui/Menu")
local HubView = import("modules/HubView")
local PresentationCatalog = import("ui/presentation/Catalog")
local PresentationHost = import("ui/PresentationHost")
local PresentationRuntime = import("ui/presentation/Runtime")
local StandardPanels = import("ui/presentation/StandardPanels")
local CosmeticsPanel = import("ui/presentation/CosmeticsPanel")
local Compatibility = import("games/Compatibility")
local Catalog = import("games/Catalog")

local previousLogger = environment.UniversalHubLogger
if type(previousLogger) == "table" and type(previousLogger.close) == "function" then
    pcall(previousLogger.close, previousLogger, { reason = "reexecution" })
end
local logger = Logger.new({
    appendFile = type(appendfile) == "function" and appendfile or nil,
    archiveName = function()
        return "session-" .. tostring(DateTime.now().UnixTimestampMillis)
    end,
    isFile = type(isfile) == "function" and isfile or nil,
    makeFolder = type(makefolder) == "function" and makefolder or nil,
    readFile = type(readfile) == "function" and readfile or nil,
    writeFile = type(writefile) == "function" and writefile or nil,
})
environment.UniversalHubLogger = logger
logger:info("bootstrap", "initializing", {
    gameId = game.GameId,
    jobId = game.JobId,
    placeId = game.PlaceId,
})
local bootTiming = configuration.BootTiming
if type(bootTiming) == "table" then
    local function seconds(value)
        return type(value) == "number" and ("%.3f"):format(value) or nil
    end
    logger:info("bootstrap", "loader timing", {
        fetchCount = bootTiming.fetchCount,
        fetchSeconds = seconds(bootTiming.fetchSeconds),
        hydroxideSeconds = seconds(bootTiming.hydroxideSeconds),
        inventorySeconds = seconds(bootTiming.inventorySeconds),
        limnSeconds = seconds(bootTiming.limnSeconds),
        menuCompileSeconds = seconds(bootTiming.menuCompileSeconds),
        menuExecuteSeconds = seconds(bootTiming.menuExecuteSeconds),
        menuSeconds = seconds(bootTiming.menuSeconds),
        mode = bootTiming.mode,
        preInitSeconds = seconds(bootTiming.preInitSeconds),
        slowestFetch = bootTiming.slowestFetch,
        slowestFetchSeconds = seconds(bootTiming.slowestFetchSeconds),
    })
end

local registry = Registry.new()
for _, definitionPath in ipairs(Catalog) do
    registry:Register(Compatibility.Compose(import(definitionPath)))
end

local adapterDefinition = registry:Resolve({
    gameId = game.GameId,
    placeId = game.PlaceId,
})
assert(
    adapterDefinition,
    ("Universal Hub does not support game %s / place %s"):format(
        tostring(game.GameId),
        tostring(game.PlaceId)
    )
)
logger:info("bootstrap", "game selected", {
    adapter = adapterDefinition.id,
    label = adapterDefinition.label,
})
local adapterModule = import(adapterDefinition.module)
assert(
    type(adapterModule) == "table" and type(adapterModule.new) == "function",
    "Invalid game adapter module"
)
local presentation = import(adapterDefinition.presentation)
local features = adapterDefinition.features
local compositionModule
local compositionDependencies = {}
if adapterDefinition.composition then
    compositionModule = import(adapterDefinition.composition)
    assert(
        type(compositionModule) == "table" and type(compositionModule.bind) == "function",
        "Invalid game composition module"
    )
    local declaredSources = {}
    for _, path in ipairs(adapterDefinition.sources) do
        declaredSources[path] = true
    end
    local dependencyNames = {}
    for name, path in pairs(compositionModule.dependencies or {}) do
        assert(
            type(name) == "string" and name ~= "",
            "Composition dependency names must be strings"
        )
        assert(
            type(path) == "string" and declaredSources[path],
            "Composition dependency must be declared by the selected definition"
        )
        table.insert(dependencyNames, name)
    end
    table.sort(dependencyNames)
    for _, name in ipairs(dependencyNames) do
        compositionDependencies[name] = import(compositionModule.dependencies[name])
    end
end

local Limn = assert(configuration.Limn, "Universal Hub loader must stage Limn before init")
assert(type(Limn) == "table" and type(Limn.new) == "function", "Universal Hub requires Limn")
local Helpers = assert(
    configuration.HydroxideHelpers,
    "Universal Hub loader must stage Hydroxide Helpers before init"
)
local hydroxideImport = assert(
    configuration.HydroxideImport,
    "Universal Hub loader must stage a Hydroxide importer before init"
)
assert(
    type(Helpers) == "table" and type(Helpers.load) == "function",
    "Universal Hub requires Hydroxide Helpers.load"
)
local helpers = Helpers.load({
    import = hydroxideImport,
    modules = adapterDefinition.hydroxide or {},
})
for _, name in ipairs(adapterDefinition.hydroxide or {}) do
    assert(type(helpers[name]) == "table", "Missing Hydroxide helper module: " .. tostring(name))
end

Session.stopPrevious(environment)
local drawingRuntime = Limn.new({
    Drawing = Drawing,
    DrawingImmediate = DrawingImmediate,
    Vector2 = Vector2,
    Input = {
        MapPosition = function(position)
            local topLeftInset = GuiService:GetGuiInset()
            return position + topLeftInset
        end,
        -- The visible menu intentionally sinks pointer input before Limn receives it.
        Processed = "allow",
    },
})
configuration.Limn = nil
configuration.HydroxideHelpers = nil
configuration.HydroxideImport = nil

local configPath = configuration.ConfigPath
    or ("universal-hub/configs/%s.json"):format(adapterDefinition.id)
local ephemeralSettings = PresentationCatalog.collectEphemeralSettings(presentation)
local configStore = Config.new({
    decode = function(source)
        return HttpService:JSONDecode(source)
    end,
    encode = function(value)
        return HttpService:JSONEncode(value)
    end,
    isFile = type(isfile) == "function" and isfile or nil,
    omittedKeys = ephemeralSettings,
    path = configPath,
    readFile = type(readfile) == "function" and readfile or nil,
    writeFile = type(writefile) == "function" and writefile or nil,
})
local configDefaults = copyData(adapterDefinition.defaults)
local settings = configStore:load(configDefaults)
local hasPersistedConfig = type(isfile) == "function" and isfile(configPath)
if not hasPersistedConfig then
    for name, value in pairs(environment.UniversalHubSettings or {}) do
        if settings[name] ~= nil and not ephemeralSettings[name] then
            settings[name] = value
        end
    end
end
local taskAutomationWasNormalized = configuration.TeleportBootstrap ~= true
    and settings.taskAutomationEnabled == true
if taskAutomationWasNormalized then
    settings.taskAutomationEnabled = false
end

local session
local overlay
local adapter
local store
local pendingAdapterOptions = {}
local function setAdapterOption(name, enabled, persist)
    if session then
        session:setOption(name, enabled, persist)
        return true
    end
    table.insert(pendingAdapterOptions, {
        name = name,
        enabled = enabled,
        persist = persist,
    })
    return false
end
local function noAfterAdapter(_adapter) end
local composition = {
    adapter = {},
    afterAdapter = noAfterAdapter,
    inputCapture = {
        releaseMouseOnDisable = false,
    },
    overlay = {},
}
if compositionModule then
    composition = compositionModule.bind({
        config = function(name, fallback)
            local value = configuration[name]
            return value == nil and fallback or value
        end,
        decode = function(source)
            return HttpService:JSONDecode(source)
        end,
        encode = function(value)
            return HttpService:JSONEncode(value)
        end,
        files = {
            delete = type(delfile) == "function" and delfile or nil,
            isFile = type(isfile) == "function" and isfile or nil,
            list = type(listfiles) == "function" and listfiles or nil,
            makeFolder = type(makefolder) == "function" and makefolder or nil,
            read = type(readfile) == "function" and readfile or nil,
            write = type(writefile) == "function" and writefile or nil,
        },
        getAdapter = function()
            return adapter
        end,
        getStore = function()
            return store
        end,
        spawn = task.spawn,
        userId = LocalPlayer.UserId,
    }, compositionDependencies)
    assert(type(composition) == "table", "Game composition must return a table")
    assert(
        composition.adapter == nil or type(composition.adapter) == "table",
        "Game composition adapter context must be a table"
    )
    assert(
        composition.inputCapture == nil or type(composition.inputCapture) == "table",
        "Game composition input context must be a table"
    )
    assert(
        composition.overlay == nil or type(composition.overlay) == "table",
        "Game composition overlay context must be a table"
    )
    assert(
        composition.afterAdapter == nil or type(composition.afterAdapter) == "function",
        "Game composition afterAdapter must be a function"
    )
    composition.adapter = composition.adapter or {}
    composition.afterAdapter = composition.afterAdapter or noAfterAdapter
    composition.inputCapture = composition.inputCapture or {}
    composition.overlay = composition.overlay or {}
end

local startupCleanups = {}
local function ownStartup(cleanup)
    table.insert(startupCleanups, cleanup)
end
local function failStartup(message)
    logger:error("bootstrap", "startup failed", { error = message })
    for index = #startupCleanups, 1, -1 do
        pcall(startupCleanups[index])
    end
    table.clear(startupCleanups)
    logger:close({ reason = "startup-failed" })
    if environment.UniversalHubLogger == logger then
        environment.UniversalHubLogger = nil
    end
    error(message, 0)
end

local initialState = copyData(adapterDefinition.initialState)
initialState.settings = settings
initialState.status = ("Loading %s"):format(adapterDefinition.label)
if settings.taskAutomationEnabled == true then
    initialState.menuVisible = false
end
store = Store.new(initialState)
ownStartup(function()
    store:Destroy()
end)
environment.UniversalHubSettings = store:Get().settings
local footerSubscriptions = {}
local footerElapsed = 1
local footerConnection = RunService.Heartbeat:Connect(function(deltaTime)
    footerElapsed += deltaTime
    if footerElapsed < 1 then
        return
    end
    footerElapsed = 0
    local metrics = {}
    for id, subscription in pairs(footerSubscriptions) do
        local ok, value = pcall(subscription.read)
        if ok then
            table.insert(metrics, {
                id = id,
                kind = subscription.kind,
                label = subscription.label,
                value = value,
            })
        end
    end
    store:Patch({ footerMetrics = metrics })
end)
local function subscribeFooterMetric(id, spec, read)
    footerSubscriptions[id] = { kind = spec.kind, label = spec.label, read = read }
    return function()
        footerSubscriptions[id] = nil
    end
end
ownStartup(function()
    footerConnection:Disconnect()
end)

local inputCaptureCreated, inputCaptureResult = pcall(InputCapture.new, {
    releaseMouseOnDisable = composition.inputCapture.releaseMouseOnDisable == true,
})
if not inputCaptureCreated then
    failStartup(inputCaptureResult)
end
local inputCapture = inputCaptureResult
ownStartup(function()
    inputCapture:Destroy()
end)
local thirdPersonState

local function setInputCaptured(captured)
    inputCapture:SetEnabled(captured)
end

local function setThirdPerson(enabled)
    if enabled then
        if not thirdPersonState then
            thirdPersonState = {
                cameraMode = LocalPlayer.CameraMode,
                maximumZoom = LocalPlayer.CameraMaxZoomDistance,
                minimumZoom = LocalPlayer.CameraMinZoomDistance,
            }
        end
        LocalPlayer.CameraMode = Enum.CameraMode.Classic
        LocalPlayer.CameraMaxZoomDistance = 12
        LocalPlayer.CameraMinZoomDistance = 8
    elseif thirdPersonState then
        LocalPlayer.CameraMode = thirdPersonState.cameraMode
        LocalPlayer.CameraMaxZoomDistance = thirdPersonState.maximumZoom
        LocalPlayer.CameraMinZoomDistance = thirdPersonState.minimumZoom
        thirdPersonState = nil
    end
end

local adapterCapabilityContext = {
    fireTouchInterestAvailable = type(environment.firetouchinterest) == "function",
    getConnectionsAvailable = type(getconnections) == "function",
    getNamecallMethodAvailable = type(getnamecallmethod) == "function",
    hookFunctionAvailable = type(hookfunction) == "function",
    hookMetaMethodAvailable = type(hookmetamethod) == "function",
    restoreFunctionAvailable = type(restorefunction) == "function",
    gameId = game.GameId,
    placeId = game.PlaceId,
}
if type(adapterModule.capabilityContext) == "function" then
    local succeeded, nativeContext = pcall(adapterModule.capabilityContext)
    if succeeded and type(nativeContext) == "table" then
        extend(adapterCapabilityContext, nativeContext)
    end
end
local adapterCapabilities = type(adapterModule.capabilitiesFor) == "function"
        and adapterModule.capabilitiesFor(adapterCapabilityContext, features.capabilities)
    or features.capabilities
adapterCapabilities = copyData(adapterCapabilities)
local function customAsset(path)
    if type(getcustomasset) ~= "function" or type(isfile) ~= "function" or not isfile(path) then
        return nil
    end
    local succeeded, asset = pcall(getcustomasset, path)
    return succeeded and asset or nil
end
local brandIcon = customAsset(root .. "/assets/brand/universal-hub.png")
local gameIcon = ("rbxthumb://type=GameIcon&id=%d&w=150&h=150"):format(game.GameId)
local enemyAudienceIcon = customAsset(root .. "/assets/icons/enemies.png")
local allyAudienceIcon = customAsset(root .. "/assets/icons/allies.png")
local alphaCheckerboard = customAsset(root .. "/assets/ui/alpha-checkerboard.png")
local pageIcons = {}
for page, file in pairs({
    Combat = "combat.png",
    Rage = "rage.png",
    Movement = "movement.png",
    Visuals = "visuals.png",
    Tools = "tools.png",
    Settings = "settings.png",
}) do
    pageIcons[page] = customAsset(root .. "/assets/icons/" .. file)
end

local uiParent = (function()
    local success, parent = pcall(function()
        if type(gethui) == "function" then
            return gethui()
        end
        return game:GetService("CoreGui")
    end)
    return success and parent or nil
end)()

local overlayContext = {
    capabilities = adapterCapabilities,
    highlightsSupported = table.find(adapterCapabilities, "worldRenderer") ~= nil,
    visualPolicy = VisualPolicy,
    catalog = PresentationCatalog,
    cosmetics = features.cosmetics,
    prismMenu = assert(
        configuration.Menu,
        "Universal Hub loader must stage the compiled Prism menu"
    ),
    worldOnly = true,
    gameLabel = adapterDefinition.label,
    getCamera = function()
        return Workspace.CurrentCamera
    end,
    uiParent = uiParent,
    guiParent = uiParent,
    players = Players,
    localPlayer = LocalPlayer,
    runService = RunService,
    brandIcon = brandIcon,
    gameIcon = gameIcon,
    enemyAudienceIcon = enemyAudienceIcon,
    allyAudienceIcon = allyAudienceIcon,
    alphaCheckerboard = alphaCheckerboard,
    optionLabels = features.optionLabels,
    pageIcons = pageIcons,
    presentation = presentation,
    presentationHost = PresentationHost,
    presentationParts = {
        cosmetics = CosmeticsPanel,
        standard = StandardPanels,
    },
    presentationRuntime = PresentationRuntime,
    inputService = UserInputService,
    limn = drawingRuntime,
    setFov = function(value, persist)
        local current = session
        if not current then
            return
        end
        local settings = current.store:Get().settings
        local name = settings.shotAim == true and "shotFov" or "cameraFov"
        local clamped = math.clamp(value, settings.minimumFov, settings.maximumFov)
        current:patchSettings({ fov = clamped, [name] = clamped }, persist)
    end,
    setCosmeticsOpen = function(open)
        local current = session
        if not current then
            return
        end
        current:setCosmeticsOpen(open)
    end,
    setCosmeticMode = function(mode)
        local current = session
        if not current then
            return
        end
        current:setCosmeticMode(mode)
    end,
    setInputCaptured = setInputCaptured,
    menuEnabled = false,
    setMenuKey = function(value)
        local current = session
        if not current then
            return
        end
        current:setMenuKey(value)
    end,
    setMenuVisible = function(visible)
        local current = session
        if not current then
            return
        end
        current:setMenuVisible(visible)
    end,
    setSetting = function(name, value, persist)
        local current = session
        if not current then
            return
        end
        current:setSetting(name, value, persist)
    end,
    setOption = function(name, enabled, persist)
        local current = session
        if not current then
            return
        end
        current:setOption(name, enabled, persist)
        if enabled and features.exclusiveOptions then
            for _, excluded in ipairs(features.exclusiveOptions[name] or {}) do
                current:setOption(excluded, false, persist)
            end
        end
    end,
    setRate = function(name, value, persist)
        local current = session
        if not current then
            return
        end
        current:setRate(name, value, persist)
    end,
    store = store,
}
extend(overlayContext, composition.overlay)
local worldCreated, worldResult = pcall(function()
    local drawingWorld = DrawingRenderer.new(overlayContext)
    local highlightsCreated, highlightWorld = pcall(HighlightRenderer.new, overlayContext)
    if not highlightsCreated then
        drawingWorld:destroy()
        error(highlightWorld, 0)
    end
    return WorldRenderer.new(overlayContext, drawingWorld, highlightWorld)
end)
if not worldCreated then
    failStartup(worldResult)
end
local worldOverlay = worldResult
overlayContext.optionSupport = worldOverlay.optionSupport
local menuCreated, menuResult = pcall(HubMenu.new, overlayContext)
if not menuCreated then
    worldOverlay:destroy()
    failStartup(menuResult)
end
overlay = HubView.new(worldOverlay, menuResult)
ownStartup(function()
    overlay:destroy()
end)

local adapterContext = {
    aimClick = mouse2click,
    aimPress = mouse2press,
    aimRelease = mouse2release,
    click = mouse1click,
    contextActionService = ContextActionService,
    fireTouchInterest = type(environment.firetouchinterest) == "function"
            and environment.firetouchinterest
        or nil,
    press = mouse1press,
    release = mouse1release,
    gcObjects = function()
        return getgc(true)
    end,
    getConnections = getconnections,
    getNamecallMethod = getnamecallmethod,
    hookFunction = hookfunction,
    hookMetaMethod = hookmetamethod,
    isInputCaptured = function()
        return inputCapture:IsEnabled()
    end,
    isFireHeld = function()
        return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    end,
    isJumpHeld = function()
        return UserInputService:IsKeyDown(Enum.KeyCode.Space)
    end,
    keyPress = type(keypress) == "function" and keypress or nil,
    keyRelease = type(keyrelease) == "function" and keyrelease or nil,
    fireSignal = type(firesignal) == "function" and firesignal or nil,
    movementDirection = function()
        local horizontal = (UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0)
            - (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
        local forward = (UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0)
            - (UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0)
        if horizontal == 0 and forward == 0 then
            return Vector3.new(0, 0, 0)
        end

        local camera = Workspace.CurrentCamera
        if not camera then
            return Vector3.new(0, 0, 0)
        end
        local look = camera.CFrame.LookVector
        local right = camera.CFrame.RightVector
        local direction = Vector3.new(right.X, 0, right.Z) * horizontal
            + Vector3.new(look.X, 0, look.Z) * forward
        return direction.Magnitude > 1 and direction.Unit or direction
    end,
    limn = drawingRuntime,
    logger = logger,
    capabilities = adapterCapabilities,
    oh = helpers,
    render = function(observations, mousePosition, utilityObservations)
        overlay:render(observations, mousePosition, utilityObservations)
    end,
    restoreFunction = restorefunction,
    settingsChanged = function(updatedSettings)
        configStore:save(updatedSettings)
    end,
    subscribeFooterMetric = subscribeFooterMetric,
    setThirdPerson = setThirdPerson,
    gameId = game.GameId,
    generateGuid = function()
        return HttpService:GenerateGUID(false)
    end,
    localPlayer = LocalPlayer,
    jobId = game.JobId,
    newCClosure = newcclosure,
    now = os.time,
    placeId = game.PlaceId,
    players = Players,
    store = store,
    setOption = setAdapterOption,
    teleportBootstrap = configuration.TeleportBootstrap == true,
    wait = task.wait,
    workspace = Workspace,
}
extend(adapterContext, composition.adapter)
local created, result = pcall(adapterModule.new, adapterContext)
if not created then
    failStartup(result)
end
adapter = result
if type(worldOverlay.setPolicy) == "function" then
    worldOverlay:setPolicy(adapter.worldPolicy or {
        isPlayerEligible = adapter.isOpponent,
    })
end
ownStartup(function()
    if type(adapter.stop) == "function" then
        adapter:stop()
    end
end)
if composition.afterAdapter then
    composition.afterAdapter(adapter)
end

local sessionCreated, sessionResult = pcall(Session.new, {
    adapter = adapter,
    environment = environment,
    inputCapture = inputCapture,
    logger = logger,
    overlay = overlay,
    settingsChanged = function(updatedSettings)
        configStore:save(updatedSettings)
    end,
    store = store,
})
if not sessionCreated then
    failStartup(sessionResult)
end
session = sessionResult
for _, request in ipairs(pendingAdapterOptions) do
    session:setOption(request.name, request.enabled, request.persist)
end
table.clear(pendingAdapterOptions)
if taskAutomationWasNormalized then
    session:setOption("taskAutomationEnabled", false, true)
end
overlay.menu:setEnabled(true)
table.clear(startupCleanups)
local finalized, finalError = pcall(function()
    session.adapterId = adapterDefinition.id
    session.game = adapterDefinition.label
    session.registry = registry
    session.state = store:Get()
    session.store = store
    local menuToggleConnection = UserInputService.InputBegan:Connect(
        function(input, gameProcessedEvent)
            local bindingSettled = os.clock() - (session.menuKeyChangedAt or -math.huge) > 0.2
            if
                bindingSettled
                and MenuToggle.shouldToggle(
                    input,
                    gameProcessedEvent,
                    UserInputService,
                    store:Get().settings.menuKey
                )
            then
                session:toggleMenu()
            end
        end
    )
    session:Add(function()
        menuToggleConnection:Disconnect()
    end)

    local readyStatus = ("%s ready"):format(adapterDefinition.label)
    store:Patch({ status = readyStatus })
    if type(bootTiming) == "table" and type(bootTiming.startedAt) == "number" then
        bootTiming.totalSeconds = os.clock() - bootTiming.startedAt
    end
    logger:info("bootstrap", "ready", {
        adapter = adapterDefinition.id,
        totalSeconds = type(bootTiming) == "table" and bootTiming.totalSeconds or nil,
    })
    print("[Universal Hub]", readyStatus)

    local lastUsedStore = Config.new({
        decode = function(source)
            return HttpService:JSONDecode(source)
        end,
        encode = function(value)
            return HttpService:JSONEncode(value)
        end,
        isFile = type(isfile) == "function" and isfile or nil,
        path = configuration.LastUsedVersionPath or WhatsNew.DEFAULT_PATH,
        readFile = type(readfile) == "function" and readfile or nil,
        writeFile = type(writefile) == "function" and writefile or nil,
    })
    local remoteUrls = {}
    if type(configuration.SourceBaseUrl) == "string" and configuration.SourceBaseUrl ~= "" then
        table.insert(remoteUrls, configuration.SourceBaseUrl .. "changelog.json")
    end
    table.insert(remoteUrls, WhatsNew.PAGES_CHANGELOG_URL)
    local changelogCatalog = Changelog.load({
        decode = function(source)
            return HttpService:JSONDecode(source)
        end,
        source = configuration.ChangelogSource,
        localPath = root .. "/changelog.json",
        isFile = type(isfile) == "function" and isfile or nil,
        readFile = type(readfile) == "function" and readfile or nil,
        remoteUrls = remoteUrls,
        httpGet = type(game.HttpGet) == "function" and function(url)
            return game:HttpGet(url, true)
        end or nil,
    })
    local notice = WhatsNew.evaluate({
        catalog = changelogCatalog,
        lastUsed = lastUsedStore:load(WhatsNew.defaults()),
    })
    local function hideNotice()
        store:Patch({
            whatsNew = {
                visible = false,
            },
        })
    end
    overlayContext.whatsNewDismiss = hideNotice
    overlayContext.whatsNewDontShowAgain = function()
        if notice.current then
            lastUsedStore:save(WhatsNew.acknowledge(notice.current, true))
        end
        hideNotice()
    end
    overlayContext.whatsNewAcknowledge = function()
        if notice.current then
            lastUsedStore:save(WhatsNew.acknowledge(notice.current))
        end
        hideNotice()
    end
    overlayContext.whatsNewViewAll = function()
        store:Patch({
            whatsNew = {
                showingAll = true,
            },
        })
    end
    local function replaceWhatsNew(snapshot)
        store:Patch({
            whatsNew = false,
        })
        store:Patch({
            whatsNew = snapshot,
        })
    end
    replaceWhatsNew(WhatsNew.snapshot(notice))
    session:Add(hideNotice)

    local function fingerprint(path)
        if type(readfile) ~= "function" then
            return ""
        end
        local ok, source = pcall(readfile, path)
        if not ok or type(source) ~= "string" then
            return ""
        end
        return tostring(#source)
            .. ":"
            .. string.sub(source, 1, 48)
            .. ":"
            .. string.sub(source, -48)
    end

    local function forget(path)
        cache[path] = nil
        if type(configuration.Forget) == "function" then
            configuration.Forget(path)
        end
    end

    local function reloadChangelog()
        changelogCatalog = Changelog.load({
            decode = function(source)
                return HttpService:JSONDecode(source)
            end,
            source = configuration.HotReload == true and nil or configuration.ChangelogSource,
            localPath = root .. "/changelog.json",
            isFile = type(isfile) == "function" and isfile or nil,
            readFile = type(readfile) == "function" and readfile or nil,
            remoteUrls = remoteUrls,
            httpGet = type(game.HttpGet) == "function" and function(url)
                return game:HttpGet(url, true)
            end or nil,
        })
        notice = WhatsNew.evaluate({
            catalog = changelogCatalog,
            lastUsed = lastUsedStore:load(WhatsNew.defaults()),
        })
        replaceWhatsNew(WhatsNew.snapshot(notice))
    end

    local function restageCompiledMenu()
        if type(configuration.ReloadMenu) ~= "function" then
            return true
        end
        local ok, nextMenu = pcall(configuration.ReloadMenu)
        if not ok then
            warn("[Universal Hub] Compiled menu reload failed:", nextMenu)
            return false
        end
        if type(nextMenu) ~= "table" or type(nextMenu.mountUniversalHubMenu) ~= "function" then
            warn("[Universal Hub] Compiled menu reload returned an invalid artifact")
            return false
        end
        configuration.Menu = nextMenu
        overlayContext.prismMenu = nextMenu
        return true
    end

    local function reloadUi(options)
        local restageMenu = options == nil
            or (type(options) == "table" and options.restageMenu == true)
        if restageMenu then
            restageCompiledMenu()
        end
        forget("modules/Changelog")
        forget("ui/Menu")
        forget("ui/WhatsNew")
        forget("ui/presentation/Catalog")
        Changelog = import("modules/Changelog")
        WhatsNew = import("ui/WhatsNew")
        PresentationCatalog = import("ui/presentation/Catalog")
        HubMenu = import("ui/Menu")
        overlayContext.catalog = PresentationCatalog
        local remounted, nextMenu = pcall(HubMenu.new, overlayContext)
        if not remounted then
            warn("[Universal Hub] UI reload failed:", nextMenu)
            return false
        end
        overlay:setMenu(nextMenu)
        nextMenu:setEnabled(true)
        reloadChangelog()
        print("[Universal Hub] UI reloaded")
        return true
    end

    session.reloadUi = reloadUi
    if configuration.HotReload == true and type(readfile) == "function" then
        local watched = {
            root .. "/ui/Menu.lua",
            root .. "/ui/WhatsNew.lua",
            root .. "/ui/presentation/Catalog.lua",
            root .. "/changelog.json",
        }
        local menuStampPath = configuration.MenuStampPath
        if type(menuStampPath) == "string" and menuStampPath ~= "" then
            table.insert(watched, menuStampPath)
        end
        local last = {}
        for _, path in ipairs(watched) do
            last[path] = fingerprint(path)
        end
        local elapsed = 0
        local connection = RunService.Heartbeat:Connect(function(dt)
            elapsed += dt
            if elapsed < 0.4 then
                return
            end
            elapsed = 0
            local dirty = false
            local restageMenu = false
            for _, path in ipairs(watched) do
                local nextHash = fingerprint(path)
                if nextHash ~= last[path] then
                    last[path] = nextHash
                    dirty = true
                    if path == menuStampPath then
                        restageMenu = true
                    end
                end
            end
            if dirty then
                pcall(reloadUi, { restageMenu = restageMenu })
            end
        end)
        session:Add(function()
            connection:Disconnect()
        end)
    end
end)
if not finalized then
    session:stop()
    error(finalError, 0)
end
return session
]],
    ["modules/Changelog.lua"] = [[local Changelog = {}

local SECTION_ORDER = { "added", "changed", "fixed", "removed", "security" }
local SECTION_LABEL = {
    added = "Added",
    changed = "Changed",
    fixed = "Fixed",
    removed = "Removed",
    security = "Security",
}

local function copyList(source)
    local copy = {}
    for index, value in ipairs(source or {}) do
        copy[index] = value
    end
    return copy
end

local function isSemver(text)
    return type(text) == "string" and text:match("^%d+%.%d+%.%d+$") ~= nil
end

function Changelog.parseVersion(text)
    if text == nil or text == "" then
        return { 0, 0, 0 }
    end
    if not isSemver(text) then
        return nil
    end
    local major, minor, patch = text:match("^(%d+)%.(%d+)%.(%d+)$")
    return {
        tonumber(major),
        tonumber(minor),
        tonumber(patch),
    }
end

function Changelog.compare(left, right)
    local a = Changelog.parseVersion(left)
    local b = Changelog.parseVersion(right)
    if not a or not b then
        return nil
    end
    for index = 1, 3 do
        if a[index] < b[index] then
            return -1
        end
        if a[index] > b[index] then
            return 1
        end
    end
    return 0
end

function Changelog.isNewer(candidate, baseline)
    return Changelog.compare(candidate, baseline) == 1
end

function Changelog.sectionLabel(name)
    return SECTION_LABEL[name]
end

function Changelog.sectionOrder()
    return copyList(SECTION_ORDER)
end

function Changelog.channel(release)
    if type(release) == "table" and release.channel == "released" then
        return "released"
    end
    return "beta"
end

function Changelog.displayVersion(release)
    local version = type(release) == "table" and release.version or nil
    if type(version) ~= "string" or version == "" then
        return ""
    end
    if Changelog.channel(release) == "beta" then
        return version .. "-beta"
    end
    return version
end

function Changelog.entryText(entry)
    if type(entry) == "string" then
        return entry
    end
    if type(entry) ~= "table" then
        return ""
    end
    if type(entry.text) == "string" and entry.text ~= "" then
        return entry.text
    end
    local name = type(entry.name) == "string" and entry.name or ""
    local note = type(entry.note) == "string" and entry.note or ""
    local tab = type(entry.tab) == "string" and entry.tab or ""
    if name ~= "" and note ~= "" then
        return name .. " - " .. note
    end
    return name
end

local function entryList(value, field)
    if value == nil then
        return {}
    end
    assert(type(value) == "table", "Changelog " .. field .. " must be a list")
    local items = {}
    for _, item in ipairs(value) do
        if type(item) == "string" then
            assert(item ~= "", "Changelog " .. field .. " entries must be strings")
            table.insert(items, {
                tab = "",
                name = item,
                note = "",
                text = item,
            })
        else
            assert(type(item) == "table", "Changelog " .. field .. " entries must be strings or feature notes")
            local name = item.name or item.feature
            assert(type(name) == "string" and name ~= "", "Changelog " .. field .. " feature names must be strings")
            local tab = type(item.tab) == "string" and item.tab or ""
            local note = type(item.note) == "string" and item.note or ""
            local entry = {
                tab = tab,
                name = name,
                note = note,
            }
            entry.text = Changelog.entryText(entry)
            table.insert(items, entry)
        end
    end
    return items
end

function Changelog.validate(catalog)
    assert(type(catalog) == "table", "Changelog catalog must be a table")
    assert(isSemver(catalog.current), "Changelog current version must be semver")
    assert(type(catalog.releases) == "table", "Changelog releases must be a list")
    assert(#catalog.releases > 0, "Changelog requires at least one release")

    local seen = {}
    local releases = {}
    for _, release in ipairs(catalog.releases) do
        assert(type(release) == "table", "Changelog release must be a table")
        assert(isSemver(release.version), "Changelog release version must be semver")
        assert(not seen[release.version], "Changelog contains a duplicate version: " .. release.version)
        assert(
            type(release.date) == "string" and release.date:match("^%d%d%d%d%-%d%d%-%d%d$"),
            "Changelog release date must be YYYY-MM-DD"
        )
        assert(type(release.title) == "string" and release.title ~= "", "Changelog release title is required")
        local channel = release.channel
        if channel == nil or channel == "" then
            channel = "beta"
        end
        assert(channel == "beta" or channel == "released", "Changelog channel must be beta or released")
        seen[release.version] = true
        local normalized = {
            version = release.version,
            date = release.date,
            title = release.title,
            channel = channel,
        }
        for _, section in ipairs(SECTION_ORDER) do
            normalized[section] = entryList(release[section], section)
        end
        table.insert(releases, normalized)
    end

    table.sort(releases, function(left, right)
        return Changelog.isNewer(left.version, right.version)
    end)
    assert(releases[1].version == catalog.current, "Changelog current version must match the newest release")

    return {
        current = catalog.current,
        releases = releases,
    }
end

function Changelog.decode(source, decode)
    assert(type(source) == "string" and source ~= "", "Changelog source must be JSON text")
    assert(type(decode) == "function", "Changelog.decode requires a JSON decoder")
    return Changelog.validate(decode(source))
end

function Changelog.entriesSince(catalog, lastUsedVersion)
    local validated = Changelog.validate(catalog)
    local baseline = lastUsedVersion
    if baseline == nil or baseline == "" then
        baseline = "0.0.0"
    end
    local entries = {}
    for _, release in ipairs(validated.releases) do
        if Changelog.isNewer(release.version, baseline) then
            table.insert(entries, release)
        end
    end
    return entries
end

function Changelog.notice(catalog, lastUsedVersion)
    local validated = Changelog.validate(catalog)
    local previous = lastUsedVersion
    if previous == nil or previous == "" then
        previous = "0.0.0"
    end
    local entries = Changelog.entriesSince(validated, previous)
    return {
        shouldShow = Changelog.isNewer(validated.current, previous) and #entries > 0,
        current = validated.current,
        previous = (type(lastUsedVersion) == "string" and lastUsedVersion ~= "") and lastUsedVersion or nil,
        lastUsed = lastUsedVersion or "",
        entries = entries,
        catalog = validated,
    }
end

function Changelog.load(options)
    options = options or {}
    local decode = options.decode
    assert(type(decode) == "function", "Changelog.load requires decode")

    if type(options.catalog) == "table" then
        return Changelog.validate(options.catalog)
    end
    if type(options.source) == "table" then
        return Changelog.validate(options.source)
    end
    if type(options.source) == "string" and options.source ~= "" then
        return Changelog.decode(options.source, decode)
    end

    local paths = {}
    if type(options.localPath) == "string" and options.localPath ~= "" then
        table.insert(paths, options.localPath)
    end
    for _, path in ipairs(options.localPaths or {}) do
        table.insert(paths, path)
    end
    if type(options.isFile) == "function" and type(options.readFile) == "function" then
        for _, path in ipairs(paths) do
            if type(path) == "string" and options.isFile(path) then
                local succeeded, catalog = pcall(function()
                    return Changelog.decode(options.readFile(path), decode)
                end)
                if succeeded then
                    return catalog
                end
            end
        end
    end

    if type(options.httpGet) == "function" then
        for _, url in ipairs(options.remoteUrls or {}) do
            if type(url) == "string" and url ~= "" then
                local succeeded, catalog = pcall(function()
                    return Changelog.decode(options.httpGet(url), decode)
                end)
                if succeeded then
                    return catalog
                end
            end
        end
    end

    return nil
end

function Changelog.releaseNotes(catalog, version)
    local validated = Changelog.validate(catalog)
    for _, release in ipairs(validated.releases) do
        if release.version == version then
            local lines = {
                "## " .. release.title,
                "",
            }
            for _, section in ipairs(SECTION_ORDER) do
                local items = release[section]
                if #items > 0 then
                    table.insert(lines, "### " .. SECTION_LABEL[section])
                    table.insert(lines, "")
                    local lastTab = nil
                    for _, item in ipairs(items) do
                        local tab = type(item) == "table" and item.tab or ""
                        if tab ~= "" and tab ~= lastTab then
                            table.insert(lines, "#### " .. tab)
                            table.insert(lines, "")
                            lastTab = tab
                        end
                        table.insert(lines, "- " .. Changelog.entryText(item))
                        table.insert(lines, "")
                    end
                    table.insert(lines, "")
                end
            end
            return table.concat(lines, "\n")
        end
    end
    return nil
end

function Changelog.markdown(catalog)
    local validated = Changelog.validate(catalog)
    local lines = {
        "# Changelog",
        "",
        "All notable changes to Universal Hub are documented in this file.",
        "",
        "The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),",
        "and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).",
        "",
        "## [Unreleased]",
        "",
    }
    for _, release in ipairs(validated.releases) do
        table.insert(lines, ("## [%s] - %s"):format(Changelog.displayVersion(release), release.date))
        table.insert(lines, "")
        for _, section in ipairs(SECTION_ORDER) do
            local items = release[section]
            if #items > 0 then
                table.insert(lines, "### " .. SECTION_LABEL[section])
                table.insert(lines, "")
                local lastTab = nil
                for _, item in ipairs(items) do
                    local tab = type(item) == "table" and item.tab or ""
                    if tab ~= "" and tab ~= lastTab then
                        table.insert(lines, "#### " .. tab)
                        table.insert(lines, "")
                        lastTab = tab
                    end
                    table.insert(lines, "- " .. Changelog.entryText(item))
                    table.insert(lines, "")
                end
            end
        end
    end
    local newest = validated.releases[1].version
    table.insert(lines, ("[Unreleased]: https://github.com/3xjn/universal-hub/compare/v%s...HEAD"):format(newest))
    for _, release in ipairs(validated.releases) do
        local displayed = Changelog.displayVersion(release)
        table.insert(
            lines,
            ("[%s]: https://github.com/3xjn/universal-hub/releases/tag/v%s"):format(displayed, release.version)
        )
    end
    table.insert(lines, "")
    return table.concat(lines, "\n")
end

return Changelog
]],
    ["modules/Config.lua"] = [[local Config = {}
Config.__index = Config

local function copy(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}
    for key, child in pairs(value) do
        result[key] = copy(child)
    end
    return result
end

local function mergeKnown(target, source)
    if type(source) ~= "table" then
        return target
    end

    for key, existing in pairs(target) do
        local value = source[key]
        if value ~= nil then
            if type(existing) == "table" and type(value) == "table" then
                if next(existing) == nil then
                    target[key] = copy(value)
                else
                    mergeKnown(existing, value)
                end
            elseif existing == false and type(value) == "table" then
                target[key] = copy(value)
            elseif type(existing) == type(value) then
                target[key] = value
            end
        end
    end
    return target
end

local function omitKeys(settings, omittedKeys)
    if type(settings) ~= "table" then
        return settings
    end
    local result = copy(settings)
    for key in pairs(omittedKeys or {}) do
        result[key] = nil
    end
    return result
end

local function prettifyJson(source)
    if type(source) ~= "string" or not source:match("^%s*[%[{]") then
        return source
    end

    local result = {}
    local depth = 0
    local inString = false
    local escaped = false

    for index = 1, #source do
        local character = source:sub(index, index)
        if inString then
            table.insert(result, character)
            if escaped then
                escaped = false
            elseif character == "\\" then
                escaped = true
            elseif character == '"' then
                inString = false
            end
        elseif character == '"' then
            inString = true
            table.insert(result, character)
        elseif character == "{" or character == "[" then
            depth += 1
            table.insert(result, character .. "\n" .. string.rep("    ", depth))
        elseif character == "}" or character == "]" then
            depth -= 1
            table.insert(result, "\n" .. string.rep("    ", depth) .. character)
        elseif character == "," then
            table.insert(result, ",\n" .. string.rep("    ", depth))
        elseif character == ":" then
            table.insert(result, ": ")
        elseif not character:match("%s") then
            table.insert(result, character)
        end
    end

    return table.concat(result)
end

function Config.new(options)
    assert(options and options.path, "Config requires a workspace path")
    return setmetatable({
        decode = options.decode,
        encode = options.encode,
        isFile = options.isFile,
        omittedKeys = options.omittedKeys or {},
        path = options.path,
        readFile = options.readFile,
        writeFile = options.writeFile,
    }, Config)
end

function Config:load(defaults)
    local result = copy(defaults)
    if
        type(self.isFile) ~= "function"
        or type(self.readFile) ~= "function"
        or type(self.decode) ~= "function"
        or not self.isFile(self.path)
    then
        return result
    end

    local success, decoded = pcall(self.decode, self.readFile(self.path))
    if success then
        if type(decoded) == "table" then
            if
                decoded.taskAutomationEnabled == nil
                and type(decoded.taskAutomationPaused) == "boolean"
            then
                decoded.taskAutomationEnabled = not decoded.taskAutomationPaused
            end
            decoded.taskAutomationPaused = nil
            if decoded.cameraFov == nil then
                decoded.cameraFov = decoded.fov
            end
            if decoded.shotFov == nil then
                decoded.shotFov = decoded.fov
            end
            if decoded.cameraFullScreenAim == nil then
                decoded.cameraFullScreenAim = decoded.fullScreenAim
            end
            if decoded.shotFullScreenAim == nil then
                decoded.shotFullScreenAim = decoded.fullScreenAim
            end
            if decoded.cameraTargetMode == nil then
                decoded.cameraTargetMode = decoded.cameraFullScreenAim == true and "fullscreen"
                    or "radius"
            end
            if decoded.shotTargetMode == nil then
                decoded.shotTargetMode = decoded.shotFullScreenAim == true and "fullscreen"
                    or "radius"
            end
        end
        mergeKnown(result, omitKeys(decoded, self.omittedKeys))
    end
    return result
end

function Config:save(settings)
    if type(self.writeFile) ~= "function" or type(self.encode) ~= "function" then
        return false
    end

    local encoded = self.encode(omitKeys(settings, self.omittedKeys))
    local success = pcall(self.writeFile, self.path, prettifyJson(encoded))
    return success
end

return Config
]],
    ["modules/HubView.lua"] = [[local HubView = {}
HubView.__index = HubView

function HubView.new(world, menu)
    assert(type(world) == "table" and type(world.render) == "function")
    assert(type(menu) == "table" and type(menu.destroy) == "function")
    return setmetatable({ world = world, menu = menu, destroyed = false }, HubView)
end

local function appended(values, additions)
    if not additions or #additions == 0 then
        return values
    end
    local result = {}
    for _, value in ipairs(values or {}) do
        table.insert(result, value)
    end
    for _, value in ipairs(additions) do
        table.insert(result, value)
    end
    return result
end

function HubView:render(observations, mousePosition, utilityObservations)
    if self.destroyed then
        return
    end
    local previewPlayers, previewUtilities = self.menu:previewObservations()
    self.world:render(
        appended(observations, previewPlayers),
        mousePosition,
        appended(utilityObservations, previewUtilities)
    )
end

function HubView:isCaptured()
    return not self.destroyed and self.menu:isCaptured()
end

function HubView:setMenu(menu)
    assert(type(menu) == "table" and type(menu.destroy) == "function")
    if self.destroyed then
        menu:destroy()
        return
    end
    if self.menu and self.menu ~= menu then
        self.menu:destroy()
    end
    self.menu = menu
end

function HubView:destroy()
    if self.destroyed then
        return
    end
    self.destroyed = true
    pcall(self.menu.destroy, self.menu)
    self.world:destroy()
end

return HubView
]],
    ["modules/InputCapture.lua"] = [[local InputCapture = {}
InputCapture.__index = InputCapture

function InputCapture.new(services)
    services = services or {}
    local localPlayer = services.localPlayer
    if not localPlayer then
        local players = services.players or game:GetService("Players")
        localPlayer = players.LocalPlayer
    end
    return setmetatable({
        enabled = false,
        guiService = services.guiService or game:GetService("GuiService"),
        localPlayer = localPlayer,
        releaseMouseOnDisable = services.releaseMouseOnDisable == true,
        runService = services.runService or game:GetService("RunService"),
        userInputService = services.userInputService or game:GetService("UserInputService"),
    }, InputCapture)
end

function InputCapture:_enforceCursor()
    self.localPlayer.CameraMode = Enum.CameraMode.Classic
    self.userInputService.MouseBehavior = Enum.MouseBehavior.Default
    self.userInputService.MouseIconEnabled = true
    self.userInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.ForceShow
end

function InputCapture:_guardProperty(instance, propertyName)
    return instance:GetPropertyChangedSignal(propertyName):Connect(function()
        if self.enabled then
            self:_enforceCursor()
        end
    end)
end

function InputCapture:SetEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then
        return
    end
    self.enabled = enabled

    if enabled then
        self.previousMouseBehavior = self.userInputService.MouseBehavior
        self.previousMouseIconEnabled = self.userInputService.MouseIconEnabled
        self.previousMouseIconOverride = self.userInputService.OverrideMouseIconBehavior
        self.previousCameraMode = self.localPlayer.CameraMode
        self.propertyConnections = {
            self:_guardProperty(self.localPlayer, "CameraMode"),
            self:_guardProperty(self.userInputService, "MouseBehavior"),
            self:_guardProperty(self.userInputService, "MouseIconEnabled"),
            self:_guardProperty(self.userInputService, "OverrideMouseIconBehavior"),
        }
        self.heartbeatConnection = self.runService.Heartbeat:Connect(function()
            self:_enforceCursor()
        end)
        self.menuClosedConnection = self.guiService.MenuClosed:Connect(function()
            self:_enforceCursor()
        end)
        self:_enforceCursor()
        return
    end

    self.heartbeatConnection:Disconnect()
    self.heartbeatConnection = nil
    self.menuClosedConnection:Disconnect()
    self.menuClosedConnection = nil
    for _, connection in ipairs(self.propertyConnections) do
        connection:Disconnect()
    end
    self.propertyConnections = nil
    local releaseMouse = self.releaseMouseOnDisable
        or self.previousCameraMode ~= Enum.CameraMode.LockFirstPerson
    self.localPlayer.CameraMode = self.previousCameraMode
    self.userInputService.MouseBehavior = releaseMouse and Enum.MouseBehavior.Default
        or self.previousMouseBehavior
    self.userInputService.MouseIconEnabled = self.previousMouseIconEnabled
    self.userInputService.OverrideMouseIconBehavior = self.previousMouseIconOverride
    self.previousCameraMode = nil
    self.previousMouseBehavior = nil
    self.previousMouseIconEnabled = nil
    self.previousMouseIconOverride = nil
end

function InputCapture:IsEnabled()
    return self.enabled
end

function InputCapture:Destroy()
    self:SetEnabled(false)
end

return InputCapture
]],
    ["modules/Logger.lua"] = [[local Logger = {}
Logger.__index = Logger

local function sanitize(value)
	return tostring(value):gsub("[\r\n]+", " ")
end

local function formatFields(fields)
	if type(fields) ~= "table" then
		return ""
	end
	local keys = {}
	for key in pairs(fields) do
		table.insert(keys, tostring(key))
	end
	table.sort(keys)
	local parts = {}
	for _, key in ipairs(keys) do
		table.insert(parts, ("%s=%s"):format(key, sanitize(fields[key])))
	end
	return #parts > 0 and " " .. table.concat(parts, " ") or ""
end

local function fileExists(options, path)
	if not options.isFile then
		return false
	end
	local succeeded, exists = pcall(options.isFile, path)
	return succeeded and exists == true
end

local function tryRead(options, path)
	if not options.readFile then
		return nil
	end
	if options.isFile and not fileExists(options, path) then
		return nil
	end
	local succeeded, content = pcall(options.readFile, path)
	return succeeded and type(content) == "string" and content or nil
end

function Logger.new(options)
	options = options or {}
	local directory = options.directory or "universal-hub/logs"
	local latestPath = directory .. "/latest.log"
	if options.makeFolder then
		pcall(options.makeFolder, "universal-hub")
		pcall(options.makeFolder, directory)
	end

	local previous = tryRead(options, latestPath)
	if previous and previous ~= "" and options.writeFile then
		local name = type(options.archiveName) == "function" and options.archiveName() or tostring(os.time())
		local archivePath = directory .. "/" .. sanitize(name) .. ".log"
		local suffix = 2
		while fileExists(options, archivePath) do
			archivePath = directory .. "/" .. sanitize(name) .. "-" .. suffix .. ".log"
			suffix += 1
		end
		pcall(options.writeFile, archivePath, previous)
	end

	local self = setmetatable({
		appendFile = options.appendFile,
		closed = false,
		latestPath = latestPath,
		lines = {},
		maxLines = options.maxLines or 2000,
		now = options.now or os.clock,
		startedAt = (options.now or os.clock)(),
		writeFile = options.writeFile,
	}, Logger)
	if self.writeFile then
		pcall(self.writeFile, self.latestPath, "")
	end
	self:info("logger", "START", { path = self.latestPath })
	return self
end

function Logger:_write(line)
	table.insert(self.lines, line)
	if #self.lines > self.maxLines then
		table.remove(self.lines, 1)
	end
	if self.appendFile then
		local appended = pcall(self.appendFile, self.latestPath, line .. "\n")
		if appended then
			return
		end
	end
	if self.writeFile then
		pcall(self.writeFile, self.latestPath, table.concat(self.lines, "\n") .. "\n")
	end
end

function Logger:log(level, scope, message, fields)
	if self.closed then
		return
	end
	self:_write(
		("[%08.3f] %-5s %-24s %s%s"):format(
			self.now() - self.startedAt,
			sanitize(level),
			sanitize(scope),
			sanitize(message),
			formatFields(fields)
		)
	)
end

function Logger:info(scope, message, fields)
	self:log("INFO", scope, message, fields)
end

function Logger:warn(scope, message, fields)
	self:log("WARN", scope, message, fields)
end

function Logger:error(scope, message, fields)
	self:log("ERROR", scope, message, fields)
end

function Logger:snapshot()
	return table.clone(self.lines)
end

function Logger:close(fields)
	if self.closed then
		return
	end
	self:info("logger", "STOP", fields)
	self.closed = true
end

return Logger
]],
    ["modules/MenuToggle.lua"] = [[local MenuToggle = {}

function MenuToggle.shouldToggle(input, gameProcessedEvent, userInputService, configuredKey)
    local keyCode = configuredKey
    if type(keyCode) == "string" then
        keyCode = Enum.KeyCode[keyCode]
    end
    keyCode = keyCode or Enum.KeyCode.RightShift
    if not input or input.KeyCode ~= keyCode or gameProcessedEvent then
        return false
    end

    return not (
        userInputService
        and type(userInputService.GetFocusedTextBox) == "function"
        and userInputService:GetFocusedTextBox()
    )
end

return MenuToggle
]],
    ["modules/Registry.lua"] = [[local Registry = {}
Registry.__index = Registry

local function validSourcePath(path)
    return type(path) == "string"
        and path ~= ""
        and path:match("^[%w_/%-]+$") ~= nil
        and not path:find("//", 1, true)
end

local function validateManifestIds(manifest, field)
    local values = manifest[field]
    if values == nil then
        return 0
    end
    assert(type(values) == "table", "Game definition manifest " .. field .. " must be a table")

    local seen = {}
    for _, value in ipairs(values) do
        assert(
            type(value) == "number" and value > 0 and value % 1 == 0,
            "Game definition manifest ids must be positive integers"
        )
        assert(not seen[value], "Game definition manifest contains duplicate id: " .. tostring(value))
        seen[value] = true
    end
    return #values
end

local function validateData(value, path, seen)
    local valueType = type(value)
    assert(
        valueType == "nil"
            or valueType == "boolean"
            or valueType == "number"
            or valueType == "string"
            or valueType == "table",
        path .. " must contain only data"
    )
    if valueType ~= "table" then
        return
    end

    seen = seen or {}
    assert(not seen[value], path .. " must not contain cycles")
    seen[value] = true
    for key, child in pairs(value) do
        validateData(key, path .. " key", seen)
        validateData(child, path .. "." .. tostring(key), seen)
    end
    seen[value] = nil
end

local function validateStringList(values, path, allowed)
    assert(type(values) == "table", path .. " must be a table")
    local seen = {}
    for _, value in ipairs(values) do
        assert(type(value) == "string" and value ~= "", path .. " entries must be non-empty strings")
        assert(not seen[value], path .. " contains duplicate entry: " .. value)
        assert(not allowed or allowed[value], path .. " contains unsupported entry: " .. value)
        seen[value] = true
    end
end

function Registry.Validate(definition)
    assert(type(definition) == "table", "Game definition must be a table")
    assert(
        type(definition.id) == "string" and definition.id:match("%S") ~= nil,
        "Game definition requires a non-empty id"
    )
    assert(
        type(definition.label) == "string" and definition.label:match("%S") ~= nil,
        "Game definition requires a non-empty label"
    )
    assert(type(definition.manifest) == "table", "Game definition requires a manifest")

    local gameIdCount = validateManifestIds(definition.manifest, "gameIds")
    local placeIdCount = validateManifestIds(definition.manifest, "placeIds")
    assert(
        gameIdCount + placeIdCount > 0,
        "Game definition manifest requires a numeric gameId or placeId"
    )

    local hasModule = definition.module ~= nil
    local hasFactory = definition.factory ~= nil
    assert(hasModule ~= hasFactory, "Game definition requires exactly one module or factory")
    if hasModule then
        assert(validSourcePath(definition.module), "Game definition module must be a valid source path")
        assert(definition.match == nil, "Module game definitions must not contain runtime callbacks")
        assert(
            validSourcePath(definition.presentation),
            "Game definition presentation must be a valid source path"
        )
    else
        assert(type(definition.factory) == "function", "Game definition factory must be a function")
    end

    assert(type(definition.sources) == "table", "Game definition sources must be a table")
    local seenSources = {}
    for _, source in ipairs(definition.sources) do
        assert(
            type(source) ~= "string" or not source:match("%.lua$"),
            "Game definition sources use module paths without .lua"
        )
        assert(validSourcePath(source), "Game definition source must be a valid module path")
        assert(not seenSources[source], "Game definition contains duplicate source: " .. source)
        seenSources[source] = true
    end
    if hasModule then
        assert(seenSources[definition.module], "Game definition sources must include its module")
        assert(
            seenSources[definition.presentation],
            "Game definition sources must include its presentation"
        )
        if definition.composition ~= nil then
            assert(
                validSourcePath(definition.composition),
                "Game definition composition must be a valid source path"
            )
            assert(
                seenSources[definition.composition],
                "Game definition sources must include its composition"
            )
        end
    end

    assert(type(definition.defaults) == "table", "Game definition defaults must be a table")
    assert(type(definition.initialState) == "table", "Game definition initialState must be a table")
    assert(type(definition.features) == "table", "Game definition features must be a table")
    validateStringList(definition.features.capabilities, "Game definition capabilities")
    assert(
        definition.features.cosmetics == nil or type(definition.features.cosmetics) == "boolean",
        "Game definition cosmetics must be a boolean when declared"
    )
    if definition.features.optionLabels ~= nil then
        assert(type(definition.features.optionLabels) == "table", "Game definition optionLabels must be a table")
    end
    if definition.features.exclusiveOptions ~= nil then
        assert(
            type(definition.features.exclusiveOptions) == "table",
            "Game definition exclusiveOptions must be a table"
        )
        for option, exclusions in pairs(definition.features.exclusiveOptions) do
            assert(type(option) == "string" and option ~= "", "Game definition exclusion keys must be strings")
            validateStringList(exclusions, "Game definition exclusion " .. option)
        end
    end
    validateStringList(definition.hydroxide, "Hydroxide requirements", {
        closure = true,
        lifecycle = true,
        targeting = true,
    })
    validateData(definition.defaults, "Game definition defaults")
    validateData(definition.initialState, "Game definition initialState")
    validateData(definition.features, "Game definition features")

    return definition
end

local function matchManifest(manifest, context)
    local score = 0

    for _, placeId in ipairs(manifest.placeIds or {}) do
        if placeId == context.placeId then
            score = math.max(score, 200)
        end
    end

    for _, gameId in ipairs(manifest.gameIds or {}) do
        if gameId == context.gameId then
            score = math.max(score, 100)
        end
    end

    return score
end

function Registry.new()
    return setmetatable({
        adapters = {},
        order = {},
    }, Registry)
end

function Registry:Register(definition)
    Registry.Validate(definition)
    assert(self.adapters[definition.id] == nil, "Duplicate game definition id: " .. definition.id)

    self.adapters[definition.id] = definition
    table.insert(self.order, definition)
    return definition
end

function Registry:Resolve(context)
    local selected = {}
    local selectedScore = 0

    for _, adapter in ipairs(self.order) do
        local score
        if type(adapter.match) == "function" then
            score = adapter.match(context)
            if score == true then
                score = 1
            elseif score == false or score == nil then
                score = 0
            end
        else
            score = matchManifest(adapter.manifest or {}, context)
        end

        if type(score) == "number" and score > selectedScore then
            selected = { adapter }
            selectedScore = score
        elseif type(score) == "number" and score > 0 and score == selectedScore then
            table.insert(selected, adapter)
        end
    end

    if #selected > 1 then
        local ids = {}
        for _, definition in ipairs(selected) do
            table.insert(ids, definition.id)
        end
        table.sort(ids)
        error(
            ("Ambiguous game definitions at score %s: %s"):format(
                tostring(selectedScore),
                table.concat(ids, ", ")
            ),
            2
        )
    end

    return selected[1], selectedScore
end

function Registry:List()
    local adapters = {}
    for _, adapter in ipairs(self.order) do
        table.insert(adapters, adapter)
    end
    table.sort(adapters, function(left, right)
        return left.id < right.id
    end)
    return adapters
end

return Registry
]],
    ["modules/Session.lua"] = [[local Session = {}
Session.__index = Session

function Session.stopPrevious(environment)
    assert(type(environment) == "table", "Hub session cleanup requires an environment")
    local previous = environment.UniversalHubSession
    if type(previous) ~= "table" or type(previous.stop) ~= "function" then
        return nil
    end

    local helpers = environment.oh
    local resources = type(helpers) == "table" and helpers.Resources or nil
    local legacyIndex = type(resources) == "table" and table.find(resources, previous) or nil

    pcall(previous.stop, previous)
    if environment.UniversalHubSession == previous then
        environment.UniversalHubSession = nil
    end
    if legacyIndex and resources[legacyIndex] == previous then
        table.remove(resources, legacyIndex)
    end
    return previous
end

function Session.new(options)
    assert(options and options.environment, "Hub session requires an environment")
    assert(options.store, "Hub session requires a store")
    assert(options.overlay, "Hub session requires an overlay")
    assert(options.adapter, "Hub session requires an adapter")

    local self = setmetatable({
        adapter = options.adapter,
        environment = options.environment,
        inputCapture = options.inputCapture,
        logger = options.logger,
        overlay = options.overlay,
        resources = {},
        settingsChanged = options.settingsChanged,
        stopped = false,
        store = options.store,
    }, Session)

    self.environment.UniversalHubSession = self
    if self.logger then
        self.logger:info("session", "created")
    end
    return self
end

function Session:Add(cleanup)
    assert(type(cleanup) == "function", "Hub cleanup must be a function")
    if self.stopped then
        cleanup()
        return cleanup
    end

    table.insert(self.resources, cleanup)
    return cleanup
end

function Session:patchSettings(patch, persist)
    self.store:Patch({ settings = patch })
    if persist ~= false and self.settingsChanged then
        self.settingsChanged(self.store:Get().settings)
    end
end

function Session:setSetting(name, value, persist)
    local state = self.store:Get()
    local current = state.settings[name]
    assert(current ~= nil, "Unknown hub setting: " .. tostring(name))
    assert(type(current) == type(value), "Invalid hub setting type: " .. tostring(name))
    self:patchSettings({
        [name] = value,
    }, persist)
end

function Session:setOption(name, enabled, persist)
    self:setSetting(name, enabled == true, persist)
end

function Session:setRate(name, value, persist)
    assert(
        name == "aimSmoothness"
            or name == "aimAssistStrength"
            or name == "headshotRate"
            or name == "missRate",
        "Unknown hub rate: " .. tostring(name)
    )
    self:patchSettings({
        [name] = math.clamp(math.round(value), 0, 100),
    }, persist)
end

function Session:setCosmeticsOpen(open)
    self.store:Patch({
        cosmeticsOpen = open == true,
    })
end

function Session:setCosmeticMode(mode)
    self.store:Patch({
        cosmeticMode = mode == "gloves" and "gloves" or "weapon",
    })
end

function Session:setMenuKey(value)
    if
        typeof(value) ~= "EnumItem"
        or value.EnumType ~= Enum.KeyCode
        or value == Enum.KeyCode.Unknown
    then
        return false
    end
    self.menuKeyChangedAt = os.clock()
    self:patchSettings({ menuKey = value.Name })
    return true
end

function Session:setMenuVisible(visible)
    self.store:Patch({
        menuVisible = visible == true,
    })
end

function Session:toggleMenu()
    self:setMenuVisible(not self.store:Get().menuVisible)
end

function Session:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    if self.logger then
        self.logger:info("session", "stopping")
    end

    for index = #self.resources, 1, -1 do
        pcall(self.resources[index])
    end
    table.clear(self.resources)

    if self.adapter and type(self.adapter.stop) == "function" then
        pcall(self.adapter.stop, self.adapter)
    end
    if self.overlay and type(self.overlay.destroy) == "function" then
        pcall(self.overlay.destroy, self.overlay)
    end
    if self.inputCapture and type(self.inputCapture.Destroy) == "function" then
        pcall(self.inputCapture.Destroy, self.inputCapture)
    end
    if self.store and type(self.store.Destroy) == "function" then
        self.store:Destroy()
    end

    if self.environment.UniversalHubSession == self then
        self.environment.UniversalHubSession = nil
    end
    if self.logger then
        self.logger:close({ reason = "session-stop" })
        if self.environment.UniversalHubLogger == self.logger then
            self.environment.UniversalHubLogger = nil
        end
    end
end

Session.Destroy = Session.stop

return Session
]],
    ["modules/Sources.lua"] = [[local Sources = {}
Sources.__index = Sources

local CORE = {
    "modules/Store",
    "modules/Config",
    "modules/Changelog",
    "ui/WhatsNew",
    "modules/InputCapture",
    "modules/MenuToggle",
    "modules/Registry",
    "modules/Logger",
    "modules/Session",
    "ui/esp/DrawingRenderer",
    "ui/esp/ColorPolicy",
    "ui/esp/VisualPolicy",
    "ui/esp/HighlightRenderer",
    "ui/esp/WorldRenderer",
    "ui/Menu",
    "modules/HubView",
    "ui/PresentationHost",
    "ui/presentation/Catalog",
    "ui/presentation/Runtime",
    "ui/presentation/StandardPanels",
    "ui/presentation/CosmeticsPanel",
    "modules/Sources",
    "games/Compatibility",
    "games/Catalog",
    "games/Counterblox",
}

local function copyList(source)
    local copy = {}
    for index, value in ipairs(source) do
        copy[index] = value
    end
    return copy
end

local function validPath(path)
    return type(path) == "string"
        and path ~= ""
        and path:match("^[%w_/%-]+$") ~= nil
        and not path:find("//", 1, true)
end

local function appendUnique(ordered, seen, path)
    if not seen[path] then
        seen[path] = true
        table.insert(ordered, path)
    end
end

function Sources.Core()
    return copyList(CORE)
end

function Sources.new(options)
    assert(type(options) == "table", "Sources options must be a table")
    assert(type(options.catalog) == "table", "Sources catalog must be a table")
    assert(type(options.definitions) == "table", "Sources definitions must be a table")
    assert(
        #options.catalog == #options.definitions,
        "Sources requires one definition per catalog entry"
    )

    local core = options.core or CORE
    assert(type(core) == "table", "Sources core must be a table")
    local ordered = {}
    local seen = {}
    local ownerByPath = {}
    for _, path in ipairs(core) do
        assert(validPath(path), "Invalid core source path: " .. tostring(path))
        assert(not ownerByPath[path], "Duplicate core source path: " .. path)
        ownerByPath[path] = "core"
        appendUnique(ordered, seen, path)
    end
    for _, path in ipairs(options.catalog) do
        assert(validPath(path), "Invalid catalog definition path: " .. tostring(path))
        if ownerByPath[path] and ownerByPath[path] ~= "core" then
            error("Catalog definition path conflicts with game source owner: " .. path, 2)
        end
        ownerByPath[path] = "core"
        appendUnique(ordered, seen, path)
    end

    local definitionById = {}
    local claims = {}
    for _, definition in ipairs(options.definitions) do
        assert(type(definition) == "table", "Sources definition must be a table")
        assert(
            type(definition.id) == "string" and definition.id ~= "",
            "Sources definition requires an id"
        )
        assert(
            not definitionById[definition.id],
            "Duplicate Sources definition id: " .. definition.id
        )
        assert(type(definition.sources) == "table", "Sources definition sources must be a table")
        definitionById[definition.id] = definition
        for _, path in ipairs(definition.sources) do
            assert(validPath(path), "Invalid game source path: " .. tostring(path))
            claims[path] = claims[path] or {}
            claims[path][definition.id] = true
            appendUnique(ordered, seen, path)
        end
    end

    for path, owners in pairs(claims) do
        if ownerByPath[path] ~= "core" then
            local ids = {}
            for id in pairs(owners) do
                table.insert(ids, id)
            end
            table.sort(ids)
            if #ids > 1 then
                error(
                    ("Source path owned by multiple game definitions: %s (%s)"):format(
                        path,
                        table.concat(ids, ", ")
                    ),
                    2
                )
            end
            ownerByPath[path] = ids[1]
        end
    end

    return setmetatable({
        catalog = copyList(options.catalog),
        definitionById = definitionById,
        ordered = ordered,
        ownerByPath = ownerByPath,
    }, Sources)
end

function Sources:All()
    return copyList(self.ordered)
end

function Sources:Allow(selectedId)
    local selected = self.definitionById[selectedId]
    assert(selected, "Unknown selected game definition: " .. tostring(selectedId))
    local allowed = {}
    for path, owner in pairs(self.ownerByPath) do
        if owner == "core" or owner == selectedId then
            allowed[path] = true
        end
    end
    return allowed
end

function Sources:Owner(path)
    return self.ownerByPath[path]
end

return Sources
]],
    ["modules/Store.lua"] = [[local Store = {}
Store.__index = Store

local function copy(source)
    local result = {}
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            result[key] = copy(value)
        else
            result[key] = value
        end
    end
    return result
end

local function isList(value)
    if type(value) ~= "table" then
        return false
    end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false
        end
        count += 1
    end
    return count == #value
end

local function merge(target, patch)
    for key, value in pairs(patch) do
        if type(value) == "table" and type(target[key]) == "table" then
            if isList(value) and (next(value) ~= nil or isList(target[key])) then
                target[key] = copy(value)
            else
                merge(target[key], value)
            end
        else
            target[key] = value
        end
    end
end

function Store.new(initial)
    return setmetatable({
        listeners = {},
        state = copy(initial),
        stopped = false,
    }, Store)
end

function Store:Get()
    return self.state
end

function Store:Patch(patch)
    if self.stopped then
        return self.state
    end

    merge(self.state, patch)
    for listener in pairs(self.listeners) do
        listener(self.state)
    end
    return self.state
end

function Store:Subscribe(listener, emitCurrent)
    assert(type(listener) == "function", "Store subscriber must be a function")
    if self.stopped then
        return function() end
    end

    self.listeners[listener] = true
    if emitCurrent ~= false then
        listener(self.state)
    end

    local connected = true
    return function()
        if connected then
            connected = false
            self.listeners[listener] = nil
        end
    end
end

function Store:Destroy()
    if self.stopped then
        return
    end
    self.stopped = true
    table.clear(self.listeners)
end

return Store
]],
    ["ui/Menu.lua"] = [[local HubMenu = {}
HubMenu.__index = HubMenu

local function restoreExecutorThread()
    local setter = setthreadidentity or setidentity or setthreadcontext
    if type(setter) == "function" then
        pcall(setter, 8)
    end
end

local SHELL = Color3.fromRGB(18, 18, 19)
local SURFACE = Color3.fromRGB(24, 24, 26)
local DIVIDER = Color3.fromRGB(48, 48, 52)
local BORDER = Color3.fromRGB(68, 68, 73)
local TEXT = Color3.fromRGB(244, 247, 249)
local MUTED = Color3.fromRGB(177, 188, 199)
local DIM = Color3.fromRGB(103, 115, 126)
local ACCENT = Color3.fromRGB(255, 118, 87)
local INK = Color3.fromRGB(28, 11, 8)
local SECTION_COLOR = {
    added = Color3.fromRGB(98, 214, 173),
    changed = Color3.fromRGB(255, 167, 145),
    fixed = Color3.fromRGB(157, 199, 235),
    removed = Color3.fromRGB(255, 163, 176),
    security = Color3.fromRGB(255, 190, 92),
}

local MONTHS =
    { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

local function formatDate(value)
    local year, month, day = tostring(value or ""):match("^(%d+)%-(%d+)%-(%d+)$")
    if not month then
        return tostring(value or "")
    end
    return string.format("%s %d", MONTHS[tonumber(month)], tonumber(day))
end

local function applyType(instance, size, weight)
    instance.Font = Enum.Font.BuilderSans
    instance.TextSize = size
    instance.TextStrokeTransparency = 1
    instance.BorderSizePixel = 0
    instance.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", weight)
end

local function createText(parent, name, size, weight, color)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.BackgroundTransparency = 1
    label.TextColor3 = color
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.TextWrapped = true
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.Size = UDim2.new(1, 0, 0, 0)
    applyType(label, size, weight)
    label.Parent = parent
    return label
end

local function createGhost(parent, name, text)
    local button = Instance.new("TextButton")
    button.Name = name
    button.AutoButtonColor = false
    button.BackgroundTransparency = 1
    button.Text = text
    button.TextColor3 = DIM
    button.AutomaticSize = Enum.AutomaticSize.XY
    button.Size = UDim2.fromOffset(0, 28)
    applyType(button, 13, Enum.FontWeight.Medium)
    button.Parent = parent
    button.MouseEnter:Connect(function()
        button.TextColor3 = TEXT
    end)
    button.MouseLeave:Connect(function()
        button.TextColor3 = DIM
    end)
    return button
end

local function createFill(parent, name, text)
    local button = Instance.new("TextButton")
    button.Name = name
    button.AutoButtonColor = false
    button.BackgroundColor3 = ACCENT
    button.Text = text
    button.TextColor3 = INK
    button.Size = UDim2.fromOffset(72, 28)
    applyType(button, 13, Enum.FontWeight.Bold)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = button
    button.Parent = parent
    return button
end

local function mountWhatsNew(parent, onAction)
    local layer = Instance.new("ScreenGui")
    layer.Name = "UniversalHubWhatsNew"
    layer.DisplayOrder = 1100
    layer.IgnoreGuiInset = true
    layer.ResetOnSpawn = false
    layer.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    layer.Enabled = false
    layer.Parent = parent

    local dim = Instance.new("TextButton")
    dim.Name = "Backdrop"
    dim.AutoButtonColor = false
    dim.Text = ""
    dim.TextTransparency = 1
    dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    dim.BackgroundTransparency = 0.46
    dim.BorderSizePixel = 0
    dim.Size = UDim2.fromScale(1, 1)
    dim.Parent = layer

    local card = Instance.new("Frame")
    card.Name = "Card"
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(0.5, 0.5)
    card.Size = UDim2.fromOffset(520, 420)
    card.BackgroundColor3 = SHELL
    card.BorderSizePixel = 0
    card.ClipsDescendants = true
    card.Parent = layer
    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 10)
    cardCorner.Parent = card
    local cardStroke = Instance.new("UIStroke")
    cardStroke.Color = BORDER
    cardStroke.Transparency = 0.2
    cardStroke.Thickness = 1
    cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    cardStroke.Parent = card

    local header = Instance.new("Frame")
    header.Name = "Header"
    header.BackgroundColor3 = SURFACE
    header.BorderSizePixel = 0
    header.Size = UDim2.new(1, 0, 0, 48)
    header.Parent = card
    local heading = createText(header, "Title", 16, Enum.FontWeight.Bold, TEXT)
    heading.AutomaticSize = Enum.AutomaticSize.None
    heading.Position = UDim2.fromOffset(16, 14)
    heading.Size = UDim2.fromOffset(220, 20)
    heading.Text = "What's New"
    heading.TextYAlignment = Enum.TextYAlignment.Center
    local close = Instance.new("TextButton")
    close.Name = "Close"
    close.AutoButtonColor = false
    close.BackgroundTransparency = 1
    close.Text = "×"
    close.TextColor3 = DIM
    close.AnchorPoint = Vector2.new(1, 0)
    close.Position = UDim2.new(1, -10, 0, 10)
    close.Size = UDim2.fromOffset(28, 28)
    applyType(close, 20, Enum.FontWeight.Regular)
    close.Parent = header
    close.MouseEnter:Connect(function()
        close.TextColor3 = TEXT
    end)
    close.MouseLeave:Connect(function()
        close.TextColor3 = DIM
    end)

    local split = Instance.new("Frame")
    split.Name = "Split"
    split.BackgroundTransparency = 1
    split.BorderSizePixel = 0
    split.Position = UDim2.fromOffset(0, 48)
    split.Size = UDim2.new(1, 0, 1, -92)
    split.Parent = card

    local rail = Instance.new("ScrollingFrame")
    rail.Name = "Rail"
    rail.BackgroundColor3 = SURFACE
    rail.BorderSizePixel = 0
    rail.AutomaticCanvasSize = Enum.AutomaticSize.Y
    rail.CanvasSize = UDim2.new(0, 0, 0, 0)
    rail.ScrollBarThickness = 5
    rail.ScrollBarImageColor3 = MUTED
    rail.ScrollBarImageTransparency = 0.15
    rail.ScrollingDirection = Enum.ScrollingDirection.Y
    rail.Size = UDim2.new(0, 132, 1, 0)
    rail.Parent = split
    local railPad = Instance.new("UIPadding")
    railPad.PaddingTop = UDim.new(0, 12)
    railPad.PaddingBottom = UDim.new(0, 12)
    railPad.PaddingLeft = UDim.new(0, 10)
    railPad.PaddingRight = UDim.new(0, 10)
    railPad.Parent = rail
    local railLayout = Instance.new("UIListLayout")
    railLayout.FillDirection = Enum.FillDirection.Vertical
    railLayout.Padding = UDim.new(0, 6)
    railLayout.SortOrder = Enum.SortOrder.LayoutOrder
    railLayout.Parent = rail

    local gutter = Instance.new("Frame")
    gutter.Name = "Gutter"
    gutter.BackgroundColor3 = DIVIDER
    gutter.BackgroundTransparency = 0.25
    gutter.BorderSizePixel = 0
    gutter.Position = UDim2.fromOffset(132, 0)
    gutter.Size = UDim2.new(0, 1, 1, 0)
    gutter.Parent = split

    local notes = Instance.new("ScrollingFrame")
    notes.Name = "Notes"
    notes.BackgroundTransparency = 1
    notes.BorderSizePixel = 0
    notes.AutomaticCanvasSize = Enum.AutomaticSize.Y
    notes.CanvasSize = UDim2.new(0, 0, 0, 0)
    notes.ScrollBarThickness = 5
    notes.ScrollBarImageColor3 = MUTED
    notes.ScrollBarImageTransparency = 0.15
    notes.ScrollingDirection = Enum.ScrollingDirection.Y
    notes.Position = UDim2.fromOffset(133, 0)
    notes.Size = UDim2.new(1, -133, 1, 0)
    notes.Parent = split
    local notesPad = Instance.new("UIPadding")
    notesPad.PaddingTop = UDim.new(0, 20)
    notesPad.PaddingBottom = UDim.new(0, 20)
    notesPad.PaddingLeft = UDim.new(0, 20)
    notesPad.PaddingRight = UDim.new(0, 14)
    notesPad.Parent = notes
    local notesLayout = Instance.new("UIListLayout")
    notesLayout.FillDirection = Enum.FillDirection.Vertical
    notesLayout.Padding = UDim.new(0, 0)
    notesLayout.SortOrder = Enum.SortOrder.LayoutOrder
    notesLayout.Parent = notes

    local footer = Instance.new("Frame")
    footer.Name = "Footer"
    footer.BackgroundColor3 = SURFACE
    footer.BorderSizePixel = 0
    footer.AnchorPoint = Vector2.new(0, 1)
    footer.Position = UDim2.fromScale(0, 1)
    footer.Size = UDim2.new(1, 0, 0, 44)
    footer.Parent = card
    local mute = createGhost(footer, "Mute", "Don't show again")
    mute.Position = UDim2.fromOffset(16, 8)
    local gotIt = createFill(footer, "GotIt", "Got it")
    gotIt.AnchorPoint = Vector2.new(1, 0)
    gotIt.Position = UDim2.new(1, -16, 0, 8)

    local selectedVersion = ""
    local railButtons = {}

    local function paintRail()
        for version, button in pairs(railButtons) do
            local active = version == selectedVersion
            local versionLabel = button:FindFirstChild("Version")
            local titleLabel = button:FindFirstChild("Title")
            if versionLabel then
                versionLabel.TextColor3 = active and TEXT or MUTED
            end
            if titleLabel then
                titleLabel.TextColor3 = active and MUTED or DIM
            end
            local mark = button:FindFirstChild("Active")
            if mark then
                mark.BackgroundTransparency = active and 0 or 1
            end
        end
    end

    local function showVersion(version)
        selectedVersion = version
        paintRail()
        for _, child in ipairs(notes:GetChildren()) do
            if child:IsA("Frame") then
                child.Visible = child.Name == "Release_" .. version
            end
        end
        notes.CanvasPosition = Vector2.new(0, 0)
    end

    dim.MouseButton1Click:Connect(function()
        onAction("whatsNewDismiss")
    end)
    close.MouseButton1Click:Connect(function()
        onAction("whatsNewDismiss")
    end)
    mute.MouseButton1Click:Connect(function()
        onAction("whatsNewDontShowAgain")
    end)
    gotIt.MouseButton1Click:Connect(function()
        onAction("whatsNewAcknowledge")
    end)

    local function render(notice)
        notice = notice or {}
        layer.Enabled = notice.visible == true
        if notice.visible ~= true then
            return
        end
        local releases = notice.releases
        if type(releases) ~= "table" or #releases == 0 then
            releases = notice.entries or {}
        end
        local fresh = notice.fresh or {}
        selectedVersion = type(notice.current) == "string" and notice.current
            or (releases[1] and releases[1].version)
            or ""
        table.clear(railButtons)
        for _, child in ipairs(rail:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end
        for _, child in ipairs(notes:GetChildren()) do
            if child:IsA("Frame") then
                child:Destroy()
            end
        end
        for index, release in ipairs(releases) do
            local version = tostring(release.version or "")
            local button = Instance.new("TextButton")
            button.Name = "Version_" .. version
            button.AutoButtonColor = false
            button.BackgroundTransparency = 1
            button.Text = ""
            button.Size = UDim2.new(1, 0, 0, 40)
            button.LayoutOrder = index
            button.Parent = rail
            local active = Instance.new("Frame")
            active.Name = "Active"
            active.BackgroundColor3 = ACCENT
            active.BackgroundTransparency = 1
            active.BorderSizePixel = 0
            active.Position = UDim2.fromOffset(-6, 8)
            active.Size = UDim2.fromOffset(2, 24)
            active.Parent = button
            local versionLabel = createText(button, "Version", 13, Enum.FontWeight.Bold, MUTED)
            versionLabel.AutomaticSize = Enum.AutomaticSize.None
            versionLabel.Position = UDim2.fromOffset(6, 4)
            versionLabel.Size = UDim2.new(1, -14, 0, 16)
            versionLabel.Text = tostring(release.displayVersion or version)
            versionLabel.TextYAlignment = Enum.TextYAlignment.Center
            local titleLabel = createText(button, "Title", 11, Enum.FontWeight.Medium, DIM)
            titleLabel.AutomaticSize = Enum.AutomaticSize.None
            titleLabel.Position = UDim2.fromOffset(6, 20)
            titleLabel.Size = UDim2.new(1, -14, 0, 16)
            titleLabel.Text = tostring(release.title or "")
            titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
            titleLabel.TextYAlignment = Enum.TextYAlignment.Center
            if fresh[version] then
                local pip = Instance.new("Frame")
                pip.Name = "Fresh"
                pip.BackgroundColor3 = ACCENT
                pip.BorderSizePixel = 0
                pip.AnchorPoint = Vector2.new(1, 0.5)
                pip.Position = UDim2.new(1, 0, 0.5, 0)
                pip.Size = UDim2.fromOffset(5, 5)
                pip.Parent = button
                local pipCorner = Instance.new("UICorner")
                pipCorner.CornerRadius = UDim.new(1, 0)
                pipCorner.Parent = pip
            end
            button.MouseButton1Click:Connect(function()
                showVersion(version)
            end)
            railButtons[version] = button

            local entry = Instance.new("Frame")
            entry.Name = "Release_" .. version
            entry.BackgroundTransparency = 1
            entry.BorderSizePixel = 0
            entry.AutomaticSize = Enum.AutomaticSize.Y
            entry.Size = UDim2.new(1, 0, 0, 0)
            entry.Visible = false
            entry.LayoutOrder = 1
            entry.Parent = notes
            local entryLayout = Instance.new("UIListLayout")
            entryLayout.FillDirection = Enum.FillDirection.Vertical
            entryLayout.Padding = UDim.new(0, 20)
            entryLayout.SortOrder = Enum.SortOrder.LayoutOrder
            entryLayout.Parent = entry
            local headingBlock = Instance.new("Frame")
            headingBlock.Name = "Heading"
            headingBlock.BackgroundTransparency = 1
            headingBlock.BorderSizePixel = 0
            headingBlock.AutomaticSize = Enum.AutomaticSize.Y
            headingBlock.Size = UDim2.new(1, 0, 0, 0)
            headingBlock.LayoutOrder = 1
            headingBlock.Parent = entry
            local headingLayout = Instance.new("UIListLayout")
            headingLayout.FillDirection = Enum.FillDirection.Vertical
            headingLayout.Padding = UDim.new(0, 2)
            headingLayout.SortOrder = Enum.SortOrder.LayoutOrder
            headingLayout.Parent = headingBlock
            local headingLine =
                createText(headingBlock, "Title", 22, Enum.FontWeight.ExtraBold, TEXT)
            headingLine.LayoutOrder = 1
            headingLine.Text = tostring(release.title or "")
            local meta = createText(headingBlock, "Meta", 12, Enum.FontWeight.Medium, DIM)
            meta.LayoutOrder = 2
            local stamped = formatDate(release.date)
            if release.channel == "beta" then
                stamped = stamped .. " · Beta"
            end
            meta.Text = stamped
            local order = 2
            for _, section in ipairs(release.sections or {}) do
                local block = Instance.new("Frame")
                block.Name = "Section"
                block.BackgroundTransparency = 1
                block.BorderSizePixel = 0
                block.AutomaticSize = Enum.AutomaticSize.Y
                block.Size = UDim2.new(1, 0, 0, 0)
                block.LayoutOrder = order
                block.Parent = entry
                order += 1
                local blockLayout = Instance.new("UIListLayout")
                blockLayout.FillDirection = Enum.FillDirection.Vertical
                blockLayout.Padding = UDim.new(0, 8)
                blockLayout.SortOrder = Enum.SortOrder.LayoutOrder
                blockLayout.Parent = block
                local label = createText(
                    block,
                    "Label",
                    14,
                    Enum.FontWeight.ExtraBold,
                    SECTION_COLOR[section.id] or MUTED
                )
                label.LayoutOrder = 1
                label.Text = tostring(section.label or "")
                local items = Instance.new("Frame")
                items.Name = "Items"
                items.BackgroundTransparency = 1
                items.BorderSizePixel = 0
                items.AutomaticSize = Enum.AutomaticSize.Y
                items.Size = UDim2.new(1, 0, 0, 0)
                items.LayoutOrder = 2
                items.Parent = block
                local itemsLayout = Instance.new("UIListLayout")
                itemsLayout.FillDirection = Enum.FillDirection.Vertical
                itemsLayout.Padding = UDim.new(0, 10)
                itemsLayout.SortOrder = Enum.SortOrder.LayoutOrder
                itemsLayout.Parent = items
                local groups = section.groups
                if type(groups) ~= "table" or #groups == 0 then
                    groups = {
                        {
                            tab = "",
                            items = {},
                        },
                    }
                    for _, item in ipairs(section.items or {}) do
                        table.insert(groups[1].items, {
                            name = tostring(item),
                            note = "",
                        })
                    end
                end
                for groupIndex, group in ipairs(groups) do
                    local cluster = Instance.new("Frame")
                    cluster.Name = "Tab"
                    cluster.BackgroundTransparency = 1
                    cluster.BorderSizePixel = 0
                    cluster.AutomaticSize = Enum.AutomaticSize.Y
                    cluster.Size = UDim2.new(1, 0, 0, 0)
                    cluster.LayoutOrder = groupIndex
                    cluster.Parent = items
                    local clusterLayout = Instance.new("UIListLayout")
                    clusterLayout.FillDirection = Enum.FillDirection.Vertical
                    clusterLayout.Padding = UDim.new(0, 6)
                    clusterLayout.SortOrder = Enum.SortOrder.LayoutOrder
                    clusterLayout.Parent = cluster
                    local nextOrder = 1
                    if type(group.tab) == "string" and group.tab ~= "" then
                        local tabLabel =
                            createText(cluster, "Tab", 12, Enum.FontWeight.ExtraBold, TEXT)
                        tabLabel.LayoutOrder = nextOrder
                        tabLabel.Text = group.tab
                        nextOrder += 1
                    end
                    for featureIndex, feature in ipairs(group.items or {}) do
                        local row = Instance.new("Frame")
                        row.Name = "Item"
                        row.BackgroundTransparency = 1
                        row.BorderSizePixel = 0
                        row.AutomaticSize = Enum.AutomaticSize.Y
                        row.Size = UDim2.new(1, 0, 0, 0)
                        row.LayoutOrder = nextOrder + featureIndex - 1
                        row.Parent = cluster
                        local rowLayout = Instance.new("UIListLayout")
                        rowLayout.FillDirection = Enum.FillDirection.Vertical
                        rowLayout.Padding = UDim.new(0, 2)
                        rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
                        rowLayout.Parent = row
                        local nameRow = Instance.new("Frame")
                        nameRow.Name = "Feature"
                        nameRow.BackgroundTransparency = 1
                        nameRow.BorderSizePixel = 0
                        nameRow.AutomaticSize = Enum.AutomaticSize.Y
                        nameRow.Size = UDim2.new(1, 0, 0, 0)
                        nameRow.LayoutOrder = 1
                        nameRow.Parent = row
                        local bullet = Instance.new("Frame")
                        bullet.Name = "Bullet"
                        bullet.BackgroundColor3 = MUTED
                        bullet.BorderSizePixel = 0
                        bullet.Position = UDim2.fromOffset(0, 6)
                        bullet.Size = UDim2.fromOffset(4, 4)
                        bullet.Parent = nameRow
                        local bulletCorner = Instance.new("UICorner")
                        bulletCorner.CornerRadius = UDim.new(1, 0)
                        bulletCorner.Parent = bullet
                        local name = createText(nameRow, "Name", 13, Enum.FontWeight.Medium, MUTED)
                        name.Position = UDim2.fromOffset(12, 0)
                        name.Size = UDim2.new(1, -12, 0, 0)
                        local label = tostring(feature.name or feature.text or "")
                        if type(feature.note) == "string" and feature.note ~= "" then
                            label = label .. " - " .. feature.note
                        end
                        name.Text = label
                    end
                end
            end
        end
        showVersion(selectedVersion)
    end

    return {
        gui = layer,
        update = render,
        destroy = function()
            layer:Destroy()
        end,
    }
end

local function withExecutorScheduler(fn)
    restoreExecutorThread()
    local delay, defer, spawn = task.delay, task.defer, task.spawn
    local function wrapCallback(callback)
        if type(callback) ~= "function" then
            return callback
        end
        return function(...)
            restoreExecutorThread()
            return callback(...)
        end
    end
    pcall(function()
        task.delay = function(duration, callback, ...)
            return delay(duration, wrapCallback(callback), ...)
        end
        task.defer = function(callback, ...)
            return defer(wrapCallback(callback), ...)
        end
        task.spawn = function(callback, ...)
            return spawn(wrapCallback(callback), ...)
        end
    end)
    local ok, result = pcall(fn)
    pcall(function()
        task.delay = delay
        task.defer = defer
        task.spawn = spawn
    end)
    if not ok then
        error(result, 0)
    end
    return result
end

function HubMenu.new(context)
    assert(type(context) == "table", "HubMenu requires context")
    assert(
        type(context.prismMenu) == "table"
            and type(context.prismMenu.mountUniversalHubMenu) == "function",
        "HubMenu requires the compiled Prism artifact"
    )
    assert(
        type(context.presentation) == "table" and type(context.presentation.mount) == "function",
        "HubMenu requires a game presentation"
    )
    assert(
        type(context.catalog) == "table" and type(context.catalog.new) == "function",
        "HubMenu requires PresentationCatalog"
    )
    assert(context.store, "HubMenu requires Store")
    assert(typeof(context.uiParent) == "Instance", "HubMenu requires a gethui() parent")
    restoreExecutorThread()

    local existing = context.uiParent:FindFirstChild("UniversalHubNative")
    if existing then
        existing:Destroy()
    end
    local existingNotice = context.uiParent:FindFirstChild("UniversalHubWhatsNew")
    if existingNotice then
        existingNotice:Destroy()
    end

    local createInstance = context.createInstance or Instance.new
    local screenGui = createInstance("ScreenGui")
    screenGui.Name = "UniversalHubNative"
    screenGui.DisplayOrder = 1000
    screenGui.IgnoreGuiInset = true
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Enabled = context.menuEnabled ~= false
    screenGui.Parent = context.uiParent

    local publishedPreview
    context.publishPreviewObservation = function(observation)
        publishedPreview = observation
    end
    context.reportPreviewStatus = function(stage, detail)
        context.previewStatus = { stage = stage, detail = detail }
    end
    local catalog = context.catalog.new(context)
    context.presentation.mount(catalog)
    catalog:finalize()
    local model = catalog:model(context.store:Get())
    local handle = withExecutorScheduler(function()
        return context.prismMenu.mountUniversalHubMenu(screenGui, model)
    end)
    local whatsNew = mountWhatsNew(context.uiParent, function(name)
        catalog:action(name)
    end)
    whatsNew.update(model.whatsNew)
    local self = setmetatable({
        catalog = catalog,
        context = context,
        destroyed = false,
        gui = screenGui,
        handle = handle,
        whatsNew = whatsNew,
        model = model,
        previewObservation = function()
            return publishedPreview
        end,
    }, HubMenu)
    self.unsubscribe = context.store:Subscribe(function(state)
        if self.destroyed then
            return
        end
        withExecutorScheduler(function()
            self.model = self.catalog:model(state)
            self.handle.update(self.model)
            if self.whatsNew then
                self.whatsNew.update(self.model.whatsNew)
            end
        end)
        if self.context.setInputCaptured then
            self.context.setInputCaptured(state.menuVisible ~= false)
        end
    end)
    return self
end

function HubMenu:setEnabled(enabled)
    if self.destroyed or not self.gui then
        return
    end
    restoreExecutorThread()
    self.gui.Enabled = enabled == true
end

local function activePreview(model)
    for _, page in ipairs(model and model.pages or {}) do
        if page.preview and page.preview.kind == "character" then
            return page.preview
        end
    end
    return nil
end

function HubMenu:previewObservations()
    if self.destroyed or self.context.store:Get().menuVisible == false then
        return nil, nil
    end
    local published = self.previewObservation and self.previewObservation() or nil
    if not published or not published.bounds or not published.bodyParts then
        return nil, nil
    end
    self.previewPlayer = self.previewPlayer
        or {
            Name = game:GetService("Players").LocalPlayer.Name,
        }
    local preview = activePreview(self.model) or {}
    return {
        {
            player = self.previewPlayer,
            visible = true,
            health = 72,
            maxHealth = 100,
            weapon = preview.weaponLabel,
            tone = preview.tone,
            previewRenderer = preview.worldRenderer,
            bounds = published.bounds,
            bodyParts = published.bodyParts,
        },
    },
        nil
end

function HubMenu:isCaptured()
    return not self.destroyed and self.context.store:Get().menuVisible ~= false
end

function HubMenu:destroy()
    if self.destroyed then
        return
    end
    self.destroyed = true
    restoreExecutorThread()
    local unsubscribe = self.unsubscribe
    self.unsubscribe = nil
    if unsubscribe then
        pcall(unsubscribe)
    end
    if self.context.setInputCaptured then
        pcall(self.context.setInputCaptured, false)
    end
    if self.context.publishPreviewObservation then
        pcall(self.context.publishPreviewObservation, nil)
        self.context.publishPreviewObservation = nil
    end
    local whatsNew = self.whatsNew
    self.whatsNew = nil
    if whatsNew then
        pcall(whatsNew.destroy)
    end
    local handle = self.handle
    self.handle = nil
    if handle then
        pcall(function()
            withExecutorScheduler(function()
                handle.destroy()
            end)
        end)
    end
    local gui = self.gui
    self.gui = nil
    if gui then
        pcall(gui.Destroy, gui)
    end
end

return HubMenu
]],
    ["ui/PresentationHost.lua"] = [[local PresentationHost = {}

function PresentationHost.mount(facade, presentation)
    assert(type(facade) == "table", "PresentationHost requires a generic Overlay facade")
    assert(type(facade.register) == "function", "PresentationHost requires panel registration")
    assert(type(facade.read) == "function", "PresentationHost requires state reads")
    assert(type(facade.patch) == "function", "PresentationHost requires state patches")
    assert(type(facade.action) == "function", "PresentationHost requires actions")
    assert(type(presentation) == "table" and type(presentation.mount) == "function")
    presentation.mount(facade)
    if type(facade.finalize) == "function" then
        facade:finalize()
    end
    return facade
end

return PresentationHost
]],
    ["ui/WhatsNew.lua"] = [[local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local Changelog = importDependency("modules/Changelog", "../modules/Changelog")

local WhatsNew = {}
WhatsNew.DEFAULT_PATH = "universal-hub/last-used-version.json"
WhatsNew.PAGES_CHANGELOG_URL = "https://3xjn.github.io/universal-hub/changelog.json"

local function copyLastUsed(value)
    return {
        version = type(value) == "table" and type(value.version) == "string" and value.version or "",
        suppressPopups = type(value) == "table" and value.suppressPopups == true,
    }
end

function WhatsNew.defaults()
    return {
        version = "",
        suppressPopups = false,
    }
end

local function readLocalCatalog()
    if type(getgenv) ~= "function" or type(readfile) ~= "function" then
        return nil
    end
    local environment = getgenv()
    local configuration = environment and environment.UniversalHubConfig
    local root = type(configuration) == "table" and configuration.LocalRoot or "universal-hub/local"
    local path = root .. "/changelog.json"
    if type(isfile) == "function" and not isfile(path) then
        return nil
    end
    local ok, catalog = pcall(function()
        return Changelog.decode(readfile(path), function(source)
            return game:GetService("HttpService"):JSONDecode(source)
        end)
    end)
    if ok then
        return catalog
    end
    return nil
end

function WhatsNew.evaluate(options)
    options = options or {}
    local catalog = options.catalog
    if type(catalog) ~= "table" or type(catalog.releases) ~= "table" then
        catalog = readLocalCatalog()
    end
    if type(catalog) ~= "table" then
        return {
            shouldShow = false,
        }
    end
    local lastUsed = copyLastUsed(options.lastUsed)
    local notice = Changelog.notice(catalog, lastUsed.version)
    notice.suppressPopups = lastUsed.suppressPopups
    if lastUsed.suppressPopups then
        notice.shouldShow = false
    end
    return notice
end

function WhatsNew.acknowledge(current, suppressPopups)
    assert(type(current) == "string" and current ~= "", "WhatsNew.acknowledge requires the current version")
    return {
        version = current,
        suppressPopups = suppressPopups == true,
    }
end

local SECTION_LABEL = {
    added = "New features",
    changed = "Changes",
    fixed = "Bugfixes",
    removed = "Removed",
    security = "Security",
}

function WhatsNew.sectionLabel(name)
    return SECTION_LABEL[name] or Changelog.sectionLabel(name)
end

local function featureEntry(item)
    if type(item) == "table" then
        return {
            tab = type(item.tab) == "string" and item.tab or "",
            name = item.name or item.text or "",
            note = type(item.note) == "string" and item.note or "",
            text = item.text or (Changelog.entryText and Changelog.entryText(item)) or item.name or "",
        }
    end
    local text = tostring(item or "")
    return {
        tab = "",
        name = text,
        note = "",
        text = text,
    }
end

function WhatsNew.releaseSections(release)
    local sections = {}
    for _, name in ipairs(Changelog.sectionOrder()) do
        local items = release and release[name]
        if items and #items > 0 then
            local copy = {}
            local groups = {}
            local current
            for index, item in ipairs(items) do
                local entry = featureEntry(item)
                copy[index] = entry.text
                if not current or current.tab ~= entry.tab then
                    current = {
                        tab = entry.tab,
                        items = {},
                    }
                    table.insert(groups, current)
                end
                table.insert(current.items, entry)
            end
            table.insert(sections, {
                id = name,
                label = WhatsNew.sectionLabel(name),
                items = copy,
                groups = groups,
            })
        end
    end
    return sections
end

function WhatsNew.releaseBody(release)
    local lines = {}
    for _, section in ipairs(WhatsNew.releaseSections(release)) do
        table.insert(lines, section.label)
        for _, group in ipairs(section.groups or {}) do
            if group.tab ~= "" then
                table.insert(lines, group.tab)
            end
            for _, item in ipairs(group.items or {}) do
                table.insert(lines, item.name)
                if item.note ~= "" then
                    table.insert(lines, item.note)
                end
            end
        end
    end
    return table.concat(lines, "\n")
end

local function copyReleases(source)
    local releases = {}
    for index, release in ipairs(type(source) == "table" and source or {}) do
        releases[index] = release
    end
    return releases
end

function WhatsNew.snapshot(notice)
    notice = notice or {}
    local catalog = notice.catalog
    local board = copyReleases(catalog and catalog.releases)
    return {
        visible = notice.shouldShow == true,
        current = notice.current,
        previous = notice.previous,
        showingAll = false,
        entries = notice.entries or {},
        catalog = catalog,
        history = board,
        timeline = board,
        lanes = board,
        board = board,
        outline = board,
        guide = board,
        pack = board,
    }
end

local function publishedReleases(state)
    if type(state) ~= "table" then
        return {}
    end
    if type(state.pack) == "table" and #state.pack > 0 then
        return state.pack
    end
    if type(state.guide) == "table" and #state.guide > 0 then
        return state.guide
    end
    if type(state.outline) == "table" and #state.outline > 0 then
        return state.outline
    end
    if type(state.board) == "table" and #state.board > 0 then
        return state.board
    end
    if type(state.lanes) == "table" and #state.lanes > 0 then
        return state.lanes
    end
    if type(state.timeline) == "table" and #state.timeline > 0 then
        return state.timeline
    end
    if type(state.history) == "table" and #state.history > 0 then
        return state.history
    end
    if type(state.catalog) == "table" and type(state.catalog.releases) == "table" then
        return state.catalog.releases
    end
    return state.entries or {}
end

function WhatsNew.releases(state)
    if type(state) ~= "table" then
        return {}
    end
    if state.showingAll == true then
        return publishedReleases(state)
    end
    return state.entries or {}
end

local function releaseChannel(release)
    if Changelog.channel then
        return Changelog.channel(release)
    end
    if type(release) == "table" and release.channel == "released" then
        return "released"
    end
    return "beta"
end

local function displayVersion(release)
    if Changelog.displayVersion then
        return Changelog.displayVersion(release)
    end
    local version = type(release) == "table" and release.version or ""
    if releaseChannel(release) == "beta" then
        return version .. "-beta"
    end
    return version
end

local function mapRelease(release)
    return {
        version = release.version,
        displayVersion = displayVersion(release),
        channel = releaseChannel(release),
        date = release.date,
        title = release.title,
        body = WhatsNew.releaseBody(release),
        sections = WhatsNew.releaseSections(release),
    }
end

function WhatsNew.model(state)
    local entries = {}
    for _, release in ipairs(WhatsNew.releases(state)) do
        table.insert(entries, mapRelease(release))
    end
    local releases = {}
    for _, release in ipairs(publishedReleases(state)) do
        table.insert(releases, mapRelease(release))
    end
    local fresh = {}
    for _, release in ipairs(type(state) == "table" and state.entries or {}) do
        if type(release.version) == "string" then
            fresh[release.version] = true
        end
    end
    return {
        visible = type(state) == "table" and state.visible == true,
        current = type(state) == "table" and state.current or "",
        previous = type(state) == "table" and state.previous or nil,
        showingAll = type(state) == "table" and state.showingAll == true,
        entries = entries,
        releases = releases,
        fresh = fresh,
    }
end

return WhatsNew
]],
    ["ui/esp/ColorPolicy.lua"] = [[local ColorPolicy = {}

ColorPolicy.RELATIONSHIPS = table.freeze({ "enemy", "teammate" })
ColorPolicy.TARGETS = table.freeze({ "outline", "fill", "name", "weapon", "healthLow", "healthHigh" })

local PREFIX = table.freeze({
    enemy = "espEnemy",
    teammate = "espTeammate",
})

local function title(value)
    return value:sub(1, 1):upper() .. value:sub(2)
end

function ColorPolicy.relationship(tone)
    if tone == "team" or tone == "teammate" or tone == "ally" or tone == "allies" then
        return "teammate"
    end
    return "enemy"
end

function ColorPolicy.settingName(relationship, target)
    local prefix = PREFIX[ColorPolicy.relationship(relationship)]
    if target == "fillAlpha" then
        return prefix .. "FillAlpha"
    end
    for _, candidate in ipairs(ColorPolicy.TARGETS) do
        if candidate == target then
            return prefix .. title(target) .. "Color"
        end
    end
    return nil
end

local function channel(value)
    return math.clamp(math.floor(value + 0.5), 0, 255)
end

function ColorPolicy.parseHex(value)
    if type(value) ~= "string" then return nil end
    local source = value:gsub("^#", "")
    if #source == 3 then
        source = source:sub(1, 1):rep(2) .. source:sub(2, 2):rep(2) .. source:sub(3, 3):rep(2)
    end
    if #source ~= 6 or source:find("[^%x]") then return nil end
    return Color3.fromRGB(
        tonumber(source:sub(1, 2), 16),
        tonumber(source:sub(3, 4), 16),
        tonumber(source:sub(5, 6), 16)
    )
end

function ColorPolicy.toHex(color)
    return ("#%02X%02X%02X"):format(channel(color.R * 255), channel(color.G * 255), channel(color.B * 255))
end

function ColorPolicy.color(settings, target, fallback, relationship)
    local setting = ColorPolicy.settingName(relationship, target)
    local value = setting and settings and settings[setting]
    if value ~= nil then
        return ColorPolicy.parseHex(value) or fallback
    end
    -- Only previously saved configs lack relationship-specific keys. Once a
    -- relationship is changed or reset, its explicit value suppresses legacy.
    local legacy = "esp" .. title(target) .. "Color"
    return ColorPolicy.parseHex(settings and settings[legacy]) or fallback
end

function ColorPolicy.fillAlpha(settings, fallback, relationship)
    local setting = ColorPolicy.settingName(relationship, "fillAlpha")
    local value = setting and settings and settings[setting]
    if value ~= nil then
        if type(value) == "number" and value >= 0 and value <= 1 then return value, true end
        return fallback, false
    end
    value = settings and settings.espFillAlpha
    if type(value) == "number" and value >= 0 and value <= 1 then return value, true end
    return fallback, false
end

function ColorPolicy.healthColor(settings, fraction, fallbackLow, fallbackHigh, relationship)
    local low = ColorPolicy.color(settings, "healthLow", fallbackLow, relationship)
    local high = ColorPolicy.color(settings, "healthHigh", fallbackHigh, relationship)
    return low:Lerp(high, math.sqrt(math.clamp(fraction, 0, 1)))
end

return table.freeze(ColorPolicy)
]],
    ["ui/esp/DrawingRenderer.lua"] = [=[local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local VisualPolicy = importDependency("ui/esp/VisualPolicy", "./VisualPolicy")
local ColorPolicy = importDependency("ui/esp/ColorPolicy", "./ColorPolicy")
local Overlay = {}
Overlay.__index = Overlay

local PRESENTATION_TOKENS = {
    font = {
        control = Drawing.Fonts.Plex,
        heading = Drawing.Fonts.Plex,
    },
    control = {
        borderThickness = 1,
        fovCircleSides = 96,
        fovCircleThickness = 1.5,
        fovThumbRadius = 8,
        progressTrackHeight = 4,
        rateThumbRadius = 7,
        segmentCornerRadius = 4,
        sliderCircleSides = 32,
        sliderTrackHeight = 5,
        switchCircleSides = 24,
        switchInnerRadius = 9,
        switchInnerTrackHeight = 18,
        switchKnobRadius = 9,
        switchKnobRimRadius = 9.5,
        switchOuterRadius = 11,
        switchOuterTrackHeight = 22,
        switchTrackWidth = 20,
    },
    layout = {
        cardContentInset = 16,
        cardInset = 20,
        contentTopWithTabs = 158,
        contentTopWithoutTabs = 72,
        contentWidth = 350,
        headerContentInset = 20,
        headerHeight = 64,
        initialHeight = 790,
        innerControlWidth = 350,
        shellRightInset = 44,
        shellTopInset = 20,
        shellWidth = 390,
        shadowX = 3,
        shadowY = 4,
        statusDotRightInset = 18,
        statusDotTop = 45,
        statusTop = 36,
        tabBarHeight = 44,
        tabsTop = 84,
        titleTop = 13,
    },
    opacity = {
        divider = 0.58,
        edge = 0.72,
        focus = 0.96,
        fovCircle = 0.8,
        hitbox = 0.01,
        quietControl = 0.98,
        subDivider = 0.38,
    },
    type = {
        display = 18,
        eyebrow = 9,
        header = 16,
        label = 13,
        meta = 10,
        primary = 12,
        rateValue = 15,
        row = 12,
        section = 16,
        status = 11,
    },
}

local COLORS = {
    accent = Color3.fromRGB(160, 225, 194),
    accentSurface = Color3.fromRGB(30, 53, 44),
    border = Color3.fromRGB(39, 41, 46),
    danger = Color3.fromRGB(255, 118, 87),
    elevated = Color3.fromRGB(31, 33, 37),
    header = Color3.fromRGB(25, 26, 30),
    hover = Color3.fromRGB(37, 39, 43),
    panel = Color3.fromRGB(24, 26, 29),
    panelShadow = Color3.fromRGB(12, 14, 16),
    secondary = Color3.fromRGB(190, 192, 195),
    signal = Color3.fromRGB(98, 214, 173),
    team = Color3.fromRGB(101, 157, 214),
    tertiary = Color3.fromRGB(128, 132, 138),
    text = Color3.fromRGB(243, 243, 244),
    track = Color3.fromRGB(55, 56, 61),
    tokens = PRESENTATION_TOKENS,
    toggleActive = Color3.fromRGB(160, 225, 194),
}

local function playerColor(observation, visible)
    local presentation = observation.presentation
    if type(presentation) == "table" and presentation.color ~= nil then
        return presentation.color
    end
    if observation.tone == "team" then
        return COLORS.team
    end
    return visible == true and COLORS.signal or COLORS.danger
end

local WORLD_LAYER = {
    chams = 10,
    player = 11,
    health = 12,
    playerDetail = 13,
    utilityZone = 20,
    utility = 21,
    utilityText = 22,
}

local BODY_CUBE_FACES = {
    { 1, 2, 3, 4 },
    { 5, 8, 7, 6 },
    { 1, 5, 6, 2 },
    { 4, 3, 7, 8 },
    { 1, 4, 8, 5 },
    { 2, 6, 7, 3 },
}
local UTILITY_CUBE_EDGES = {
    { 1, 2 },
    { 2, 3 },
    { 3, 4 },
    { 4, 1 },
    { 5, 6 },
    { 6, 7 },
    { 7, 8 },
    { 8, 5 },
    { 1, 5 },
    { 2, 6 },
    { 3, 7 },
    { 4, 8 },
}

local function convexHull(points)
    if #points < 3 then
        return points
    end
    table.sort(points, function(left, right)
        return left.X == right.X and left.Y < right.Y or left.X < right.X
    end)
    local unique = {}
    for _, point in ipairs(points) do
        local previous = unique[#unique]
        if not previous or previous.X ~= point.X or previous.Y ~= point.Y then
            table.insert(unique, point)
        end
    end
    if #unique < 3 then
        return unique
    end
    local function cross(origin, left, right)
        return (left.X - origin.X) * (right.Y - origin.Y)
            - (left.Y - origin.Y) * (right.X - origin.X)
    end
    local lower = {}
    for _, point in ipairs(unique) do
        while #lower >= 2 and cross(lower[#lower - 1], lower[#lower], point) <= 0 do
            table.remove(lower)
        end
        table.insert(lower, point)
    end
    local upper = {}
    for index = #unique, 1, -1 do
        local point = unique[index]
        while #upper >= 2 and cross(upper[#upper - 1], upper[#upper], point) <= 0 do
            table.remove(upper)
        end
        table.insert(upper, point)
    end
    table.remove(lower)
    table.remove(upper)
    for _, point in ipairs(upper) do
        table.insert(lower, point)
    end
    return lower
end

local BODY_CUBE_OPACITY = 0.18
local NATIVE_PREVIEW_FILL_TRANSPARENCY = VisualPolicy.FILL_TRANSPARENCY
local EVENT_SIGNALS = {
    click = "Clicked",
    drag = "Dragged",
    pointerdown = "PointerDown",
    pointerenter = "PointerEntered",
    pointerleave = "PointerLeft",
    pointerup = "PointerUp",
}

local function wrapElement(element, canvas)
    local object = element:getObject()
    local callbacks = {}
    local node
    local methods = {}

    function methods:on(eventName, callback)
        local signalName = assert(EVENT_SIGNALS[eventName], "Unknown Limn element event: " .. tostring(eventName))
        assert(type(callback) == "function", "Limn element event handler must be a function")
        callbacks[eventName] = callback
        element:setInteractive(true)
        return element[signalName]:Connect(function(event)
            callback(node, event.position, event.input, event.delta)
        end)
    end

    function methods:set(properties)
        element:patch(properties)
        return node
    end

    methods.patch = methods.set

    function methods:destroy()
        element:destroy()
    end

    methods.Destroy = methods.destroy
    methods.Remove = methods.destroy

    function methods:getObject()
        return object
    end

    function methods:paintCaptured(zIndex, callback)
        return canvas:paintCaptured(element, zIndex, callback)
    end

    node = setmetatable({
        callbacks = callbacks,
    }, {
        __index = function(_, key)
            local method = methods[key]
            if method ~= nil then
                return method
            end
            return object[key]
        end,
        __newindex = function(_, key, value)
            element:set(key, value)
        end,
    })
    return node
end

local function createCanvasView(runtime)
    local canvas = runtime:createCanvas()
    local surface = {
        canvas = canvas,
    }

    function surface:create(kind, properties, options)
        local interactive = options ~= nil
            and (options.interactive == true or options.pointerEvents == true)
        return wrapElement(canvas:create(kind, properties, {
            interactive = interactive,
        }), canvas)
    end

    function surface:paint(zIndex, callback)
        return canvas:paint(zIndex, callback)
    end

    function surface:bindInput(inputService)
        return canvas:bindInput(inputService)
    end

    function surface:destroy()
        canvas:destroy()
    end

    return surface
end

local function clampCenteredUtilityLabel(position, viewportSize, textBounds)
    if not viewportSize then
        return position
    end
    local halfWidth = math.max(textBounds and textBounds.X * 0.5 or 0, 32)
    local halfHeight = math.max(textBounds and textBounds.Y * 0.5 or 0, 7)
    local marginX = halfWidth + 4
    local marginY = halfHeight + 4
    return Vector2.new(
        math.clamp(position.X, marginX, math.max(marginX, viewportSize.X - marginX)),
        math.clamp(position.Y, marginY, math.max(marginY, viewportSize.Y - marginY))
    )
end

local function setVisible(nodes, visible)
    for _, node in pairs(nodes) do
        if type(node) == "table" and node.Visible == nil then
            setVisible(node, visible)
        else
            node.Visible = visible
        end
    end
end

function Overlay.new(context)
    assert(context and context.limn, "Hub overlay requires a Limn runtime")
    assert(context.store, "Hub overlay requires a reactive store")

    local primitiveSupport = {}
    for _, kind in ipairs({ "Square", "Circle", "Text", "Triangle", "Quad", "Line" }) do
        primitiveSupport[kind] = context.limn:supportsPrimitive(kind)
    end
    local optionSupport = {
        chams = primitiveSupport.Quad,
    }
    local self = setmetatable({
        activeSliderVisuals = setmetatable({}, { __mode = "k" }),
        captured = false,
        context = context,
        controlColors = setmetatable({}, { __mode = "k" }),
        controls = {},
        destroyed = false,
        observations = {},
        optionSupport = optionSupport,
        primitiveSupport = primitiveSupport,
        playerNodes = {},
        utilityNodes = {},
        chamPaint = {
            enabled = false,
            observations = {},
        },
        utilityZonePaint = {
            enabled = false,
            observations = {},
        },
        worldGui = nil,
    }, Overlay)

    local missingPrimitives = {}
    for _, kind in ipairs({ "Square", "Circle", "Text", "Triangle" }) do
        if not primitiveSupport[kind] then
            table.insert(missingPrimitives, kind)
        end
    end
    self.missingPrimitives = missingPrimitives
    if #missingPrimitives > 0 then
        self.available = false
        warn(
            "[Universal Hub]",
            "overlay disabled; unsupported drawing primitives:",
            table.concat(missingPrimitives, ", ")
        )
        return self
    end

    self.available = true
    self.surface = createCanvasView(context.limn)
    self.canvas = self.surface.canvas
    if context.inputService and not context.worldOnly then
        self.surface:bindInput(context.inputService)
    end
    if not context.worldOnly then
        self:_build()
        local presentationRuntime = context.presentationRuntime.new({
        activeSliderVisuals = self.activeSliderVisuals,
        capabilities = context.capabilities,
        cosmeticsSupported = context.cosmetics ~= false,
        context = context,
        controls = self.controls,
        createKeybindControl = function(options)
            return context.limn:createKeybindControl(self.canvas, options)
        end,
        createSegmentedControl = function(options)
            return context.limn:createSegmentedControl(self.canvas, options)
        end,
        interactive = function(node)
            return self:_interactive(node)
        end,
        node = function(kind, properties, pointerEvents)
            properties = properties or {}
            if properties.Position == nil then
                properties.Position = Vector2.zero
            end
            return self.surface:create(kind, properties, {
                pointerEvents = pointerEvents == true,
            })
        end,
        optionSupport = self.optionSupport,
        refreshVisibility = function()
            self:_setMenuVisible(context.store:Get().menuVisible ~= false)
        end,
        requestLayout = function()
            self:_layout()
        end,
        requestRender = function()
            self:_renderState(context.store:Get())
        end,
        setControlColor = function(node, color)
            self:_setControlColor(node, color)
        end,
        text = function(properties, pointerEvents)
            return self:_text(properties, pointerEvents)
        end,
        theme = COLORS,
    }, context.presentationParts)
        self.presentationHost = context.presentationHost.mount(presentationRuntime, context.presentation)
        self:_layout()
    end
    self.immediateChams = pcall(function()
        self.chamPaintConnection = self.surface:paint(WORLD_LAYER.chams, function(renderer)
            self:_paintChams(renderer)
        end)
    end)
    if self.immediateChams then
        self.optionSupport.chams = true
    end
    self.immediateUtilityZones = pcall(function()
        self.utilityPaintConnection = self.surface:paint(WORLD_LAYER.utilityZone, function(renderer)
            self:_paintUtilityZones(renderer)
        end)
    end)
    if not context.worldOnly then
        self.unsubscribe = context.store:Subscribe(function(state)
            self:_renderState(state)
        end)
    end
    return self
end

function Overlay:_capture(node)
    return node
end

function Overlay:_interactive(node)
    self.controlColors[node] = node.Color
    node:on("pointerenter", function(target)
        if target.Visible then
            target.Color = COLORS.hover
        end
    end)
    node:on("pointerleave", function(target)
        target.Color = self.controlColors[target]
    end)
    return self:_capture(node)
end

function Overlay:_setControlColor(node, color)
    self.controlColors[node] = color
    node.Color = color
end

function Overlay:_text(properties, pointerEvents)
    properties.Font = properties.Font or Drawing.Fonts.Plex
    properties.Visible = properties.Visible ~= false
    if properties.Position == nil then
        properties.Position = Vector2.zero
    end
    return self.surface:create("Text", properties, {
        pointerEvents = pointerEvents == true,
    })
end

function Overlay:_build()
    local surface = self.surface
    local controls = self.controls
    local layoutTokens = PRESENTATION_TOKENS.layout

    controls.panelShadow = surface:create("Square", {
        Color = COLORS.panelShadow,
        Filled = true,
        Size = Vector2.new(layoutTokens.shellWidth, layoutTokens.initialHeight),
        Transparency = 0.32,
        Visible = true,
        ZIndex = 198,
    }, { pointerEvents = false })
    controls.panel = self:_capture(surface:create("Square", {
        Color = COLORS.panel,
        Filled = true,
        Size = Vector2.new(layoutTokens.shellWidth, layoutTokens.initialHeight),
        Transparency = 1,
        Visible = true,
        ZIndex = 200,
    }))
    controls.panelBorder = surface:create("Square", {
        Color = COLORS.border,
        Filled = false,
        Size = Vector2.new(layoutTokens.shellWidth, layoutTokens.initialHeight),
        Thickness = 1,
        Transparency = 0.9,
        Visible = true,
        ZIndex = 206,
    }, { pointerEvents = false })
    controls.headerSurface = surface:create("Square", {
        Color = COLORS.header,
        Filled = true,
        Size = Vector2.new(layoutTokens.shellWidth, layoutTokens.headerHeight),
        Transparency = 1,
        Visible = true,
        ZIndex = 201,
    }, { pointerEvents = false })
    controls.headerRail = surface:create("Square", {
        Color = COLORS.accent,
        Filled = true,
        Size = Vector2.zero,
        Visible = false,
        ZIndex = 202,
    }, { pointerEvents = false })
    controls.panel:on("pointerdown", function(_node, point)
        self.panelDragOffset = point - controls.panel.Position
    end)
    controls.panel:on("drag", function(_node, point)
        if not self.panelDragOffset then
            return
        end
        self.panelPosition = point - self.panelDragOffset
        self:_layout()
    end)
    controls.title = self:_text({
        Color = COLORS.text,
        Size = PRESENTATION_TOKENS.type.header,
        Text = "Universal Hub · " .. (self.context.gameLabel or "Universal"),
        ZIndex = 202,
    })
    controls.status = self:_text({
        Color = COLORS.secondary,
        Size = PRESENTATION_TOKENS.type.status,
        Text = "Inspecting client",
        ZIndex = 202,
    })
    controls.statusDot = surface:create("Circle", {
        Color = COLORS.accent,
        Filled = true,
        NumSides = 20,
        Radius = 3,
        Visible = false,
        ZIndex = 203,
    }, { pointerEvents = false })
end

function Overlay:_layout()
    local camera = self.context.getCamera()
    if not camera then
        return
    end

    local controls = self.controls
    local panelSize = controls.panel.Size
    local layoutTokens = PRESENTATION_TOKENS.layout
    local defaultPosition = Vector2.new(
        math.max(layoutTokens.shellRightInset, camera.ViewportSize.X - panelSize.X - layoutTokens.shellRightInset),
        layoutTokens.shellTopInset
    )
    local requestedPosition = self.panelPosition or defaultPosition
    local x = math.clamp(requestedPosition.X, 0, math.max(0, camera.ViewportSize.X - panelSize.X))
    local y = math.clamp(requestedPosition.Y, 0, math.max(0, camera.ViewportSize.Y - panelSize.Y))
    if self.panelPosition then
        self.panelPosition = Vector2.new(x, y)
    end
    controls.panel.Position = Vector2.new(x, y)
    controls.panelShadow.Position = Vector2.new(x + layoutTokens.shadowX, y + layoutTokens.shadowY)
    controls.panelBorder.Position = Vector2.new(x, y)
    controls.headerSurface.Position = Vector2.new(x, y)
    controls.headerRail.Position = Vector2.new(x, y)
    controls.title.Position = Vector2.new(x + layoutTokens.headerContentInset, y + layoutTokens.titleTop)
    controls.status.Position = Vector2.new(x + layoutTokens.headerContentInset, y + layoutTokens.statusTop)
    controls.statusDot.Position = Vector2.new(
        x + panelSize.X - layoutTokens.statusDotRightInset,
        y + layoutTokens.statusDotTop
    )
    self.presentationHost:layout(x, y)
end

function Overlay:_setMenuVisible(visible)
    local controls = self.controls
    for _, name in ipairs({
        "panel",
        "panelShadow",
        "panelBorder",
        "headerSurface",
        "title",
        "status",
    }) do
        controls[name].Visible = visible
    end
    self.presentationHost:setVisible(visible)
    if self.captured ~= visible then
        self.captured = visible
        if self.context.setInputCaptured then
            self.context.setInputCaptured(visible)
        end
    end
end

function Overlay:_renderState(state)
    if self.destroyed then
        return
    end

    local controls = self.controls
    controls.status.Text = state.status or "Ready"
    controls.status.Color = state.error and COLORS.danger or COLORS.secondary
    controls.statusDot.Color = state.error and COLORS.danger or COLORS.signal
    self:_layout()
    self.presentationHost:render(state)
    self:_layout()
    self.presentationHost:render(state)
    self:_setMenuVisible(state.menuVisible ~= false)
end

function Overlay:_ensureBombBillboard()
    if self.worldGui or not self.context.uiParent then
        return self.worldGui
    end

    local setter = setthreadidentity or setidentity or setthreadcontext
    if type(setter) == "function" then
        pcall(setter, 8)
    end
    local createInstance = self.context.createInstance or Instance.new
    local billboard = createInstance("BillboardGui")
    billboard.Name = "UniversalHubBombTimer"
    billboard.AlwaysOnTop = false
    billboard.Enabled = false
    billboard.LightInfluence = 0
    billboard.MaxDistance = 350
    billboard.Size = UDim2.fromOffset(64, 22)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
    billboard.Parent = self.context.uiParent

    local panel = createInstance("Frame")
    panel.Name = "Panel"
    panel.BackgroundColor3 = COLORS.panel
    panel.BackgroundTransparency = 0.04
    panel.BorderSizePixel = 0
    panel.Size = UDim2.fromScale(1, 1)
    panel.Parent = billboard

    local corner = createInstance("UICorner")
    corner.CornerRadius = UDim.new(0, 3)
    corner.Parent = panel

    local stroke = createInstance("UIStroke")
    stroke.Color = COLORS.border
    stroke.Thickness = 1
    stroke.Parent = panel

    local accent = createInstance("Frame")
    accent.Name = "Accent"
    accent.BackgroundColor3 = COLORS.accent
    accent.BorderSizePixel = 0
    accent.Position = UDim2.fromOffset(4, 4)
    accent.Size = UDim2.new(0, 3, 1, -8)
    accent.Parent = panel

    local title = createInstance("TextLabel")
    title.Name = "Title"
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.Code
    title.Position = UDim2.new(0, 12, 0, 0)
    title.Size = UDim2.new(0.42, -12, 1, 0)
    title.Text = "BOMB"
    title.TextColor3 = COLORS.secondary
    title.TextSize = 10
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = panel

    local timer = createInstance("TextLabel")
    timer.Name = "Timer"
    timer.BackgroundTransparency = 1
    timer.Font = Enum.Font.Code
    timer.Position = UDim2.new(0.42, 0, 0, 0)
    timer.Size = UDim2.new(0.58, -8, 1, 0)
    timer.Text = "0.0s"
    timer.TextColor3 = COLORS.text
    timer.TextSize = 13
    timer.TextXAlignment = Enum.TextXAlignment.Right
    timer.Parent = panel

    self.worldGui = {
        accent = accent,
        billboard = billboard,
        panel = panel,
        stroke = stroke,
        timer = timer,
        title = title,
    }
    return self.worldGui
end

function Overlay:_renderBomb(observation, settings)
    local visible = settings.bombTimer == true
        and type(observation) == "table"
        and observation.visible == true
        and observation.adornee ~= nil
    if not visible then
        if self.worldGui then
            self.worldGui.billboard.Enabled = false
        end
        return
    end

    local gui = self:_ensureBombBillboard()
    if not gui then
        return
    end
    local presentation = observation.presentation or {}
    gui.billboard.Adornee = observation.adornee
    gui.billboard.AlwaysOnTop = presentation.alwaysOnTop == true
    gui.billboard.Enabled = presentation.visible ~= false
    gui.billboard.Size = UDim2.fromOffset(presentation.width or 64, presentation.height or 22)
    local urgent = (observation.remaining or 0) <= 10
    gui.timer.Text = ("%.1fs"):format(math.max(observation.remaining or 0, 0))
    gui.timer.TextColor3 = urgent and COLORS.danger or COLORS.text
    gui.timer.TextSize = presentation.textSize or 13
    gui.accent.BackgroundColor3 = urgent and COLORS.danger or COLORS.accent
    gui.stroke.Color = urgent and COLORS.danger or COLORS.border
end

function Overlay:_getPlayerNodes(player)
    local nodes = self.playerNodes[player]
    if nodes then
        return nodes
    end

    nodes = {
        bodyParts = {},
        nativeHull = {},
        box = self.surface:create("Square", {
            Color = COLORS.danger,
            Filled = false,
            Thickness = 1.5,
            Visible = false,
            ZIndex = WORLD_LAYER.chams,
        }, { pointerEvents = false }),
        name = self:_text({
            Center = true,
            Color = COLORS.text,
            Outline = true,
            Size = 13,
            Text = "",
            Visible = false,
            ZIndex = WORLD_LAYER.player,
        }),
        healthTrack = self.surface:create("Square", {
            Color = COLORS.border,
            Filled = true,
            Visible = false,
            ZIndex = WORLD_LAYER.player,
        }, { pointerEvents = false }),
        healthFill = self.surface:create("Square", {
            Color = COLORS.accent,
            Filled = true,
            Visible = false,
            ZIndex = WORLD_LAYER.health,
        }, { pointerEvents = false }),
        healthTip = self.surface:create("Square", {
            Color = COLORS.text,
            Filled = true,
            Visible = false,
            ZIndex = WORLD_LAYER.playerDetail,
        }, { pointerEvents = false }),
        healthValue = self:_text({
            Center = false,
            Color = COLORS.accent,
            Outline = true,
            Size = 14,
            Text = "",
            Visible = false,
            ZIndex = WORLD_LAYER.playerDetail,
        }),
        weapon = self:_text({
            Center = true,
            Color = COLORS.secondary,
            Outline = true,
            Size = 12,
            Text = "",
            Visible = false,
            ZIndex = WORLD_LAYER.player,
        }),
    }
    self.playerNodes[player] = nodes
    return nodes
end

function Overlay:_syncBodyPartNodes(nodes, count)
    while #nodes.bodyParts < count do
        local cube = {
            faces = {},
        }
        if not self.immediateChams and self.optionSupport.chams ~= false then
            for _faceIndex = 1, #BODY_CUBE_FACES do
                table.insert(
                    cube.faces,
                    self.surface:create("Quad", {
                        Color = COLORS.danger,
                        Filled = true,
                        Transparency = BODY_CUBE_OPACITY,
                        Visible = false,
                        ZIndex = WORLD_LAYER.chams,
                    }, { pointerEvents = false })
                )
            end
        end
        table.insert(nodes.bodyParts, cube)
    end

    for index = count + 1, #nodes.bodyParts do
        setVisible(nodes.bodyParts[index], false)
    end
end

function Overlay:_ensureNativeBodyPartOutlines(cube)
    if cube.outlines or not self.primitiveSupport.Quad then
        return
    end
    cube.outlines = {}
    for _faceIndex = 1, #BODY_CUBE_FACES do
        table.insert(
            cube.outlines,
            self.surface:create("Quad", {
                Color = COLORS.danger,
                Filled = false,
                Thickness = VisualPolicy.OUTLINE_THICKNESS,
                Transparency = 0,
                Visible = false,
                ZIndex = WORLD_LAYER.player,
            }, { pointerEvents = false })
        )
    end
end

function Overlay:_syncNativeHull(nodes, count)
    while #nodes.nativeHull < count do
        table.insert(nodes.nativeHull, self.surface:create("Line", {
            Color = COLORS.danger,
            Thickness = VisualPolicy.OUTLINE_THICKNESS,
            Transparency = 0,
            Visible = false,
            ZIndex = WORLD_LAYER.player,
        }, { pointerEvents = false }))
    end
    for index = count + 1, #nodes.nativeHull do
        nodes.nativeHull[index].Visible = false
    end
end

function Overlay:_getUtilityNodes(index)
    local nodes = self.utilityNodes[index]
    if nodes then
        return nodes
    end

    nodes = {
        marker = self.surface:create("Square", {
            Color = COLORS.accent,
            Filled = false,
            Size = Vector2.new(8, 8),
            Thickness = 1.5,
            Visible = false,
            ZIndex = WORLD_LAYER.utility,
        }, { pointerEvents = false }),
        label = self:_text({
            Center = true,
            Color = COLORS.text,
            Outline = true,
            Size = 12,
            Text = "",
            Visible = false,
            ZIndex = WORLD_LAYER.utilityText,
        }),
    }
    if not self.immediateUtilityZones and self.primitiveSupport.Quad then
        nodes.zones = {}
    end
    self.utilityNodes[index] = nodes
    return nodes
end

function Overlay:_syncUtilityZones(nodes, count)
    if not nodes.zones then
        return
    end
    while #nodes.zones < count do
        table.insert(nodes.zones, self.surface:create("Quad", {
            Color = COLORS.danger,
            Filled = true,
            Transparency = 0.14,
            Visible = false,
            ZIndex = WORLD_LAYER.utilityZone,
        }, { pointerEvents = false }))
    end
    for index = count + 1, #nodes.zones do
        nodes.zones[index].Visible = false
    end
end

function Overlay:_syncUtilityWireframe(nodes, count)
    if not self.primitiveSupport.Line then
        return
    end
    nodes.wireframe = nodes.wireframe or {}
    while #nodes.wireframe < count do
        table.insert(nodes.wireframe, self.surface:create("Line", {
            Color = COLORS.danger,
            Thickness = 2,
            Visible = false,
            ZIndex = WORLD_LAYER.utility,
        }, { pointerEvents = false }))
    end
    for index = count + 1, #nodes.wireframe do
        nodes.wireframe[index].Visible = false
    end
end

function Overlay:_paintChams(renderer)
    local paint = self.chamPaint
    if not paint.enabled then
        return
    end

    for _, observation in ipairs(paint.observations) do
        if observation.previewRenderer ~= "native" and observation.bounds then
            for _, bodyPart in ipairs(observation.bodyParts or {}) do
                local corners = bodyPart.corners
                local eligiblePart = not (observation.previewRenderer == "native"
                    and paint.excludeAccessories == true
                    and bodyPart.accessory == true)
                if eligiblePart and type(corners) == "table" and #corners == 8 then
                    local fallbackColor = observation.previewRenderer == "native"
                        and (observation.tone == "team"
                            and VisualPolicy.COLORS.team
                            or VisualPolicy.COLORS.danger)
                        or playerColor(observation, bodyPart.visible)
                    local color = ColorPolicy.color(paint.settings, "fill", fallbackColor, observation.tone)
                    for _, cornerIndices in ipairs(BODY_CUBE_FACES) do
                        local pointA = corners[cornerIndices[1]]
                        local pointB = corners[cornerIndices[2]]
                        local pointC = corners[cornerIndices[3]]
                        local pointD = corners[cornerIndices[4]]
                        local transparency = ColorPolicy.fillAlpha(
                            paint.settings,
                            observation.previewRenderer == "native"
                                and (1 - NATIVE_PREVIEW_FILL_TRANSPARENCY)
                                or BODY_CUBE_OPACITY,
                            observation.tone
                        )
                        renderer.FilledQuad(pointA, pointB, pointC, pointD, color, transparency)
                    end
                end
            end
        end
    end
end

function Overlay:_paintUtilityZones(renderer)
    local paint = self.utilityZonePaint
    if not paint.enabled then
        return
    end

    for _, observation in ipairs(paint.observations) do
        local tone = observation.tone
        local color = tone == "danger" and COLORS.danger
            or (tone == "smoke" and COLORS.secondary or COLORS.signal)
        local opacity = tone == "smoke" and 0.08 or 0.14
        for _, polygon in ipairs(observation.polygons or {}) do
            if type(polygon) == "table" and #polygon == 4 then
                renderer.FilledTriangle(polygon[1], polygon[2], polygon[3], color, opacity)
                renderer.FilledTriangle(polygon[1], polygon[3], polygon[4], color, opacity)
            end
        end
    end
end

function Overlay:_renderUtilities(observations, enabled)
    observations = observations or {}
    self.utilityZonePaint.enabled = enabled == true
    self.utilityZonePaint.observations = observations
    for index, observation in ipairs(observations) do
        local nodes = self:_getUtilityNodes(index)
        local tone = observation.tone
        local color = tone == "danger" and COLORS.danger
            or (tone == "smoke" and COLORS.secondary or COLORS.signal)
        local corners = observation.wireframeCorners
        local wireframeVisible = enabled
            and self.primitiveSupport.Line
            and observation.markerStyle == "wireframeCube"
            and observation.onScreen == true
            and type(corners) == "table"
            and #corners == 8
        local markerVisible = enabled
            and not wireframeVisible
            and observation.onScreen == true
            and observation.screenPosition ~= nil
        local labelPosition
        if markerVisible then
            nodes.marker.Position = observation.screenPosition - Vector2.new(4, 4)
            labelPosition = observation.screenPosition + Vector2.new(0, 8)
        elseif wireframeVisible then
            labelPosition = observation.labelPosition
                or (observation.screenPosition - Vector2.new(0, 16))
        end
        if wireframeVisible then
            self:_syncUtilityWireframe(nodes, #UTILITY_CUBE_EDGES)
            for edgeIndex, cornerIndices in ipairs(UTILITY_CUBE_EDGES) do
                local edge = nodes.wireframe[edgeIndex]
                edge.From = corners[cornerIndices[1]]
                edge.To = corners[cornerIndices[2]]
                edge.Color = color
                edge.Visible = true
            end
        elseif nodes.wireframe then
            for _, edge in ipairs(nodes.wireframe) do
                edge.Visible = false
            end
        end
        nodes.marker.Color = color
        nodes.marker.Visible = markerVisible
        nodes.label.Color = wireframeVisible and COLORS.text or color
        nodes.label.Size = wireframeVisible and 14 or 12
        nodes.label.Text = observation.label or ""
        if wireframeVisible and labelPosition then
            local camera = self.context.getCamera()
            labelPosition = clampCenteredUtilityLabel(
                labelPosition,
                camera and camera.ViewportSize,
                nodes.label.TextBounds
            )
        end
        if labelPosition then
            nodes.label.Position = labelPosition
        end
        nodes.label.Visible = markerVisible or wireframeVisible

        local polygons = enabled and observation.polygons or {}
        if not self.immediateUtilityZones and nodes.zones then
            self:_syncUtilityZones(nodes, #polygons)
            for polygonIndex, polygon in ipairs(polygons) do
                local zone = nodes.zones[polygonIndex]
                local visible = type(polygon) == "table" and #polygon == 4
                if visible then
                    zone.PointA = polygon[1]
                    zone.PointB = polygon[2]
                    zone.PointC = polygon[3]
                    zone.PointD = polygon[4]
                end
                zone.Color = color
                zone.Transparency = tone == "smoke" and 0.08 or 0.14
                zone.Visible = visible
            end
        end
    end

    for index = #observations + 1, #self.utilityNodes do
        setVisible(self.utilityNodes[index], false)
    end
end

function Overlay:render(observations, mousePosition, utilityObservations)
    if self.destroyed or not self.available then
        return
    end

    observations = observations or {}
    self.observations = observations
    local state = self.context.store:Get()
    local settings = state.settings
    self.chamPaint.enabled = self.immediateChams
        and settings.chams == true
        and self.optionSupport.chams ~= false
    self.chamPaint.observations = observations
    self.chamPaint.excludeAccessories = settings.chamsExcludeAccessories == true
    self.chamPaint.settings = settings
    self:_renderBomb(state.bombObservation, settings)
    if self.presentationHost then
        self.presentationHost:setMousePosition(mousePosition)
    end
    local seen = {}

    for _, observation in ipairs(observations) do
        if observation.bounds then
            local nodes = self:_getPlayerNodes(observation.player)
            local bounds = observation.bounds
            local visible = observation.visible == true
            local nativePreview = observation.previewRenderer == "native"
            local nativeColor = observation.tone == "team"
                and VisualPolicy.COLORS.team
                or VisualPolicy.COLORS.danger
            local fallbackColor = nativePreview and nativeColor or playerColor(observation, visible)
            local outlineColor = ColorPolicy.color(settings, "outline", fallbackColor, observation.tone)
            local nameColor = ColorPolicy.color(settings, "name", fallbackColor, observation.tone)
            local weaponColor = ColorPolicy.color(settings, "weapon", fallbackColor, observation.tone)
            local bodyParts = observation.bodyParts or {}
            local perPartPreview = settings.chamsPerPart == true
                or settings.chamsExcludeAccessories == true
            local hullPoints = {}
            seen[observation.player] = true

            self:_syncBodyPartNodes(nodes, #bodyParts)
            for index, bodyPart in ipairs(bodyParts) do
                local cube = nodes.bodyParts[index]
                local corners = bodyPart.corners
                local validCorners = type(corners) == "table" and #corners == 8
                local eligiblePart = not (nativePreview
                    and settings.chamsExcludeAccessories == true
                    and bodyPart.accessory == true)
                local cubeVisible = settings.chams == true
                    and not nativePreview
                    and self.optionSupport.chams ~= false
                    and validCorners
                    and eligiblePart
                local outlineVisible = nativePreview
                    and perPartPreview
                    and settings.boxes == true
                    and validCorners
                    and eligiblePart
                if nativePreview and not perPartPreview and settings.boxes == true
                    and validCorners and eligiblePart
                then
                    for _, point in ipairs(corners) do
                        table.insert(hullPoints, point)
                    end
                end
                local cubeFallback = nativePreview
                    and nativeColor
                    or playerColor(observation, bodyPart.visible)
                local cubeColor = nativePreview
                    and ColorPolicy.color(settings, "outline", cubeFallback, observation.tone)
                    or ColorPolicy.color(settings, "fill", cubeFallback, observation.tone)

                if not self.immediateChams then
                    for faceIndex, cornerIndices in ipairs(BODY_CUBE_FACES) do
                        local face = cube.faces[faceIndex]
                        if face and cubeVisible then
                            face.PointA = corners[cornerIndices[1]]
                            face.PointB = corners[cornerIndices[2]]
                            face.PointC = corners[cornerIndices[3]]
                            face.PointD = corners[cornerIndices[4]]
                        end
                        if face then
                            face.Color = cubeColor
                            face.Transparency = ColorPolicy.fillAlpha(
                                settings,
                                nativePreview and (1 - NATIVE_PREVIEW_FILL_TRANSPARENCY) or BODY_CUBE_OPACITY,
                                observation.tone
                            )
                            face.Visible = cubeVisible
                        end
                    end
                end

                if nativePreview then
                    self:_ensureNativeBodyPartOutlines(cube)
                end
                for faceIndex, outline in ipairs(cube.outlines or {}) do
                    local cornerIndices = BODY_CUBE_FACES[faceIndex]
                    if outlineVisible then
                        outline.PointA = corners[cornerIndices[1]]
                        outline.PointB = corners[cornerIndices[2]]
                        outline.PointC = corners[cornerIndices[3]]
                        outline.PointD = corners[cornerIndices[4]]
                    end
                    outline.Color = cubeColor
                    outline.Visible = outlineVisible
                end
            end

            local hull = nativePreview and not perPartPreview and convexHull(hullPoints) or {}
            self:_syncNativeHull(nodes, #hull)
            for index, line in ipairs(nodes.nativeHull) do
                local visibleHull = index <= #hull and #hull >= 3
                if visibleHull then
                    line.From = hull[index]
                    line.To = hull[index % #hull + 1]
                end
                line.Color = outlineColor
                line.Visible = visibleHull
            end

            nodes.box.Position = bounds.position
            nodes.box.Size = bounds.size
            nodes.box.Color = outlineColor
            nodes.box.Visible = settings.boxes == true and not nativePreview

            nodes.name.Position = Vector2.new(bounds.position.X + bounds.size.X * 0.5, bounds.position.Y - 15)
            nodes.name.Color = nameColor
            nodes.name.Text = observation.player.Name
            nodes.name.Visible = settings.names == true

            local maximumHealth = math.max(observation.maxHealth or 100, 1)
            local healthFraction = math.clamp((observation.health or 0) / maximumHealth, 0, 1)
            local innerHeight = math.max(bounds.size.Y - 2, 0)
            local fillHeight = innerHeight * healthFraction
            nodes.healthTrack.Position = Vector2.new(bounds.position.X - 10, bounds.position.Y)
            nodes.healthTrack.Size = Vector2.new(6, bounds.size.Y)
            nodes.healthTrack.Visible = settings.health == true
            nodes.healthFill.Position =
                Vector2.new(bounds.position.X - 9, bounds.position.Y + 1 + innerHeight - fillHeight)
            nodes.healthFill.Size = Vector2.new(4, fillHeight)
            nodes.healthFill.Color = ColorPolicy.healthColor(settings, healthFraction, COLORS.danger, COLORS.signal, observation.tone)
            nodes.healthFill.Visible = settings.health == true and fillHeight > 0
            nodes.healthTip.Position = Vector2.new(bounds.position.X - 10, nodes.healthFill.Position.Y - 1)
            nodes.healthTip.Size = Vector2.new(6, 2)
            nodes.healthTip.Visible = settings.health == true and fillHeight > 0
            nodes.healthValue.Position = Vector2.new(
                bounds.position.X,
                bounds.position.Y + bounds.size.Y + 3
            )
            nodes.healthValue.Color = nodes.healthFill.Color
            nodes.healthValue.Text = ("%d HP"):format(math.ceil(observation.health or 0))
            nodes.healthValue.Visible = settings.health == true and fillHeight > 0

            nodes.weapon.Position = Vector2.new(
                bounds.position.X + bounds.size.X * 0.5,
                bounds.position.Y + bounds.size.Y + 18
            )
            nodes.weapon.Text = observation.weapon or ""
            nodes.weapon.Color = weaponColor
            nodes.weapon.Visible = settings.weapon == true and observation.weapon ~= nil
        end
    end

    for player, nodes in pairs(self.playerNodes) do
        if not seen[player] then
            setVisible(nodes, false)
        end
    end
    self:_renderUtilities(utilityObservations, settings.utilityEsp == true)
end

function Overlay:isCaptured()
    return self.captured
end

function Overlay:destroy()
    if self.destroyed then
        return
    end
    self.destroyed = true

    if not self.context.worldOnly and self.context.setInputCaptured then
        self.context.setInputCaptured(false)
    end
    if self.unsubscribe then
        self.unsubscribe()
    end
    if self.worldGui then
        self.worldGui.billboard:Destroy()
        self.worldGui = nil
    end
    if self.chamPaintConnection then
        self.chamPaintConnection:Disconnect()
        self.chamPaintConnection = nil
    end
    if self.utilityPaintConnection then
        self.utilityPaintConnection:Disconnect()
        self.utilityPaintConnection = nil
    end
    if self.presentationHost then
        self.presentationHost:destroy()
        self.presentationHost = nil
    end
    if self.surface then
        self.surface:destroy()
        self.surface = nil
        self.canvas = nil
    end
    table.clear(self.playerNodes)
    table.clear(self.utilityNodes)
end

return Overlay
]=],
    ["ui/esp/HighlightRenderer.lua"] = [=[local VisualPolicy = require("./VisualPolicy")
local ColorPolicy = require("./ColorPolicy")
local HighlightRenderer = {}
HighlightRenderer.__index = HighlightRenderer

local function restoreExecutorThread()
    local setter = setthreadidentity or setidentity or setthreadcontext
    if type(setter) == "function" then
        pcall(setter, 8)
    end
end

local function onExecutorThread(callback)
    if type(callback) ~= "function" then
        return callback
    end
    return function(...)
        restoreExecutorThread()
        return callback(...)
    end
end

-- A hard cap keeps adversarial character hierarchies from producing unbounded Instances.
HighlightRenderer.HIGHLIGHT_BUDGET = 255
HighlightRenderer.SUBJECT_HIGHLIGHT_BUDGET = 17
HighlightRenderer.HIGHLIGHT_DISTANCE = 1000
HighlightRenderer.HIGHLIGHT_DISTANCE_HYSTERESIS = 100
HighlightRenderer.DISTANCE_REFRESH_INTERVAL = 0.25

local COLORS = VisualPolicy.COLORS

local function disconnect(connection)
    if type(connection) == "function" then
        connection()
    elseif connection then
        connection:Disconnect()
    end
end

local function clearConnections(connections)
    if not connections then
        return
    end
    for _, connection in ipairs(connections) do
        disconnect(connection)
    end
    table.clear(connections)
end

local function hold(connections, handle)
    if handle then
        table.insert(connections, handle)
    end
end

local function safeDestroy(instance)
    if instance then
        instance:Destroy()
    end
end

local function findChild(character, className, name)
    if not character then
        return nil
    end
    if character.FindFirstChildOfClass then
        local child = character:FindFirstChildOfClass(className)
        if child then
            return child
        end
    end
    if name and character.FindFirstChild then
        return character:FindFirstChild(name)
    end
    return nil
end

local function label(create, parent, name, size, color, position)
    local node = create("TextLabel")
    node.Name = name
    node.AnchorPoint = Vector2.new(0.5, 0)
    node.BackgroundTransparency = 1
    node.BorderSizePixel = 0
    node.Font = Enum.Font.GothamBold
    node.Position = position
    node.Size = UDim2.new(1, -20, 0, size + 3)
    node.TextColor3 = color
    node.TextScaled = false
    node.TextSize = size
    node.TextStrokeColor3 = Color3.new(0, 0, 0)
    node.TextStrokeTransparency = 0.2
    node.TextTruncate = Enum.TextTruncate.None
    node.TextXAlignment = Enum.TextXAlignment.Center
    node.TextYAlignment = Enum.TextYAlignment.Center
    node.Parent = parent
    return node
end

function HighlightRenderer.new(context)
    assert(context and context.guiParent, "HighlightRenderer requires guiParent")
    assert(context.store, "HighlightRenderer requires a store")
    assert(context.players, "HighlightRenderer requires Players")
    assert(
        context.runService and context.runService.Heartbeat,
        "HighlightRenderer requires RunService.Heartbeat"
    )

    local rawCreate = context.createInstance or Instance.new
    local self = setmetatable({
        context = context,
        create = function(...)
            restoreExecutorThread()
            return rawCreate(...)
        end,
        policy = {},
        subjects = {},
        extraKeys = {},
        playerConnections = {},
        playerPolicyConnections = {},
        policyConnections = {},
        active = false,
        destroyed = false,
        highlightCount = 0,
        nextSubjectOrder = 0,
        distanceAccumulator = 0,
    }, HighlightRenderer)

    self.unsubscribe = context.store:Subscribe(onExecutorThread(function(state)
        self:_applyState(state)
    end))
    return self
end

function HighlightRenderer:_settings()
    local state = self.context.store:Get()
    return state.settings or {}
end

function HighlightRenderer:_ensureRoot()
    restoreExecutorThread()
    if self.root then
        return self.root
    end
    local root = self.create("Folder")
    root.Name = "UniversalHubNativeWorld"
    root.Parent = self.context.guiParent
    self.root = root
    return root
end

function HighlightRenderer:_playerTone(player, character)
    local getter = self.policy.getPlayerTone
    if getter then
        local ok, tone = pcall(getter, player, character)
        return ok and tone or nil, true
    end
    local predicate = self.policy.isPlayerEligible
    if not predicate then
        return "enemy", false
    end
    local ok, eligible = pcall(predicate, player, character)
    return ok and eligible == true and "enemy" or nil, false
end

function HighlightRenderer:_eligible(player, character)
    if player == self.context.localPlayer or player == self.context.players.LocalPlayer then
        return false, nil
    end
    local tone, declared = self:_playerTone(player, character)
    if declared then
        local settings = self:_settings()
        local selected = tone == "team" and settings.showTeammates == true
            or tone ~= "team" and settings.showEnemies ~= false
        return tone ~= nil and selected, tone
    end
    return tone ~= nil, tone
end

local function isA(instance, className)
    return instance and instance.IsA and instance:IsA(className) == true
end

function HighlightRenderer:_newHighlight(subject, adornee)
    restoreExecutorThread()
    if
        self.highlightCount >= HighlightRenderer.HIGHLIGHT_BUDGET
        or #subject.highlights >= (subject.highlightBudget or 1)
    then
        return nil
    end
    local highlight = self.create("Highlight")
    highlight.Name = "SubjectHighlight"
    highlight.Adornee = adornee
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = self:_ensureRoot()
    table.insert(subject.highlights, highlight)
    self.highlightCount = self.highlightCount + 1
    return highlight
end

function HighlightRenderer:_clearHighlights(subject)
    for _, highlight in ipairs(subject.highlights) do
        safeDestroy(highlight)
        self.highlightCount = math.max(0, self.highlightCount - 1)
    end
    table.clear(subject.highlights)
end

function HighlightRenderer:_configureHighlights(subject)
    local settings = self:_settings()
    local perPart = (settings.boxes == true or settings.chams == true)
        and settings.chamsPerPart == true
    local excludeAccessories = settings.chamsExcludeAccessories == true
    if
        subject.highlightConfigured
        and subject.perPart == perPart
        and subject.excludeAccessories == excludeAccessories
        and (
            #subject.highlights > 0
            or (perPart and (subject.highlightBudget or 0) <= 0)
            or not (settings.boxes == true or settings.chams == true)
        )
    then
        return
    end
    subject.highlightConfigured = true
    subject.perPart = perPart
    subject.excludeAccessories = excludeAccessories
    clearConnections(subject.hierarchyConnections)
    subject.rebuildHighlights = nil
    self:_clearHighlights(subject)

    if not perPart then
        subject.perPartApplied = false
        subject.highlightBudget = 1
        self:_newHighlight(subject, subject.character)
        return
    end
    if (subject.highlightBudget or 0) <= 0 then
        subject.perPartApplied = false
        return
    end

    subject.perPartApplied = true
    local function rebuild()
        restoreExecutorThread()
        if not self.active or not self.subjects[subject.key] then
            return
        end
        self:_clearHighlights(subject)
        local bodyParts = {}
        local accessoryParts = {}
        if subject.character.GetDescendants then
            for _, descendant in ipairs(subject.character:GetDescendants()) do
                if isA(descendant, "BasePart") then
                    local accessoryOwned = false
                    local ancestor = descendant.Parent
                    while ancestor and ancestor ~= subject.character do
                        if isA(ancestor, "Accessory") then
                            accessoryOwned = true
                            break
                        end
                        ancestor = ancestor.Parent
                    end
                    table.insert(accessoryOwned and accessoryParts or bodyParts, descendant)
                end
            end
        else
            local children = subject.character.GetChildren and subject.character:GetChildren() or {}
            for _, child in ipairs(children) do
                if isA(child, "BasePart") then
                    table.insert(bodyParts, child)
                elseif isA(child, "Accessory") then
                    local handle = child.FindFirstChild and child:FindFirstChild("Handle")
                    if isA(handle, "BasePart") then
                        table.insert(accessoryParts, handle)
                    end
                end
            end
        end
        for _, part in ipairs(bodyParts) do
            self:_newHighlight(subject, part)
        end
        if not excludeAccessories then
            for _, part in ipairs(accessoryParts) do
                self:_newHighlight(subject, part)
            end
        end
        self:_styleHighlights(subject)
    end
    subject.rebuildHighlights = rebuild
    local descendantAdded = subject.character.DescendantAdded or subject.character.ChildAdded
    local descendantRemoving = subject.character.DescendantRemoving
        or subject.character.ChildRemoved
    if descendantAdded then
        table.insert(
            subject.hierarchyConnections,
            descendantAdded:Connect(onExecutorThread(rebuild))
        )
    end
    if descendantRemoving then
        table.insert(
            subject.hierarchyConnections,
            descendantRemoving:Connect(onExecutorThread(rebuild))
        )
    end
    rebuild()
end

function HighlightRenderer:_perPartRelevant(settings)
    return self.active
        and (settings.boxes == true or settings.chams == true)
        and settings.chamsPerPart == true
end

function HighlightRenderer:_localRootPart()
    local localPlayer = self.context.localPlayer or self.context.players.LocalPlayer
    local character = localPlayer and localPlayer.Character
    if not character then
        return nil
    end
    local namedRoot = character.FindFirstChild and character:FindFirstChild("HumanoidRootPart")
    return character.PrimaryPart or namedRoot or findChild(character, "BasePart")
end

local function distanceSquared(first, second)
    if not first or not second or first.Position == nil or second.Position == nil then
        return nil
    end
    local ok, displacement = pcall(function()
        return first.Position - second.Position
    end)
    if not ok or displacement == nil then
        return nil
    end
    local magnitude = displacement.Magnitude
    return type(magnitude) == "number" and magnitude * magnitude or nil
end

function HighlightRenderer:_refreshHighlightDistances()
    if not self:_perPartRelevant(self:_settings()) then
        return
    end
    local localRoot = self:_localRootPart()
    local enterDistanceSquared = HighlightRenderer.HIGHLIGHT_DISTANCE ^ 2
    local exitDistanceSquared = (
        HighlightRenderer.HIGHLIGHT_DISTANCE
        + HighlightRenderer.HIGHLIGHT_DISTANCE_HYSTERESIS
    ) ^ 2
    local candidates = {}
    for _, subject in pairs(self.subjects) do
        local subjectDistanceSquared = distanceSquared(localRoot, subject.rootPart)
        local threshold = subject.withinHighlightDistance and exitDistanceSquared
            or enterDistanceSquared
        subject.withinHighlightDistance = subjectDistanceSquared ~= nil
            and subjectDistanceSquared <= threshold
        subject.highlightDistanceSquared = subjectDistanceSquared
        if subject.withinHighlightDistance then
            table.insert(candidates, subject)
        end
    end
    table.sort(candidates, function(first, second)
        if first.highlightDistanceSquared == second.highlightDistanceSquared then
            return first.order < second.order
        end
        return first.highlightDistanceSquared < second.highlightDistanceSquared
    end)

    local poolCount = math.min(#candidates, HighlightRenderer.HIGHLIGHT_BUDGET)
    local baseBudget = poolCount > 0
            and math.min(
                HighlightRenderer.SUBJECT_HIGHLIGHT_BUDGET,
                math.floor(HighlightRenderer.HIGHLIGHT_BUDGET / poolCount)
            )
        or 0
    local remainder = baseBudget < HighlightRenderer.SUBJECT_HIGHLIGHT_BUDGET
            and HighlightRenderer.HIGHLIGHT_BUDGET - baseBudget * poolCount
        or 0
    local budgets = {}
    for index = 1, poolCount do
        budgets[candidates[index]] = baseBudget + (index <= remainder and 1 or 0)
    end
    local budgetChanged = {}
    for _, subject in pairs(self.subjects) do
        local nextBudget = budgets[subject] or 0
        if subject.highlightBudget ~= nextBudget then
            subject.highlightBudget = nextBudget
            subject.highlightConfigured = false
            table.insert(budgetChanged, subject)
        end
    end
    -- Release changed allocations before rebuilding so table iteration order cannot
    -- let an old, farther allocation starve a newly nearer subject at the hard cap.
    for _, subject in ipairs(budgetChanged) do
        self:_clearHighlights(subject)
    end
    for _, subject in pairs(self.subjects) do
        self:_configureHighlights(subject)
    end
end

function HighlightRenderer:_stopDistanceRefresh()
    disconnect(self.distanceConnection)
    self.distanceConnection = nil
    self.distanceAccumulator = 0
end

function HighlightRenderer:_syncDistanceRefresh()
    if not self:_perPartRelevant(self:_settings()) then
        self:_stopDistanceRefresh()
        for _, subject in pairs(self.subjects) do
            subject.withinHighlightDistance = nil
            subject.highlightDistanceSquared = nil
        end
        return
    end
    if self.distanceConnection then
        return
    end
    self:_refreshHighlightDistances()
    self.distanceConnection =
        self.context.runService.Heartbeat:Connect(onExecutorThread(function(deltaTime)
            if not self:_perPartRelevant(self:_settings()) then
                self:_stopDistanceRefresh()
                return
            end
            self.distanceAccumulator += deltaTime
            if self.distanceAccumulator < HighlightRenderer.DISTANCE_REFRESH_INTERVAL then
                return
            end
            self.distanceAccumulator %= HighlightRenderer.DISTANCE_REFRESH_INTERVAL
            self:_refreshHighlightDistances()
        end))
end

function HighlightRenderer:_rebalanceHighlights()
    if not self.active then
        return
    end
    if self:_perPartRelevant(self:_settings()) then
        self:_refreshHighlightDistances()
        return
    end
    for _, subject in pairs(self.subjects) do
        if subject.highlightBudget ~= 1 then
            subject.highlightBudget = 1
            subject.highlightConfigured = false
        end
        self:_configureHighlights(subject)
    end
end

function HighlightRenderer:_styleHighlights(subject, color)
    restoreExecutorThread()
    local settings = self:_settings()
    color = color or subject.highlightColor or COLORS.danger
    subject.highlightColor = color
    local outlineColor = ColorPolicy.color(settings, "outline", color, subject.tone)
    local fillColor = ColorPolicy.color(settings, "fill", color, subject.tone)
    local fillAlpha =
        ColorPolicy.fillAlpha(settings, 1 - VisualPolicy.FILL_TRANSPARENCY, subject.tone)
    for _, highlight in ipairs(subject.highlights) do
        highlight.Enabled = settings.boxes == true or settings.chams == true
        highlight.OutlineColor = outlineColor
        highlight.OutlineTransparency = settings.boxes == true and 0 or 1
        highlight.FillColor = fillColor
        highlight.FillTransparency = settings.chams == true and 1 - fillAlpha or 1
    end
end

function HighlightRenderer:_connectCharacterPolicy(subject)
    clearConnections(subject.policyConnections)
    local connector = subject.player and self.policy.connectCharacterChanged
    if connector then
        hold(
            subject.policyConnections,
            connector(
                subject.player,
                subject.character,
                onExecutorThread(function()
                    if self.active and self.subjects[subject.key] == subject then
                        self:_invalidatePlayer(subject.player)
                    end
                end)
            )
        )
    end
end

function HighlightRenderer:_makeSubject(key, descriptor, player)
    restoreExecutorThread()
    if not self.active or self.subjects[key] or not descriptor or not descriptor.character then
        return nil
    end
    local tone
    if player then
        local eligible
        eligible, tone = self:_eligible(player, descriptor.character)
        if not eligible then
            return nil
        end
    end

    local character = descriptor.character
    local humanoid = descriptor.humanoid or findChild(character, "Humanoid", "Humanoid")
    local namedRoot = character.FindFirstChild and character:FindFirstChild("HumanoidRootPart")
    local rootPart = descriptor.rootPart
        or character.PrimaryPart
        or namedRoot
        or findChild(character, "BasePart")

    self:_ensureRoot()
    local billboard = self.create("BillboardGui")
    billboard.Name = "SubjectBillboard"
    billboard.Adornee = rootPart
    billboard.AlwaysOnTop = true
    billboard.ClipsDescendants = false
    billboard.LightInfluence = 0
    billboard.MaxDistance = HighlightRenderer.HIGHLIGHT_DISTANCE
    billboard.ResetOnSpawn = false
    billboard.Size = UDim2.fromOffset(240, 132)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.25, 0)
    billboard.Enabled = false
    billboard.Parent = self.context.guiParent

    local canvas = self.create("Frame")
    canvas.Name = "BodyCanvas"
    canvas.BackgroundTransparency = 1
    canvas.BorderSizePixel = 0
    canvas.Size = UDim2.fromScale(1, 1)
    canvas.Parent = billboard

    local name = label(self.create, canvas, "Name", 13, COLORS.text, UDim2.new(0.5, 0, 0, -10))
    local healthValue =
        label(self.create, canvas, "HealthValue", 12, COLORS.signal, UDim2.new(0.5, 0, 0, 106))
    local weapon =
        label(self.create, canvas, "Weapon", 12, COLORS.secondary, UDim2.new(0.5, 0, 0, 122))

    local healthTrack = self.create("Frame")
    healthTrack.Name = "HealthRail"
    healthTrack.BackgroundColor3 = COLORS.track
    healthTrack.BorderSizePixel = 0
    healthTrack.Position = UDim2.new(0.5, -34, 0, 20)
    healthTrack.Size = UDim2.fromOffset(6, 76)
    healthTrack.Parent = canvas

    local trackCorner = self.create("UICorner")
    trackCorner.CornerRadius = UDim.new(0, 3)
    trackCorner.Parent = healthTrack

    local railStroke = self.create("UIStroke")
    railStroke.Color = Color3.fromRGB(12, 14, 16)
    railStroke.Thickness = 1
    railStroke.Parent = healthTrack

    local healthFill = self.create("Frame")
    healthFill.Name = "Fill"
    healthFill.AnchorPoint = Vector2.new(0, 1)
    healthFill.BackgroundColor3 = COLORS.signal
    healthFill.BorderSizePixel = 0
    healthFill.Position = UDim2.new(0, 1, 1, 0)
    healthFill.Size = UDim2.new(0, 4, 1, 0)
    healthFill.Parent = healthTrack

    local fillCorner = self.create("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 3)
    fillCorner.Parent = healthFill

    self.nextSubjectOrder += 1
    local subject = {
        key = key,
        order = self.nextSubjectOrder,
        highlightBudget = 0,
        player = player,
        character = character,
        humanoid = humanoid,
        rootPart = rootPart,
        descriptor = descriptor,
        connections = {},
        policyConnections = {},
        hierarchyConnections = {},
        highlights = {},
        billboard = billboard,
        canvas = canvas,
        name = name,
        healthValue = healthValue,
        weapon = weapon,
        healthTrack = healthTrack,
        healthFill = healthFill,
        presentation = {},
        tone = tone,
    }
    self.subjects[key] = subject
    self:_rebalanceHighlights()
    self:_connectCharacterPolicy(subject)

    if humanoid then
        if humanoid.HealthChanged then
            table.insert(
                subject.connections,
                humanoid.HealthChanged:Connect(onExecutorThread(function()
                    self:_updateHealth(subject)
                end))
            )
        elseif humanoid.GetPropertyChangedSignal then
            table.insert(
                subject.connections,
                humanoid:GetPropertyChangedSignal("Health"):Connect(onExecutorThread(function()
                    self:_updateHealth(subject)
                end))
            )
        end
        if humanoid.GetPropertyChangedSignal then
            table.insert(
                subject.connections,
                humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(onExecutorThread(function()
                    self:_updateHealth(subject)
                end))
            )
        end
    end
    self:_updateSubject(subject)
    return subject
end

function HighlightRenderer:_removeSubject(key)
    restoreExecutorThread()
    local subject = self.subjects[key]
    if not subject then
        return
    end
    self.subjects[key] = nil
    clearConnections(subject.connections)
    clearConnections(subject.policyConnections)
    clearConnections(subject.hierarchyConnections)
    self:_clearHighlights(subject)
    safeDestroy(subject.billboard)
    self:_rebalanceHighlights()
end

function HighlightRenderer:_weapon(subject, observation)
    if observation and observation.weapon ~= nil then
        return observation.weapon
    end
    if subject.descriptor.weapon ~= nil then
        return subject.descriptor.weapon
    end
    local getter = self.policy.getWeapon
    if getter then
        local ok, value = pcall(getter, subject.player, subject.character, observation)
        if ok then
            return value
        end
    end
    return nil
end

function HighlightRenderer:_updateHealth(subject, observation)
    if not self.active or not self.subjects[subject.key] then
        return
    end
    local humanoid = subject.humanoid
    local health = observation and observation.health
    if type(health) ~= "number" then
        health = humanoid and humanoid.Health or 0
    end
    local maximum = observation and observation.maxHealth
    if type(maximum) ~= "number" then
        maximum = humanoid and humanoid.MaxHealth or 0
    end
    local finite = health == health
        and maximum == maximum
        and health ~= math.huge
        and health ~= -math.huge
        and maximum ~= math.huge
        and maximum ~= -math.huge
    local fraction
    if finite and maximum > 0 then
        fraction = math.clamp(health / maximum, 0, 1)
    else
        fraction = 0
    end
    local color = ColorPolicy.healthColor(
        self:_settings(),
        fraction,
        COLORS.danger,
        COLORS.signal,
        subject.tone
    )
    subject.healthFill.Size = UDim2.new(0, 4, fraction, 0)
    subject.healthFill.BackgroundColor3 = color
    subject.healthValue.TextColor3 = color
    subject.healthValue.Text = finite and ("%d HP"):format(math.ceil(health)) or ""
    subject.healthTrack.Visible = self:_settings().health == true and finite
    subject.healthValue.Visible = self:_settings().health == true and finite
end

function HighlightRenderer:_updateSubject(subject, observation)
    restoreExecutorThread()
    local settings = self:_settings()
    local presentation = observation and observation.presentation or subject.presentation or {}
    subject.presentation = presentation
    local tone = observation and observation.tone or subject.tone
    local color = presentation.color
        or (tone and COLORS[tone])
        or ((observation and observation.visible == true) and COLORS.signal or COLORS.danger)

    self:_configureHighlights(subject)
    self:_styleHighlights(subject, color)

    subject.name.Text = presentation.name
        or subject.descriptor.name
        or (subject.player and subject.player.Name)
        or tostring(subject.key)
    subject.name.TextColor3 = ColorPolicy.color(settings, "name", color, tone)
    subject.name.Visible = settings.names == true
    local hasHealth = subject.humanoid ~= nil
        or (observation and type(observation.health) == "number")
    subject.healthTrack.Visible = settings.health == true and hasHealth
    subject.healthValue.Visible = settings.health == true and hasHealth
    local weapon = self:_weapon(subject, observation)
    subject.weapon.Text = weapon == nil and "" or tostring(weapon)
    subject.weapon.TextColor3 = ColorPolicy.color(settings, "weapon", color, tone)
    subject.weapon.Visible = settings.weapon == true and weapon ~= nil and tostring(weapon) ~= ""
    self:_updateHealth(subject, observation)
    subject.billboard.Enabled = observation ~= nil
        and subject.rootPart ~= nil
        and (subject.name.Visible or subject.healthTrack.Visible or subject.weapon.Visible)
end

function HighlightRenderer:_attachCharacter(player, character)
    self:_removeSubject(player)
    self:_makeSubject(player, { character = character }, player)
end

function HighlightRenderer:_invalidatePlayer(player)
    restoreExecutorThread()
    if not self.active then
        return
    end
    local character = player.Character
    local subject = self.subjects[player]
    local eligible, tone = false, nil
    if character then
        eligible, tone = self:_eligible(player, character)
    end
    if not character or not eligible then
        self:_removeSubject(player)
    elseif not subject or subject.character ~= character then
        self:_attachCharacter(player, character)
    else
        subject.tone = tone
        self:_updateSubject(subject)
    end
end

function HighlightRenderer:_connectPlayerPolicy(player)
    clearConnections(self.playerPolicyConnections[player])
    local connections = {}
    self.playerPolicyConnections[player] = connections
    if self.policy.connectPlayerChanged then
        hold(
            connections,
            self.policy.connectPlayerChanged(
                player,
                onExecutorThread(function()
                    self:_invalidatePlayer(player)
                end)
            )
        )
    end
end

function HighlightRenderer:_trackPlayer(player)
    if
        player == self.context.localPlayer
        or player == self.context.players.LocalPlayer
        or self.playerConnections[player]
    then
        return
    end
    local connections = {}
    self.playerConnections[player] = connections
    self:_connectPlayerPolicy(player)
    if player.CharacterAdded then
        table.insert(
            connections,
            player.CharacterAdded:Connect(onExecutorThread(function(character)
                if self.active then
                    self:_attachCharacter(player, character)
                end
            end))
        )
    end
    if player.CharacterRemoving then
        table.insert(
            connections,
            player.CharacterRemoving:Connect(onExecutorThread(function(character)
                local subject = self.subjects[player]
                if subject and subject.character == character then
                    self:_removeSubject(player)
                end
            end))
        )
    end
    if player.Character then
        self:_attachCharacter(player, player.Character)
    end
end

function HighlightRenderer:_untrackPlayer(player)
    self:_removeSubject(player)
    local connections = self.playerConnections[player]
    self.playerConnections[player] = nil
    clearConnections(connections)
    clearConnections(self.playerPolicyConnections[player])
    self.playerPolicyConnections[player] = nil
end

function HighlightRenderer:_invalidatePolicy()
    if not self.active then
        return
    end
    local players = {}
    for player in pairs(self.playerConnections) do
        table.insert(players, player)
    end
    for _, player in ipairs(players) do
        self:_invalidatePlayer(player)
    end
    for _, subject in pairs(self.subjects) do
        self:_updateSubject(subject)
    end
end

function HighlightRenderer:_subscribePolicyChanged()
    if self.policy.subscribeChanged then
        hold(
            self.policyConnections,
            self.policy.subscribeChanged(onExecutorThread(function()
                self:_invalidatePolicy()
            end))
        )
    end
end

function HighlightRenderer:_subscribeExtras()
    local subscribe = self.policy.subscribeExtras
    if not subscribe then
        return
    end
    self.extraCleanup = subscribe(
        onExecutorThread(function(descriptor)
            if descriptor and descriptor.key ~= nil then
                self.extraKeys[descriptor.key] = true
                self:_removeSubject(descriptor.key)
                self:_makeSubject(descriptor.key, descriptor, nil)
            end
        end),
        onExecutorThread(function(keyOrDescriptor)
            local key = type(keyOrDescriptor) == "table" and keyOrDescriptor.key or keyOrDescriptor
            if key ~= nil then
                self.extraKeys[key] = nil
                self:_removeSubject(key)
            end
        end)
    )
end

function HighlightRenderer:_clearExtras()
    local keys = {}
    for key in pairs(self.extraKeys) do
        table.insert(keys, key)
    end
    table.clear(self.extraKeys)
    for _, key in ipairs(keys) do
        self:_removeSubject(key)
    end
end

function HighlightRenderer:_activate()
    if self.active then
        return
    end
    self.active = true
    self:_ensureRoot()
    local players = self.context.players
    self.playerAdded = players.PlayerAdded:Connect(onExecutorThread(function(player)
        self:_trackPlayer(player)
    end))
    self.playerRemoving = players.PlayerRemoving:Connect(onExecutorThread(function(player)
        self:_untrackPlayer(player)
    end))
    for _, player in ipairs(players:GetPlayers()) do
        self:_trackPlayer(player)
    end
    self:_subscribePolicyChanged()
    self:_subscribeExtras()
    self:_syncDistanceRefresh()
end

function HighlightRenderer:_deactivate()
    if not self.active then
        return
    end
    self.active = false
    self:_stopDistanceRefresh()
    disconnect(self.playerAdded)
    disconnect(self.playerRemoving)
    self.playerAdded = nil
    self.playerRemoving = nil
    clearConnections(self.policyConnections)
    if self.extraCleanup then
        self.extraCleanup()
        self.extraCleanup = nil
    end
    self:_clearExtras()
    local players = {}
    for player in pairs(self.playerConnections) do
        table.insert(players, player)
    end
    for _, player in ipairs(players) do
        self:_untrackPlayer(player)
    end
    local keys = {}
    for key in pairs(self.subjects) do
        table.insert(keys, key)
    end
    for _, key in ipairs(keys) do
        self:_removeSubject(key)
    end
    safeDestroy(self.root)
    self.root = nil
end

function HighlightRenderer:_applyState(state)
    restoreExecutorThread()
    if self.destroyed then
        return
    end
    local highlights = self.context.highlightsSupported ~= false
        and state.settings
        and state.settings.worldRenderer == "native"
    if highlights then
        local showEnemies = state.settings.showEnemies ~= false
        local showTeammates = state.settings.showTeammates == true
        local membershipChanged = self.active
            and (self.showEnemies ~= showEnemies or self.showTeammates ~= showTeammates)
        self.showEnemies = showEnemies
        self.showTeammates = showTeammates
        self:_activate()
        self:_syncDistanceRefresh()
        if membershipChanged then
            self:_invalidatePolicy()
        else
            for _, subject in pairs(self.subjects) do
                self:_updateSubject(subject)
            end
        end
    else
        self.showEnemies = true
        self.showTeammates = false
        self:_deactivate()
    end
end

function HighlightRenderer:setPolicy(policy)
    self.policy = policy or {}
    if not self.active then
        return
    end
    clearConnections(self.policyConnections)
    if self.extraCleanup then
        self.extraCleanup()
        self.extraCleanup = nil
    end
    self:_clearExtras()
    local players = self.context.players:GetPlayers()
    for _, player in ipairs(players) do
        if self.playerConnections[player] then
            self:_connectPlayerPolicy(player)
            self:_invalidatePlayer(player)
            local subject = self.subjects[player]
            if subject then
                self:_connectCharacterPolicy(subject)
            end
        end
    end
    self:_subscribePolicyChanged()
    self:_subscribeExtras()
end

function HighlightRenderer:render(observations)
    local unclaimed = {}
    local seen = {}
    for _, observation in ipairs(observations or {}) do
        local key = observation.key or observation.player
        local subject = not self.destroyed and self.active and key and self.subjects[key]
        if subject then
            seen[key] = true
            self:_updateSubject(subject, observation)
        else
            table.insert(unclaimed, observation)
        end
    end
    for key, subject in pairs(self.subjects) do
        if not seen[key] then
            subject.billboard.Enabled = false
        end
    end
    return unclaimed
end

function HighlightRenderer:destroy()
    if self.destroyed then
        return
    end
    self.destroyed = true
    if self.unsubscribe then
        self.unsubscribe()
        self.unsubscribe = nil
    end
    self:_deactivate()
end

return HighlightRenderer
]=],
    ["ui/esp/VisualPolicy.lua"] = [[local VisualPolicy = {
    FILL_TRANSPARENCY = 0.42,
    OUTLINE_THICKNESS = 2,
    COLORS = {
        danger = Color3.fromRGB(255, 118, 87),
        signal = Color3.fromRGB(98, 214, 173),
        text = Color3.fromRGB(243, 243, 244),
        secondary = Color3.fromRGB(190, 192, 195),
        team = Color3.fromRGB(101, 157, 214),
        track = Color3.fromRGB(39, 41, 46),
    },
}

return table.freeze(VisualPolicy)
]],
    ["ui/esp/WorldRenderer.lua"] = [[-- Two explicit ESP backends share this switch:
--   drawing   = Limn / Drawing API (ui/esp/DrawingRenderer)
--   highlights = Highlight + BillboardGui (ui/esp/HighlightRenderer)
-- The persisted setting remains worldRenderer = "limn" | "native".
local WorldRenderer = {}
WorldRenderer.__index = WorldRenderer

function WorldRenderer.new(context, drawingRenderer, highlightRenderer)
    assert(type(context) == "table" and context.store, "WorldRenderer requires context.store")
    assert(type(drawingRenderer) == "table" and type(drawingRenderer.render) == "function")
    assert(type(highlightRenderer) == "table" and type(highlightRenderer.render) == "function")
    local support = {}
    for key, value in pairs(drawingRenderer.optionSupport or {}) do
        support[key] = value
    end
    support.chams = true
    return setmetatable({
        context = context,
        drawing = drawingRenderer,
        highlights = highlightRenderer,
        optionSupport = support,
        destroyed = false,
    }, WorldRenderer)
end

function WorldRenderer:setPolicy(policy)
    if not self.destroyed then
        self.highlights:setPolicy(policy)
    end
end

function WorldRenderer:render(observations, mousePosition, utilityObservations)
    if self.destroyed then
        return
    end
    local settings = self.context.store:Get().settings or {}
    if self.context.highlightsSupported ~= false and settings.worldRenderer == "native" then
        self.highlights:render(observations)
        self.drawing:render({}, mousePosition, {})
    else
        self.highlights:render(nil)
        self.drawing:render(observations, mousePosition, utilityObservations)
    end
end

function WorldRenderer:destroy()
    if self.destroyed then
        return
    end
    self.destroyed = true
    self.highlights:destroy()
    self.drawing:destroy()
end

return WorldRenderer
]],
    ["ui/presentation/Catalog.lua"] = [=[local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local ColorPolicy = importDependency("ui/esp/ColorPolicy", "../esp/ColorPolicy")
local WhatsNew = importDependency("ui/WhatsNew", "../WhatsNew")
local Catalog = {}
Catalog.__index = Catalog

local PAGE_ORDER = { "Combat", "Rage", "Movement", "Visuals", "Tools", "Settings" }

local function isEphemeral(page, spec)
    return page == "Rage" or (type(spec) == "table" and spec.persist == false)
end

function Catalog.collectEphemeralSettings(presentation)
    assert(
        type(presentation) == "table" and type(presentation.mount) == "function",
        "Ephemeral setting collection requires a game presentation"
    )
    local result = {}
    local sections = {}
    local collector = {}

    function collector:section(page, id, _label, _lineOffset, _includesRates, _columns, spec)
        sections[id] = {
            ephemeral = isEphemeral(page, spec),
            page = page,
        }
    end

    function collector:option(sectionId, _rowIndex, id, _label, parent)
        local section =
            assert(sections[sectionId], "Unknown presentation section: " .. tostring(sectionId))
        if
            section.ephemeral
            or isEphemeral(section.page, type(parent) == "table" and parent or nil)
        then
            result[id] = true
        end
    end

    function collector:slider(sectionId, id, _label, spec)
        local section =
            assert(sections[sectionId], "Unknown presentation section: " .. tostring(sectionId))
        if section.ephemeral or isEphemeral(section.page, spec) then
            result[id] = true
        end
    end

    function collector:button() end

    function collector:keybind(sectionId, id)
        local section =
            assert(sections[sectionId], "Unknown presentation section: " .. tostring(sectionId))
        if section.ephemeral then
            result[id] = true
        end
    end

    function collector:segmented(page, spec)
        if not isEphemeral(page, spec) then
            return
        end
        result[spec.id] = true
        for _, option in ipairs(spec.options or {}) do
            for _, entry in ipairs(option.patch or {}) do
                result[entry[1]] = true
            end
        end
    end

    setmetatable(collector, {
        __index = function()
            return function() end
        end,
    })
    presentation.mount(collector)
    return result
end

local function buildAvailability(capabilities)
    local available = {}
    for key, value in pairs(capabilities or {}) do
        local name = type(key) == "number" and value or key
        if value ~= false then
            available[name] = true
        end
    end
    return available
end

function Catalog.new(context)
    assert(
        type(context) == "table" and context.store,
        "Presentation catalog requires a Store context"
    )
    return setmetatable({
        available = buildAvailability(context.capabilities),
        context = context,
        finalized = false,
        groups = {},
        groupById = {},
        hasAim = false,
        hasContent = {},
        optionSupport = context.optionSupport or {},
        pageMetadata = {},
        ephemeralSettings = {},
        rates = {},
        relatedValues = {},
        segments = {},
        segmentById = {},
        sliderById = {},
    }, Catalog)
end

function Catalog:page(page, metadata)
    assert(type(page) == "string" and page ~= "", "Presentation page metadata requires a page id")
    assert(type(metadata) == "table", "Presentation page metadata requires a descriptor")
    assert(metadata.order == nil or type(metadata.order) == "number", "Page order must be numeric")
    assert(self.pageMetadata[page] == nil, "Duplicate presentation page metadata: " .. page)
    self.pageMetadata[page] = metadata
end

function Catalog:supports(name)
    return self.available[name] == true
end

function Catalog:read()
    return self.context.store:Get()
end

function Catalog:patch(patch)
    return self.context.store:Patch(patch)
end

function Catalog:action(name, ...)
    local callback = self.context[name]
    if type(callback) == "function" then
        return callback(...)
    end
    assert(self.available[name], "Unknown presentation action: " .. tostring(name))
    return self.context.setOption(name, true, true)
end

function Catalog:_markPage(page)
    self.hasContent[page] = true
end

function Catalog:aim()
    local supported = self.available.silentAim
        or self.available.shotAim
        or self.available.triggerBot
        or self.available.aimSmoothness
        or self.available.aimAssistStrength
        or self.available.headshotRate
        or self.available.missRate
    if self.hasAim or not supported then
        return
    end
    self.hasAim = true
    self:_markPage("Combat")
end

function Catalog:rate(id, label)
    if not self.available[id] then
        return
    end
    table.insert(self.rates, { id = id, label = label })
    self:_markPage("Combat")
end

local function segmentIsSupported(available, spec)
    for _, option in ipairs(spec.options or {}) do
        for id in pairs(option.when or {}) do
            if available[id] then
                return true
            end
        end
    end
    return false
end

function Catalog:segmented(page, spec)
    assert(
        type(spec) == "table" and type(spec.id) == "string",
        "Segmented presentation control requires an id"
    )
    assert(
        type(spec.options) == "table" and #spec.options > 1,
        "Segmented presentation control requires options"
    )
    assert(not self.segmentById[spec.id], "Duplicate segmented presentation control: " .. spec.id)
    if not segmentIsSupported(self.available, spec) then
        return
    end
    spec.page = page
    spec.ephemeral = isEphemeral(page, spec)
    if spec.ephemeral then
        self.ephemeralSettings[spec.id] = true
        for _, option in ipairs(spec.options or {}) do
            for _, entry in ipairs(option.patch or {}) do
                self.ephemeralSettings[entry[1]] = true
            end
        end
    end
    self.segmentById[spec.id] = spec
    table.insert(self.segments, spec)
    self:_markPage(page)
end

function Catalog:section(page, id, label, lineOffset, includesRates, columns, spec)
    assert(not self.groupById[id], "Duplicate presentation section: " .. tostring(id))
    spec = type(spec) == "table" and spec or {}
    local group = {
        id = id,
        page = page,
        label = label,
        lineOffset = lineOffset,
        includesRates = includesRates == true,
        columns = columns or 1,
        ephemeral = isEphemeral(page, spec),
        renderEmpty = spec.renderEmpty == true,
        treatment = spec.treatment,
        actions = {},
        options = {},
        keybinds = {},
        sliders = {},
    }
    self.groupById[id] = group
    table.insert(self.groups, group)
end

function Catalog:button(sectionId, id, label, spec)
    if not self.available[id] then
        return
    end
    local group =
        assert(self.groupById[sectionId], "Unknown presentation section: " .. tostring(sectionId))
    spec = type(spec) == "table" and spec or { variant = spec }
    table.insert(group.actions, {
        action = id,
        confirm = spec.confirm,
        id = id,
        label = label,
        variant = spec.variant,
    })
    self:_markPage(group.page)
end

function Catalog:option(sectionId, rowIndex, id, label, parent, visibility)
    if not self.available[id] then
        return
    end
    local group =
        assert(self.groupById[sectionId], "Unknown presentation section: " .. tostring(sectionId))
    local spec = type(parent) == "table" and parent or nil
    if spec then
        parent = spec.parent
        visibility = spec.visibility or spec.when or visibility
    end
    local placement = spec and spec.placement or nil
    local ephemeral = group.ephemeral or isEphemeral(group.page, spec)
    if placement == nil then
        if parent == "audience" then
            placement = "audience"
        elseif type(parent) == "string" then
            placement = "details"
        else
            placement = "grid"
        end
    end
    if placement == "audience" then
        parent = nil
    end
    table.insert(group.options, {
        ephemeral = ephemeral,
        id = id,
        label = label,
        parent = parent,
        placement = placement,
        row = rowIndex,
        visibility = visibility,
    })
    if ephemeral then
        self.ephemeralSettings[id] = true
    end
    self:_markPage(group.page)
end

function Catalog:slider(sectionId, id, label, spec)
    if not self.available[id] then
        return
    end
    local group =
        assert(self.groupById[sectionId], "Unknown presentation section: " .. tostring(sectionId))
    spec = spec or {}
    local slider = {
        ephemeral = group.ephemeral or isEphemeral(group.page, spec),
        id = id,
        label = label,
        min = spec.min or 0,
        max = spec.max or 100,
        step = spec.step or 1,
        unit = spec.unit or "",
        parent = spec.parent,
    }
    if slider.ephemeral then
        self.ephemeralSettings[id] = true
    end
    table.insert(group.sliders, slider)
    self.sliderById[id] = slider
    self:_markPage(group.page)
end

function Catalog:keybind(sectionId, id, label, defaultValue)
    local group =
        assert(self.groupById[sectionId], "Unknown presentation section: " .. tostring(sectionId))
    table.insert(group.keybinds, { id = id, label = label, defaultValue = defaultValue })
    if group.ephemeral then
        self.ephemeralSettings[id] = true
    end
    self:_markPage(group.page)
end

function Catalog:cosmetics()
    if self.context.cosmetics == false then
        return
    end
    self.hasCosmetics = true
    self:_markPage("Visuals")
end

function Catalog:register(panel)
    -- Legacy custom panels are retained by the Drawing presentation until their
    -- game registers an equivalent renderer-neutral catalog descriptor.
    if panel and panel.page then
        self:_markPage(panel.page)
    end
    return panel
end

function Catalog:finalize()
    if self.finalized then
        return
    end
    self.finalized = true
    for _, page in ipairs(PAGE_ORDER) do
        if self.hasContent[page] then
            self:_markPage("Settings")
            break
        end
    end
end

local function append(list, value)
    table.insert(list, value)
    return value
end

local function selectedSegmentValue(segment, settings)
    local selected = segment.options[1].value
    for _, option in ipairs(segment.options) do
        local matches = true
        for id, expected in pairs(option.when or {}) do
            if settings[id] ~= expected then
                matches = false
                break
            end
        end
        if matches then
            return option.value
        end
    end
    return selected
end

local function selectedTargetMode(settings, cameraMode)
    local mode = cameraMode and settings.cameraTargetMode or settings.shotTargetMode
    if mode == "radius" or mode == "fullscreen" or mode == "360" then
        return mode
    end
    local fullScreenAim = cameraMode
            and (settings.cameraFullScreenAim == nil and settings.fullScreenAim or settings.cameraFullScreenAim)
        or not cameraMode
            and (settings.shotFullScreenAim == nil and settings.fullScreenAim or settings.shotFullScreenAim)
    return fullScreenAim == true and "fullscreen" or "radius"
end

function Catalog:model(state)
    self:finalize()
    state = state or self.context.store:Get()
    local settings = state.settings
    local sectionsByPage = {}
    for _, page in ipairs(PAGE_ORDER) do
        sectionsByPage[page] = {}
    end

    for _, segment in ipairs(self.segments) do
        local selected = selectedSegmentValue(segment, settings)
        local controls = {
            {
                id = segment.id,
                kind = "segmented",
                label = segment.label,
                value = selected,
                emphasis = segment.emphasis,
                options = segment.options,
            },
        }
        for _, related in ipairs(segment.related or {}) do
            local kind = related.kind or "toggle"
            local parentActive = not related.parent or settings[related.parent] == true
            if related.when == selected and self.available[related.id] and parentActive then
                local value = settings[related.id]
                append(controls, {
                    id = related.id,
                    kind = kind,
                    label = related.label,
                    max = kind == "slider" and (related.max or 100) or nil,
                    min = kind == "slider" and (related.min or 0) or nil,
                    parent = related.parent,
                    step = kind == "slider" and (related.step or 1) or nil,
                    unit = kind == "slider" and related.unit or nil,
                    value = kind == "slider" and value or value == true,
                    status = self.optionSupport[related.id] == false and "unavailable"
                        or "available",
                })
            end
        end
        append(sectionsByPage[segment.page], {
            id = segment.id,
            label = segment.sectionLabel or segment.label,
            treatment = segment.treatment or (segment.id == "worldRenderer" and "style" or "card"),
            controls = controls,
        })
    end

    if self.hasAim then
        local cameraMode = settings.shotAim ~= true
        local targetMode = selectedTargetMode(settings, cameraMode)
        local targetOptions = {
            { value = "radius", label = "Radius" },
            { value = "fullscreen", label = "Fullscreen" },
        }
        if self.available.target360 then
            table.insert(targetOptions, { value = "360", label = "360" })
        end
        local controls = {
            {
                id = "fullScreenAim",
                kind = "segmented",
                label = "Target Mode",
                value = targetMode,
                emphasis = "prominent",
                options = targetOptions,
            },
        }
        if targetMode == "radius" then
            append(controls, {
                id = "fov",
                kind = "slider",
                label = "FOV",
                value = (cameraMode and settings.cameraFov or settings.shotFov) or settings.fov,
                min = settings.minimumFov,
                max = settings.maximumFov,
                step = 1,
                unit = "px",
                emphasis = "row",
            })
        end
        append(sectionsByPage.Combat, {
            id = "targeting",
            label = "Targeting",
            treatment = "card",
            controls = controls,
        })
    end

    if #self.rates > 0 then
        local controls = {}
        for _, rate in ipairs(self.rates) do
            append(controls, {
                id = rate.id,
                kind = "slider",
                label = rate.label,
                value = math.clamp(settings[rate.id] or 0, 0, 100),
                min = 0,
                max = 100,
                step = 1,
                unit = "%",
                emphasis = "row",
            })
        end
        append(sectionsByPage.Combat, {
            id = "response",
            label = "Response",
            treatment = "card",
            controls = controls,
        })
    end

    for _, group in ipairs(self.groups) do
        if
            #group.actions > 0
            or #group.options > 0
            or #group.keybinds > 0
            or #group.sliders > 0
            or group.renderEmpty
        then
            local controls = {}
            for _, action in ipairs(group.actions) do
                append(controls, {
                    action = action.action,
                    confirm = action.confirm,
                    id = action.id,
                    kind = "action",
                    label = action.label,
                    variant = action.variant,
                })
            end
            for _, keybind in ipairs(group.keybinds) do
                local value = settings[keybind.id]
                append(controls, {
                    id = keybind.id,
                    kind = "keybind",
                    label = keybind.label,
                    value = type(value) == "string" and Enum.KeyCode[value]
                        or Enum.KeyCode[keybind.defaultValue or "End"],
                    readOnly = false,
                })
            end
            for _, option in ipairs(group.options) do
                local parentActive = not option.parent
                    or option.parent == "audience"
                    or settings[option.parent] == true
                local visible = option.visibility ~= "when-parent" or parentActive
                if type(option.visibility) == "table" then
                    local expected = option.visibility.equals
                    visible = settings[option.visibility.setting] == expected
                        and (option.visibility.whenParent ~= true or parentActive)
                end
                if visible then
                    local status = "available"
                    if self.optionSupport[option.id] == false then
                        status = "unavailable"
                    elseif not parentActive then
                        status = "standby"
                    end
                    append(controls, {
                        id = option.id,
                        kind = "toggle",
                        label = option.label,
                        parent = option.parent,
                        placement = option.placement,
                        value = settings[option.id] == true,
                        status = status,
                    })
                    for _, slider in ipairs(group.sliders) do
                        if slider.parent == option.id and settings[option.id] == true then
                            local value = settings[slider.id]
                            if type(value) ~= "number" then
                                value = slider.min
                            end
                            append(controls, {
                                id = slider.id,
                                kind = "slider",
                                label = slider.label,
                                parent = slider.parent,
                                value = math.clamp(value, slider.min, slider.max),
                                min = slider.min,
                                max = slider.max,
                                step = slider.step,
                                unit = slider.unit,
                                emphasis = "nested",
                            })
                        end
                    end
                end
            end
            for _, slider in ipairs(group.sliders) do
                if slider.parent then
                    continue
                end
                local value = settings[slider.id]
                if type(value) ~= "number" then
                    value = slider.min
                end
                append(controls, {
                    id = slider.id,
                    kind = "slider",
                    label = slider.label,
                    value = math.clamp(value, slider.min, slider.max),
                    min = slider.min,
                    max = slider.max,
                    step = slider.step,
                    unit = slider.unit,
                    emphasis = "row",
                })
            end
            if #controls > 0 or group.renderEmpty then
                local treatment = group.treatment
                if treatment == nil then
                    local metadata = self.pageMetadata[group.page] or {}
                    if metadata.layout == "toggle-grid" then
                        for _, option in ipairs(group.options) do
                            if option.placement == "grid" then
                                treatment = "grid"
                                break
                            end
                        end
                    end
                end
                append(sectionsByPage[group.page], {
                    id = group.id,
                    label = group.label,
                    treatment = treatment or "list",
                    controls = controls,
                })
            end
        end
    end

    if self.hasCosmetics then
        local cosmetics = state.cosmetics or {}
        local gloves = state.gloves or {}
        local minimumWear = cosmetics.minimumWear or 0
        local maximumWear = cosmetics.maximumWear or 1
        local minimumGloveWear = gloves.minimumWear or 0
        local maximumGloveWear = gloves.maximumWear or 1
        append(sectionsByPage.Visuals, {
            id = "skin-changer",
            label = "Skin changer",
            treatment = "plain",
            controls = {
                {
                    id = "cosmeticModelViewer",
                    kind = "model-viewer",
                    label = "Weapon preview",
                    height = 230,
                    key = type(self.context.getWeaponPreviewKey) == "function"
                            and self.context.getWeaponPreviewKey(state)
                        or tostring(state.previewRevision or 0),
                    resolve = type(self.context.getWeaponPreviewSubject) == "function"
                            and function()
                                return self.context.getWeaponPreviewSubject(state)
                            end
                        or nil,
                },
                {
                    id = "previousCosmeticWeapon",
                    kind = "action",
                    action = "previousCosmeticWeapon",
                    label = "Previous weapon",
                },
                {
                    id = "nextCosmeticWeapon",
                    kind = "action",
                    action = "nextCosmeticWeapon",
                    label = "Next weapon · " .. tostring(cosmetics.weapon or "Weapon"),
                },
                {
                    id = "previousSkin",
                    kind = "action",
                    action = "previousSkin",
                    label = "Previous skin",
                },
                {
                    id = "nextSkin",
                    kind = "action",
                    action = "nextSkin",
                    label = "Next skin · "
                        .. tostring(cosmetics.skinLabel or cosmetics.skin or "Stock"),
                },
                {
                    id = "cosmeticWear",
                    kind = "slider",
                    label = "Knife wear",
                    value = math.clamp(cosmetics.wear or minimumWear, minimumWear, maximumWear),
                    min = minimumWear,
                    max = maximumWear,
                    step = 0.01,
                },
                {
                    id = "cosmeticStatTrak",
                    kind = "toggle",
                    label = "StatTrak",
                    value = cosmetics.statTrak == true,
                    disabled = cosmetics.supportsStatTrak ~= true,
                },
                {
                    id = "resetSkin",
                    kind = "action",
                    action = "resetSkin",
                    label = "Reset knife",
                },
            },
        })
        append(sectionsByPage.Visuals, {
            id = "glove-changer",
            label = "Gloves",
            treatment = "plain",
            controls = {
                {
                    id = "previousGlove",
                    kind = "action",
                    action = "previousGlove",
                    label = "Previous gloves",
                },
                {
                    id = "nextGlove",
                    kind = "action",
                    action = "nextGlove",
                    label = "Next gloves · " .. tostring(gloves.skin or "Game equipped"),
                },
                {
                    id = "gloveWear",
                    kind = "slider",
                    label = "Glove wear",
                    value = math.clamp(
                        gloves.wear or minimumGloveWear,
                        minimumGloveWear,
                        maximumGloveWear
                    ),
                    min = minimumGloveWear,
                    max = maximumGloveWear,
                    step = 0.01,
                },
                {
                    id = "resetGlove",
                    kind = "action",
                    action = "resetGlove",
                    label = "Use game-equipped gloves",
                },
            },
        })
    end

    append(sectionsByPage.Settings, {
        id = "menu",
        label = "Menu",
        treatment = "card",
        controls = {
            {
                id = "menuKey",
                kind = "keybind",
                label = "Toggle interface",
                value = type(settings.menuKey) == "string" and Enum.KeyCode[settings.menuKey]
                    or Enum.KeyCode.RightShift,
                readOnly = false,
            },
        },
    })

    local pages = {}
    local pageRanks = {}
    for defaultOrder, page in ipairs(PAGE_ORDER) do
        if self.hasContent[page] then
            local metadata = self.pageMetadata[page] or {}
            pageRanks[page] = metadata.order or defaultOrder
            local preview
            if metadata.preview then
                preview = {}
                for key, value in pairs(metadata.preview) do
                    preview[key] = value
                end
                preview.worldRenderer = settings.worldRenderer
                preview.tone = "enemy"
                local visualPolicy = self.context.visualPolicy
                local defaultAlpha = preview.worldRenderer == "native"
                        and (1 - (visualPolicy and visualPolicy.FILL_TRANSPARENCY or 0.42))
                    or 0.18
                local defaults = {
                    enemy = Color3.fromRGB(255, 118, 87),
                    teammate = Color3.fromRGB(101, 157, 214),
                    weapon = Color3.fromRGB(177, 188, 199),
                    healthLow = Color3.fromRGB(255, 118, 87),
                    healthHigh = Color3.fromRGB(98, 214, 173),
                }
                local function relationshipPalette(relationship, label)
                    local primary = defaults[relationship]
                    local fillAlpha = ColorPolicy.fillAlpha(settings, defaultAlpha, relationship)
                    return {
                        id = relationship,
                        label = label,
                        fillAlpha = fillAlpha,
                        targets = {
                            {
                                id = "outline",
                                label = "Outline",
                                color = ColorPolicy.color(
                                    settings,
                                    "outline",
                                    primary,
                                    relationship
                                ),
                                defaultColor = primary,
                            },
                            {
                                id = "fill",
                                label = "Fill",
                                color = ColorPolicy.color(settings, "fill", primary, relationship),
                                alpha = fillAlpha,
                                defaultColor = primary,
                                defaultAlpha = defaultAlpha,
                            },
                            {
                                id = "name",
                                label = "Name",
                                color = ColorPolicy.color(settings, "name", primary, relationship),
                                defaultColor = primary,
                            },
                            {
                                id = "weapon",
                                label = "Weapon",
                                color = ColorPolicy.color(
                                    settings,
                                    "weapon",
                                    defaults.weapon,
                                    relationship
                                ),
                                defaultColor = defaults.weapon,
                            },
                            {
                                id = "healthLow",
                                label = "Health Low",
                                color = ColorPolicy.color(
                                    settings,
                                    "healthLow",
                                    defaults.healthLow,
                                    relationship
                                ),
                                defaultColor = defaults.healthLow,
                            },
                            {
                                id = "healthHigh",
                                label = "Health High",
                                color = ColorPolicy.color(
                                    settings,
                                    "healthHigh",
                                    defaults.healthHigh,
                                    relationship
                                ),
                                defaultColor = defaults.healthHigh,
                            },
                        },
                    }
                end
                local enemyPalette = relationshipPalette("enemy", "Enemies")
                preview.chamsColor = enemyPalette.targets[2].color
                preview.chamsTransparency = 1 - enemyPalette.fillAlpha
                preview.outlineColor = enemyPalette.targets[1].color
                preview.palette = {
                    checkerboardImage = self.context.alphaCheckerboard,
                    relationships = {
                        enemyPalette,
                        relationshipPalette("teammate", "Teammates"),
                    },
                }
                preview.nameLabel = self.context.localPlayer and self.context.localPlayer.Name
                    or "Preview Player"
                preview.weaponLabel = preview.weaponLabel or "Assault Rifle"
                preview.boxes = settings.boxes == true
                preview.chams = settings.chams == true
                preview.names = settings.names == true
                preview.health = settings.health == true
                preview.weapon = settings.weapon == true
                preview.chamsExcludeAccessories = settings.chamsExcludeAccessories == true
                preview.chamsPerPart = settings.chamsPerPart == true
                if type(self.context.publishPreviewObservation) == "function" then
                    preview.publish = self.context.publishPreviewObservation
                end
                if type(self.context.reportPreviewStatus) == "function" then
                    preview.report = self.context.reportPreviewStatus
                end
                if type(self.context.getPreviewSubject) == "function" then
                    preview.key = type(self.context.getPreviewKey) == "function"
                            and self.context.getPreviewKey(state)
                        or tostring(state.previewRevision or 0)
                    preview.resolve = function()
                        return self.context.getPreviewSubject(state)
                    end
                end
            end
            local views = metadata.views
            if views == nil and preview and preview.palette then
                views = {
                    { id = "preview", label = "Preview" },
                    { id = "colors", label = "ESP Colors" },
                }
            end
            append(pages, {
                id = page,
                label = page,
                icon = self.context.pageIcons and self.context.pageIcons[page] or nil,
                layout = metadata.layout,
                views = views,
                preview = preview,
                sections = sectionsByPage[page],
            })
        end
    end
    table.sort(pages, function(left, right)
        return pageRanks[left.id] < pageRanks[right.id]
    end)
    local footer = {}
    for _, metric in ipairs(state.footerMetrics or {}) do
        local tone = "neutral"
        local icon
        local value = tostring(metric.value)
        if metric.kind == "latency" and type(metric.value) == "number" then
            icon = "signal"
            tone = metric.value <= 80 and "positive"
                or metric.value <= 150 and "warning"
                or "negative"
            value ..= " ms"
        end
        table.insert(footer, {
            icon = icon,
            id = metric.id,
            label = metric.label,
            tone = tone,
            value = value,
        })
    end

    return {
        brandLabel = "universal-hub",
        brandIcon = self.context.brandIcon,
        gameLabel = self.context.gameLabel or "Universal",
        gameIcon = self.context.gameIcon,
        floatingMonitor = type(state.floatingMonitor) == "table" and state.floatingMonitor or nil,
        notification = type(state.notification) == "table" and state.notification or nil,
        enemyAudienceIcon = self.context.enemyAudienceIcon,
        allyAudienceIcon = self.context.allyAudienceIcon,
        visible = state.menuVisible ~= false,
        whatsNew = WhatsNew.model(state.whatsNew),
        pages = pages,
        footer = footer,
        onDismissNotification = function()
            self.context.store:Patch({ notification = false })
        end,
        onValueChange = function(id, value, persist)
            local segment = self.segmentById[id]
            if segment then
                local shouldPersist = not segment.ephemeral
                local currentSettings = self.context.store:Get().settings
                local currentValue = selectedSegmentValue(segment, currentSettings)
                for _, related in ipairs(segment.related or {}) do
                    if related.when == currentValue and self.available[related.id] then
                        self.relatedValues[related.id] = currentSettings[related.id]
                    end
                end
                for _, option in ipairs(segment.options) do
                    if option.value == value then
                        for _, entry in ipairs(option.patch or {}) do
                            if
                                type(entry[2]) == "boolean"
                                or type(self.context.setSetting) ~= "function"
                            then
                                self.context.setOption(entry[1], entry[2], shouldPersist)
                            else
                                self.context.setSetting(entry[1], entry[2], shouldPersist)
                            end
                        end
                        for _, related in ipairs(segment.related or {}) do
                            local retained = self.relatedValues[related.id]
                            if related.when == value and retained ~= nil then
                                if type(retained) == "boolean" then
                                    self.context.setOption(related.id, retained, shouldPersist)
                                else
                                    self.context.setRate(related.id, retained, shouldPersist)
                                end
                            end
                        end
                        if id == "aimMode" then
                            local settings = self.context.store:Get().settings
                            local shotOnly = settings.shotAim == true
                            local targetMode = selectedTargetMode(settings, not shotOnly)
                            self.context.setFov(
                                (shotOnly and settings.shotFov or settings.cameraFov)
                                    or settings.fov,
                                shouldPersist
                            )
                            self.context.setOption(
                                "fullScreenAim",
                                targetMode ~= "radius",
                                shouldPersist
                            )
                        end
                        return
                    end
                end
            end
            if id == "menuKey" and self.context.setMenuKey then
                self.context.setMenuKey(value)
            elseif id == "taskAutomationEmergencyKey" and value ~= nil then
                self.context.setSetting(id, value.Name, persist == true)
            elseif id == "fov" then
                self.context.setFov(value, persist == true)
            elseif id:sub(1, 9) == "espColor:" then
                local relationship, target = id:match("^espColor:([^:]+):([^:]+)$")
                local setting = relationship and ColorPolicy.settingName(relationship, target)
                if setting then
                    self.context.setSetting(setting, value, persist == true)
                end
            elseif id:sub(1, 9) == "espAlpha:" then
                local relationship = id:match("^espAlpha:([^:]+)$")
                local setting = relationship and ColorPolicy.settingName(relationship, "fillAlpha")
                if setting then
                    local nextValue = value == -1 and -1 or math.clamp(value, 0, 1)
                    self.context.setSetting(setting, nextValue, persist == true)
                end
            elseif id:sub(1, 21) == "resetEspRelationship:" then
                local relationship = id:match("^resetEspRelationship:([^:]+)$")
                for _, target in ipairs(ColorPolicy.TARGETS) do
                    self.context.setSetting(
                        ColorPolicy.settingName(relationship, target),
                        "",
                        persist == true
                    )
                end
                self.context.setSetting(
                    ColorPolicy.settingName(relationship, "fillAlpha"),
                    -1,
                    persist == true
                )
            elseif id == "resetEspAll" then
                for _, relationship in ipairs(ColorPolicy.RELATIONSHIPS) do
                    for _, target in ipairs(ColorPolicy.TARGETS) do
                        self.context.setSetting(
                            ColorPolicy.settingName(relationship, target),
                            "",
                            persist == true
                        )
                    end
                    self.context.setSetting(
                        ColorPolicy.settingName(relationship, "fillAlpha"),
                        -1,
                        persist == true
                    )
                end
            elseif id == "fullScreenAim" then
                local settings = self.context.store:Get().settings
                local modeName = settings.shotAim == true and "shotTargetMode" or "cameraTargetMode"
                if settings[modeName] ~= nil then
                    self.context.setSetting(modeName, value, persist == true)
                end
                local fullScreenName = settings.shotAim == true and "shotFullScreenAim"
                    or "cameraFullScreenAim"
                if settings[fullScreenName] == nil then
                    fullScreenName = "fullScreenAim"
                end
                self.context.setOption(fullScreenName, value ~= "radius", persist == true)
                if fullScreenName ~= "fullScreenAim" then
                    self.context.setOption("fullScreenAim", value ~= "radius", persist == true)
                end
            elseif id == "cosmeticWear" and self.context.setWear then
                local cosmetics = self.context.store:Get().cosmetics or {}
                local minimum = cosmetics.minimumWear or 0
                local maximum = cosmetics.maximumWear or 1
                self.context.setWear(
                    maximum > minimum and (value - minimum) / (maximum - minimum) or 0
                )
            elseif id == "gloveWear" and self.context.setGloveWear then
                local gloves = self.context.store:Get().gloves or {}
                local minimum = gloves.minimumWear or 0
                local maximum = gloves.maximumWear or 1
                self.context.setGloveWear(
                    maximum > minimum and (value - minimum) / (maximum - minimum) or 0
                )
            elseif id == "cosmeticStatTrak" and self.context.toggleStatTrak then
                local cosmetics = self.context.store:Get().cosmetics or {}
                if (cosmetics.statTrak == true) ~= (value == true) then
                    self.context.toggleStatTrak()
                end
            elseif self.sliderById[id] then
                local slider = self.sliderById[id]
                local nextValue = math.clamp(math.round(value), slider.min, slider.max)
                self.context.setSetting(id, nextValue, persist == true and not slider.ephemeral)
            elseif self.groupById[id] or self.available[id] then
                if type(value) == "boolean" then
                    self.context.setOption(id, value, not self.ephemeralSettings[id])
                else
                    self.context.setRate(id, value, persist == true)
                end
            elseif id == "cosmeticsOpen" and self.context.setCosmeticsOpen then
                self.context.setCosmeticsOpen(value == true)
            end
        end,
        onAction = function(name)
            return self:action(name)
        end,
    }
end

return Catalog
]=],
    ["ui/presentation/CosmeticsPanel.lua"] = [[local CosmeticsPanel = {}
CosmeticsPanel.__index = CosmeticsPanel

local ACTIVE_CONTROL_LAYER = 206
local COLOR_TRACK_WIDTH = 310
local CONTENT_INSET = 20
local CONTENT_WIDTH = 350
local HITBOX_TRANSPARENCY = 0.01
local MODE_WIDTH = 171
local SELECTOR_WIDTH = 282
local WEAR_TRACK_WIDTH = 350
local WEAPON_CONTROLS = {
    weaponBackground = true,
    weaponName = true,
    weaponNext = true,
    weaponNextLabel = true,
    weaponPrevious = true,
    weaponPreviousLabel = true,
}

local function setVisible(nodes, visible)
    for _, node in pairs(nodes or {}) do
        if type(node) == "table" and (type(node.set) == "function" or node.Visible ~= nil) then
            node.Visible = visible
        elseif type(node) == "table" then
            setVisible(node, visible)
        end
    end
end

local function registerActiveSliderPaint(hit, draw)
    local connected, connection = pcall(function()
        return hit:paintCaptured(ACTIVE_CONTROL_LAYER, function(painter, event)
            draw(painter, event.position)
        end)
    end)
    return connected and connection ~= nil
end

local function setRetainedSliderVisible(state, fill, knob, visible)
    fill.Visible = visible
    knob.Visible = visible
    if visible then
        state.activeSliderVisuals[fill] = nil
        state.activeSliderVisuals[knob] = nil
        state.bridge.refreshVisibility()
    else
        state.activeSliderVisuals[fill] = true
        state.activeSliderVisuals[knob] = true
    end
end

local function paintActiveSlider(painter, track, width, knobX, radius, fillColor, knobColor)
    painter.FilledRectangle(track.Position, Vector2.new(math.max(0, width), 4), fillColor, 1, 0)
    painter.FilledCircle(
        Vector2.new(knobX, track.Position.Y + track.Size.Y * 0.5),
        radius,
        knobColor,
        1,
        32
    )
end

function CosmeticsPanel.new(bridge)
    local self = setmetatable({
        activeSliderVisuals = bridge.activeSliderVisuals,
        bridge = bridge,
        controls = bridge.controls,
        theme = bridge.theme,
    }, CosmeticsPanel)
    self:_build()
    return self
end

function CosmeticsPanel:_build()
    local state = self
    local controls = state.controls
    local colors = state.theme
    local function node(kind, properties, pointerEvents)
        return state.bridge.node(kind, properties, pointerEvents == true)
    end
    local function interactive(kind, properties)
        return state.bridge.interactive(node(kind, properties, true))
    end
    local function text(properties)
        return state.bridge.text(properties)
    end

    controls.cosmetics = {
        header = interactive("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(CONTENT_WIDTH, 30),
            Visible = true,
            ZIndex = 202,
        }),
        headerLabel = text({
            Color = colors.accent,
            Size = 11,
            Text = "COSMETICS",
            ZIndex = 203,
        }),
        indicator = text({
            Center = true,
            Color = colors.secondary,
            Size = 14,
            Text = "+",
            ZIndex = 203,
        }),
        weaponMode = interactive("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(MODE_WIDTH, 24),
            Visible = false,
            ZIndex = 202,
        }),
        weaponModeLabel = text({
            Center = true,
            Color = colors.text,
            Size = 12,
            Text = "Weapons",
            Visible = false,
            ZIndex = 203,
        }),
        gloveMode = interactive("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(MODE_WIDTH, 24),
            Visible = false,
            ZIndex = 202,
        }),
        gloveModeLabel = text({
            Center = true,
            Color = colors.text,
            Size = 12,
            Text = "Gloves",
            Visible = false,
            ZIndex = 203,
        }),
        weaponBackground = node("Square", {
            Color = colors.panel,
            Filled = true,
            Size = Vector2.new(SELECTOR_WIDTH, 30),
            Visible = false,
            ZIndex = 202,
        }),
        weaponName = text({
            Center = true,
            Color = colors.text,
            Size = 13,
            Text = "Weapon",
            Visible = false,
            ZIndex = 203,
        }),
        weaponNext = interactive("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(30, 30),
            Visible = false,
            ZIndex = 202,
        }),
        weaponNextLabel = text({
            Center = true,
            Color = colors.text,
            Size = 15,
            Text = ">",
            Visible = false,
            ZIndex = 203,
        }),
        weaponPrevious = interactive("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(30, 30),
            Visible = false,
            ZIndex = 202,
        }),
        weaponPreviousLabel = text({
            Center = true,
            Color = colors.text,
            Size = 15,
            Text = "<",
            Visible = false,
            ZIndex = 203,
        }),
        next = interactive("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(30, 30),
            Visible = false,
            ZIndex = 202,
        }),
        nextLabel = text({
            Center = true,
            Color = colors.text,
            Size = 15,
            Text = ">",
            Visible = false,
            ZIndex = 203,
        }),
        previous = interactive("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(30, 30),
            Visible = false,
            ZIndex = 202,
        }),
        previousLabel = text({
            Center = true,
            Color = colors.text,
            Size = 15,
            Text = "<",
            Visible = false,
            ZIndex = 203,
        }),
        reset = interactive("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(MODE_WIDTH, 30),
            Visible = false,
            ZIndex = 202,
        }),
        resetLabel = text({
            Color = colors.text,
            Size = 13,
            Text = "Reset Stock",
            Visible = false,
            ZIndex = 203,
        }),
        skinBackground = node("Square", {
            Color = colors.panel,
            Filled = true,
            Size = Vector2.new(SELECTOR_WIDTH, 30),
            Visible = false,
            ZIndex = 202,
        }),
        skinName = text({
            Center = true,
            Color = colors.text,
            Size = 13,
            Text = "Stock",
            Visible = false,
            ZIndex = 203,
        }),
        statTrak = interactive("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(MODE_WIDTH, 30),
            Visible = false,
            ZIndex = 202,
        }),
        statTrakLabel = text({
            Color = colors.text,
            Size = 13,
            Text = "StatTrak",
            Visible = false,
            ZIndex = 203,
        }),
        statTrakValue = text({
            Center = true,
            Color = colors.secondary,
            Size = 12,
            Text = "N/A",
            Visible = false,
            ZIndex = 203,
        }),
        wearFill = node("Square", {
            Color = colors.accent,
            Filled = true,
            Visible = false,
            ZIndex = 204,
        }),
        wearHit = interactive("Square", {
            Color = colors.panel,
            Filled = true,
            Size = Vector2.new(WEAR_TRACK_WIDTH, 22),
            Transparency = HITBOX_TRANSPARENCY,
            Visible = false,
            ZIndex = 202,
        }),
        wearKnob = node("Circle", {
            Color = colors.text,
            Filled = true,
            NumSides = 32,
            Radius = 6,
            Visible = false,
            ZIndex = 205,
        }),
        wearLabel = text({
            Color = colors.secondary,
            Size = 12,
            Text = "Wear",
            Visible = false,
            ZIndex = 203,
        }),
        wearTrack = node("Square", {
            Color = colors.border,
            Filled = true,
            Size = Vector2.new(WEAR_TRACK_WIDTH, 4),
            Visible = false,
            ZIndex = 203,
        }),
        wearValue = text({
            Center = true,
            Color = colors.secondary,
            Size = 12,
            Text = "0.00",
            Visible = false,
            ZIndex = 203,
        }),
    }
    controls.cosmetics.colorChannels = {}
    for _, channel in ipairs({
        { id = "r", label = "R", color = Color3.fromRGB(230, 107, 110) },
        { id = "g", label = "G", color = colors.accent },
        { id = "b", label = "B", color = Color3.fromRGB(91, 155, 213) },
    }) do
        controls.cosmetics.colorChannels[channel.id] = {
            fill = node("Square", {
                Color = channel.color,
                Filled = true,
                Visible = false,
                ZIndex = 204,
            }),
            hit = interactive("Square", {
                Color = colors.panel,
                Filled = true,
                Size = Vector2.new(COLOR_TRACK_WIDTH, 20),
                Transparency = HITBOX_TRANSPARENCY,
                Visible = false,
                ZIndex = 202,
            }),
            knob = node("Circle", {
                Color = colors.text,
                Filled = true,
                NumSides = 32,
                Radius = 5,
                Visible = false,
                ZIndex = 205,
            }),
            label = text({
                Color = channel.color,
                Size = 12,
                Text = channel.label,
                Visible = false,
                ZIndex = 203,
            }),
            track = node("Square", {
                Color = colors.border,
                Filled = true,
                Size = Vector2.new(COLOR_TRACK_WIDTH, 4),
                Visible = false,
                ZIndex = 203,
            }),
            value = text({
                Center = true,
                Color = colors.secondary,
                Size = 11,
                Text = "0",
                Visible = false,
                ZIndex = 203,
            }),
        }
    end

    controls.cosmetics.header:on("click", function()
        state.bridge.context.setCosmeticsOpen(not state.bridge.context.store:Get().cosmeticsOpen)
    end)
    controls.cosmetics.weaponMode:on("click", function()
        state.bridge.context.setCosmeticMode("weapon")
    end)
    controls.cosmetics.gloveMode:on("click", function()
        state.bridge.context.setCosmeticMode("gloves")
    end)
    controls.cosmetics.weaponPrevious:on("click", function()
        state.bridge.context.cycleCosmeticWeapon(-1)
    end)
    controls.cosmetics.weaponNext:on("click", function()
        state.bridge.context.cycleCosmeticWeapon(1)
    end)
    controls.cosmetics.previous:on("click", function()
        if state.bridge.context.store:Get().cosmeticMode == "gloves" then
            state.bridge.context.cycleGlove(-1)
        else
            state.bridge.context.cycleSkin(-1)
        end
    end)
    controls.cosmetics.next:on("click", function()
        if state.bridge.context.store:Get().cosmeticMode == "gloves" then
            state.bridge.context.cycleGlove(1)
        else
            state.bridge.context.cycleSkin(1)
        end
    end)
    controls.cosmetics.statTrak:on("click", function()
        local currentState = state.bridge.context.store:Get()
        if currentState.cosmeticMode == "gloves" then
            local current = currentState.settings.gloveColorOverride
            if type(current) == "table" then
                state.bridge.context.setGloveColor(false)
            else
                state.bridge.context.setGloveColor({ b = 0.68, g = 0.84, r = 0.38 })
            end
        else
            state.bridge.context.toggleStatTrak()
        end
    end)
    controls.cosmetics.reset:on("click", function()
        if state.bridge.context.store:Get().cosmeticMode == "gloves" then
            state.bridge.context.resetGlove()
        else
            state.bridge.context.resetSkin()
        end
    end)

    local function setWear(point)
        local alpha = math.clamp((point.X - state.wearStartX) / WEAR_TRACK_WIDTH, 0, 1)
        if state.bridge.context.store:Get().cosmeticMode == "gloves" then
            state.bridge.context.setGloveWear(alpha)
        else
            state.bridge.context.setWear(alpha)
        end
    end
    local wearActivePaint = registerActiveSliderPaint(controls.cosmetics.wearHit, function(painter, point)
        local alpha = math.clamp((point.X - state.wearStartX) / WEAR_TRACK_WIDTH, 0, 1)
        paintActiveSlider(
            painter,
            controls.cosmetics.wearTrack,
            WEAR_TRACK_WIDTH * alpha,
            state.wearStartX + WEAR_TRACK_WIDTH * alpha,
            6,
            colors.accent,
            colors.text
        )
    end)
    for _, eventName in ipairs({ "pointerdown", "drag", "pointerup" }) do
        controls.cosmetics.wearHit:on(eventName, function(_node, point)
            setWear(point)
            if wearActivePaint then
                setRetainedSliderVisible(
                    state,
                    controls.cosmetics.wearFill,
                    controls.cosmetics.wearKnob,
                    eventName == "pointerup"
                )
            end
        end)
    end
    for channelName, channel in pairs(controls.cosmetics.colorChannels) do
        local function setColor(point)
            local current = state.bridge.context.store:Get().settings.gloveColorOverride
            if type(current) ~= "table" then
                return
            end
            local color = { b = current.b, g = current.g, r = current.r }
            color[channelName] = math.clamp((point.X - state.colorStartX) / COLOR_TRACK_WIDTH, 0, 1)
            state.bridge.context.setGloveColor(color)
        end
        local activePaint = registerActiveSliderPaint(channel.hit, function(painter, point)
            local alpha = math.clamp((point.X - state.colorStartX) / COLOR_TRACK_WIDTH, 0, 1)
            paintActiveSlider(
                painter,
                channel.track,
                COLOR_TRACK_WIDTH * alpha,
                state.colorStartX + COLOR_TRACK_WIDTH * alpha,
                5,
                channel.label.Color,
                colors.text
            )
        end)
        for _, eventName in ipairs({ "pointerdown", "drag", "pointerup" }) do
            channel.hit:on(eventName, function(_node, point)
                setColor(point)
                if activePaint then
                    setRetainedSliderVisible(
                        state,
                        channel.fill,
                        channel.knob,
                        eventName == "pointerup"
                    )
                end
            end)
        end
    end
end

function CosmeticsPanel:layout(x, _y, cursor)
    local cosmetics = self.controls.cosmetics
    cosmetics.header.Position = Vector2.new(x + CONTENT_INSET, cursor)
    cosmetics.headerLabel.Position = Vector2.new(x + CONTENT_INSET + 12, cursor + 9)
    cosmetics.indicator.Position = Vector2.new(x + CONTENT_INSET + CONTENT_WIDTH - 14, cursor + 7)
    cosmetics.weaponMode.Position = Vector2.new(x + CONTENT_INSET, cursor + 30)
    cosmetics.weaponModeLabel.Position = Vector2.new(x + CONTENT_INSET + MODE_WIDTH * 0.5, cursor + 37)
    cosmetics.gloveMode.Position = Vector2.new(x + CONTENT_INSET + MODE_WIDTH + 8, cursor + 30)
    cosmetics.gloveModeLabel.Position = Vector2.new(x + CONTENT_INSET + MODE_WIDTH + 8 + MODE_WIDTH * 0.5, cursor + 37)
    cosmetics.weaponPrevious.Position = Vector2.new(x + CONTENT_INSET, cursor + 58)
    cosmetics.weaponPreviousLabel.Position = Vector2.new(x + CONTENT_INSET + 15, cursor + 65)
    cosmetics.weaponBackground.Position = Vector2.new(x + CONTENT_INSET + 34, cursor + 58)
    cosmetics.weaponName.Position = Vector2.new(x + CONTENT_INSET + 34 + SELECTOR_WIDTH * 0.5, cursor + 66)
    cosmetics.weaponNext.Position = Vector2.new(x + CONTENT_INSET + CONTENT_WIDTH - 30, cursor + 58)
    cosmetics.weaponNextLabel.Position = Vector2.new(x + CONTENT_INSET + CONTENT_WIDTH - 15, cursor + 65)
    local weaponOffset = self.cosmeticMode == "weapon" and 34 or 0
    cosmetics.previous.Position = Vector2.new(x + CONTENT_INSET, cursor + 58 + weaponOffset)
    cosmetics.previousLabel.Position = Vector2.new(x + CONTENT_INSET + 15, cursor + 65 + weaponOffset)
    cosmetics.skinBackground.Position = Vector2.new(x + CONTENT_INSET + 34, cursor + 58 + weaponOffset)
    cosmetics.skinName.Position = Vector2.new(x + CONTENT_INSET + 34 + SELECTOR_WIDTH * 0.5, cursor + 66 + weaponOffset)
    cosmetics.next.Position = Vector2.new(x + CONTENT_INSET + CONTENT_WIDTH - 30, cursor + 58 + weaponOffset)
    cosmetics.nextLabel.Position = Vector2.new(x + CONTENT_INSET + CONTENT_WIDTH - 15, cursor + 65 + weaponOffset)
    cosmetics.wearLabel.Position = Vector2.new(x + CONTENT_INSET, cursor + 94 + weaponOffset)
    cosmetics.wearValue.Position = Vector2.new(x + CONTENT_INSET + CONTENT_WIDTH - 12, cursor + 94 + weaponOffset)
    self.wearStartX = x + CONTENT_INSET
    cosmetics.wearHit.Position = Vector2.new(x + CONTENT_INSET, cursor + 106 + weaponOffset)
    cosmetics.wearTrack.Position = Vector2.new(x + CONTENT_INSET, cursor + 115 + weaponOffset)
    cosmetics.wearFill.Position = cosmetics.wearTrack.Position
    cosmetics.statTrak.Position = Vector2.new(x + CONTENT_INSET, cursor + 132 + weaponOffset)
    cosmetics.statTrakLabel.Position = Vector2.new(x + CONTENT_INSET + 10, cursor + 140 + weaponOffset)
    cosmetics.statTrakValue.Position = Vector2.new(x + CONTENT_INSET + MODE_WIDTH - 18, cursor + 140 + weaponOffset)
    cosmetics.reset.Position = Vector2.new(x + CONTENT_INSET + MODE_WIDTH + 8, cursor + 132 + weaponOffset)
    cosmetics.resetLabel.Position = Vector2.new(x + CONTENT_INSET + MODE_WIDTH + 18, cursor + 140 + weaponOffset)
    self.colorStartX = x + CONTENT_INSET + 20
    for index, channelName in ipairs({ "r", "g", "b" }) do
        local channel = cosmetics.colorChannels[channelName]
        local channelY = cursor + 166 + weaponOffset + (index - 1) * 24
        channel.label.Position = Vector2.new(x + CONTENT_INSET, channelY + 4)
        channel.hit.Position = Vector2.new(x + CONTENT_INSET + 20, channelY)
        channel.track.Position = Vector2.new(x + CONTENT_INSET + 20, channelY + 8)
        channel.fill.Position = channel.track.Position
        channel.value.Position = Vector2.new(x + CONTENT_INSET + CONTENT_WIDTH - 8, channelY + 3)
    end
    return cursor
end

function CosmeticsPanel:panelHeight(baseHeight)
    local collapsedHeight = baseHeight + 36
    if not self.cosmeticsOpen then
        return collapsedHeight
    end
    if self.cosmeticMode == "weapon" then
        return collapsedHeight + 162
    end
    return collapsedHeight + (self.gloveColorVisible and 202 or 128)
end

function CosmeticsPanel:setVisible(visible)
    local cosmetics = self.controls.cosmetics
    cosmetics.header.Visible = visible
    cosmetics.headerLabel.Visible = visible
    cosmetics.indicator.Visible = visible
    for name, node in pairs(cosmetics) do
        if name ~= "header" and name ~= "headerLabel" and name ~= "indicator" then
            if name == "colorChannels" then
                for _, channel in pairs(node) do
                    setVisible(channel, visible and self.cosmeticsOpen and self.gloveColorVisible)
                end
            elseif WEAPON_CONTROLS[name] then
                node.Visible = visible and self.cosmeticsOpen and self.cosmeticMode == "weapon"
            else
                node.Visible = visible and self.cosmeticsOpen
            end
        end
    end
end

function CosmeticsPanel:render(current)
    local colors = self.theme
    local settings = current.settings
    self.cosmeticMode = current.cosmeticMode == "gloves" and "gloves" or "weapon"
    self.cosmeticsOpen = current.cosmeticsOpen == true
    local cosmeticMode = self.cosmeticMode
    local gloveColor = settings.gloveColorOverride
    self.gloveColorVisible = cosmeticMode == "gloves" and type(gloveColor) == "table"
    local cosmetics = cosmeticMode == "gloves" and (current.gloves or {}) or (current.cosmetics or {})
    local controls = self.controls.cosmetics
    local minimumWear = cosmetics.minimumWear or 0
    local maximumWear = cosmetics.maximumWear or 1
    local wearRange = maximumWear - minimumWear
    local wearAlpha = wearRange > 0 and ((cosmetics.wear or minimumWear) - minimumWear) / wearRange or 0
    controls.indicator.Text = self.cosmeticsOpen and "-" or "+"
    self.bridge.setControlColor(
        controls.weaponMode,
        cosmeticMode == "weapon" and colors.accentSurface or colors.elevated
    )
    self.bridge.setControlColor(
        controls.gloveMode,
        cosmeticMode == "gloves" and colors.accentSurface or colors.elevated
    )
    controls.weaponModeLabel.Color = cosmeticMode == "weapon" and colors.accent or colors.text
    controls.gloveModeLabel.Color = cosmeticMode == "gloves" and colors.accent or colors.text
    controls.weaponModeLabel.Text =
        cosmeticMode == "weapon" and (cosmetics.weapon or "Weapon") or "Weapons"
    controls.gloveModeLabel.Text =
        cosmeticMode == "gloves" and (cosmetics.weapon or "Gloves") or "Gloves"
    controls.weaponName.Text = current.cosmeticWeapon or current.activeWeapon or "Select weapon"
    controls.skinName.Text = cosmetics.skinLabel or cosmetics.skin or "Stock"
    controls.wearValue.Text = ("%.2f"):format(cosmetics.wear or 0)
    controls.wearFill.Size = Vector2.new(WEAR_TRACK_WIDTH * wearAlpha, 4)
    controls.wearKnob.Position =
        Vector2.new(self.wearStartX + WEAR_TRACK_WIDTH * wearAlpha, controls.wearTrack.Position.Y + 2)
    local supportsStatTrak = cosmeticMode ~= "gloves" and cosmetics.supportsStatTrak == true
    local solidColor = cosmeticMode == "gloves" and type(gloveColor) == "table"
    for _, channel in pairs(controls.colorChannels) do
        setVisible(channel, self.cosmeticsOpen and solidColor)
    end
    self.bridge.setControlColor(
        controls.statTrak,
        solidColor and colors.accentSurface
            or (supportsStatTrak
                and (cosmetics.statTrak and colors.accentSurface or colors.elevated)
                or colors.elevated)
    )
    controls.statTrakLabel.Color =
        (supportsStatTrak or cosmeticMode == "gloves") and colors.text or colors.secondary
    controls.statTrakValue.Color =
        (solidColor or (supportsStatTrak and cosmetics.statTrak)) and colors.accent or colors.secondary
    controls.statTrakLabel.Text = cosmeticMode == "gloves" and "Solid Color" or "StatTrak"
    controls.statTrakValue.Text = cosmeticMode == "gloves"
            and (solidColor and "On" or "Off")
        or (not supportsStatTrak and "N/A" or (cosmetics.statTrak and "On" or "Off"))
    if solidColor then
        for _, channelName in ipairs({ "r", "g", "b" }) do
            local channel = controls.colorChannels[channelName]
            local value = math.clamp(gloveColor[channelName] or 0, 0, 1)
            channel.fill.Size = Vector2.new(COLOR_TRACK_WIDTH * value, 4)
            channel.knob.Position =
                Vector2.new(self.colorStartX + COLOR_TRACK_WIDTH * value, channel.track.Position.Y + 2)
            channel.value.Text = tostring(math.round(value * 255))
        end
    end
    controls.resetLabel.Text = cosmeticMode == "gloves" and "Reset Game" or "Reset Stock"
end

function CosmeticsPanel:destroy() end

return CosmeticsPanel
]],
    ["ui/presentation/Runtime.lua"] = [[local Runtime = {}
Runtime.__index = Runtime

local PRIVATE = setmetatable({}, { __mode = "k" })
local function private(runtime)
    return assert(PRIVATE[runtime], "Presentation runtime is unavailable")
end

local function buildAvailability(capabilities)
    local available = {}
    for key, value in pairs(capabilities or {}) do
        local name = type(key) == "number" and value or key
        if value ~= false then
            available[name] = true
        end
    end
    return available
end

function Runtime.new(bridge, parts)
    assert(type(bridge) == "table", "Presentation runtime requires an Overlay facade")
    assert(type(bridge.node) == "function", "Presentation runtime requires node construction")
    assert(type(bridge.text) == "function", "Presentation runtime requires text construction")
    assert(type(bridge.setControlColor) == "function", "Presentation runtime requires control coloring")
    assert(type(bridge.requestLayout) == "function", "Presentation runtime requires layout invalidation")
    assert(bridge.controls and bridge.context and bridge.theme)
    assert(type(parts) == "table", "Presentation runtime requires control parts")
    assert(type(parts.standard) == "table" and type(parts.standard.new) == "function")
    assert(type(parts.cosmetics) == "table" and type(parts.cosmetics.new) == "function")

    local controls = bridge.controls
    controls.rates = {}
    controls.sections = {}
    controls.options = {}
    controls.cosmetics = {}

    local runtime = setmetatable({}, Runtime)
    PRIVATE[runtime] = {
        activeSliderVisuals = bridge.activeSliderVisuals,
        available = buildAvailability(bridge.capabilities),
        bridge = bridge,
        cosmeticsSupported = bridge.cosmeticsSupported == true,
        parts = parts,
        panels = {},
        standard = nil,
        cosmetics = nil,
    }
    return runtime
end

function Runtime:_standard()
    local state = private(self)
    if not state.standard then
        state.standard = state.parts.standard.new(state.bridge, state.available)
        self:register(state.standard)
    end
    return state.standard
end

function Runtime:register(panel)
    assert(type(panel) == "table", "Registered presentation panel must be a table")
    assert(type(panel.layout) == "function", "Registered presentation panel requires layout")
    assert(type(panel.render) == "function", "Registered presentation panel requires render")
    assert(type(panel.setVisible) == "function", "Registered presentation panel requires visibility")
    assert(type(panel.destroy) == "function", "Registered presentation panel requires cleanup")
    table.insert(private(self).panels, panel)
    if panel.page then
        self:_standard():includePage(panel.page)
    end
    return panel
end

function Runtime:supports(name)
    return private(self).available[name] == true
end

function Runtime:read()
    return private(self).bridge.context.store:Get()
end

function Runtime:patch(patch)
    return private(self).bridge.context.store:Patch(patch)
end

function Runtime:action(name, ...)
    local callback = private(self).bridge.context[name]
    assert(type(callback) == "function", "Unknown presentation action: " .. tostring(name))
    return callback(...)
end

function Runtime:node(kind, properties, pointerEvents)
    return private(self).bridge.node(kind, properties, pointerEvents == true)
end

function Runtime:interactive(node)
    return private(self).bridge.interactive(node)
end

function Runtime:text(properties, pointerEvents)
    return private(self).bridge.text(properties, pointerEvents)
end

function Runtime:setControlColor(node, color)
    return private(self).bridge.setControlColor(node, color)
end

function Runtime:requestLayout()
    return private(self).bridge.requestLayout()
end

function Runtime:controls()
    return private(self).bridge.controls
end

function Runtime:theme()
    return private(self).bridge.theme
end

function Runtime:uiParent()
    return private(self).bridge.context.uiParent
end

function Runtime:createInstance(className)
    local context = private(self).bridge.context
    return (context.createInstance or Instance.new)(className)
end

function Runtime:aim()
    return self:_standard():aim()
end

function Runtime:rate(id, label)
    return self:_standard():rate(id, label)
end

function Runtime:segmented(page, spec)
    -- The native catalog owns typed segmented controls. The legacy runtime
    -- only keeps the page visible while the menu migration completes.
    self:_standard():includePage(page)
    return spec
end

function Runtime:section(page, id, label, lineOffset, includesRates, columns)
    return self:_standard():section(page, id, label, lineOffset, includesRates, columns)
end

function Runtime:option(sectionId, rowIndex, id, label, parent, visibility)
    return self:_standard():option(sectionId, rowIndex, id, label, parent, visibility)
end

function Runtime:cosmetics()
    local state = private(self)
    if not state.cosmeticsSupported then
        return
    end
    if not state.cosmetics then
        self:_standard():includePage("Tools")
        state.cosmetics = state.parts.cosmetics.new(state.bridge)
        state.cosmetics.page = "Tools"
        self:register(state.cosmetics)
    end
end

function Runtime:finalize()
    local state = private(self)
    if state.standard then
        state.standard:finalize()
    end
    state.finalized = true
end

function Runtime:activePage()
    local state = private(self)
    return state.standard and state.standard:activePage() or nil
end

function Runtime:layout(x, y)
    local state = private(self)
    local shell = assert(state.bridge.theme.tokens.layout, "Presentation theme requires shell layout tokens")
    local activePage = self:activePage()
    local cursor = y + (activePage and shell.contentTopWithTabs or shell.contentTopWithoutTabs)
    for _, panel in ipairs(state.panels) do
        if not panel.page or panel.page == activePage then
            cursor = panel:layout(x, y, cursor) or cursor
        end
    end
    state.contentHeight = cursor - y + 12
    local panelHeight = state.contentHeight
    local current = state.bridge.context.store:Get()
    for _, panel in ipairs(state.panels) do
        if (not panel.page or panel.page == activePage) and type(panel.panelHeight) == "function" then
            panelHeight = panel:panelHeight(panelHeight, current) or panelHeight
        end
    end
    state.panelHeight = panelHeight
    local size = Vector2.new(shell.shellWidth, panelHeight)
    state.bridge.controls.panel.Size = size
    state.bridge.controls.panelShadow.Size = size
    state.bridge.controls.panelBorder.Size = size
    return state.contentHeight
end

function Runtime:render(current)
    local state = private(self)
    local shell = assert(state.bridge.theme.tokens.layout, "Presentation theme requires shell layout tokens")
    local panelHeight = state.contentHeight or shell.initialHeight
    local activePage = self:activePage()
    for _, panel in ipairs(state.panels) do
        if not panel.page or panel.page == activePage then
            panel:render(current)
        end
    end
    for _, panel in ipairs(state.panels) do
        if (not panel.page or panel.page == activePage) and type(panel.panelHeight) == "function" then
            panelHeight = panel:panelHeight(panelHeight, current) or panelHeight
        end
    end
    local size = Vector2.new(shell.shellWidth, panelHeight)
    state.panelHeight = panelHeight
    state.bridge.controls.panel.Size = size
    state.bridge.controls.panelShadow.Size = size
    state.bridge.controls.panelBorder.Size = size
end

function Runtime:setVisible(visible)
    local state = private(self)
    local activePage = self:activePage()
    for _, panel in ipairs(state.panels) do
        panel:setVisible(visible and (not panel.page or panel.page == activePage))
    end
    for node in pairs(state.activeSliderVisuals) do
        node.Visible = false
    end
end

function Runtime:setMousePosition(position)
    for _, panel in ipairs(private(self).panels) do
        if type(panel.setMousePosition) == "function" then
            panel:setMousePosition(position)
        end
    end
end

function Runtime:destroy()
    local state = PRIVATE[self]
    if not state then
        return
    end
    for index = #state.panels, 1, -1 do
        state.panels[index]:destroy()
    end
    table.clear(state.panels)
    PRIVATE[self] = nil
end

return Runtime
]],
    ["ui/presentation/StandardPanels.lua"] = [=[local StandardPanels = {}
StandardPanels.__index = StandardPanels

local LAYOUT = {
    cardContentInset = 12,
    cardInset = 20,
    columnGap = 8,
    contentWidth = 350,
    fovAmountTop = 12,
    fovCardHeight = 58,
    fovCardTop = 24,
    fovCircleInitialRadius = 180,
    fovLabelTop = 0,
    fovRangeLabelTop = 34,
    fovSliderHitTop = 22,
    fovSliderTrackTop = 36,
    fovTrackInset = 58,
    fovTrackWidth = 227,
    groupGap = 22,
    groupHeaderHeight = 32,
    innerControlWidth = 350,
    navigationIndicatorHalfWidth = 30,
    navigationIndicatorHeight = 1,
    navigationIndicatorWidth = 60,
    navigationEdgeInset = 29,
    optionLabelInset = 4,
    optionLabelTop = 13,
    optionMarkerLabelInset = 18,
    optionMarkerHeight = 12,
    optionMarkerLeft = 6,
    optionMarkerTop = 10,
    optionMarkerWidth = 2,
    optionSeparatorInset = 0,
    optionSwitchRightInset = 28,
    optionSwitchTop = 19,
    optionValueRightInset = 48,
    optionValueTop = 13,
    keycapHeight = 32,
    keycapWidth = 86,
    rateRowHeight = 39,
    rateLabelInset = 16,
    rateLabelTop = 13,
    rateSeparatorInset = 0,
    rateSliderHitTop = 5,
    rateSliderLeft = 122,
    rateSliderTrackTop = 17,
    rateTrackWidth = 171,
    rateValueRightInset = 20,
    responseHeaderHeight = 35,
    rowGap = 0,
    rowHeight = 38,
    settingsCardHeight = 76,
    settingsEyebrowTop = 14,
    settingsKeycapTop = 22,
    settingsLabelTop = 38,
    settingsValueTop = 31,
    sectionDividerGap = 16,
    sectionLabelTop = 6,
    sliderHitHeight = 28,
    tabBarHeight = 44,
    tabLabelTop = 14,
    tabsTop = 84,
    targetModeHeight = 34,
    targetModeLabelTop = 10,
    targetModeTitleGap = 30,
    targetModeTitleHeight = 28,
}

local LAYER = {
    activeControl = 206,
    activeLabel = 207,
    background = 201,
    control = 202,
    detail = 204,
    foreground = 203,
    knob = 205,
    worldFov = 50,
}
local CARD_INSET = LAYOUT.cardInset
local CARD_CONTENT_INSET = LAYOUT.cardContentInset
local CONTENT_WIDTH = LAYOUT.contentWidth
local FOV_TRACK_WIDTH = LAYOUT.fovTrackWidth
local FOV_CARD_HEIGHT = LAYOUT.fovCardHeight
local GROUP_GAP = LAYOUT.groupGap
local GROUP_HEADER_HEIGHT = LAYOUT.groupHeaderHeight
local INNER_CONTROL_WIDTH = LAYOUT.innerControlWidth
local KEYCAP_WIDTH = LAYOUT.keycapWidth
local RATE_TRACK_WIDTH = LAYOUT.rateTrackWidth
local RATE_ROW_HEIGHT = LAYOUT.rateRowHeight
local ROW_GAP = LAYOUT.rowGap
local ROW_HEIGHT = LAYOUT.rowHeight
local SETTINGS_CARD_HEIGHT = LAYOUT.settingsCardHeight
local SLIDER_HIT_HEIGHT = LAYOUT.sliderHitHeight
local TAB_BAR_HEIGHT = LAYOUT.tabBarHeight
local PAGE_ORDER = { "Combat", "Rage", "Movement", "Visuals", "Tools", "Settings" }
local SINGLE_PIXEL = 1

local function segmentLayout(index, count, position, size)
    return {
        LabelPosition = Vector2.new(
            position.X + size.X * ((index - 0.5) / count),
            position.Y + LAYOUT.tabLabelTop
        ),
    }
end

local function navigationLayout(index, count, position, size)
    if count <= 2 then
        return segmentLayout(index, count, position, size)
    end
    return {
        LabelPosition = Vector2.new(
            position.X
                + LAYOUT.navigationEdgeInset
                + (size.X - LAYOUT.navigationEdgeInset * 2) * ((index - 1) / (count - 1)),
            position.Y + LAYOUT.tabLabelTop
        ),
    }
end

local function controlStyle(colors)
    local tokens = assert(colors.tokens, "Presentation theme requires shared tokens")
    return {
        Disabled = {},
        Focused = { Color = colors.hover, Transparency = tokens.opacity.focus },
        Frame = { Color = colors.border, Filled = false, Thickness = tokens.control.borderThickness, Transparency = tokens.opacity.edge, Visible = true },
        Hovered = { Color = colors.hover },
        Label = {
            Center = true,
            Color = colors.text,
            Font = tokens.font.control,
            Size = tokens.type.label,
            Visible = true,
        },
        Listening = { Color = colors.accentSurface },
        Option = { Color = colors.panel, Filled = true, Transparency = 1, Visible = true },
        Selected = {
            Color = colors.accent,
            Filled = false,
            Thickness = tokens.control.borderThickness,
            Transparency = tokens.opacity.edge,
        },
        SelectedLabel = {
            Color = colors.accent,
        },
        Value = {
            Center = true,
            Color = colors.accent,
            Font = tokens.font.control,
            Size = tokens.type.label,
            Visible = true,
        },
    }
end

local function navigationStyle(colors)
    local style = controlStyle(colors)
    style.Focused = { Color = colors.panel, Transparency = 1 }
    style.Frame = { Color = colors.panel, Filled = true, Transparency = 1, Visible = true }
    style.Hovered = { Color = colors.panel }
    style.Option = { Color = colors.panel, Filled = true, Transparency = 1, Visible = true }
    style.Selected = { Color = colors.panel }
    style.Label.Color = colors.secondary
    style.Label.Size = colors.tokens.type.primary
    return style
end

local function keybindStyle(colors)
    local tokens = colors.tokens
    local style = controlStyle(colors)
    style.Frame = {
        Color = colors.border,
        Filled = false,
        Thickness = tokens.control.borderThickness,
        Transparency = tokens.opacity.edge,
        Visible = true,
    }
    style.Listening = { Color = colors.accent }
    style.Value = {
        Center = true,
        Color = colors.secondary,
        Size = tokens.type.row,
        Visible = true,
    }
    return style
end

local function setVisible(nodes, visible)
    for _, node in pairs(nodes or {}) do
        if type(node) == "table" and (type(node.set) == "function" or node.Visible ~= nil) then
            node.Visible = visible
        elseif type(node) == "table" then
            setVisible(node, visible)
        end
    end
end

local function registerActiveSliderPaint(hit, layer, draw)
    local connected, connection = pcall(function()
        return hit:paintCaptured(layer, function(painter, event)
            draw(painter, event.position)
        end)
    end)
    return connected and connection ~= nil
end

local function setRetainedSliderVisible(state, fill, knob, visible)
    fill.Visible = visible
    knob.Visible = visible
    if visible then
        state.activeSliderVisuals[fill] = nil
        state.activeSliderVisuals[knob] = nil
        state.bridge.refreshVisibility()
    else
        state.activeSliderVisuals[fill] = true
        state.activeSliderVisuals[knob] = true
    end
end

local function paintActiveSlider(painter, track, fillWidth, knobX, knobRadius, trackHeight, fillColor, knobColor)
    painter.FilledRectangle(
        track.Position,
        Vector2.new(math.max(0, fillWidth), trackHeight),
        fillColor,
        1,
        0
    )
    painter.FilledCircle(
        Vector2.new(knobX, track.Position.Y + track.Size.Y * 0.5),
        knobRadius,
        knobColor,
        1,
        32
    )
end

local function slider(state, options)
    return {
        hit = state.bridge.node("Square", options.hit, true),
        track = state.bridge.node("Square", options.track, false),
        fill = state.bridge.node("Square", options.fill, false),
        knob = state.bridge.node("Circle", options.knob, false),
    }
end

local function card(state, options)
    return {
        background = state.bridge.node("Square", options.background, false),
        border = state.bridge.node("Square", options.border, false),
    }
end

function StandardPanels.new(bridge, available)
    local aimControlsSupported = available.silentAim == true
        or available.shotAim == true
        or available.triggerBot == true
        or available.aimSmoothness == true
        or available.aimAssistStrength == true
        or available.headshotRate == true
        or available.missRate == true
    return setmetatable({
        activeSliderVisuals = bridge.activeSliderVisuals,
        aimControlsSupported = aimControlsSupported,
        available = available,
        bridge = bridge,
        controls = bridge.controls,
        ephemeralSettings = {},
        groups = {},
        groupById = {},
        pages = {},
        activePageName = nil,
        optionSupport = bridge.optionSupport or {},
        parents = {},
        rates = {},
        theme = bridge.theme,
    }, StandardPanels)
end

function StandardPanels:_page(name)
    local page = self.pages[name]
    if not page then
        page = { hasContent = false, name = name }
        self.pages[name] = page
    end
    return page
end

function StandardPanels:_markPage(name)
    self:_page(name).hasContent = true
end

function StandardPanels:includePage(name)
    self:_markPage(name)
end

function StandardPanels:activePage()
    return self.activePageName
end

function StandardPanels:finalize()
    if self.finalized then
        return
    end
    self.finalized = true
    local hasContent = false
    for _, page in pairs(self.pages) do
        if page.hasContent then
            hasContent = true
            break
        end
    end
    if not hasContent then
        return
    end
    self:_markPage("Settings")
    local options = {}
    for _, name in ipairs(PAGE_ORDER) do
        if self:_page(name).hasContent then
            table.insert(options, { Label = name, Value = name })
        end
    end
    self.pageOptions = options
    self.pageIndexByName = {}
    for index, option in ipairs(options) do
        self.pageIndexByName[option.Value] = index
    end
    self.activePageName = options[1].Value
    self.controls.navigation = self.controls.navigation or {}
    local tokens = self.theme.tokens
    self.controls.navigation.tabs = self.bridge.createSegmentedControl({
        CornerRadius = tokens.control.segmentCornerRadius,
        Layout = navigationLayout,
        Options = options,
        Position = Vector2.zero,
        Size = Vector2.new(CONTENT_WIDTH, TAB_BAR_HEIGHT),
        Style = navigationStyle(self.theme),
        Value = self.activePageName,
        ZIndex = LAYER.foreground,
    })
    self.controls.navigation.indicator = self.bridge.node("Square", {
        Color = self.theme.accent,
        Filled = true,
        Size = Vector2.zero,
        Visible = true,
        ZIndex = LAYER.activeControl,
    }, false)
    self.controls.navigation.rule = self.bridge.node("Square", {
        Color = self.theme.border,
        Filled = true,
        Size = Vector2.new(CONTENT_WIDTH, SINGLE_PIXEL),
        Transparency = tokens.opacity.divider,
        Visible = true,
        ZIndex = LAYER.control,
    }, false)
    self.controls.navigation.tabs.Changed:Connect(function(value, _previous, source)
        if source == "programmatic" or self.activePageName == value then
            return
        end
        self.activePageName = value
        self.bridge.refreshVisibility()
        if type(self.bridge.requestRender) == "function" then
            self.bridge.requestRender()
        else
            self.bridge.requestLayout()
        end
    end)
    self.controls.navigation.menuKey = self.bridge.createKeybindControl({
        Disabled = true,
        Position = Vector2.zero,
        Size = Vector2.new(KEYCAP_WIDTH, LAYOUT.keycapHeight),
        Style = keybindStyle(self.theme),
        Value = "RightShift",
        ZIndex = LAYER.foreground,
    })
    self.controls.settings = {
        background = self.bridge.node("Square", {
            Color = self.theme.elevated,
            Filled = true,
            Size = Vector2.new(CONTENT_WIDTH, SETTINGS_CARD_HEIGHT),
            Visible = true,
            ZIndex = LAYER.background,
        }, false),
        border = self.bridge.node("Square", {
            Color = self.theme.border,
            Filled = false,
            Size = Vector2.new(CONTENT_WIDTH, SETTINGS_CARD_HEIGHT),
            Thickness = tokens.control.borderThickness,
            Transparency = tokens.opacity.edge,
            Visible = true,
            ZIndex = LAYER.control,
        }, false),
        eyebrow = self.bridge.text({
            Color = self.theme.text,
            Font = tokens.font.heading,
            Size = tokens.type.section,
            Text = "Menu",
            ZIndex = LAYER.foreground,
        }),
        label = self.bridge.text({
            Color = self.theme.secondary,
            Size = tokens.type.row,
            Text = "Fixed keyboard shortcut",
            ZIndex = LAYER.foreground,
        }),
    }
end

function StandardPanels:aim()
    if self.aimBuilt or not self.aimControlsSupported then
        return
    end
    self.aimBuilt = true
    self:_markPage("Combat")
    local state = self
    local controls = state.controls
    local colors = state.theme
    local tokens = colors.tokens

    local fovCard = card(state, {
        background = {
            Color = colors.elevated, Filled = true, Size = Vector2.new(CONTENT_WIDTH, FOV_CARD_HEIGHT), Visible = true, ZIndex = LAYER.background,
        },
        border = {
            Color = colors.border, Filled = false, Size = Vector2.new(CONTENT_WIDTH, FOV_CARD_HEIGHT), Thickness = tokens.control.borderThickness, Transparency = tokens.opacity.edge, Visible = true, ZIndex = LAYER.control,
        },
    })
    controls.fovCard = fovCard.background
    controls.fovCardBorder = fovCard.border
    controls.fovTopHighlight = state.bridge.node("Square", {
        Color = colors.border,
        Filled = true,
        Size = Vector2.zero,
        Transparency = tokens.opacity.edge,
        Visible = false,
        ZIndex = LAYER.foreground,
    }, false)
    controls.targetingLabel = state.bridge.text({
        Color = colors.tertiary,
        Size = tokens.type.eyebrow,
        Text = "",
        Visible = false,
        ZIndex = LAYER.foreground,
    })
    controls.fovLabel = state.bridge.text({
        Color = colors.text,
        Font = tokens.font.heading,
        Size = tokens.type.section,
        Text = "FOV",
        ZIndex = LAYER.control,
    })
    controls.fovValue = state.bridge.text({
        Center = true,
        Color = colors.secondary,
        Size = tokens.type.primary,
        Text = "",
        ZIndex = LAYER.control,
    })
    controls.fovAmount = state.bridge.text({
        Center = true,
        Color = colors.accent,
        Size = tokens.type.display,
        Text = "500 px",
        ZIndex = LAYER.foreground,
    })
    controls.targetModeLabel = state.bridge.text({
        Color = colors.text,
        Font = tokens.font.heading,
        Size = tokens.type.section,
        Text = "Target Mode",
        ZIndex = LAYER.foreground,
    })
    controls.fovMinimum = state.bridge.text({
        Color = colors.tertiary or colors.secondary,
        Size = tokens.type.meta,
        Text = "",
        ZIndex = LAYER.foreground,
    })
    controls.fovMaximum = state.bridge.text({
        Center = true,
        Color = colors.tertiary or colors.secondary,
        Size = tokens.type.meta,
        Text = "",
        ZIndex = LAYER.foreground,
    })
    controls.targetMode = state.bridge.createSegmentedControl({
        CornerRadius = tokens.control.segmentCornerRadius,
        Layout = segmentLayout,
        Options = {
            { Label = "Radius", Value = "radius" },
            { Label = "Fullscreen", Value = "fullscreen" },
        },
        Position = Vector2.zero,
        Size = Vector2.new(INNER_CONTROL_WIDTH, LAYOUT.targetModeHeight),
        Style = controlStyle(colors),
        Value = "radius",
        ZIndex = LAYER.foreground,
    })
    controls.targetMode.Changed:Connect(function(value, _previous, source)
        if source ~= "programmatic" then
            state.bridge.context.setOption("fullScreenAim", value == "fullscreen")
        end
    end)
    local fovSlider = slider(state, {
        hit = { Color = colors.panel, Filled = true, Size = Vector2.new(FOV_TRACK_WIDTH, SLIDER_HIT_HEIGHT), Transparency = tokens.opacity.hitbox, Visible = true, ZIndex = LAYER.control },
        track = { Color = colors.track, Filled = true, Size = Vector2.new(FOV_TRACK_WIDTH, tokens.control.sliderTrackHeight), Visible = true, ZIndex = LAYER.foreground },
        fill = { Color = colors.accent, Filled = true, Visible = true, ZIndex = LAYER.detail },
        knob = { Color = colors.accent, Filled = true, NumSides = tokens.control.sliderCircleSides, Radius = tokens.control.fovThumbRadius, Visible = true, ZIndex = LAYER.knob },
    })
    controls.sliderHit = fovSlider.hit
    controls.sliderTrack = fovSlider.track
    controls.sliderFill = fovSlider.fill
    controls.sliderKnob = fovSlider.knob
    controls.fovCircle = state.bridge.node("Circle", {
        Color = colors.accent,
        Filled = false,
        NumSides = tokens.control.fovCircleSides,
        Radius = LAYOUT.fovCircleInitialRadius,
        Thickness = tokens.control.fovCircleThickness,
        Transparency = tokens.opacity.fovCircle,
        Visible = true,
        ZIndex = LAYER.worldFov,
    }, false)

    local function setFov(point, persist)
        local current = state.bridge.context.store:Get()
        if current.settings.fullScreenAim then
            return
        end
        local alpha = math.clamp((point.X - state.sliderStartX) / FOV_TRACK_WIDTH, 0, 1)
        local settings = current.settings
        state.bridge.context.setFov(
            settings.minimumFov + (settings.maximumFov - settings.minimumFov) * alpha,
            persist
        )
    end
    local function fovSliderEnabled()
        return state.bridge.context.store:Get().settings.fullScreenAim ~= true
    end
    local fovActivePaint = registerActiveSliderPaint(controls.sliderHit, LAYER.activeControl, function(painter, point)
        if not fovSliderEnabled() then
            return
        end
        local alpha = math.clamp((point.X - state.sliderStartX) / FOV_TRACK_WIDTH, 0, 1)
        local knobX = state.sliderStartX + FOV_TRACK_WIDTH * alpha
        paintActiveSlider(
            painter,
            controls.sliderTrack,
            FOV_TRACK_WIDTH * alpha,
            knobX,
            tokens.control.fovThumbRadius,
            tokens.control.sliderTrackHeight,
            colors.accent,
            colors.accent
        )
    end)
    controls.sliderHit:on("pointerdown", function(_node, point)
        setFov(point, false)
        if fovActivePaint and fovSliderEnabled() then
            setRetainedSliderVisible(state, controls.sliderFill, controls.sliderKnob, false)
        end
    end)
    controls.sliderHit:on("drag", function(_node, point)
        setFov(point, false)
        if fovActivePaint and fovSliderEnabled() then
            setRetainedSliderVisible(state, controls.sliderFill, controls.sliderKnob, false)
        end
    end)
    controls.sliderHit:on("pointerup", function(_node, point)
        setFov(point, true)
        if fovActivePaint then
            setRetainedSliderVisible(state, controls.sliderFill, controls.sliderKnob, true)
        end
    end)
end

function StandardPanels:slider(_sectionId, _id, _label, _spec)
end

function StandardPanels:rate(id, label)
    if not self.available[id] or self.controls.rates[id] then
        return
    end
    local state = self
    state:_markPage("Combat")
    local colors = state.theme
    local tokens = colors.tokens
    local thumbRadius = tokens.control.rateThumbRadius
    local control = {
        slider = slider(state, {
            hit = { Color = colors.panel, Filled = true, Size = Vector2.new(RATE_TRACK_WIDTH, SLIDER_HIT_HEIGHT), Transparency = tokens.opacity.hitbox, Visible = true, ZIndex = LAYER.control },
            track = { Color = colors.track, Filled = true, Size = Vector2.new(RATE_TRACK_WIDTH, tokens.control.sliderTrackHeight), Visible = true, ZIndex = LAYER.foreground },
            fill = { Color = colors.accent, Filled = true, Visible = true, ZIndex = LAYER.detail },
            knob = { Color = colors.accent, Filled = true, NumSides = tokens.control.sliderCircleSides, Radius = thumbRadius, Visible = true, ZIndex = LAYER.knob },
        }),
        label = state.bridge.text({
            Color = colors.text,
            Size = tokens.type.row,
            Text = label,
            ZIndex = LAYER.foreground,
        }),
        value = state.bridge.text({
            Center = true,
            Color = colors.accent,
            Size = tokens.type.rateValue,
            Text = "0%",
            ZIndex = LAYER.foreground,
        }),
        separator = state.bridge.node("Square", {
            Color = colors.border,
            Filled = true,
            Size = Vector2.new(INNER_CONTROL_WIDTH - LAYOUT.rateSeparatorInset * 2, SINGLE_PIXEL),
            Transparency = tokens.opacity.subDivider,
            Visible = true,
            ZIndex = LAYER.control,
        }, false),
    }
    control.hit = control.slider.hit
    control.track = control.slider.track
    control.fill = control.slider.fill
    control.knob = control.slider.knob
    local activePaint = registerActiveSliderPaint(control.hit, LAYER.activeControl, function(painter, point)
        local alpha = math.clamp((point.X - control.hit.Position.X) / RATE_TRACK_WIDTH, 0, 1)
        local thumbTravel = RATE_TRACK_WIDTH - thumbRadius * 2
        local thumbX = control.track.Position.X + thumbRadius + thumbTravel * alpha
        paintActiveSlider(
            painter,
            control.track,
            thumbX - control.track.Position.X,
            thumbX,
            thumbRadius,
            tokens.control.sliderTrackHeight,
            colors.accent,
            colors.accent
        )
    end)
    local function setRate(point, persist)
        local alpha = math.clamp((point.X - control.hit.Position.X) / RATE_TRACK_WIDTH, 0, 1)
        state.bridge.context.setRate(id, math.round(alpha * 100), persist)
    end
    control.hit:on("pointerdown", function(_node, point)
        setRate(point, false)
        if activePaint then
            setRetainedSliderVisible(state, control.fill, control.knob, false)
        end
    end)
    control.hit:on("drag", function(_node, point)
        setRate(point, false)
        if activePaint then
            setRetainedSliderVisible(state, control.fill, control.knob, false)
        end
    end)
    control.hit:on("pointerup", function(_node, point)
        setRate(point, true)
        if activePaint then
            setRetainedSliderVisible(state, control.fill, control.knob, true)
        end
    end)
    state.controls.rates[id] = control
    table.insert(state.rates, id)
end

function StandardPanels:section(page, id, label, lineOffset, includesRates, columns, spec)
    assert(not self.groupById[id], "Duplicate presentation section: " .. id)
    assert(type(page) == "string" and page ~= "", "Presentation sections require a game-owned page")
    local group = {
        id = id,
        page = page,
        label = label,
        lineOffset = lineOffset or 70,
        includesRates = includesRates == true,
        columns = columns or 1,
        ephemeral = page == "Rage" or (type(spec) == "table" and spec.persist == false),
        maxRow = 0,
        rows = {},
    }
    self.groupById[id] = group
    self:_page(group.page)
    table.insert(self.groups, group)
end

local function buildSection(state, group)
    if state.controls.sections[group.id] then
        return
    end
    local tokens = state.theme.tokens
    local rateCount = #state.rates
    state.controls.sections[group.id] = {
        divider = state.bridge.node("Square", {
            Color = state.theme.border,
            Filled = true,
            Size = Vector2.new(INNER_CONTROL_WIDTH, SINGLE_PIXEL),
            Transparency = tokens.opacity.divider,
            Visible = true,
            ZIndex = LAYER.control,
        }, false),
        label = state.bridge.text({
            Color = state.theme.text,
            Font = tokens.font.heading,
            Size = tokens.type.section,
            Text = group.label,
            ZIndex = LAYER.foreground,
        }),
        responseLabel = group.includesRates and state.bridge.text({
            Color = state.theme.text,
            Font = tokens.font.heading,
            Size = tokens.type.section,
            Text = "Response",
            ZIndex = LAYER.foreground,
        }) or nil,
        responseBackground = group.includesRates and state.bridge.node("Square", {
            Color = state.theme.elevated,
            Filled = true,
            Size = Vector2.new(INNER_CONTROL_WIDTH, math.max(1, rateCount) * RATE_ROW_HEIGHT),
            Visible = true,
            ZIndex = LAYER.background,
        }, false) or nil,
        responseBorder = group.includesRates and state.bridge.node("Square", {
            Color = state.theme.border,
            Filled = false,
            Size = Vector2.new(INNER_CONTROL_WIDTH, math.max(1, rateCount) * RATE_ROW_HEIGHT),
            Thickness = tokens.control.borderThickness,
            Transparency = tokens.opacity.edge,
            Visible = true,
            ZIndex = LAYER.control,
        }, false) or nil,
    }
end

function StandardPanels:option(sectionId, rowIndex, id, label, parent)
    if not self.available[id] then
        return
    end
    local state = self
    local group = assert(state.groupById[sectionId], "Unknown presentation section: " .. sectionId)
    local optionSpec = type(parent) == "table" and parent or nil
    local ephemeral = group.ephemeral or (optionSpec and optionSpec.persist == false)
    if ephemeral then
        state.ephemeralSettings[id] = true
    end
    buildSection(state, group)
    group.rows[rowIndex] = group.rows[rowIndex] or {}
    table.insert(group.rows[rowIndex], id)
    group.maxRow = math.max(group.maxRow, rowIndex)
    state.parents[id] = parent
    state:_markPage(group.page)

    local colors = state.theme
    local tokens = colors.tokens
    local controlTokens = tokens.control
    local row = state.bridge.interactive(state.bridge.node("Square", {
        Color = colors.panel,
        Filled = true,
        Size = Vector2.new(INNER_CONTROL_WIDTH, ROW_HEIGHT),
        Visible = true,
        ZIndex = LAYER.control,
    }, true))
    local labelNode = state.bridge.text({
        Color = colors.text,
        Size = tokens.type.row,
        Text = label,
        ZIndex = LAYER.foreground,
    })
    local value = state.bridge.text({
        Center = true,
        Color = colors.secondary,
        Size = tokens.type.meta,
        Text = "Off",
        ZIndex = LAYER.foreground,
    })
    local separator = state.bridge.node("Square", {
        Color = colors.border,
        Filled = true,
        Size = Vector2.new(INNER_CONTROL_WIDTH - LAYOUT.optionSeparatorInset * 2, SINGLE_PIXEL),
        Transparency = tokens.opacity.subDivider,
        Visible = true,
        ZIndex = LAYER.control,
    }, false)
    local function switchNode(kind, properties)
        return state.bridge.node(kind, properties, false)
    end
    local switchShadowTrack = switchNode("Square", {
        Color = colors.panelShadow, Filled = true, Size = Vector2.new(controlTokens.switchTrackWidth, controlTokens.switchOuterTrackHeight), Visible = true, ZIndex = LAYER.foreground,
    })
    local switchShadowLeft = switchNode("Circle", {
        Color = colors.panelShadow, Filled = true, NumSides = controlTokens.switchCircleSides, Radius = controlTokens.switchOuterRadius, Visible = true, ZIndex = LAYER.foreground,
    })
    local switchShadowRight = switchNode("Circle", {
        Color = colors.panelShadow, Filled = true, NumSides = controlTokens.switchCircleSides, Radius = controlTokens.switchOuterRadius, Visible = true, ZIndex = LAYER.foreground,
    })
    local switchTrack = switchNode("Square", {
        Color = colors.border, Filled = true, Size = Vector2.new(controlTokens.switchTrackWidth, controlTokens.switchOuterTrackHeight), Visible = true, ZIndex = LAYER.detail,
    })
    local switchLeft = switchNode("Circle", {
        Color = colors.border, Filled = true, NumSides = controlTokens.switchCircleSides, Radius = controlTokens.switchOuterRadius, Visible = true, ZIndex = LAYER.detail,
    })
    local switchRight = switchNode("Circle", {
        Color = colors.border, Filled = true, NumSides = controlTokens.switchCircleSides, Radius = controlTokens.switchOuterRadius, Visible = true, ZIndex = LAYER.detail,
    })
    local switchFillTrack = switchNode("Square", {
        Color = colors.elevated, Filled = true, Size = Vector2.new(controlTokens.switchTrackWidth, controlTokens.switchInnerTrackHeight), Visible = true, ZIndex = LAYER.knob,
    })
    local switchFillLeft = switchNode("Circle", {
        Color = colors.elevated, Filled = true, NumSides = controlTokens.switchCircleSides, Radius = controlTokens.switchInnerRadius, Visible = true, ZIndex = LAYER.knob,
    })
    local switchFillRight = switchNode("Circle", {
        Color = colors.elevated, Filled = true, NumSides = controlTokens.switchCircleSides, Radius = controlTokens.switchInnerRadius, Visible = true, ZIndex = LAYER.knob,
    })
    local switchKnobRim = switchNode("Circle", {
        Color = colors.border, Filled = true, NumSides = controlTokens.switchCircleSides, Radius = controlTokens.switchKnobRimRadius, Visible = true, ZIndex = LAYER.activeControl,
    })
    local switchKnob = switchNode("Circle", {
        Color = colors.text, Filled = true, NumSides = controlTokens.switchCircleSides, Radius = controlTokens.switchKnobRadius, Visible = true, ZIndex = LAYER.activeLabel,
    })
    local marker
    if parent then
        marker = switchNode("Square", {
            Color = colors.border,
            Filled = true,
            Size = Vector2.new(LAYOUT.optionMarkerWidth, LAYOUT.optionMarkerHeight),
            Visible = true,
            ZIndex = LAYER.foreground,
        })
    end
    row:on("click", function()
        if state.optionSupport[id] == false then
            return
        end
        local current = state.bridge.context.store:Get()
        state.bridge.context.setOption(id, not current.settings[id], not ephemeral)
    end)
    state.controls.options[id] = {
        row = row,
        separator = separator,
        sectionId = sectionId,
        label = labelNode,
        marker = marker,
        switch = {
            fillLeft = switchFillLeft,
            fillRight = switchFillRight,
            fillTrack = switchFillTrack,
            knob = switchKnob,
            knobRim = switchKnobRim,
            left = switchLeft,
            right = switchRight,
            shadowLeft = switchShadowLeft,
            shadowRight = switchShadowRight,
            shadowTrack = switchShadowTrack,
            track = switchTrack,
        },
        value = value,
    }
end

function StandardPanels:layout(x, y, cursor)
    local controls = self.controls
    local controlTokens = self.theme.tokens.control
    local settings = self.bridge.context.store:Get().settings
    if controls.navigation then
        controls.navigation.tabs:setLayout({
            Layout = navigationLayout,
            Position = Vector2.new(x + CARD_INSET, y + LAYOUT.tabsTop),
            Size = Vector2.new(CONTENT_WIDTH, TAB_BAR_HEIGHT),
        })
        local activeIndex = self.pageIndexByName[self.activePageName]
        local activeTabLayout = navigationLayout(
            activeIndex,
            #self.pageOptions,
            Vector2.new(x + CARD_INSET, y + LAYOUT.tabsTop),
            Vector2.new(CONTENT_WIDTH, TAB_BAR_HEIGHT)
        )
        controls.navigation.rule.Position = Vector2.new(
            x + CARD_INSET,
            y + LAYOUT.tabsTop + TAB_BAR_HEIGHT - SINGLE_PIXEL
        )
        controls.navigation.indicator.Position = Vector2.new(
            activeTabLayout.LabelPosition.X - LAYOUT.navigationIndicatorHalfWidth,
            y + LAYOUT.tabsTop + TAB_BAR_HEIGHT - LAYOUT.navigationIndicatorHeight
        )
        controls.navigation.indicator.Size = Vector2.new(
            LAYOUT.navigationIndicatorWidth,
            LAYOUT.navigationIndicatorHeight
        )
    end
    if self.aimBuilt and self.activePageName == "Combat" then
        local fovCardX = x + CARD_INSET
        local fovCardY = cursor + LAYOUT.fovCardTop
        controls.fovLabel.Position = Vector2.new(fovCardX, cursor + LAYOUT.fovLabelTop)
        controls.fovCard.Position = Vector2.new(fovCardX, fovCardY)
        controls.fovCardBorder.Position = controls.fovCard.Position
        controls.fovTopHighlight.Position = controls.fovCard.Position
        self.sliderStartX = fovCardX + LAYOUT.fovTrackInset
        controls.sliderHit.Position = Vector2.new(self.sliderStartX, fovCardY + LAYOUT.fovSliderHitTop)
        controls.sliderTrack.Position = Vector2.new(self.sliderStartX, fovCardY + LAYOUT.fovSliderTrackTop)
        controls.sliderFill.Position = controls.sliderTrack.Position
        local fovAlpha = (settings.fov - settings.minimumFov)
            / (settings.maximumFov - settings.minimumFov)
        local fovThumbX = self.sliderStartX + FOV_TRACK_WIDTH * fovAlpha
        controls.sliderKnob.Position = Vector2.new(
            fovThumbX,
            controls.sliderTrack.Position.Y + controlTokens.sliderTrackHeight * 0.5
        )
        controls.fovAmount.Position = Vector2.new(fovThumbX, fovCardY + LAYOUT.fovAmountTop)
        controls.fovMinimum.Position = Vector2.new(fovCardX + CARD_CONTENT_INSET, fovCardY + LAYOUT.fovRangeLabelTop)
        controls.fovMaximum.Position = Vector2.new(
            fovCardX + CONTENT_WIDTH - CARD_CONTENT_INSET - 12,
            fovCardY + LAYOUT.fovRangeLabelTop
        )

        local targetModeLabelY = fovCardY + FOV_CARD_HEIGHT + LAYOUT.targetModeTitleGap
        local targetModeY = targetModeLabelY + LAYOUT.targetModeTitleHeight
        controls.targetModeLabel.Position = Vector2.new(fovCardX, targetModeLabelY)
        controls.targetMode:setLayout({
            Layout = segmentLayout,
            Position = Vector2.new(fovCardX, targetModeY),
            Size = Vector2.new(INNER_CONTROL_WIDTH, LAYOUT.targetModeHeight),
        })
        cursor = targetModeY + LAYOUT.targetModeHeight + GROUP_GAP
    end

    if self.activePageName == "Settings" and controls.navigation then
        local settings = controls.settings
        settings.background.Position = Vector2.new(x + CARD_INSET, cursor)
        settings.border.Position = settings.background.Position
        settings.eyebrow.Position = Vector2.new(x + CARD_INSET + CARD_CONTENT_INSET, cursor + LAYOUT.settingsEyebrowTop)
        settings.label.Position = Vector2.new(x + CARD_INSET + CARD_CONTENT_INSET, cursor + LAYOUT.settingsLabelTop)
        controls.navigation.menuKey:setLayout({
            Position = Vector2.new(x + CARD_INSET + CONTENT_WIDTH - CARD_CONTENT_INSET - KEYCAP_WIDTH, cursor + LAYOUT.settingsKeycapTop),
            Size = Vector2.new(KEYCAP_WIDTH, LAYOUT.keycapHeight),
            Layout = {
                ValuePosition = Vector2.new(x + CARD_INSET + CONTENT_WIDTH - CARD_CONTENT_INSET - KEYCAP_WIDTH * 0.5, cursor + LAYOUT.settingsValueTop),
            },
        })
        return cursor + SETTINGS_CARD_HEIGHT + GROUP_GAP
    end

    for _, group in ipairs(self.groups) do
        if group.page == self.activePageName then
            local section = controls.sections[group.id]
            if section then
                local innerX = x + CARD_INSET
                if group.includesRates then
                    section.responseLabel.Position = Vector2.new(
                        innerX,
                        cursor + LAYOUT.sectionLabelTop
                    )
                    cursor = cursor + LAYOUT.responseHeaderHeight
                    local responseHeight = #self.rates * RATE_ROW_HEIGHT
                    section.responseBackground.Position = Vector2.new(innerX, cursor)
                    section.responseBackground.Size = Vector2.new(INNER_CONTROL_WIDTH, responseHeight)
                    section.responseBorder.Position = section.responseBackground.Position
                    section.responseBorder.Size = section.responseBackground.Size
                    for rateIndex, id in ipairs(self.rates) do
                        local control = controls.rates[id]
                        local rateY = cursor + (rateIndex - 1) * RATE_ROW_HEIGHT
                        control.label.Position = Vector2.new(
                            innerX + LAYOUT.rateLabelInset,
                            rateY + LAYOUT.rateLabelTop
                        )
                        control.value.Position = Vector2.new(
                            innerX + INNER_CONTROL_WIDTH - LAYOUT.rateValueRightInset,
                            rateY + LAYOUT.rateLabelTop
                        )
                        control.hit.Position = Vector2.new(
                            innerX + LAYOUT.rateSliderLeft,
                            rateY + LAYOUT.rateSliderHitTop
                        )
                        control.track.Position = Vector2.new(
                            innerX + LAYOUT.rateSliderLeft,
                            rateY + LAYOUT.rateSliderTrackTop
                        )
                        control.fill.Position = control.track.Position
                        control.separator.Position = Vector2.new(
                            innerX + LAYOUT.rateSeparatorInset,
                            rateY + RATE_ROW_HEIGHT - SINGLE_PIXEL
                        )
                        local rateValue = math.clamp(settings[id] or 0, 0, 100)
                        local rateThumbRadius = controlTokens.rateThumbRadius
                        local rateThumbTravel = RATE_TRACK_WIDTH - rateThumbRadius * 2
                        local rateThumbX = control.track.Position.X
                            + rateThumbRadius
                            + rateThumbTravel * (rateValue / 100)
                        control.knob.Position = Vector2.new(
                            rateThumbX,
                            control.track.Position.Y + controlTokens.sliderTrackHeight * 0.5
                        )
                    end
                    cursor = cursor + responseHeight + GROUP_GAP
                end

                section.divider.Position = Vector2.new(innerX, cursor)
                cursor = cursor + LAYOUT.sectionDividerGap

                section.label.Position = Vector2.new(
                    innerX,
                    cursor + LAYOUT.sectionLabelTop
                )
                cursor = cursor + GROUP_HEADER_HEIGHT

                local optionRowCount = 0
                for rowIndex = 1, group.maxRow do
                    local rowOptions = group.rows[rowIndex] or {}
                    local columns = math.max(1, group.columns)
                    local visualRows = math.ceil(#rowOptions / columns)
                    optionRowCount = optionRowCount + visualRows
                    local columnWidth = (INNER_CONTROL_WIDTH - LAYOUT.columnGap * (columns - 1)) / columns
                    for optionIndex, optionName in ipairs(rowOptions) do
                        local option = controls.options[optionName]
                        if option then
                            local columnIndex = (optionIndex - 1) % columns
                            local visualRowIndex = math.floor((optionIndex - 1) / columns)
                            local rowX = innerX
                                + columnIndex * (columnWidth + LAYOUT.columnGap)
                            local rowY = cursor + visualRowIndex * (ROW_HEIGHT + ROW_GAP)
                            option.row.Position = Vector2.new(rowX, rowY)
                            option.row.Size = Vector2.new(columnWidth, ROW_HEIGHT)
                            option.separator.Position = Vector2.new(
                                rowX + LAYOUT.optionSeparatorInset,
                                rowY + ROW_HEIGHT - SINGLE_PIXEL
                            )
                            option.separator.Size = Vector2.new(
                                columnWidth - LAYOUT.optionSeparatorInset * 2,
                                SINGLE_PIXEL
                            )
                            if option.marker then
                                option.marker.Position = Vector2.new(
                                    rowX + LAYOUT.optionMarkerLeft,
                                    rowY + LAYOUT.optionMarkerTop
                                )
                            end
                            local parentAvailable = not option.marker
                                or settings[self.parents[optionName]] == true
                            option.label.Position = Vector2.new(
                                rowX
                                    + (option.marker and parentAvailable and LAYOUT.optionMarkerLabelInset
                                        or LAYOUT.optionLabelInset),
                                rowY + LAYOUT.optionLabelTop
                            )
                            option.value.Position = Vector2.new(
                                rowX + columnWidth - LAYOUT.optionValueRightInset,
                                rowY + LAYOUT.optionValueTop
                            )
                            local switchX = rowX + columnWidth - LAYOUT.optionSwitchRightInset
                            local switchY = rowY + LAYOUT.optionSwitchTop
                            local halfTrackWidth = controlTokens.switchTrackWidth * 0.5
                            local outerHalfHeight = controlTokens.switchOuterTrackHeight * 0.5
                            local innerHalfHeight = controlTokens.switchInnerTrackHeight * 0.5
                            local shadowOffset = SINGLE_PIXEL
                            option.switch.shadowTrack.Position = Vector2.new(
                                switchX - halfTrackWidth,
                                switchY - outerHalfHeight + shadowOffset
                            )
                            option.switch.shadowLeft.Position = Vector2.new(
                                switchX - halfTrackWidth,
                                switchY + shadowOffset
                            )
                            option.switch.shadowRight.Position = Vector2.new(
                                switchX + halfTrackWidth,
                                switchY + shadowOffset
                            )
                            option.switch.track.Position = Vector2.new(
                                switchX - halfTrackWidth,
                                switchY - outerHalfHeight
                            )
                            option.switch.left.Position = Vector2.new(switchX - halfTrackWidth, switchY)
                            option.switch.right.Position = Vector2.new(switchX + halfTrackWidth, switchY)
                            option.switch.fillTrack.Position = Vector2.new(
                                switchX - halfTrackWidth,
                                switchY - innerHalfHeight
                            )
                            option.switch.fillLeft.Position = Vector2.new(switchX - halfTrackWidth, switchY)
                            option.switch.fillRight.Position = Vector2.new(switchX + halfTrackWidth, switchY)
                            local knobPosition = Vector2.new(
                                switchX + (settings[optionName] == true and halfTrackWidth or -halfTrackWidth),
                                switchY
                            )
                            option.switch.knobRim.Position = knobPosition
                            option.switch.knob.Position = knobPosition
                        end
                    end
                    if visualRows > 0 then
                        cursor = cursor + visualRows * (ROW_HEIGHT + ROW_GAP)
                    end
                end
                if optionRowCount > 0 then
                    cursor = cursor - ROW_GAP
                end
                cursor = cursor + GROUP_GAP
            end
        end
    end
    return cursor
end

function StandardPanels:setVisible(visible)
    local controls = self.controls
    local combatVisible = visible and self.activePageName == "Combat"
    if controls.navigation then
        controls.navigation.tabs:setVisible(visible)
        controls.navigation.indicator.Visible = visible
        controls.navigation.rule.Visible = visible
        controls.navigation.menuKey:setVisible(visible and self.activePageName == "Settings")
        setVisible(controls.settings, visible and self.activePageName == "Settings")
    end
    if self.aimBuilt then
        for _, name in ipairs({
            "fovCard",
            "fovCardBorder",
            "fovLabel",
            "fovAmount",
            "fovMinimum",
            "fovMaximum",
            "targetModeLabel",
            "sliderHit",
            "sliderTrack",
            "sliderFill",
            "sliderKnob",
        }) do
            controls[name].Visible = combatVisible
        end
        controls.targetMode:setVisible(combatVisible)
        controls.fovValue.Visible = false
        controls.fovTopHighlight.Visible = false
        controls.targetingLabel.Visible = false
    end
    for _, option in pairs(controls.options) do
        local optionVisible = visible and self.groupById[option.sectionId].page == self.activePageName
        setVisible(option, optionVisible)
        option.value.Visible = optionVisible
            and (option.value.Text == "N/A" or option.value.Text == "Standby")
    end
    for _, rate in pairs(controls.rates) do
        setVisible(rate, combatVisible)
    end
    for _, group in ipairs(self.groups) do
        if controls.sections[group.id] then
            setVisible(controls.sections[group.id], visible and group.page == self.activePageName)
        end
    end
end

function StandardPanels:render(current)
    local settings = current.settings
    local controls = self.controls
    local colors = self.theme
    local tokens = colors.tokens
    local rateThumbRadius = tokens.control.rateThumbRadius

    for optionName, option in pairs(controls.options) do
        if self.groupById[option.sectionId].page == self.activePageName then
            local enabled = settings[optionName] == true
            local parent = self.parents[optionName]
            local supported = self.optionSupport[optionName] ~= false
            local available = supported and (not parent or settings[parent] == true)
            self.bridge.setControlColor(option.row, colors.panel)
            option.label.Color = available and colors.text or (colors.tertiary or colors.secondary)
            local trackColor = available and (enabled and colors.accent or colors.track) or colors.elevated
            local fillColor = available and (enabled and colors.accent or colors.elevated) or colors.elevated
            option.switch.track.Color = trackColor
            option.switch.left.Color = trackColor
            option.switch.right.Color = trackColor
            option.switch.fillTrack.Color = fillColor
            option.switch.fillLeft.Color = fillColor
            option.switch.fillRight.Color = fillColor
            option.switch.knobRim.Color = available and (enabled and colors.accent or colors.border) or colors.panel
            option.switch.knob.Color = available
                and (enabled and colors.text or colors.secondary)
                or colors.tertiary
            if option.marker then
                option.marker.Visible = available
            end
            local knobTravel = tokens.control.switchTrackWidth * 0.5
            local switchCenterX = option.switch.track.Position.X + knobTravel
            local switchCenterY = option.switch.left.Position.Y
            local knobPosition = Vector2.new(
                switchCenterX + (enabled and knobTravel or -knobTravel),
                switchCenterY
            )
            option.switch.knobRim.Position = knobPosition
            option.switch.knob.Position = knobPosition
            if option.marker then
                option.marker.Color = available and colors.accent or colors.border
            end
            option.value.Color = available and enabled and colors.accent or colors.secondary
            option.value.Text = not supported and "N/A"
                or (not available and enabled and "Standby" or "")
            option.value.Visible = current.menuVisible ~= false
                and (option.value.Text == "N/A" or option.value.Text == "Standby")
        end
    end

    if self.activePageName == "Combat" then
        for _, id in ipairs(self.rates) do
            local control = controls.rates[id]
            if not control or not control.track or not control.track.Position then
                continue
            end
            local value = math.clamp(settings[id] or 0, 0, 100)
            local alpha = value / 100
            local thumbTravel = RATE_TRACK_WIDTH - rateThumbRadius * 2
            local thumbX = control.track.Position.X + rateThumbRadius + thumbTravel * alpha
            control.fill.Size = Vector2.new(
                math.max(0, thumbX - control.track.Position.X),
                tokens.control.sliderTrackHeight
            )
            control.knob.Position = Vector2.new(
                thumbX,
                control.track.Position.Y + tokens.control.sliderTrackHeight * 0.5
            )
            control.value.Text = ("%d%%"):format(math.round(value))
            control.value.Color = colors.accent
        end
    end

    if self.aimBuilt and self.activePageName == "Combat" then
        local alpha = (settings.fov - settings.minimumFov) / (settings.maximumFov - settings.minimumFov)
        controls.sliderFill.Size = Vector2.new(
            FOV_TRACK_WIDTH * alpha,
            tokens.control.sliderTrackHeight
        )
        controls.sliderKnob.Position = Vector2.new(
            self.sliderStartX + FOV_TRACK_WIDTH * alpha,
            controls.sliderTrack.Position.Y + tokens.control.sliderTrackHeight * 0.5
        )
        controls.targetMode:setValue(settings.fullScreenAim and "fullscreen" or "radius")
        controls.sliderFill.Color = settings.fullScreenAim and colors.border or colors.accent
        controls.sliderKnob.Color = settings.fullScreenAim and colors.secondary or colors.accent
        controls.fovValue.Color = settings.fullScreenAim and colors.accent or colors.secondary
        controls.fovLabel.Text = "FOV"
        controls.fovAmount.Text = settings.fullScreenAim and "Fullscreen" or ("%d px"):format(math.round(settings.fov))
        controls.fovAmount.Position = Vector2.new(
            settings.fullScreenAim and (self.sliderStartX + FOV_TRACK_WIDTH * 0.5)
                or (self.sliderStartX + FOV_TRACK_WIDTH * alpha),
            controls.fovCard.Position.Y + LAYOUT.fovAmountTop
        )
        controls.fovMinimum.Text = ("%d px"):format(math.round(settings.minimumFov))
        controls.fovMaximum.Text = ("%d px"):format(math.round(settings.maximumFov))
        controls.fovValue.Text = "Fullscreen"
        controls.fovCircle.Radius = settings.fov
        controls.fovCircle.Visible = self.aimControlsSupported
            and settings.fovCircle ~= false
            and not settings.fullScreenAim
    end
end

function StandardPanels:setMousePosition(position)
    if self.controls.fovCircle then
        self.controls.fovCircle.Position = position
    end
end

function StandardPanels:destroy()
    if self.controls.navigation then
        self.controls.navigation.tabs:destroy()
        self.controls.navigation.menuKey:destroy()
    end
    if self.controls.targetMode then
        self.controls.targetMode:destroy()
    end
end

return StandardPanels
]=],
    ["vendor/Limn.lua"] = [[-- Generated by scripts/build.luau. Do not edit.
local __modules = {}
local __cache = {}
local function __require(name)
	if __cache[name] ~= nil then return __cache[name] end
	local loader = assert(__modules[name], "unknown Limn module " .. name)
	local value = loader()
	__cache[name] = value
	return value
end

__modules["Signal"] = function()

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, callback: (...any) -> ()) -> Connection,
	Once: (self: Signal, callback: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	Destroy: (self: Signal) -> (),
}

type PrivateSignal = Signal & {
	_nextId: number,
	_listeners: { [number]: (...any) -> () },
	_destroyed: boolean,
}

local Signal = {}
Signal.__index = Signal

function Signal.new(): Signal
	return setmetatable({
		_nextId = 0,
		_listeners = {},
		_destroyed = false,
	}, Signal) :: any
end

function Signal:Connect(callback: (...any) -> ()): Connection
	local self = self :: PrivateSignal
	assert(not self._destroyed, "cannot connect to a destroyed signal")

	self._nextId += 1
	local id = self._nextId
	self._listeners[id] = callback

	local connection = {
		Connected = true,
	} :: any

	function connection:Disconnect()
		if not self.Connected then
			return
		end
		self.Connected = false
		self._signal._listeners[self._id] = nil
	end

	connection._signal = self
	connection._id = id
	return connection
end

function Signal:Once(callback: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function Signal:Fire(...: any)
	local self = self :: PrivateSignal
	if self._destroyed then
		return
	end

	local snapshot = table.clone(self._listeners)
	for id, callback in snapshot do
		if self._listeners[id] == callback then
			callback(...)
		end
	end
end

function Signal:Destroy()
	local self = self :: PrivateSignal
	if self._destroyed then
		return
	end
	self._destroyed = true
	table.clear(self._listeners)
end

return Signal

end

__modules["Geometry"] = function()

export type Point = {
	X: number,
	Y: number,
}

type Properties = { [string]: any }

local Geometry = {}

local function distanceSquared(a: Point, b: Point): number
	local x = a.X - b.X
	local y = a.Y - b.Y
	return x * x + y * y
end

local function pointInTriangle(point: Point, a: Point, b: Point, c: Point): boolean
	local ab = (point.X - b.X) * (a.Y - b.Y) - (a.X - b.X) * (point.Y - b.Y)
	local bc = (point.X - c.X) * (b.Y - c.Y) - (b.X - c.X) * (point.Y - c.Y)
	local ca = (point.X - a.X) * (c.Y - a.Y) - (c.X - a.X) * (point.Y - a.Y)
	local hasNegative = ab < 0 or bc < 0 or ca < 0
	local hasPositive = ab > 0 or bc > 0 or ca > 0
	return not (hasNegative and hasPositive)
end

local function pointNearLine(point: Point, from: Point, to: Point, tolerance: number): boolean
	local dx = to.X - from.X
	local dy = to.Y - from.Y
	local lengthSquared = dx * dx + dy * dy
	if lengthSquared == 0 then
		return distanceSquared(point, from) <= tolerance * tolerance
	end

	local projection = ((point.X - from.X) * dx + (point.Y - from.Y) * dy) / lengthSquared
	local clamped = math.clamp(projection, 0, 1)
	local closest = {
		X = from.X + clamped * dx,
		Y = from.Y + clamped * dy,
	}
	return distanceSquared(point, closest) <= tolerance * tolerance
end

local function pointInRectangle(point: Point, position: Point, size: Point): boolean
	return point.X >= position.X
		and point.Y >= position.Y
		and point.X <= position.X + size.X
		and point.Y <= position.Y + size.Y
end

function Geometry.contains(
	kind: string,
	properties: Properties,
	point: Point,
	padding: number?
): boolean
	local extra = padding or 0

	if kind == "Square" or kind == "Image" then
		local position = properties.Position :: Point
		local size = properties.Size :: Point
		return pointInRectangle(point, {
			X = position.X - extra,
			Y = position.Y - extra,
		}, {
			X = size.X + extra * 2,
			Y = size.Y + extra * 2,
		})
	elseif kind == "Text" then
		local position = properties.Position :: Point
		local bounds = properties.TextBounds :: Point
		if properties.Center or properties.Centered then
			position = {
				X = position.X - bounds.X / 2,
				Y = position.Y,
			}
		end
		return pointInRectangle(point, position, bounds)
	elseif kind == "Circle" then
		local radius = properties.Radius + extra
		return distanceSquared(point, properties.Position) <= radius * radius
	elseif kind == "Line" then
		return pointNearLine(
			point,
			properties.From,
			properties.To,
			math.max(properties.Thickness / 2, 1) + extra
		)
	elseif kind == "Triangle" then
		return pointInTriangle(point, properties.PointA, properties.PointB, properties.PointC)
	elseif kind == "Quad" then
		return pointInTriangle(point, properties.PointA, properties.PointB, properties.PointC)
			or pointInTriangle(point, properties.PointA, properties.PointC, properties.PointD)
	end

	return false
end

return Geometry

end

__modules["Element"] = function()

local Geometry = __require("Geometry")
local Signal = __require("Signal")

export type Properties = { [string]: any }

export type Element = {
	Kind: string,
	PointerEntered: Signal.Signal,
	PointerLeft: Signal.Signal,
	PointerDown: Signal.Signal,
	PointerUp: Signal.Signal,
	Clicked: Signal.Signal,
	Dragged: Signal.Signal,
	Focused: Signal.Signal,
	FocusLost: Signal.Signal,
	KeyDown: Signal.Signal,
	set: (self: Element, property: string, value: any) -> Element,
	patch: (self: Element, properties: Properties) -> Element,
	get: (self: Element, property: string) -> any,
	getObject: (self: Element) -> any,
	setInteractive: (self: Element, interactive: boolean) -> Element,
	isInteractive: (self: Element) -> boolean,
	setFocusable: (self: Element, focusable: boolean) -> Element,
	isFocusable: (self: Element) -> boolean,
	contains: (self: Element, point: Geometry.Point, padding: number?) -> boolean,
	isAlive: (self: Element) -> boolean,
	destroy: (self: Element) -> (),
}

type PrivateElement = Element & {
	_object: any,
	_sequence: number,
	_interactive: boolean,
	_onInteractiveChanged: (Element, boolean) -> (),
	_focusable: boolean,
	_alive: boolean,
	_onDestroy: (Element) -> (),
}

local Element = {}
Element.__index = Element

function Element.new(
	kind: string,
	object: any,
	sequence: number,
	interactive: boolean,
	onInteractiveChanged: (Element, boolean) -> (),
	onDestroy: (Element) -> ()
): Element
	return setmetatable({
		Kind = kind,
		PointerEntered = Signal.new(),
		PointerLeft = Signal.new(),
		PointerDown = Signal.new(),
		PointerUp = Signal.new(),
		Clicked = Signal.new(),
		Dragged = Signal.new(),
		Focused = Signal.new(),
		FocusLost = Signal.new(),
		KeyDown = Signal.new(),
		_object = object,
		_sequence = sequence,
		_interactive = interactive,
		_onInteractiveChanged = onInteractiveChanged,
		_focusable = false,
		_alive = true,
		_onDestroy = onDestroy,
	}, Element) :: any
end

function Element:set(property: string, value: any): Element
	local self = self :: PrivateElement
	assert(self._alive, "cannot update a destroyed element")
	self._object[property] = value
	return self
end

function Element:patch(properties: Properties): Element
	for property, value in properties do
		self:set(property, value)
	end
	return self
end

function Element:get(property: string): any
	local self = self :: PrivateElement
	assert(self._alive, "cannot read a destroyed element")
	return self._object[property]
end

function Element:getObject(): any
	local self = self :: PrivateElement
	assert(self._alive, "cannot access a destroyed element")
	return self._object
end

function Element:setInteractive(interactive: boolean): Element
	local self = self :: PrivateElement
	assert(self._alive, "cannot update a destroyed element")
	if self._interactive == interactive then
		return self
	end
	self._interactive = interactive
	self._onInteractiveChanged(self, interactive)
	return self
end

function Element:isInteractive(): boolean
	local self = self :: PrivateElement
	return self._alive and self._interactive
end

function Element:setFocusable(focusable: boolean): Element
	local self = self :: PrivateElement
	assert(self._alive, "cannot update a destroyed element")
	self._focusable = focusable
	return self
end

function Element:isFocusable(): boolean
	local self = self :: PrivateElement
	return self._alive and self._focusable
end

function Element:contains(point: Geometry.Point, padding: number?): boolean
	local self = self :: PrivateElement
	if not self._alive or self._object.Visible == false or self._object.Transparency == 0 then
		return false
	end
	return Geometry.contains(self.Kind, self._object, point, padding)
end

function Element:isAlive(): boolean
	return (self :: PrivateElement)._alive
end

function Element:destroy()
	local self = self :: PrivateElement
	if not self._alive then
		return
	end

	self._alive = false
	self._object:Remove()
	self._onDestroy(self)
	self.PointerEntered:Destroy()
	self.PointerLeft:Destroy()
	self.PointerDown:Destroy()
	self.PointerUp:Destroy()
	self.Clicked:Destroy()
	self.Dragged:Destroy()
	self.Focused:Destroy()
	self.FocusLost:Destroy()
	self.KeyDown:Destroy()
end

return Element

end

__modules["InputRouter"] = function()

local ElementModule = __require("Element")

type Element = ElementModule.Element

export type PointerPhase = "move" | "down" | "up" | "cancel"

export type PointerEvent = {
	phase: PointerPhase,
	position: {
		X: number,
		Y: number,
	},
	pointerId: string,
	processed: boolean,
}

export type InputRouter = {
	dispatch: (self: InputRouter, event: PointerEvent) -> (),
	releaseElement: (self: InputRouter, element: Element) -> (),
	destroy: (self: InputRouter) -> (),
}

type PrivateInputRouter = InputRouter & {
	_getTarget: (event: PointerEvent) -> Element?,
	_acceptProcessed: boolean,
	_hovered: { [string]: Element },
	_captured: { [string]: Element },
	_destroyed: boolean,
}

local InputRouter = {}
InputRouter.__index = InputRouter

function InputRouter.new(
	getTarget: (PointerEvent) -> Element?,
	acceptProcessed: boolean?
): InputRouter
	return setmetatable({
		_getTarget = getTarget,
		_acceptProcessed = acceptProcessed == true,
		_hovered = {},
		_captured = {},
		_destroyed = false,
	}, InputRouter) :: any
end

local function updateHover(self: PrivateInputRouter, event: PointerEvent, target: Element?)
	local previous = self._hovered[event.pointerId]
	if previous == target then
		return
	end

	if previous and previous:isAlive() then
		previous.PointerLeft:Fire(event)
	end
	if target then
		self._hovered[event.pointerId] = target
		target.PointerEntered:Fire(event)
	else
		self._hovered[event.pointerId] = nil
	end
end

function InputRouter:dispatch(event: PointerEvent)
	local self = self :: PrivateInputRouter
	if self._destroyed then
		return
	end

	local captured: Element? = self._captured[event.pointerId]
	if captured and not captured:isAlive() then
		self._captured[event.pointerId] = nil
		captured = nil
	end

	if event.processed and not self._acceptProcessed and captured == nil then
		return
	end

	local target = self._getTarget(event)
	if event.phase == "move" then
		updateHover(self, event, target)
		if captured then
			captured.Dragged:Fire(event)
		end
	elseif event.phase == "down" then
		updateHover(self, event, target)
		if target then
			self._captured[event.pointerId] = target
			target.PointerDown:Fire(event)
		end
	elseif event.phase == "up" then
		if captured then
			captured.PointerUp:Fire(event)
			if target == captured then
				captured.Clicked:Fire(event)
			end
		end
		self._captured[event.pointerId] = nil
		updateHover(self, event, target)
	elseif event.phase == "cancel" then
		if captured then
			captured.PointerUp:Fire(event)
		end
		self._captured[event.pointerId] = nil
		updateHover(self, event, nil)
	end
end

function InputRouter:releaseElement(element: Element)
	local self = self :: PrivateInputRouter
	for pointerId, hovered in self._hovered do
		if hovered == element then
			self._hovered[pointerId] = nil
		end
	end
	for pointerId, captured in self._captured do
		if captured == element then
			self._captured[pointerId] = nil
		end
	end
end

function InputRouter:destroy()
	local self = self :: PrivateInputRouter
	if self._destroyed then
		return
	end
	self._destroyed = true
	table.clear(self._hovered)
	table.clear(self._captured)
end

return InputRouter

end

__modules["Canvas"] = function()

local ElementModule = __require("Element")
local InputRouterModule = __require("InputRouter")

type Element = ElementModule.Element
type Properties = ElementModule.Properties
type PointerEvent = InputRouterModule.PointerEvent
type Point = {
	X: number,
	Y: number,
}
type MapPosition = (position: Point, input: any) -> Point
type CreatePrimitive = (kind: string) -> any

export type CreateOptions = {
	interactive: boolean?,
}

export type Connection = {
	Disconnect: (self: Connection) -> (),
}

export type InputSignal = {
	Connect: (self: InputSignal, callback: (any, boolean) -> ()) -> Connection,
}

export type InputService = {
	InputBegan: InputSignal,
	InputChanged: InputSignal,
	InputEnded: InputSignal,
}

export type Canvas = {
	create: (
		self: Canvas,
		kind: string,
		properties: Properties?,
		options: CreateOptions?
	) -> Element,
	getElements: (self: Canvas) -> { Element },
	dispatchPointer: (self: Canvas, event: PointerEvent) -> (),
	focus: (self: Canvas, element: Element?) -> (),
	getFocusedElement: (self: Canvas) -> Element?,
	bindInput: (self: Canvas, inputService: InputService, vector2: any?) -> Connection,
	paint: (self: Canvas, zIndex: number, callback: (any) -> ()) -> Connection,
	paintCaptured: (
		self: Canvas,
		element: Element,
		zIndex: number,
		callback: (any, PointerEvent) -> ()
	) -> Connection,
	clear: (self: Canvas) -> (),
	destroy: (self: Canvas) -> (),
}

type DrawingImmediate = {
	GetPaint: (zIndex: number) -> any,
}

type PrivateCanvas = Canvas & {
	_createPrimitive: CreatePrimitive,
	_immediate: DrawingImmediate?,
	_vector2: any?,
	_mapPosition: MapPosition?,
	_acceptProcessed: boolean,
	_elements: { Element },
	_focused: Element?,
	_dispatchKey: (self: Canvas, input: any, processed: boolean) -> (),
	_sequence: number,
	_router: InputRouterModule.InputRouter,
	_connections: { Connection },
	_destroyed: boolean,
}

local Canvas = {}
Canvas.__index = Canvas

local function elementZIndex(element: Element): number
	return element:get("ZIndex") or 0
end

function Canvas.new(
	createPrimitive: CreatePrimitive,
	immediate: DrawingImmediate?,
	vector2: any?,
	acceptProcessed: boolean?,
	mapPosition: MapPosition?
): Canvas
	local self = setmetatable({
		_createPrimitive = createPrimitive,
		_immediate = immediate,
		_vector2 = vector2,
		_mapPosition = mapPosition,
		_acceptProcessed = acceptProcessed == true,
		_elements = {},
		_focused = nil,
		_sequence = 0,
		_connections = {},
		_destroyed = false,
	}, Canvas) :: any

	self._router = InputRouterModule.new(function(event: PointerEvent): Element?
		local target: Element? = nil
		local targetZIndex = -math.huge
		local targetSequence = -math.huge

		for _, element in self._elements do
			if element:isInteractive() and element:contains(event.position) then
				local zIndex = elementZIndex(element)
				local sequence = (element :: any)._sequence
				if
					zIndex > targetZIndex or (zIndex == targetZIndex and sequence > targetSequence)
				then
					target = element
					targetZIndex = zIndex
					targetSequence = sequence
				end
			end
		end
		return target
	end, acceptProcessed)

	return self
end

function Canvas:create(kind: string, properties: Properties?, options: CreateOptions?): Element
	local canvas = self :: PrivateCanvas
	assert(not canvas._destroyed, "cannot create on a destroyed canvas")

	canvas._sequence += 1
	local object = canvas._createPrimitive(kind)
	local element: Element
	element = ElementModule.new(
		kind,
		object,
		canvas._sequence,
		options ~= nil and options.interactive == true,
		function(changed: Element, interactive: boolean)
			if not interactive then
				canvas._router:releaseElement(changed)
			end
		end,
		function()
			if canvas._focused == element then
				canvas:focus(nil)
			end
			canvas._router:releaseElement(element)
			local index = table.find(canvas._elements, element)
			if index then
				table.remove(canvas._elements, index)
			end
		end
	)
	table.insert(canvas._elements, element)
	element.PointerDown:Connect(function()
		if element:isFocusable() then
			canvas:focus(element)
		end
	end)

	if properties then
		element:patch(properties)
	end
	return element
end

function Canvas:getElements(): { Element }
	return table.clone((self :: PrivateCanvas)._elements)
end

function Canvas:dispatchPointer(event: PointerEvent)
	(self :: PrivateCanvas)._router:dispatch(event)
end

function Canvas:focus(element: Element?)
	local canvas = self :: PrivateCanvas
	if canvas._destroyed and element then
		return
	end
	if element then
		assert(table.find(canvas._elements, element), "focus element must belong to this canvas")
		assert(element:isFocusable(), "focus element must be alive and focusable")
	end

	local previous = canvas._focused
	if previous == element then
		return
	end
	canvas._focused = element
	if previous then
		previous.FocusLost:Fire()
	end
	if element then
		element.Focused:Fire()
	end
end

function Canvas:getFocusedElement(): Element?
	local canvas = self :: PrivateCanvas
	local focused = canvas._focused
	if focused and (not focused:isAlive() or not focused:isFocusable()) then
		canvas:focus(nil)
		return nil
	end
	return focused
end

local function normalizedKey(input: any): string?
	local keyCode = input.KeyCode
	if keyCode == nil then
		return nil
	end
	local name = keyCode.Name
	if type(name) == "string" and name ~= "Unknown" then
		return name
	end
	local text = tostring(keyCode)
	local lastDot = string.match(text, ".*()%.%")
	local fallback = if lastDot then string.sub(text, lastDot + 1) else text
	if fallback == "" or fallback == "Unknown" then
		return nil
	end
	return fallback
end

function Canvas:_dispatchKey(input: any, processed: boolean)
	local canvas = self :: PrivateCanvas
	if canvas._destroyed or (processed and not canvas._acceptProcessed) then
		return
	end
	local focused = canvas:getFocusedElement()
	local key = normalizedKey(input)
	if focused and key then
		focused.KeyDown:Fire(input, key)
	end
end

local function inputPosition(input: any, vector2: any, mapPosition: MapPosition?): Point
	local position = vector2.new(input.Position.X, input.Position.Y)
	if mapPosition then
		return mapPosition(position, input)
	end
	return position
end

local function pointerId(input: any): string
	if tostring(input.UserInputType):find("Touch", 1, true) then
		return tostring(input)
	end
	return "mouse"
end

function Canvas:bindInput(inputService: InputService, vector2: any?): Connection
	local canvas = self :: PrivateCanvas
	assert(not canvas._destroyed, "cannot bind input on a destroyed canvas")
	local vector2Library = vector2 or canvas._vector2
	assert(
		vector2Library,
		"bindInput requires Vector2 in Limn.new options or as its second argument"
	)

	local connections = {
		inputService.InputBegan:Connect(function(input: any, processed: boolean)
			local kind = tostring(input.UserInputType)
			if kind:find("MouseButton1", 1, true) or kind:find("Touch", 1, true) then
				canvas:dispatchPointer({
					phase = "down",
					position = inputPosition(input, vector2Library, canvas._mapPosition),
					pointerId = pointerId(input),
					processed = processed,
				})
			elseif kind:find("Keyboard", 1, true) then
				canvas:_dispatchKey(input, processed)
			end
		end),
		inputService.InputChanged:Connect(function(input: any, processed: boolean)
			local kind = tostring(input.UserInputType)
			if kind:find("MouseMovement", 1, true) or kind:find("Touch", 1, true) then
				canvas:dispatchPointer({
					phase = "move",
					position = inputPosition(input, vector2Library, canvas._mapPosition),
					pointerId = pointerId(input),
					processed = processed,
				})
			end
		end),
		inputService.InputEnded:Connect(function(input: any, processed: boolean)
			local kind = tostring(input.UserInputType)
			if kind:find("MouseButton1", 1, true) or kind:find("Touch", 1, true) then
				canvas:dispatchPointer({
					phase = "up",
					position = inputPosition(input, vector2Library, canvas._mapPosition),
					pointerId = pointerId(input),
					processed = processed,
				})
			end
		end),
	}

	local composite = {
		Connected = true,
	} :: any
	function composite:Disconnect()
		if not self.Connected then
			return
		end
		self.Connected = false
		for _, connection in self._connections do
			connection:Disconnect()
		end
	end
	composite._connections = connections
	table.insert(canvas._connections, composite)
	return composite
end

function Canvas:paint(zIndex: number, callback: (any) -> ()): Connection
	local canvas = self :: PrivateCanvas
	assert(not canvas._destroyed, "cannot paint on a destroyed canvas")
	assert(canvas._immediate, "DrawingImmediate is unavailable")

	local connection = canvas._immediate.GetPaint(zIndex):Connect(function()
		callback(canvas._immediate)
	end)
	table.insert(canvas._connections, connection)
	return connection
end

function Canvas:paintCaptured(
	element: Element,
	zIndex: number,
	callback: (any, PointerEvent) -> ()
): Connection
	local canvas = self :: PrivateCanvas
	assert(not canvas._destroyed, "cannot paint on a destroyed canvas")
	assert(canvas._immediate, "DrawingImmediate is unavailable")
	assert(
		table.find(canvas._elements, element),
		"paintCaptured element must belong to this canvas"
	)

	local activeEvents: { [string]: PointerEvent } = {}
	local connections = {
		element.PointerDown:Connect(function(event: PointerEvent)
			activeEvents[event.pointerId] = event
		end),
		element.Dragged:Connect(function(event: PointerEvent)
			activeEvents[event.pointerId] = event
		end),
		element.PointerUp:Connect(function(event: PointerEvent)
			activeEvents[event.pointerId] = nil
		end),
		canvas._immediate.GetPaint(zIndex):Connect(function()
			if not element:isAlive() then
				table.clear(activeEvents)
				return
			end
			for _, event in activeEvents do
				callback(canvas._immediate, event)
			end
		end),
	}

	local composite = {
		Connected = true,
	} :: any
	function composite:Disconnect()
		if not self.Connected then
			return
		end
		self.Connected = false
		table.clear(activeEvents)
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	table.insert(canvas._connections, composite)
	return composite
end

function Canvas:clear()
	local canvas = self :: PrivateCanvas
	local elements = table.clone(canvas._elements)
	for _, element in elements do
		element:destroy()
	end
end

function Canvas:destroy()
	local canvas = self :: PrivateCanvas
	if canvas._destroyed then
		return
	end
	canvas._destroyed = true
	canvas:clear()
	canvas._router:destroy()
	for _, connection in canvas._connections do
		connection:Disconnect()
	end
	table.clear(canvas._connections)
end

return Canvas

end

__modules["Controls"] = function()

local CanvasModule = __require("Canvas")
local ElementModule = __require("Element")
local Signal = __require("Signal")

type Canvas = CanvasModule.Canvas
type Element = ElementModule.Element
type RoundedVisual = {
	center: Element,
	top: Element,
	bottom: Element,
	left: Element,
	right: Element,
	triangles: { Element },
	leftRounded: boolean,
	rightRounded: boolean,
}

local Controls = {}
local CORNER_SECTORS = 4
local HIT_TARGET_TRANSPARENCY = 0.001

local function copy(properties: { [string]: any }?): { [string]: any }
	return if properties then table.clone(properties) else {}
end

local function patch(element: Element, properties: { [string]: any }?)
	if properties then
		element:patch(properties)
	end
end

local function connect(connections: { any }, signal: Signal.Signal, callback: (...any) -> ())
	local connection = signal:Connect(callback)
	table.insert(connections, connection)
	return connection
end

local function disconnectAll(connections: { any })
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function displayKey(value: string?): string
	if value == nil then
		return "Unbound"
	end
	local words = string.gsub(value, "(%l)(%u)", "%1 %2")
	words = string.gsub(words, "(%a)(%d)", "%1 %2")
	return words
end

local function normalizeKey(value: string?): string?
	if value == nil then
		return nil
	end
	local normalized = string.gsub(value, "^Enum%.KeyCode%.", "")
	assert(normalized ~= "" and normalized ~= "Unknown", "keybind value must name a key")
	return normalized
end

local function baseSquare(properties: { [string]: any }?, position: any, size: any, zIndex: number)
	local result = copy(properties)
	result.Position = position
	result.Size = size
	result.ZIndex = zIndex
	if result.Visible == nil then
		result.Visible = true
	end
	if result.Filled == nil then
		result.Filled = true
	end
	return result
end

local function baseText(properties: { [string]: any }?, text: string, position: any, zIndex: number)
	local result = copy(properties)
	result.Text = text
	result.Position = position
	result.ZIndex = zIndex
	if result.Visible == nil then
		result.Visible = true
	end
	return result
end

local function baseTriangle(
	properties: { [string]: any }?,
	pointA: any,
	pointB: any,
	pointC: any,
	zIndex: number
)
	local result = copy(properties)
	result.Position = nil
	result.Size = nil
	result.Radius = nil
	result.PointA = pointA
	result.PointB = pointB
	result.PointC = pointC
	result.ZIndex = zIndex
	if result.Visible == nil then
		result.Visible = true
	end
	if result.Filled == nil then
		result.Filled = true
	end
	return result
end

function Controls.createSegmented(
	canvas: Canvas,
	options: any,
	vector2: any,
	supportsPrimitive: ((kind: string) -> boolean)?
): any
	assert(type(options) == "table", "segmented control options are required")
	assert(
		type(options.Options) == "table" and #options.Options > 0,
		"segmented control needs Options"
	)
	assert(options.Position and options.Size, "segmented control needs Position and Size")
	assert(vector2, "segmented controls require Vector2 in Limn.new options")
	local cornerRadius = if options.CornerRadius == nil then 0 else options.CornerRadius
	assert(
		type(cornerRadius) == "number" and cornerRadius >= 0,
		"segmented CornerRadius must be a nonnegative number"
	)
	if cornerRadius > 0 then
		assert(
			supportsPrimitive and supportsPrimitive("Triangle"),
			"segmented CornerRadius requires Triangle support"
		)
	end

	local style = options.Style or {}
	local values = options.Options
	local position = options.Position
	local size = options.Size
	local layout = options.Layout
	local selectedIndex = 1
	for index, option in values do
		if option.Value == options.Value then
			selectedIndex = index
			break
		end
	end
	local disabled = options.Disabled == true
	local visible = true
	local hoveredIndex: number? = nil
	local focusedIndex: number? = nil
	local destroyed = false
	local state = "idle"
	local changed = Signal.new()
	local stateChanged = Signal.new()
	local connections = {}
	local owned: { Element } = {}
	local segments: { Element } = {}
	local labels: { Element? } = {}
	local roundedSegments: { RoundedVisual? } = {}

	local frame =
		canvas:create("Square", baseSquare(style.Frame, position, size, options.ZIndex or 0))
	table.insert(owned, frame)

	local function own(element: Element): Element
		table.insert(owned, element)
		return element
	end

	local function createRoundedVisual(
		center: Element?,
		properties: { [string]: any }?,
		zIndex: number,
		leftRounded: boolean,
		rightRounded: boolean
	): RoundedVisual
		local visual = {
			center = center
				or own(canvas:create("Square", baseSquare(properties, position, size, zIndex))),
			top = own(canvas:create("Square", baseSquare(properties, position, size, zIndex))),
			bottom = own(canvas:create("Square", baseSquare(properties, position, size, zIndex))),
			left = own(canvas:create("Square", baseSquare(properties, position, size, zIndex))),
			right = own(canvas:create("Square", baseSquare(properties, position, size, zIndex))),
			triangles = {},
			leftRounded = leftRounded,
			rightRounded = rightRounded,
		}
		for _ = 1, CORNER_SECTORS * 4 do
			table.insert(
				visual.triangles,
				own(
					canvas:create(
						"Triangle",
						baseTriangle(properties, position, position, position, zIndex)
					)
				)
			)
		end
		return visual
	end

	local roundedFrame: RoundedVisual? = nil
	if cornerRadius > 0 then
		roundedFrame = createRoundedVisual(frame, style.Frame, options.ZIndex or 0, true, true)
	end

	local control = {
		Changed = changed,
		StateChanged = stateChanged,
	} :: any

	local function currentState(): string
		if disabled then
			return "disabled"
		end
		if focusedIndex then
			return "focused"
		end
		return "idle"
	end

	local function updateState()
		local nextState = currentState()
		if state ~= nextState then
			state = nextState
			stateChanged:Fire(state)
		end
	end

	local function patchRoundedVisual(visual: RoundedVisual, properties: { [string]: any }?)
		if not properties then
			return
		end
		local visualProperties = copy(properties)
		visualProperties.Position = nil
		visualProperties.Size = nil
		visualProperties.Radius = nil
		visualProperties.PointA = nil
		visualProperties.PointB = nil
		visualProperties.PointC = nil
		visualProperties.ZIndex = nil
		visualProperties.Visible = nil
		patch(visual.center, visualProperties)
		patch(visual.top, visualProperties)
		patch(visual.bottom, visualProperties)
		patch(visual.left, visualProperties)
		patch(visual.right, visualProperties)
		for _, triangle in visual.triangles do
			patch(triangle, visualProperties)
		end
	end

	local function setRoundedVisible(visual: RoundedVisual, nextVisible: boolean)
		visual.center:set("Visible", nextVisible)
		visual.top:set("Visible", nextVisible)
		visual.bottom:set("Visible", nextVisible)
		visual.left:set("Visible", nextVisible)
		visual.right:set("Visible", nextVisible)
		for index, triangle in visual.triangles do
			local corner = math.ceil(index / CORNER_SECTORS)
			local rounded = if corner == 1 or corner == 4
				then visual.leftRounded
				else visual.rightRounded
			triangle:set("Visible", nextVisible and rounded)
		end
	end

	local function updateRoundedGeometry(
		visual: RoundedVisual,
		nextPosition: any,
		nextSize: any,
		zIndex: number
	)
		local radius = math.min(cornerRadius, nextSize.X / 2, nextSize.Y / 2)
		local leftRadius = if visual.leftRounded then radius else 0
		local rightRadius = if visual.rightRounded then radius else 0
		local verticalRadius = if leftRadius > 0 or rightRadius > 0 then radius else 0
		visual.center:patch({
			Position = vector2.new(nextPosition.X + leftRadius, nextPosition.Y + verticalRadius),
			Size = vector2.new(
				nextSize.X - leftRadius - rightRadius,
				nextSize.Y - verticalRadius * 2
			),
			ZIndex = zIndex,
		})
		visual.top:patch({
			Position = vector2.new(nextPosition.X + leftRadius, nextPosition.Y),
			Size = vector2.new(nextSize.X - leftRadius - rightRadius, verticalRadius),
			ZIndex = zIndex,
		})
		visual.bottom:patch({
			Position = vector2.new(
				nextPosition.X + leftRadius,
				nextPosition.Y + nextSize.Y - verticalRadius
			),
			Size = vector2.new(nextSize.X - leftRadius - rightRadius, verticalRadius),
			ZIndex = zIndex,
		})
		visual.left:patch({
			Position = vector2.new(nextPosition.X, nextPosition.Y + verticalRadius),
			Size = vector2.new(leftRadius, nextSize.Y - verticalRadius * 2),
			ZIndex = zIndex,
		})
		visual.right:patch({
			Position = vector2.new(
				nextPosition.X + nextSize.X - rightRadius,
				nextPosition.Y + verticalRadius
			),
			Size = vector2.new(rightRadius, nextSize.Y - verticalRadius * 2),
			ZIndex = zIndex,
		})
		local function updateFan(
			firstIndex: number,
			center: any,
			startAngle: number,
			endAngle: number
		)
			local step = (endAngle - startAngle) / CORNER_SECTORS
			for offset = 0, CORNER_SECTORS - 1 do
				local from = startAngle + step * offset
				local to = from + step
				visual.triangles[firstIndex + offset]:patch({
					PointA = center,
					PointB = vector2.new(
						center.X + math.cos(from) * radius,
						center.Y + math.sin(from) * radius
					),
					PointC = vector2.new(
						center.X + math.cos(to) * radius,
						center.Y + math.sin(to) * radius
					),
					ZIndex = zIndex,
				})
			end
		end
		updateFan(
			1,
			vector2.new(nextPosition.X + leftRadius, nextPosition.Y + verticalRadius),
			-math.pi / 2,
			-math.pi
		)
		updateFan(
			CORNER_SECTORS + 1,
			vector2.new(nextPosition.X + nextSize.X - rightRadius, nextPosition.Y + verticalRadius),
			-math.pi / 2,
			0
		)
		updateFan(
			CORNER_SECTORS * 2 + 1,
			vector2.new(
				nextPosition.X + nextSize.X - rightRadius,
				nextPosition.Y + nextSize.Y - verticalRadius
			),
			0,
			math.pi / 2
		)
		updateFan(
			CORNER_SECTORS * 3 + 1,
			vector2.new(nextPosition.X + leftRadius, nextPosition.Y + nextSize.Y - verticalRadius),
			math.pi / 2,
			math.pi
		)
	end

	local function updateSegment(index: number)
		local segment = segments[index]
		if not segment:isAlive() then
			return
		end
		patch(segment, style.Option)
		if index == selectedIndex then
			patch(segment, style.Selected)
		end
		if index == hoveredIndex then
			patch(segment, style.Hovered)
		end
		if index == focusedIndex then
			patch(segment, style.Focused)
		end
		if disabled then
			patch(segment, style.Disabled)
		end
		local roundedVisual = roundedSegments[index]
		if roundedVisual then
			patchRoundedVisual(roundedVisual, style.Option)
			if index == selectedIndex then
				patchRoundedVisual(roundedVisual, style.Selected)
			end
			if index == hoveredIndex then
				patchRoundedVisual(roundedVisual, style.Hovered)
			end
			if index == focusedIndex then
				patchRoundedVisual(roundedVisual, style.Focused)
			end
			if disabled then
				patchRoundedVisual(roundedVisual, style.Disabled)
			end
			setRoundedVisible(roundedVisual, visible)
			segment:set("Transparency", HIT_TARGET_TRANSPARENCY)
		end
		segment:setInteractive(not disabled and visible)
		segment:setFocusable(not disabled and visible)
		segment:set("Visible", visible)
	end

	local function segmentLayout(index: number): (any, any, any)
		local defaultPosition =
			vector2.new(position.X + size.X * ((index - 1) / #values), position.Y)
		local defaultSize = vector2.new(size.X / #values, size.Y)
		local custom = if layout then layout(index, #values, position, size) else nil
		local segmentPosition = if custom and custom.Position
			then custom.Position
			else defaultPosition
		local segmentSize = if custom and custom.Size then custom.Size else defaultSize
		local labelPosition = if custom and custom.LabelPosition
			then custom.LabelPosition
			else segmentPosition
		return segmentPosition, segmentSize, labelPosition
	end

	local function updateGeometry()
		if roundedFrame then
			updateRoundedGeometry(roundedFrame, position, size, options.ZIndex or 0)
		elseif frame:isAlive() then
			frame:patch({ Position = position, Size = size, ZIndex = options.ZIndex or 0 })
		end
		for index, segment in segments do
			local segmentPosition, segmentSize, labelPosition = segmentLayout(index)
			if segment:isAlive() then
				segment:patch({
					Position = segmentPosition,
					Size = segmentSize,
					ZIndex = (options.ZIndex or 0) + 1,
				})
			end
			local roundedVisual = roundedSegments[index]
			if roundedVisual then
				updateRoundedGeometry(
					roundedVisual,
					segmentPosition,
					segmentSize,
					(options.ZIndex or 0) + 1
				)
			end
			local label = labels[index]
			if label and label:isAlive() then
				label:patch({ Position = labelPosition, ZIndex = (options.ZIndex or 0) + 2 })
			end
		end
	end

	local function updateAll()
		for index = 1, #segments do
			updateSegment(index)
		end
		if roundedFrame then
			patchRoundedVisual(roundedFrame, style.Frame)
			if disabled then
				patchRoundedVisual(roundedFrame, style.Disabled)
			end
			setRoundedVisible(roundedFrame, visible)
		elseif frame:isAlive() then
			patch(frame, style.Frame)
			if disabled then
				patch(frame, style.Disabled)
			end
			frame:set("Visible", visible)
		end
		for index, label in labels do
			if label and label:isAlive() then
				patch(label, style.Label)
				if index == selectedIndex then
					patch(label, style.SelectedLabel)
				end
				label:set("Visible", visible)
			end
		end
		updateGeometry()
		updateState()
	end

	local function setValue(value: any, source: string): boolean
		if destroyed or disabled then
			return false
		end
		local nextIndex: number? = nil
		for index, option in values do
			if option.Value == value then
				nextIndex = index
				break
			end
		end
		assert(nextIndex, "segmented control value must match an option")
		if nextIndex == selectedIndex then
			return false
		end
		local previous = values[selectedIndex].Value
		selectedIndex = nextIndex
		updateAll()
		changed:Fire(values[selectedIndex].Value, previous, source)
		return true
	end

	for index, option in values do
		local segmentPosition, segmentSize, labelPosition = segmentLayout(index)
		local segment = canvas:create(
			"Square",
			baseSquare(style.Option, segmentPosition, segmentSize, (options.ZIndex or 0) + 1),
			{
				interactive = not disabled,
			}
		)
		segment:setFocusable(not disabled and visible)
		table.insert(owned, segment)
		table.insert(segments, segment)
		if cornerRadius > 0 then
			roundedSegments[index] = createRoundedVisual(
				nil,
				style.Option,
				(options.ZIndex or 0) + 1,
				index == 1,
				index == #values
			)
		end

		if option.Label ~= nil then
			local label = canvas:create(
				"Text",
				baseText(
					style.Label,
					tostring(option.Label),
					labelPosition,
					(options.ZIndex or 0) + 2
				)
			)
			table.insert(owned, label)
			labels[index] = label
		end

		connect(connections, segment.PointerEntered, function()
			if not disabled then
				hoveredIndex = index
				updateSegment(index)
			end
		end)
		connect(connections, segment.PointerLeft, function()
			if hoveredIndex == index then
				hoveredIndex = nil
				updateSegment(index)
			end
		end)
		connect(connections, segment.Focused, function()
			focusedIndex = index
			updateAll()
		end)
		connect(connections, segment.FocusLost, function()
			if focusedIndex == index then
				focusedIndex = nil
				updateAll()
			end
		end)
		connect(connections, segment.Clicked, function()
			setValue(option.Value, "pointer")
		end)
		connect(connections, segment.KeyDown, function(_: any, key: string)
			if disabled then
				return
			end
			if key == "Left" or key == "Up" then
				canvas:focus(segments[math.max(1, index - 1)])
			elseif key == "Right" or key == "Down" then
				canvas:focus(segments[math.min(#segments, index + 1)])
			elseif key == "Enter" or key == "Space" then
				setValue(option.Value, "keyboard")
			end
		end)
	end

	function control:getValue(): any
		return values[selectedIndex].Value
	end

	function control:getState(): string
		return currentState()
	end

	function control:setValue(value: any): boolean
		return setValue(value, "programmatic")
	end

	function control:setDisabled(value: boolean)
		if destroyed or disabled == value then
			return
		end
		disabled = value
		if disabled and focusedIndex then
			canvas:focus(nil)
		end
		updateAll()
	end

	function control:setLayout(nextLayout: any)
		assert(type(nextLayout) == "table", "segmented control layout is required")
		assert(
			nextLayout.Position and nextLayout.Size,
			"segmented control layout needs Position and Size"
		)
		if destroyed then
			return
		end
		position = nextLayout.Position
		size = nextLayout.Size
		layout = nextLayout.Layout
		updateAll()
	end

	function control:setVisible(nextVisible: boolean)
		if destroyed or visible == nextVisible then
			return
		end
		visible = nextVisible
		if not visible then
			hoveredIndex = nil
			if focusedIndex then
				canvas:focus(nil)
			end
		end
		updateAll()
	end

	function control:destroy()
		if destroyed then
			return
		end
		destroyed = true
		if focusedIndex then
			canvas:focus(nil)
		end
		disconnectAll(connections)
		for _, element in owned do
			element:destroy()
		end
		changed:Destroy()
		stateChanged:Destroy()
	end

	updateAll()
	return control
end

function Controls.createKeybind(canvas: Canvas, options: any, vector2: any): any
	assert(type(options) == "table", "keybind control options are required")
	assert(options.Position and options.Size, "keybind control needs Position and Size")
	assert(vector2, "keybind controls require Vector2 in Limn.new options")
	assert(
		options.Value == nil or type(options.Value) == "string",
		"keybind control Value must be a key name or nil"
	)

	local style = options.Style or {}
	local position = options.Position
	local size = options.Size
	local layout = options.Layout or {}
	local disabled = options.Disabled == true
	local visible = true
	local listening = false
	local focused = false
	local destroyed = false
	local value: string? = normalizeKey(options.Value)
	local state = "idle"
	local changed = Signal.new()
	local listeningChanged = Signal.new()
	local stateChanged = Signal.new()
	local connections = {}
	local owned: { Element } = {}
	local zIndex = options.ZIndex or 0
	local frame = canvas:create("Square", baseSquare(style.Frame, position, size, zIndex), {
		interactive = not disabled,
	})
	frame:setFocusable(not disabled and visible)
	table.insert(owned, frame)
	local label: Element? = nil
	if options.Label ~= nil then
		label = canvas:create(
			"Text",
			baseText(
				style.Label,
				tostring(options.Label),
				layout.LabelPosition or position,
				zIndex + 1
			)
		)
		table.insert(owned, label)
	end
	local displayPosition = layout.ValuePosition
		or vector2.new(position.X + size.X * 0.5, position.Y)
	local display =
		canvas:create("Text", baseText(style.Value, displayKey(value), displayPosition, zIndex + 1))
	table.insert(owned, display)

	local control = {
		Changed = changed,
		ListeningChanged = listeningChanged,
		StateChanged = stateChanged,
	} :: any

	local function updateGeometry()
		if frame:isAlive() then
			frame:patch({ Position = position, Size = size, ZIndex = zIndex })
		end
		if label and label:isAlive() then
			label:patch({ Position = layout.LabelPosition or position, ZIndex = zIndex + 1 })
		end
		if display:isAlive() then
			local nextDisplayPosition = layout.ValuePosition
				or vector2.new(position.X + size.X * 0.5, position.Y)
			display:patch({ Position = nextDisplayPosition, ZIndex = zIndex + 1 })
		end
	end

	local function currentState(): string
		if disabled then
			return "disabled"
		end
		if listening then
			return "listening"
		end
		if focused then
			return "focused"
		end
		return "idle"
	end

	local function update()
		if frame:isAlive() then
			patch(frame, style.Frame)
			patch(display, style.Value)
			if focused then
				patch(frame, style.Focused)
				patch(display, style.Focused)
			end
			if listening then
				patch(frame, style.Listening)
				patch(display, style.Listening)
				display:set("Text", (options.ListeningLabel or "Listening"))
			else
				display:set("Text", (options.FormatKey or displayKey)(value))
			end
			if disabled then
				patch(frame, style.Disabled)
				patch(display, style.Disabled)
			end
			frame:setInteractive(not disabled and visible)
			frame:setFocusable(not disabled and visible)
			frame:set("Visible", visible)
		end
		if label and label:isAlive() then
			label:set("Visible", visible)
		end
		if display:isAlive() then
			display:set("Visible", visible)
		end
		updateGeometry()
		local nextState = currentState()
		if nextState ~= state then
			state = nextState
			stateChanged:Fire(state)
		end
	end

	local function cancel()
		if not listening then
			return false
		end
		listening = false
		listeningChanged:Fire(false)
		update()
		return true
	end

	local function assign(nextValue: string?, source: string): boolean
		if destroyed or disabled then
			return false
		end
		local previous = value
		cancel()
		if previous == nextValue then
			return false
		end
		value = nextValue
		update()
		changed:Fire(value, previous, source)
		return true
	end

	function control:getValue(): string?
		return value
	end

	function control:getDisplayValue(): string
		return (options.FormatKey or displayKey)(value)
	end

	function control:getState(): string
		return currentState()
	end

	function control:begin(): boolean
		if destroyed or disabled or not visible or listening then
			return false
		end
		canvas:focus(frame)
		listening = true
		listeningChanged:Fire(true)
		update()
		return true
	end

	function control:cancel(): boolean
		return cancel()
	end

	function control:clear(): boolean
		return assign(nil, "clear")
	end

	function control:setValue(nextValue: string?): boolean
		assert(
			nextValue == nil or type(nextValue) == "string",
			"keybind value must be a key name or nil"
		)
		return assign(normalizeKey(nextValue), "programmatic")
	end

	function control:setDisabled(nextDisabled: boolean)
		if destroyed or disabled == nextDisabled then
			return
		end
		disabled = nextDisabled
		if disabled then
			cancel()
			if canvas:getFocusedElement() == frame then
				canvas:focus(nil)
			end
		end
		update()
	end

	function control:setLayout(nextLayout: any)
		assert(type(nextLayout) == "table", "keybind control layout is required")
		assert(
			nextLayout.Position and nextLayout.Size,
			"keybind control layout needs Position and Size"
		)
		if destroyed then
			return
		end
		position = nextLayout.Position
		size = nextLayout.Size
		layout = nextLayout.Layout or {}
		update()
	end

	function control:setVisible(nextVisible: boolean)
		if destroyed or visible == nextVisible then
			return
		end
		visible = nextVisible
		if not visible then
			cancel()
			if canvas:getFocusedElement() == frame then
				canvas:focus(nil)
			end
		end
		update()
	end

	function control:destroy()
		if destroyed then
			return
		end
		destroyed = true
		if canvas:getFocusedElement() == frame then
			canvas:focus(nil)
		end
		disconnectAll(connections)
		for _, element in owned do
			element:destroy()
		end
		changed:Destroy()
		listeningChanged:Destroy()
		stateChanged:Destroy()
	end

	connect(connections, frame.Focused, function()
		focused = true
		update()
	end)
	connect(connections, frame.FocusLost, function()
		focused = false
		if not frame:isAlive() then
			listening = false
			return
		end
		cancel()
		update()
	end)
	connect(connections, frame.Clicked, function()
		control:begin()
	end)
	connect(connections, frame.KeyDown, function(_: any, key: string)
		if disabled or not visible then
			return
		end
		if not listening then
			if key == "Enter" or key == "Space" then
				control:begin()
			end
			return
		end
		if key == "Escape" then
			cancel()
		elseif key == "Backspace" or key == "Delete" then
			control:clear()
		else
			assign(key, "keyboard")
		end
	end)

	update()
	return control
end

return Controls

end

__modules["Limn"] = function()

local CanvasModule = __require("Canvas")
local Controls = __require("Controls")

export type ProcessedInputPolicy = "ignore" | "allow"

export type Point = {
	X: number,
	Y: number,
}

export type InputOptions = {
	Processed: ProcessedInputPolicy?,
	MapPosition: ((position: Point, input: any) -> Point)?,
}

export type Options = {
	Drawing: {
		new: (kind: string) -> any,
	},
	DrawingImmediate: {
		GetPaint: (zIndex: number) -> any,
	}?,
	Vector2: any?,
	SupportsPrimitive: ((kind: string) -> boolean)?,
	Input: InputOptions?,
}

export type Limn = {
	supportsPrimitive: (self: Limn, kind: string) -> boolean,
	createCanvas: (self: Limn) -> CanvasModule.Canvas,
	createSegmentedControl: (self: Limn, canvas: CanvasModule.Canvas, options: any) -> any,
	createKeybindControl: (self: Limn, canvas: CanvasModule.Canvas, options: any) -> any,
}

type PrivateLimn = Limn & {
	_createPrimitive: (self: PrivateLimn, kind: string) -> any,
	_drawing: {
		new: (kind: string) -> any,
	},
	_immediate: {
		GetPaint: (zIndex: number) -> any,
	}?,
	_vector2: any?,
	_supportsPrimitive: ((kind: string) -> boolean)?,
	_primitiveSupport: { [string]: boolean },
	_acceptProcessed: boolean,
	_mapPosition: ((position: Point, input: any) -> Point)?,
}

local Limn = {}
Limn.__index = Limn

local function removeProbe(object: any): boolean
	local remove = object.Remove
	if type(remove) == "function" then
		return pcall(remove, object)
	end
	local destroy = object.Destroy
	if type(destroy) == "function" then
		return pcall(destroy, object)
	end
	return false
end

function Limn.new(options: Options): Limn
	assert(options.Drawing, "Limn requires the Volt Drawing library")
	local inputOptions = options.Input
	local processed = if inputOptions then inputOptions.Processed else nil
	assert(
		processed == nil or processed == "ignore" or processed == "allow",
		'Input.Processed must be "ignore" or "allow"'
	)
	return setmetatable({
		_drawing = options.Drawing,
		_immediate = options.DrawingImmediate,
		_vector2 = options.Vector2,
		_supportsPrimitive = options.SupportsPrimitive,
		_primitiveSupport = {},
		_acceptProcessed = processed == "allow",
		_mapPosition = if inputOptions then inputOptions.MapPosition else nil,
	}, Limn) :: any
end

function Limn:supportsPrimitive(kind: string): boolean
	local runtime = self :: PrivateLimn
	local cached = runtime._primitiveSupport[kind]
	if cached ~= nil then
		return cached
	end

	local supports = runtime._supportsPrimitive
	local supported: boolean
	if supports then
		supported = supports(kind) == true
	else
		local ok, object = pcall(runtime._drawing.new, kind)
		supported = ok and object ~= nil and removeProbe(object)
	end
	runtime._primitiveSupport[kind] = supported
	return supported
end

function Limn:_createPrimitive(kind: string): any
	local runtime = self :: PrivateLimn
	local cached = runtime._primitiveSupport[kind]
	if
		cached == false
		or (cached == nil and runtime._supportsPrimitive and not runtime:supportsPrimitive(kind))
	then
		error(string.format("unsupported drawing kind %q", kind), 2)
	end

	local ok, object = pcall(runtime._drawing.new, kind)
	if not ok or object == nil then
		runtime._primitiveSupport[kind] = false
		error(string.format("unsupported drawing kind %q", kind), 2)
	end
	runtime._primitiveSupport[kind] = true
	return object
end

function Limn:createCanvas(): CanvasModule.Canvas
	local runtime = self :: PrivateLimn
	return CanvasModule.new(function(kind: string): any
		return runtime:_createPrimitive(kind)
	end, runtime._immediate, runtime._vector2, runtime._acceptProcessed, runtime._mapPosition)
end

function Limn:createSegmentedControl(canvas: CanvasModule.Canvas, options: any): any
	local runtime = self :: PrivateLimn
	return Controls.createSegmented(
		canvas,
		options,
		runtime._vector2,
		function(kind: string): boolean
			return runtime:supportsPrimitive(kind)
		end
	)
end

function Limn:createKeybindControl(canvas: CanvasModule.Canvas, options: any): any
	return Controls.createKeybind(canvas, options, (self :: PrivateLimn)._vector2)
end

return Limn

end

return __require("Limn")
]],
}
local external = {
    ["https://raw.githubusercontent.com/3xjn/hydroxide/38778f8a78762d48fba916cade6eb93399e7c404/modules/Closure.lua"] = [[local Closure = {}

local placeholderUserdataConstant = {}

local function defaultContext()
    local environment = getgenv()
    local resolvedIsExecutorClosure = isexecutorclosure
        or environment.checkclosure
        or environment.is_synapse_function
        or environment.issentinelclosure
        or environment.is_sirhurt_closure
        or environment.iselectronfunction
        or environment.istempleclosure

    return {
        GetConstants = debug.getconstants or environment.getconstants or environment.getconsts,
        GetEnvironment = getfenv,
        GetGc = getgc or environment.get_gc_objects,
        GetInfo = debug.getinfo or environment.getinfo,
        GetProtos = debug.getprotos or environment.getprotos,
        GetScriptClosure = getscriptclosure or environment.getscriptclosure,
        GetUpvalue = debug.getupvalue or environment.getupvalue or environment.getupval,
        GetUpvalues = debug.getupvalues or environment.getupvalues or environment.getupvals,
        IsExecutorClosure = resolvedIsExecutorClosure,
        IsLClosure = islclosure
            or environment.is_l_closure
            or (iscclosure and function(value)
                return not iscclosure(value)
            end),
    }
end

local function requireMethod(context, name)
    return assert(context[name], "Closure helper requires " .. name)
end

function Closure.new(context)
    context = context or defaultContext()

    local helper = {
        placeholderUserdataConstant = context.PlaceholderUserdataConstant or placeholderUserdataConstant,
    }

    function helper.isGameClosure(value)
        if type(value) ~= "function" then
            return false
        end

        local isLClosure = requireMethod(context, "IsLClosure")
        local isExecutorClosure = requireMethod(context, "IsExecutorClosure")
        return isLClosure(value) and not isExecutorClosure(value)
    end

    function helper.forEachGameClosure(visitor)
        local getGc = requireMethod(context, "GetGc")

        for _index, value in pairs(getGc()) do
            if helper.isGameClosure(value) and visitor(value) == false then
                return
            end
        end
    end

    local function matchesConstants(closure, expected)
        if not expected then
            return true
        end

        local getConstants = requireMethod(context, "GetConstants")
        local constants = getConstants(closure)

        for index, value in pairs(expected) do
            if constants[index] ~= value and value ~= helper.placeholderUserdataConstant then
                return false
            end
        end

        return true
    end

    local function matchesScript(closure, expected)
        local getEnvironment = requireMethod(context, "GetEnvironment")
        local succeeded, environment = pcall(getEnvironment, closure)
        if not succeeded or type(environment) ~= "table" then
            return false
        end

        local parentScript = rawget(environment, "script")
        if expected ~= nil then
            return parentScript == expected
        end

        return parentScript == nil or parentScript.Parent == nil
    end

    function helper.searchClosure(script, name, upvalueIndex, constants)
        local getInfo = requireMethod(context, "GetInfo")
        local getUpvalue = requireMethod(context, "GetUpvalue")
        local found

        helper.forEachGameClosure(function(closure)
            if not matchesScript(closure, script) then
                return
            end

            if not pcall(getUpvalue, closure, upvalueIndex) then
                return
            end

            local closureName = getInfo(closure).name
            local hasNamedMatch = name and name ~= "Unnamed function" and closureName == name
            local hasUnnamedMatch = not name or name == "Unnamed function"

            if (hasNamedMatch or hasUnnamedMatch) and matchesConstants(closure, constants) then
                found = closure
                return false
            end

            return nil
        end)

        return found
    end

    function helper.searchClosures(script, queries)
        local getInfo = requireMethod(context, "GetInfo")
        local getUpvalue = requireMethod(context, "GetUpvalue")
        local found = {}
        local remaining = 0
        for _key in pairs(queries or {}) do
            remaining += 1
        end

        helper.forEachGameClosure(function(closure)
            if not matchesScript(closure, script) then
                return
            end
            local closureName = getInfo(closure).name
            for key, query in pairs(queries or {}) do
                if found[key] == nil
                    and (not query.name or query.name == closureName)
                    and (not query.upvalueIndex or pcall(getUpvalue, closure, query.upvalueIndex))
                    and matchesConstants(closure, query.constants)
                then
                    found[key] = closure
                    remaining -= 1
                end
            end
            if remaining == 0 then
                return false
            end
            return nil
        end)
        return found
    end

    function helper.findStringConstants(script, pattern)
        local getConstants = requireMethod(context, "GetConstants")
        local getProtos = requireMethod(context, "GetProtos")
        local getScriptClosure = requireMethod(context, "GetScriptClosure")
        local results = {}
        local seenTargets = {}
        local seenValues = {}
        local succeeded, root = pcall(getScriptClosure, script)

        if not succeeded or type(root) == "string" then
            return results
        end

        local function visit(target)
            if seenTargets[target] then
                return
            end
            seenTargets[target] = true

            local constantsSucceeded, constants = pcall(getConstants, target)
            if constantsSucceeded then
                for _index, value in pairs(constants) do
                    if
                        type(value) == "string"
                        and value:match(pattern)
                        and not seenValues[value]
                    then
                        seenValues[value] = true
                        table.insert(results, value)
                    end
                end
            end

            local protosSucceeded, protos = pcall(getProtos, target)
            if protosSucceeded then
                for _index, proto in pairs(protos) do
                    visit(proto)
                end
            end
        end

        visit(root)
        return results
    end

    function helper.findUpvalue(script, predicate)
        local getUpvalues = requireMethod(context, "GetUpvalues")
        local found

        helper.forEachGameClosure(function(closure)
            if not matchesScript(closure, script) then
                return
            end

            local succeeded, upvalues = pcall(getUpvalues, closure)
            if not succeeded then
                return
            end

            for index, value in pairs(upvalues) do
                if predicate(value, index, closure) then
                    found = value
                    return false
                end
            end

            return nil
        end)

        return found
    end

    return helper
end

local defaultHelper
local function getDefaultHelper()
    if not defaultHelper then
        defaultHelper = Closure.new()
    end

    return defaultHelper
end

Closure.placeholderUserdataConstant = placeholderUserdataConstant
Closure.isGameClosure = function(...)
    return getDefaultHelper().isGameClosure(...)
end
Closure.forEachGameClosure = function(...)
    return getDefaultHelper().forEachGameClosure(...)
end
Closure.findStringConstants = function(...)
    return getDefaultHelper().findStringConstants(...)
end
Closure.findUpvalue = function(...)
    return getDefaultHelper().findUpvalue(...)
end
Closure.searchClosure = function(...)
    return getDefaultHelper().searchClosure(...)
end
Closure.searchClosures = function(...)
    return getDefaultHelper().searchClosures(...)
end

return Closure
]],
    ["https://raw.githubusercontent.com/3xjn/hydroxide/38778f8a78762d48fba916cade6eb93399e7c404/modules/Helpers.lua"] = [[local Helpers = {}

local moduleFiles = {
    closure = "Closure",
    lifecycle = "Lifecycle",
    remote = "Remote",
    targeting = "Targeting",
}

function Helpers.load(options)
    options = options or {}

    local cache = {}
    local importModule = options.import
    local localRoot = options.localRoot
    local sourceBaseUrl = options.sourceBaseUrl

    assert(
        importModule or localRoot or sourceBaseUrl,
        "Hydroxide helpers require import, localRoot, or sourceBaseUrl"
    )

    local function load(name)
        local fileName = assert(moduleFiles[name], "Unknown Hydroxide helper module: " .. tostring(name))

        if cache[name] ~= nil then
            return cache[name]
        end

        local asset = "modules/" .. fileName
        local module

        if importModule then
            module = importModule(asset)
        else
            local file = asset .. ".lua"
            local source

            if localRoot then
                local readFile = options.readFile or readfile
                source = assert(readFile, "Local Hydroxide helpers require readfile")(localRoot .. "/" .. file)
            else
                local httpGet = options.httpGet or function(url)
                    return game:HttpGetAsync(url)
                end
                source = httpGet(sourceBaseUrl .. file)
            end

            local loadString = options.loadString or loadstring
            local chunk, compileError = loadString(source, file)
            module = assert(chunk, compileError)()
        end

        cache[name] = assert(module, "Hydroxide helper module returned nil: " .. name)
        return module
    end

    local oh = {
        constants = options.constants or {},
        state = options.state,
    }

    oh.load = function(name)
        local module = load(name)
        oh[name] = module
        return module
    end

    for _index, name in ipairs(options.modules or {}) do
        oh.load(name)
    end

    return oh
end

function Helpers.attach(session, options)
    assert(type(session) == "table", "Hydroxide helpers require a session")
    options = options or {}
    options.constants = options.constants or session.Constants or session.constants
    options.state = options.state or session.State or session.state
    options.modules = options.modules or {
        "closure",
        "lifecycle",
        "targeting",
    }

    local helpers = Helpers.load(options)
    for _, name in ipairs(options.modules) do
        session[name] = helpers[name]
    end
    session.constants = helpers.constants
    session.state = helpers.state
    session.load = helpers.load
    return session
end

return Helpers
]],
    ["https://raw.githubusercontent.com/3xjn/hydroxide/38778f8a78762d48fba916cade6eb93399e7c404/modules/Lifecycle.lua"] = [[local Lifecycle = {}

local function defaultContext()
    local Players = game:GetService("Players")

    return {
        Connect = function(signal, callback)
            return signal:Connect(callback)
        end,
        GetBackpack = function(player)
            return player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack")
        end,
        GetCharacter = function(player)
            return player.Character
        end,
        GetCharacterAdded = function(player)
            return player.CharacterAdded
        end,
        GetChildAdded = function(container)
            return container.ChildAdded
        end,
        GetChildren = function(container)
            return container:GetChildren()
        end,
        GetDestroying = function(instance)
            return instance.Destroying
        end,
        GetLocalPlayer = function()
            return Players.LocalPlayer
        end,
        IsTool = function(instance)
            return instance:IsA("Tool")
        end,
    }
end

local function newScope(context)
    local cleanups = {}
    local stopped = false
    local scope = {}

    function scope.add(cleanup)
        if stopped then
            cleanup()
            return cleanup
        end

        table.insert(cleanups, cleanup)
        return cleanup
    end

    function scope.connect(signal, callback)
        local connection = context.Connect(signal, callback)
        scope.add(function()
            connection:Disconnect()
        end)
        return connection
    end

    function scope.stop()
        if stopped then
            return
        end

        stopped = true
        for index = #cleanups, 1, -1 do
            pcall(cleanups[index])
        end
        table.clear(cleanups)
    end

    return scope
end

function Lifecycle.new(context)
    context = context or defaultContext()

    local lifecycle = {}

    function lifecycle.bindTools(matches, callback)
        local player = context.GetLocalPlayer()
        local sessionScope = newScope(context)
        local characterScope
        local toolScopes = {}

        local function clearTools()
            for tool, scope in pairs(toolScopes) do
                scope.stop()
                toolScopes[tool] = nil
            end
        end

        local function bind(tool)
            if toolScopes[tool] or not context.IsTool(tool) or not matches(tool) then
                return
            end

            local scope = newScope(context)
            toolScopes[tool] = scope
            callback(tool, scope)

            local destroying = context.GetDestroying and context.GetDestroying(tool)
            if destroying then
                scope.connect(destroying, function()
                    scope.stop()
                    toolScopes[tool] = nil
                end)
            end
        end

        local function watch(container, scope)
            if not container then
                return
            end

            for _index, child in ipairs(context.GetChildren(container)) do
                bind(child)
            end
            scope.connect(context.GetChildAdded(container), bind)
        end

        local function rebind(character)
            if characterScope then
                characterScope.stop()
            end
            clearTools()

            characterScope = newScope(context)
            watch(context.GetBackpack(player), characterScope)
            watch(character, characterScope)
        end

        sessionScope.connect(context.GetCharacterAdded(player), rebind)
        rebind(context.GetCharacter(player))

        local stopSession = sessionScope.stop
        function sessionScope.stop()
            if characterScope then
                characterScope.stop()
                characterScope = nil
            end
            clearTools()
            stopSession()
        end

        return sessionScope
    end

    function lifecycle.bindTool(toolName, callback)
        return lifecycle.bindTools(function(tool)
            return tool.Name == toolName
        end, callback)
    end

    return lifecycle
end

local defaultLifecycle
local function getDefaultLifecycle()
    if not defaultLifecycle then
        defaultLifecycle = Lifecycle.new()
    end

    return defaultLifecycle
end

Lifecycle.bindTool = function(...)
    return getDefaultLifecycle().bindTool(...)
end
Lifecycle.bindTools = function(...)
    return getDefaultLifecycle().bindTools(...)
end

return Lifecycle
]],
    ["https://raw.githubusercontent.com/3xjn/hydroxide/38778f8a78762d48fba916cade6eb93399e7c404/modules/Targeting.lua"] = [[local Targeting = {}

local partNames = {
    "Head",
    "UpperTorso",
    "Torso",
    "LowerTorso",
    "HumanoidRootPart",
    "LeftUpperArm",
    "RightUpperArm",
    "LeftLowerArm",
    "RightLowerArm",
    "LeftUpperLeg",
    "RightUpperLeg",
    "LeftLowerLeg",
    "RightLowerLeg",
    "LeftHand",
    "RightHand",
    "LeftFoot",
    "RightFoot",
    "Left Arm",
    "Right Arm",
    "Left Leg",
    "Right Leg",
}

function Targeting.getCharacterHitboxParts(character)
    local parts = {}
    for _index, child in ipairs(character:GetChildren()) do
        if child:IsA("BasePart") then
            table.insert(parts, child)
        end
    end
    return parts
end

function Targeting.predictIntercept(origin, targetPosition, targetVelocity, projectileSpeed)
    assert(projectileSpeed > 0, "Projectile speed must be positive")

    local offset = targetPosition - origin
    local a = targetVelocity:Dot(targetVelocity) - projectileSpeed * projectileSpeed
    local b = 2 * offset:Dot(targetVelocity)
    local c = offset:Dot(offset)
    local interceptTime

    if math.abs(a) < 1e-6 then
        if math.abs(b) >= 1e-6 then
            local candidate = -c / b
            if candidate > 0 then
                interceptTime = candidate
            end
        end
    else
        local discriminant = b * b - 4 * a * c
        if discriminant >= 0 then
            local root = math.sqrt(discriminant)
            local first = (-b - root) / (2 * a)
            local second = (-b + root) / (2 * a)
            if first > 0 and second > 0 then
                interceptTime = math.min(first, second)
            elseif first > 0 then
                interceptTime = first
            elseif second > 0 then
                interceptTime = second
            end
        end
    end

    interceptTime = interceptTime or math.sqrt(c) / projectileSpeed
    return targetPosition + targetVelocity * interceptTime, interceptTime
end

local function defaultContext()
    local Players = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local sampleOffsets = {
        Vector3.zero,
        Vector3.new(0.35, 0, 0),
        Vector3.new(-0.35, 0, 0),
        Vector3.new(0, 0.35, 0),
        Vector3.new(0, -0.35, 0),
    }

    local function isEligible(localPlayer, player, character)
        if player == localPlayer or not character then
            return false
        end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            return false
        end

        local localGame = localPlayer:GetAttribute("Game")
        local playerGame = player:GetAttribute("Game")
        if (localGame ~= nil or playerGame ~= nil) and playerGame ~= localGame then
            return false
        end

        local localTeam = localPlayer:GetAttribute("Team") or localPlayer.Team
        local playerTeam = player:GetAttribute("Team") or player.Team
        return localTeam == nil or playerTeam == nil or playerTeam ~= localTeam
    end

    local function projectPart(camera, part)
        local halfSize = part.Size / 2
        local minimumX = math.huge
        local minimumY = math.huge
        local maximumX = -math.huge
        local maximumY = -math.huge
        local projected = false
        local localCorners = {
            Vector3.new(-halfSize.X, -halfSize.Y, -halfSize.Z),
            Vector3.new(halfSize.X, -halfSize.Y, -halfSize.Z),
            Vector3.new(halfSize.X, halfSize.Y, -halfSize.Z),
            Vector3.new(-halfSize.X, halfSize.Y, -halfSize.Z),
            Vector3.new(-halfSize.X, -halfSize.Y, halfSize.Z),
            Vector3.new(halfSize.X, -halfSize.Y, halfSize.Z),
            Vector3.new(halfSize.X, halfSize.Y, halfSize.Z),
            Vector3.new(-halfSize.X, halfSize.Y, halfSize.Z),
        }
        local projectedCorners = {}
        local allCornersProjected = true

        for index, localPoint in ipairs(localCorners) do
            local worldPoint = part.CFrame:PointToWorldSpace(localPoint)
            local viewportPoint = camera:WorldToViewportPoint(worldPoint)
            if viewportPoint.Z > 0 then
                projected = true
                minimumX = math.min(minimumX, viewportPoint.X)
                minimumY = math.min(minimumY, viewportPoint.Y)
                maximumX = math.max(maximumX, viewportPoint.X)
                maximumY = math.max(maximumY, viewportPoint.Y)
                projectedCorners[index] = Vector2.new(viewportPoint.X, viewportPoint.Y)
            else
                allCornersProjected = false
            end
        end

        if not projected then
            return nil
        end

        local viewportSize = camera.ViewportSize
        minimumX = math.max(minimumX, 0)
        minimumY = math.max(minimumY, 0)
        maximumX = math.min(maximumX, viewportSize.X)
        maximumY = math.min(maximumY, viewportSize.Y)
        if maximumX <= minimumX or maximumY <= minimumY then
            return nil
        end

        local bounds = {
            position = Vector2.new(minimumX, minimumY),
            size = Vector2.new(maximumX - minimumX, maximumY - minimumY),
        }

        return bounds, allCornersProjected and projectedCorners or nil
    end

    local function getVisibleAim(localPlayer, character)
        local camera = Workspace.CurrentCamera
        if not camera then
            return nil, {}
        end

        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        raycastParams.FilterDescendantsInstances = localPlayer.Character and { localPlayer.Character } or {}
        raycastParams.IgnoreWater = true

        local origin = camera:GetRenderCFrame().Position
        local bestPart
        local bestPosition
        local bestVisibleSamples = 0
        local bodyParts = {}

        for _index, partName in ipairs(partNames) do
            local part = character:FindFirstChild(partName)
            if part and part:IsA("BasePart") then
                local visibleSamples = 0
                local visiblePosition = Vector3.zero

                for _sampleIndex, offset in ipairs(sampleOffsets) do
                    local localPoint = Vector3.new(
                        part.Size.X * offset.X,
                        part.Size.Y * offset.Y,
                        part.Size.Z * offset.Z
                    )
                    local worldPoint = part.CFrame:PointToWorldSpace(localPoint)
                    local viewportPoint, onScreen = camera:WorldToViewportPoint(worldPoint)

                    if onScreen and viewportPoint.Z > 0 then
                        local raycastResult = Workspace:Raycast(origin, worldPoint - origin, raycastParams)
                        if not raycastResult or raycastResult.Instance:IsDescendantOf(character) then
                            visibleSamples = visibleSamples + 1
                            visiblePosition = visiblePosition + worldPoint
                        end
                    end
                end

                local bounds, corners = projectPart(camera, part)
                if bounds and partName ~= "HumanoidRootPart" then
                    table.insert(bodyParts, {
                        bounds = bounds,
                        corners = corners,
                        name = partName,
                        part = part,
                        visibility = visibleSamples / #sampleOffsets,
                        visible = visibleSamples > 0,
                    })
                end

                if visibleSamples > bestVisibleSamples then
                    bestPart = part
                    bestPosition = visiblePosition / visibleSamples
                    bestVisibleSamples = visibleSamples
                end
            end
        end

        if not bestPart then
            return nil, bodyParts
        end

        local viewportPoint = camera:WorldToViewportPoint(bestPosition)
        return {
                part = bestPart,
                position = bestPosition,
                screenPosition = Vector2.new(viewportPoint.X, viewportPoint.Y),
                visibility = bestVisibleSamples / #sampleOffsets,
            },
            bodyParts
    end

    local function getDistance(localPlayer, character, position)
        local localCharacter = localPlayer.Character
        local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
        local targetRoot = character:FindFirstChild("HumanoidRootPart")

        if localRoot and targetRoot then
            return (targetRoot.Position - localRoot.Position).Magnitude
        end

        local camera = Workspace.CurrentCamera
        return camera and (position - camera:GetRenderCFrame().Position).Magnitude or math.huge
    end

    local function getPlayerObservation(localPlayer, _player, character, options)
        options = options or {}
        local camera = Workspace.CurrentCamera
        if not camera then
            return nil
        end

        local hitboxParts = Targeting.getCharacterHitboxParts(character)
        if #hitboxParts == 0 then
            return nil
        end

        local minimumX = math.huge
        local minimumY = math.huge
        local maximumX = -math.huge
        local maximumY = -math.huge
        local projected = false

        for _index, part in ipairs(hitboxParts) do
            local halfSize = part.Size / 2
            for x = -1, 1, 2 do
                for y = -1, 1, 2 do
                    for z = -1, 1, 2 do
                        local worldPoint = part.CFrame:PointToWorldSpace(Vector3.new(
                            halfSize.X * x,
                            halfSize.Y * y,
                            halfSize.Z * z
                        ))
                        local viewportPoint = camera:WorldToViewportPoint(worldPoint)
                        if viewportPoint.Z > 0 then
                            projected = true
                            minimumX = math.min(minimumX, viewportPoint.X)
                            minimumY = math.min(minimumY, viewportPoint.Y)
                            maximumX = math.max(maximumX, viewportPoint.X)
                            maximumY = math.max(maximumY, viewportPoint.Y)
                        end
                    end
                end
            end
        end

        if not projected then
            return nil
        end

        local viewportSize = camera.ViewportSize
        minimumX = math.max(minimumX, 0)
        minimumY = math.max(minimumY, 0)
        maximumX = math.min(maximumX, viewportSize.X)
        maximumY = math.min(maximumY, viewportSize.Y)
        if maximumX <= minimumX or maximumY <= minimumY then
            return nil
        end

        local aim, bodyParts = getVisibleAim(localPlayer, character)
        local fallbackPart
        local fallbackPosition
        local fallbackScreenPosition
        local fallbackScreenDistance = math.huge

        if not aim then
            for _index, partName in ipairs(partNames) do
                local part = character:FindFirstChild(partName)
                if part and part:IsA("BasePart") then
                    local viewportPoint, onScreen = camera:WorldToViewportPoint(part.Position)
                    if onScreen and viewportPoint.Z > 0 then
                        local screenPosition = Vector2.new(viewportPoint.X, viewportPoint.Y)
                        local screenDistance = 0
                        if options.screenOrigin then
                            screenDistance = (screenPosition - options.screenOrigin).Magnitude
                        end
                        if not fallbackPart or screenDistance < fallbackScreenDistance then
                            fallbackPart = part
                            fallbackPosition = part.Position
                            fallbackScreenPosition = screenPosition
                            fallbackScreenDistance = screenDistance
                        end
                    end
                end
            end
        end

        local worldPosition = aim and aim.position or fallbackPosition or hitboxParts[1].Position
        local center = camera:WorldToViewportPoint(worldPosition)

        return {
            bodyParts = bodyParts,
            bounds = {
                position = Vector2.new(minimumX, minimumY),
                size = Vector2.new(maximumX - minimumX, maximumY - minimumY),
            },
            distance = getDistance(localPlayer, character, worldPosition),
            part = aim and aim.part or fallbackPart,
            position = aim and aim.position or fallbackPosition,
            screenPosition = aim and aim.screenPosition
                or fallbackScreenPosition
                or Vector2.new(center.X, center.Y),
            visibility = aim and aim.visibility or 0,
            visible = aim ~= nil,
        }
    end

    return {
        GetCharacter = function(player)
            return player.Character
        end,
        GetDistance = getDistance,
        GetLocalPlayer = function()
            return Players.LocalPlayer
        end,
        GetPlayers = function()
            return Players:GetPlayers()
        end,
        GetPlayerObservation = getPlayerObservation,
        GetVisibleAim = getVisibleAim,
        IsEligible = isEligible,
    }
end

function Targeting.new(context)
    context = context or defaultContext()

    local targeting = {}

    local function getScreenDistance(origin, position)
        if not origin or not position then
            return nil
        end

        local deltaX = position.X - origin.X
        local deltaY = position.Y - origin.Y
        return math.sqrt(deltaX * deltaX + deltaY * deltaY)
    end

    local function isPlayerEligible(options, localPlayer, player, character)
        if options.isEligible then
            return options.isEligible(player, character)
        end

        return context.IsEligible(localPlayer, player, character)
    end

    local function observeCharacter(localPlayer, character, options)
        local getPlayerObservation = assert(
            context.GetPlayerObservation,
            "Targeting observations require GetPlayerObservation"
        )
        local source = getPlayerObservation(localPlayer, nil, character, options)
        if not source or options.maxDistance and source.distance and source.distance > options.maxDistance then
            return nil
        end

        local observation = {}
        for key, value in pairs(source) do
            observation[key] = value
        end
        observation.character = character
        observation.screenDistance = getScreenDistance(options.screenOrigin, source.screenPosition)
        return observation
    end

    function targeting.observeCharacter(character, options)
        options = options or {}
        return observeCharacter(context.GetLocalPlayer(), character, options)
    end

    function targeting.observePlayers(options)
        options = options or {}

        local localPlayer = context.GetLocalPlayer()
        local observed = {}

        for _index, player in ipairs(context.GetPlayers()) do
            local character = context.GetCharacter(player)
            if isPlayerEligible(options, localPlayer, player, character) then
                local observation = observeCharacter(localPlayer, character, options)
                if observation then
                    observation.player = player
                    table.insert(observed, observation)
                end
            end
        end

        return observed
    end

    function targeting.nearestVisiblePlayer(options)
        options = options or {}

        local localPlayer = context.GetLocalPlayer()
        local nearest

        for _index, player in ipairs(context.GetPlayers()) do
            local character = context.GetCharacter(player)
            if isPlayerEligible(options, localPlayer, player, character) then
                local aim = context.GetVisibleAim(localPlayer, character, options)
                if aim then
                    local distance = context.GetDistance(localPlayer, character, aim.position)
                    local aimScreenDistance = getScreenDistance(options.screenOrigin, aim.screenPosition)
                    local metric = aimScreenDistance or distance
                    if (not options.maxDistance or distance <= options.maxDistance)
                        and (not options.maxScreenDistance
                            or aimScreenDistance and aimScreenDistance <= options.maxScreenDistance)
                        and (not nearest or metric < nearest.metric)
                    then
                        nearest = {
                            character = character,
                            distance = distance,
                            metric = metric,
                            part = aim.part,
                            player = player,
                            position = aim.position,
                            screenDistance = aimScreenDistance,
                            screenPosition = aim.screenPosition,
                            visibility = aim.visibility,
                        }
                    end
                end
            end
        end

        return nearest
    end

    function targeting.nearestObservation(observations, options)
        options = options or {}
        local nearest

        for _index, observation in ipairs(observations) do
            if observation.position and (observation.visible or options.includeBlocked) then
                local metric = observation.screenDistance or observation.distance or math.huge
                if
                    (not options.maxScreenDistance
                        or observation.screenDistance
                            and observation.screenDistance <= options.maxScreenDistance)
                    and (not nearest or metric < nearest.metric)
                then
                    observation.metric = metric
                    nearest = observation
                end
            end
        end

        return nearest
    end

    function targeting.nearestPlayer(options)
        options = options or {}
        return targeting.nearestObservation(targeting.observePlayers(options), options)
    end

    return targeting
end

local defaultTargeting
local function getDefaultTargeting()
    if not defaultTargeting then
        defaultTargeting = Targeting.new()
    end

    return defaultTargeting
end

Targeting.nearestVisiblePlayer = function(...)
    return getDefaultTargeting().nearestVisiblePlayer(...)
end
Targeting.nearestPlayer = function(...)
    return getDefaultTargeting().nearestPlayer(...)
end
Targeting.nearestObservation = function(...)
    return getDefaultTargeting().nearestObservation(...)
end
Targeting.observeCharacter = function(...)
    return getDefaultTargeting().observeCharacter(...)
end
Targeting.observePlayers = function(...)
    return getDefaultTargeting().observePlayers(...)
end

return Targeting
]],
}
local gameIds = {
    ["10563114921"] = [[stealanegg]],
    ["10648640958"] = [[hoodrivals]],
    ["115797356"] = [[counterblox]],
    ["1718755273"] = [[town]],
    ["6035872082"] = [[rivals]],
    ["7633926880"] = [[bloxstrike]],
    ["9051406594"] = [[duelinggrounds]],
}
local placeIds = {
    ["107778070777162"] = [[stealanegg]],
    ["113272123504853"] = [[hoodrivals]],
    ["114234929420007"] = [[bloxstrike]],
    ["17625359962"] = [[rivals]],
    ["301549746"] = [[counterblox]],
    ["4991214437"] = [[town]],
    ["77463332823746"] = [[hoodrivals]],
    ["94217045453265"] = [[duelinggrounds]],
}
local function run(bundle)
    assert(type(bundle) == "table" and type(bundle.id) == "string", "Invalid game bundle")
    assert(bundle.buildId == buildId, "Runtime and game bundle builds do not match")
    assert(type(bundle.sources) == "table", "Game bundle sources are missing")
    local expected = placeIds[tostring(game.PlaceId)] or gameIds[tostring(game.GameId)]
    assert(expected == bundle.id, "Wrong game bundle: " .. tostring(bundle.id))

    local environment = assert(getgenv, "<UH> ~ Your executor is not supported")()
    local configuration = environment.UniversalHubConfig or {}
    local sourceRoot = assert(configuration.SourceBaseUrl, "Bundled loader source root is missing")
    local timing = configuration.BootTiming or { startedAt = os.clock() }
    timing.mode = "bundle"
    timing.bundle = bundle.id
    timing.bundleSourceCount = 0
    for _ in pairs(shared) do
        timing.bundleSourceCount += 1
    end
    for path, source in pairs(bundle.sources) do
        assert(type(path) == "string" and type(source) == "string", "Invalid bundled source")
        assert(shared[path] == nil, "Game bundle replaces shared source: " .. path)
        timing.bundleSourceCount += 1
    end
    configuration.BootTiming = timing
    configuration.Fetch = function(url)
        local source = external[url]
        if source == nil and url:sub(1, #sourceRoot) == sourceRoot then
            local path = url:sub(#sourceRoot + 1)
            source = bundle.sources[path] or shared[path]
        end
        return assert(source, "Source is absent from runtime bundle: " .. tostring(url))
    end
    environment.UniversalHubConfig = configuration

    local chunk, compileError = loadstring(shared["hub.lua"], "universal-hub/hub.lua")
    return assert(chunk, compileError)()
end

return {
    buildId = buildId,
    gameIds = gameIds,
    placeIds = placeIds,
    run = run,
}
