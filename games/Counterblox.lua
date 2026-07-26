local Counterblox = {
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
        "names",
        "health",
        "weapon",
    },
    id = "counterblox",
    label = "Counterblox",
    manifest = {
        gameIds = { 7633926880 },
        placeIds = { 114234929420007 },
    },
}

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

local function contains(list, value)
    for _, candidate in ipairs(list or {}) do
        if candidate == value then
            return true
        end
    end
    return false
end

function Counterblox.match(context)
    if contains(Counterblox.manifest.placeIds, context.placeId) then
        return 200
    end
    if contains(Counterblox.manifest.gameIds, context.gameId) then
        return 100
    end
    return 0
end

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

    local function isOpponent(player, character)
        if player == LocalPlayer or not character or character:GetAttribute("Dead") == true then
            return false
        end
        if isSpectatedCharacter(character) then
            return false
        end

        local referencePlayer = spectatedPlayer() or LocalPlayer
        local localTeam = referencePlayer:GetAttribute("Team")
        local playerTeam = player:GetAttribute("Team")
        local gameMode = Workspace:GetAttribute("Gamemode")
        local serverGameMode = Workspace:GetAttribute("ServerGamemode")
        local isDeathmatch = (type(gameMode) == "string" and gameMode:lower() == "deathmatch")
            or (type(serverGameMode) == "string" and serverGameMode:lower() == "deathmatch")
        if not isDeathmatch and localTeam ~= nil and playerTeam ~= nil and localTeam == playerTeam then
            return false
        end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        return humanoid == nil or humanoid.Health > 0
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

    local function updateObservations()
        observations = targeting.observePlayers({
            isEligible = isOpponent,
            raycastIgnore = spectatorRaycastIgnore(),
            screenOrigin = UserInputService:GetMouseLocation(),
        })

        local visibleCount = 0
        for _, observation in ipairs(observations) do
            local humanoid = observation.character and observation.character:FindFirstChildOfClass("Humanoid")
            observation.health = humanoid and humanoid.Health or 0
            observation.maxHealth = humanoid and humanoid.MaxHealth or 100
            observation.weapon = equippedWeapon(observation.player)
            if observation.visible then
                visibleCount = visibleCount + 1
            end
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
        local visibleCount = updateObservations()
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
        context.render(observations, UserInputService:GetMouseLocation(), utilityObservations)
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

    self.capabilities = Counterblox.capabilities
    self.classify = Counterblox.classifyWeapon
    self.isOpponent = isOpponent
    self.selectTarget = selectTarget
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
