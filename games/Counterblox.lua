local Counterblox = {
    id = "counterblox",
    label = "Counterblox",
    manifest = {
        gameIds = { 7633926880 },
        placeIds = { 114234929420007 },
    },
}

local KNIFE_AURA_INTERVAL = 0.12
local KNIFE_EXTRA_REACH = 3
local KNIFE_FALLBACK_RANGE = 7
local KNIFE_MICRO_STEP = 0.75
local BHOP_AIR_ACCELERATION = 10
local SPIN_SPEED = math.rad(1440)
local THIRD_PERSON_DISTANCE = 8
local MOVEMENT_RENDER_STEP = "UniversalHubCounterbloxMovement"
local MOVEMENT_RENDER_PRIORITY = 2000

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

local function targetVisible(target)
    if target.visible ~= nil then
        return target.visible == true
    end
    if type(target.visibility) == "table" then
        return target.visibility.visible == true
    end
    return false
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
    local LocalPlayer = Players.LocalPlayer

    local loadModule: (any) -> any = context.requireModule or require
    local Bullet = loadModule(ReplicatedStorage.Components.Weapon.Classes.Bullet)
    local Melee = loadModule(ReplicatedStorage.Components.Melee)
    local CameraController = loadModule(ReplicatedStorage.Controllers.CameraController)
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
    local hookFunction = assert(context.hookFunction, "Counterblox adapter requires hookfunction")
    local restoreFunction = assert(context.restoreFunction, "Counterblox adapter requires restorefunction")
    local setThirdPerson = context.setThirdPerson or function() end
    local isJumpHeld = context.isJumpHeld or function()
        return UserInputService:IsKeyDown(Enum.KeyCode.Space)
    end
    local movementDirection = context.movementDirection
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
    local nextTriggerAt = 0
    local noFlashApplied = false
    local noSmokeApplied = false
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
    local gloveCatalogCache
    local trackedComponents = setmetatable({}, { __mode = "k" })
    local characterTransparency = setmetatable({}, { __mode = "k" })
    local viewmodelTransparency = setmetatable({}, { __mode = "k" })

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

    local function isSpectatedCharacter(character)
        local camera = Workspace.CurrentCamera
        local subject = camera and camera.CameraSubject
        return subject ~= nil
            and (subject == character or subject.Parent == character or subject:IsDescendantOf(character))
    end

    local function isOpponent(player, character)
        if player == LocalPlayer or not character or character:GetAttribute("Dead") == true then
            return false
        end
        if isSpectatedCharacter(character) then
            return false
        end

        local localTeam = LocalPlayer:GetAttribute("Team")
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
                if source.skin ~= "Stock" then
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
        return overrides and overrides[weaponName]
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
        local schema, index = cosmeticSchema(weaponName, override.skin, override.weapon)
        local range = schema.floatRange or { min = 0, max = 1 }
        local catalog = cosmeticCatalog(weaponName)
        local key = table.concat({
            weaponName,
            override.weapon or weaponName,
            override.skin,
            tostring(override.wear),
            tostring(override.statTrak),
            tostring(#catalog),
        }, "|")
        if key == lastCosmeticKey then
            return
        end
        lastCosmeticKey = key
        store:Patch({
            cosmetics = {
                maximumWear = range.max or 1,
                minimumWear = range.min or 0,
                skin = override.skin,
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
        local wasEquipped = oldViewmodel and oldViewmodel.IsEquipped == true
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
        if not settings.silentAim then
            return result
        end

        local wallbangActive = settings.silentAim and settings.wallbang
        local target = currentTarget or selectTarget(wallbangActive)
        currentTarget = nil
        if not target or not result or not result.Origin then
            store:Patch({ lastShot = "No target" })
            return result
        end

        if not targetVisible(target) and not wallbangActive then
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

    hooks.recoilTarget = CameraController.weaponKick
    hooks.recoilOriginal = hookFunction(hooks.recoilTarget, function(...)
        if not stopped and store:Get().settings.noRecoil then
            return nil
        end
        return hooks.recoilOriginal(...)
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

    local function equippedGunBullet()
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
                return component.Bullet
            end
        end
        return nil
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
        if not targetVisible(target)
            and not (settings.silentAim and settings.wallbang and penetrationAccepted(target))
        then
            return
        end

        currentTarget = settings.silentAim and target or nil
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

    local function runKnifeAura()
        local settings = store:Get().settings
        if not settings.knifeAura
            or activeWeaponKind ~= "Knife"
            or context.isInputCaptured()
            or os.clock() < nextAuraAt
        then
            return
        end

        local _, humanoid, root = localCharacter()
        if not root then
            return true
        end

        local target = selectTarget(false)
        if not target or not targetVisible(target) then
            return true
        end

        local offset = target.position - root.CFrame.Position
        local distance = offset.Magnitude
        if distance > meleeRange then
            if not settings.microStep or distance > meleeRange + KNIFE_EXTRA_REACH then
                return true
            end

            local horizontal = Vector3.new(offset.X, 0, offset.Z)
            if horizontal.Magnitude <= 0.001
                or not humanoid.FloorMaterial
                or humanoid.FloorMaterial.Name == "Air"
            then
                return true
            end
            local stepDistance = math.min(KNIFE_MICRO_STEP, distance - meleeRange)
            root.CFrame = root.CFrame + horizontal.Unit * stepDistance
            return true
        end

        currentTarget = target
        nextAuraAt = os.clock() + KNIFE_AURA_INTERVAL
        click()
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
                bhopSpeedLimit = math.max(bhopMomentum.Magnitude, humanoid.WalkSpeed)
            end
            if moveDirection.Magnitude > 0.001 then
                local direction = moveDirection.Unit
                local speed = bhopMomentum.Magnitude
                local acceleration = math.min(
                    math.max(humanoid.WalkSpeed - bhopMomentum:Dot(direction), 0),
                    humanoid.WalkSpeed * BHOP_AIR_ACCELERATION * (deltaTime or 0)
                )
                local steered = bhopMomentum + direction * acceleration
                if speed > 0.001 and steered.Magnitude < speed then
                    steered = steered.Unit * speed
                end
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
        publishCosmetics(activeWeapon)
        publishGloves()
        local visibleCount = updateObservations()
        store:Patch({
            activeWeapon = activeWeapon,
            activeWeaponKind = activeWeaponKind,
            observations = observations,
            status = ("%d enemies · %d visible"):format(#observations, visibleCount),
        })
        context.render(observations, UserInputService:GetMouseLocation())
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
        restoreFunction(hooks.recoilTarget)
        restoreFunction(hooks.spreadTarget)
        restoreFunction(hooks.bulletTarget)
    end

    self.capabilities = {
        "silentAim",
        "triggerBot",
        "wallbang",
        "knifeAura",
        "microStep",
        "spinBot",
        "bhop",
        "noSpread",
        "noRecoil",
        "noFlash",
        "noSmoke",
        "noWeaponSlow",
        "boxes",
        "names",
        "health",
        "weapon",
    }
    self.classify = Counterblox.classifyWeapon
    self.isOpponent = isOpponent
    self.selectTarget = selectTarget
    function self:cycleSkin(direction)
        local weaponName = store:Get().activeWeapon or lastEquippedName
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
        local weaponName = store:Get().activeWeapon or lastEquippedName
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
        local weaponName = store:Get().activeWeapon or lastEquippedName
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
        local weaponName = store:Get().activeWeapon or lastEquippedName
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
