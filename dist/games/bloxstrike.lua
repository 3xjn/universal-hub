return {
    buildId = [[610c86b0]],
    id = [[bloxstrike]],
    sources = {
        ["games/Bloxstrike.lua"] = [[local Bloxstrike = {}

function Bloxstrike.new(context)
    assert(type(context) == "table", "Bloxstrike adapter requires context")
    local base = assert(context.tacticalAdapter, "Bloxstrike requires the shared tactical adapter")
    local preview = assert(context.bloxstrikePreview, "Bloxstrike requires its preview adapter")
    local adapter = base.new(context)
    preview.install(adapter, context)
    return adapter
end

return Bloxstrike
]],
        ["games/bloxstrike/Composition.lua"] = [[local Composition = {}

Composition.dependencies = {
    bloxstrikePreview = "games/bloxstrike/Preview",
    tacticalAdapter = "games/Counterblox",
}

function Composition.bind(context, dependencies)
    assert(type(context) == "table" and type(context.getAdapter) == "function")
    assert(type(dependencies) == "table")
    local function adapter()
        return context.getAdapter()
    end
    return {
        adapter = {
            bloxstrikePreview = assert(dependencies.bloxstrikePreview),
            tacticalAdapter = assert(dependencies.tacticalAdapter),
        },
        overlay = {
            getWeaponPreviewKey = function(state)
                local current = adapter()
                return current and current:weaponPreviewKey(state) or "bloxstrike-weapon-pending"
            end,
            getWeaponPreviewSubject = function(state)
                local current = adapter()
                return current and current:weaponPreviewSubject(state) or nil
            end,
            getPreviewKey = function(state)
                local current = adapter()
                return current and current:previewKey(state) or "bloxstrike-pending"
            end,
            getPreviewSubject = function(state)
                local current = adapter()
                return current and current:previewSubject(state) or nil
            end,
            cycleGlove = function(direction)
                adapter():cycleGlove(direction)
            end,
            previousGlove = function()
                adapter():cycleGlove(-1)
            end,
            nextGlove = function()
                adapter():cycleGlove(1)
            end,
            cycleSkin = function(direction)
                adapter():cycleSkin(direction)
            end,
            previousSkin = function()
                adapter():cycleSkin(-1)
            end,
            nextSkin = function()
                adapter():cycleSkin(1)
            end,
            cycleCosmeticWeapon = function(direction)
                adapter():cycleCosmeticWeapon(direction)
            end,
            previousCosmeticWeapon = function()
                adapter():cycleCosmeticWeapon(-1)
            end,
            nextCosmeticWeapon = function()
                adapter():cycleCosmeticWeapon(1)
            end,
            resetSkin = function()
                adapter():resetSkin()
            end,
            resetGlove = function()
                adapter():resetGlove()
            end,
            setGloveWear = function(alpha)
                adapter():setGloveWear(alpha)
            end,
            setGloveColor = function(color)
                adapter():setGloveColor(color)
            end,
            setWear = function(alpha)
                adapter():setWear(alpha)
            end,
            toggleStatTrak = function()
                adapter():toggleStatTrak()
            end,
        },
    }
end

return Composition
]],
        ["games/bloxstrike/Presentation.lua"] = [[local Presentation = {}

function Presentation.mount(host)
    if type(host.page) == "function" then
        host:page("Visuals", {
            layout = "toggle-grid",
            views = {
                { id = "preview", label = "Preview" },
                { id = "colors", label = "ESP Colors" },
            },
            preview = { kind = "character", weaponLabel = "KNIFE" },
        })
    end
    host:aim()
    host:rate("headshotRate", "Headshot Rate")
    host:rate("missRate", "Miss Rate")

    host:segmented("Visuals", {
        id = "worldRenderer",
        sectionLabel = "ESP",
        label = "Style",
        treatment = "style",
        options = {
            {
                label = "Classic",
                value = "limn",
                when = { worldRenderer = "limn" },
                patch = { { "worldRenderer", "limn" } },
            },
            {
                label = "Highlights",
                value = "native",
                when = { worldRenderer = "native" },
                patch = { { "worldRenderer", "native" } },
            },
        },
    })

    host:section("Combat", "rage", "AIM", 64, true, 2)
    host:option("rage", 1, "silentAim", "Silent Aim")
    host:option("rage", 1, "wallbang", "Wallbang", "silentAim")
    host:option("rage", 2, "rapidFire", "Rapid Fire")
    host:option("rage", 3, "triggerBot", "Trigger Bot")
    host:option("rage", 3, "noSpread", "No Spread")
    host:option("rage", 4, "noRecoil", "No Recoil")
    host:option("rage", 4, "noWeaponSlow", "No Weapon Slow")

    host:section("Combat", "melee", "MELEE", 70, false, 2)
    host:option("melee", 1, "knifeAura", "Knife Aura")
    host:option("melee", 1, "microStep", "Micro Step", "knifeAura")

    host:section("Movement", "movement", "MOVEMENT", 70)
    host:option("movement", 1, "spinBot", "Spin Bot")
    host:option("movement", 1, "bhop", "Bunny Hop")

    host:section("Visuals", "visuals", "VISUALS", 70, false, 1, { treatment = "grid" })
    host:option("visuals", 1, "boxes", "Hitboxes")
    host:option("visuals", 1, "chams", "Chams")
    host:option("visuals", 2, "chamsExcludeAccessories", "Ignore Accessories", "chams", {
        setting = "worldRenderer", equals = "native",
    })
    host:option("visuals", 2, "chamsPerPart", "Part Highlights", "chams", {
        setting = "worldRenderer", equals = "native",
    })
    host:option("visuals", 3, "names", "Names")
    host:option("visuals", 3, "health", "Health")
    host:option("visuals", 4, "weapon", "Weapons")
    host:option("visuals", 20, "showEnemies", "Enemies", "audience")
    host:option("visuals", 21, "showTeammates", "Allies", "audience")
    host:option("visuals", 5, "bombTimer", "Bomb Timer")
    host:option("visuals", 6, "utilityEsp", "Utility ESP")
    host:cosmetics()
end

return Presentation
]],
        ["games/bloxstrike/Preview.lua"] = [[local Preview = {}

local function decodedJson(value, decode)
    if type(value) == "table" then
        return value
    end
    if type(value) ~= "string" then
        return nil
    end
    local success, result = pcall(decode, value)
    return success and type(result) == "table" and result or nil
end

local function stockGlove(team)
    return team == "Counter-Terrorists" and "CT Glove" or "T Glove"
end

function Preview.resolveLoadout(player, settings, decode)
    settings = type(settings) == "table" and settings or {}
    decode = decode or function(source)
        return game:GetService("HttpService"):JSONDecode(source)
    end
    local slot = player and decodedJson(player:GetAttribute("Slot3"), decode) or nil
    local baseWeapon = slot and (slot.Weapon or slot.Name) or nil
    local team = player and player:GetAttribute("Team") or nil
    if team ~= "Counter-Terrorists" and team ~= "Terrorists" then
        baseWeapon = "T Knife"
    elseif type(baseWeapon) ~= "string" or baseWeapon == "" then
        baseWeapon = team == "Counter-Terrorists" and "CT Knife" or "T Knife"
    end
    local knife = {
        baseWeapon = baseWeapon,
        weapon = baseWeapon,
        skin = slot and slot.Skin or "Stock",
        wear = slot and (slot.Float or slot.Wear) or 0,
        statTrak = slot and slot.StatTrack == true or false,
    }
    local override = type(settings.skinOverrides) == "table" and settings.skinOverrides[baseWeapon] or nil
    if type(override) == "table" then
        knife.weapon = type(override.weapon) == "string" and override.weapon or baseWeapon
        knife.skin = type(override.skin) == "string" and override.skin or knife.skin
        knife.wear = type(override.wear) == "number" and override.wear or knife.wear
        knife.statTrak = override.statTrak == true
    end

    local glove = type(settings.gloveOverride) == "table" and settings.gloveOverride or nil
    if glove then
        glove = {
            weapon = type(glove.weapon) == "string" and glove.weapon or stockGlove(team),
            skin = type(glove.skin) == "string" and glove.skin or "Stock",
            wear = type(glove.wear) == "number" and glove.wear or 0,
        }
    else
        local equipped = player and player.Character
            and decodedJson(player.Character:GetAttribute("EquippedGloves"), decode)
            or nil
        local identifier = equipped and equipped.SkinIdentifier
        local weapon = equipped and (equipped.Name or equipped.Weapon)
        local skin = equipped and equipped.Skin
        if type(identifier) == "string" then
            weapon = string.match(identifier, "^(.-)_Stock$") or weapon
            skin = string.match(identifier, "^[^_]+_(.+)$") or skin
        end
        glove = {
            weapon = type(weapon) == "string" and weapon or stockGlove(team),
            skin = type(skin) == "string" and skin or "Stock",
            wear = equipped and (equipped.Float or equipped.Wear) or 0,
        }
    end
    return {
        glove = glove,
        gloveColor = type(settings.gloveColorOverride) == "table" and settings.gloveColorOverride or nil,
        knife = knife,
    }
end

function Preview.install(self, context)
    assert(type(self) == "table", "Bloxstrike preview requires an adapter")
    assert(type(context) == "table" and context.store, "Bloxstrike preview requires context")
    local Players = game:GetService("Players")
    local HttpService = game:GetService("HttpService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = context.localPlayer or Players.LocalPlayer
    local loadModule = context.requireModule or require
    local Skins = loadModule(ReplicatedStorage.Database.Components.Libraries.Skins)
    local AttachGlovesToCharacter = loadModule(
        ReplicatedStorage.Database.Components.Common.AttachGlovesToCharacter
    )
    local Attachments = loadModule(
        ReplicatedStorage.Database.Custom.GameStats.Character.Attachments
    )
    local store = context.store

    local function previewLoadout(state)
        return Preview.resolveLoadout(LocalPlayer, state and state.settings, function(source)
            return HttpService:JSONDecode(source)
        end)
    end

    if not store:Get().activeWeapon then
        store:Patch({ activeWeapon = previewLoadout(store:Get()).knife.baseWeapon })
    end

    local function applyPreviewGloves(character, loadout)
        local glove = loadout.glove
        local success, gloveModel = pcall(Skins.GetGloves, glove.weapon, glove.skin, glove.wear)
        if not success or typeof(gloveModel) ~= "Instance" or not gloveModel:IsA("Model") then
            return
        end
        local armor = character:FindFirstChild("CharacterArmor")
        if not armor then
            armor = Instance.new("Folder")
            armor.Name = "CharacterArmor"
            armor.Parent = character
        end
        for _, name in ipairs({ "LeftGlove", "RightGlove" }) do
            local previous = armor:FindFirstChild(name)
            if previous then
                previous:Destroy()
            end
        end
        pcall(AttachGlovesToCharacter, gloveModel:GetChildren(), character, armor)
        gloveModel:Destroy()
        local colorOverride = loadout.gloveColor
        if type(colorOverride) == "table" then
            local color = Color3.new(colorOverride.r or 1, colorOverride.g or 1, colorOverride.b or 1)
            for _, name in ipairs({ "LeftGlove", "RightGlove" }) do
                local part = armor:FindFirstChild(name)
                if part and part:IsA("BasePart") then
                    part.Color = color
                    for _, appearance in ipairs(part:GetChildren()) do
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
    end

    local function applyPreviewKnife(character, loadout)
        local knife = loadout.knife
        local success, characterModel = pcall(
            Skins.GetCharacterModel,
            knife.weapon,
            knife.skin,
            knife.wear,
            knife.statTrak
        )
        if not success or typeof(characterModel) ~= "Instance" or not characterModel:IsA("Model") then
            return
        end
        local primaryPart = characterModel.PrimaryPart
        if not primaryPart then
            local weapon = characterModel:FindFirstChild("Weapon")
            local insert = weapon and weapon:FindFirstChild("Insert")
                or characterModel:FindFirstChild("Insert", true)
            if insert and insert:IsA("BasePart") then
                characterModel.PrimaryPart = insert
                primaryPart = insert
            end
        end
        local jointPartName = Attachments.WEAPON_JOINT_PARTS[knife.weapon]
            or Attachments.DEFAULT_JOINT_PART
        local jointPart = character:FindFirstChild(jointPartName)
            or character:FindFirstChild("RightHand")
            or character:FindFirstChild("Right Arm")
        if not primaryPart or not jointPart or not jointPart:IsA("BasePart") then
            characterModel:Destroy()
            return
        end
        local previous = character:FindFirstChild("UniversalHubPreviewWeapon")
        if previous then
            previous:Destroy()
        end
        for _, part in ipairs(characterModel:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Anchored = false
                part.CanCollide = false
                part.CanQuery = false
                part.CanTouch = false
                part.Massless = true
            end
        end
        characterModel.Name = "UniversalHubPreviewWeapon"
        characterModel.Parent = character
        local oldJoint = jointPart:FindFirstChild("WeaponAttachment")
        if oldJoint then
            oldJoint:Destroy()
        end
        local joint = Instance.new("Motor6D")
        joint.Name = "WeaponAttachment"
        joint.Part0 = jointPart
        joint.Part1 = primaryPart
        joint.Parent = jointPart
        local properties = characterModel:FindFirstChild("Properties")
        if not properties then
            local weapon = characterModel:FindFirstChild("Weapon")
            properties = weapon and weapon:FindFirstChild("Properties")
                or characterModel:FindFirstChild("Properties", true)
        end
        local c0 = properties and properties:FindFirstChild("C0")
        local c1 = properties and properties:FindFirstChild("C1")
        joint.C0 = c0 and c0:IsA("CFrameValue") and c0.Value or CFrame.new()
        joint.C1 = c1 and c1:IsA("CFrameValue") and c1.Value or CFrame.new()
    end

    function self:previewKey(state)
        local loadout = previewLoadout(state or store:Get())
        local knife = loadout.knife
        local glove = loadout.glove
        local color = loadout.gloveColor
        return table.concat({
            tostring(LocalPlayer.Character),
            knife.baseWeapon,
            knife.weapon,
            knife.skin,
            tostring(knife.wear),
            tostring(knife.statTrak),
            glove.weapon,
            glove.skin,
            tostring(glove.wear),
            color and table.concat({ tostring(color.r), tostring(color.g), tostring(color.b) }, ",") or "game",
        }, "|")
    end

    local function weaponPreviewSelection(state)
        state = state or store:Get()
        local cosmetics = state.cosmetics
        if type(cosmetics) == "table"
            and type(cosmetics.weapon) == "string"
            and cosmetics.weapon ~= ""
        then
            return {
                weapon = cosmetics.weapon,
                skin = type(cosmetics.skin) == "string" and cosmetics.skin or "Stock",
                wear = type(cosmetics.wear) == "number" and cosmetics.wear or 0,
                statTrak = cosmetics.statTrak == true,
            }
        end
        return previewLoadout(state).knife
    end

    function self:weaponPreviewKey(state)
        local selection = weaponPreviewSelection(state)
        return table.concat({
            "weapon",
            selection.weapon,
            selection.skin,
            tostring(selection.wear),
            tostring(selection.statTrak),
        }, "|")
    end

    function self:weaponPreviewSubject(state)
        local selection = weaponPreviewSelection(state)
        local success, weapon = pcall(
            Skins.GetCharacterModel,
            selection.weapon,
            selection.skin,
            selection.wear,
            selection.statTrak
        )
        if not success or typeof(weapon) ~= "Instance" or not weapon:IsA("Model") then
            return nil
        end
        weapon.Name = "UniversalHubWeaponPreview"
        return weapon
    end

    function self:previewSubject(state)
        local source = LocalPlayer.Character
        local character
        if source and source:IsA("Model") then
            local wasArchivable = source.Archivable
            source.Archivable = true
            local success, result = pcall(source.Clone, source)
            source.Archivable = wasArchivable
            if success then
                character = result
            end
        end
        if not character then
            local characters = ReplicatedStorage.Assets:FindFirstChild("Characters")
            local team = LocalPlayer:GetAttribute("Team")
            local templateName = team == "Counter-Terrorists" and "IDF" or "Anarchist"
            local template = characters and characters:FindFirstChild(templateName)
            if template and template:IsA("Model") then
                local success, result = pcall(template.Clone, template)
                if success then
                    character = result
                end
            end
        end
        if not character then
            return nil
        end
        local loadout = previewLoadout(state or store:Get())
        applyPreviewGloves(character, loadout)
        applyPreviewKnife(character, loadout)
        local weaponAnimations = ReplicatedStorage.Assets:FindFirstChild("WeaponAnimations")
        local animationFolder = weaponAnimations and weaponAnimations:FindFirstChild(loadout.knife.weapon)
        local characterAnimations = animationFolder and animationFolder:FindFirstChild("CharacterAnimations")
        local previewAnimation = characterAnimations and characterAnimations:FindFirstChild("Idle")
        if previewAnimation and previewAnimation:IsA("Animation") then
            local idle = previewAnimation:Clone()
            idle.Name = "UniversalHubPreviewIdle"
            idle.Parent = character
        end
        character.Name = "LimnPreviewAvatar"
        return character
    end
    return self
end

return Preview
]],
    },
}
