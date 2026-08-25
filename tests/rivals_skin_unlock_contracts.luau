local fs = require("@lune/fs")
local Definition = require("../games/rivals/Definition")
local SkinUnlock = require("../games/rivals/features/SkinUnlock")
local Store = require("../modules/Store")

local NONE = "NONE_COSMETIC"

local function findEntry(encoded, weapon, cosmeticType)
    for _, entry in ipairs(encoded or {}) do
        if entry.weapon == weapon and entry.cosmeticType == cosmeticType then
            return entry
        end
    end
    return nil
end

local cosmeticLibrary = {
    Cosmetics = {
        ["Owned Skin"] = { Type = "Skin", ItemName = "Assault Rifle" },
        ["Visible Skin"] = { Type = "Skin", ItemName = "Assault Rifle" },
        ["Unowned Skin"] = { Type = "Skin", ItemName = "Handgun" },
        ["Hidden Skin"] = { Type = "Skin", ItemName = "Assault Rifle", Hidden = true },
        ["Owned Wrap"] = { Type = "Wrap" },
        ["Visible Wrap"] = { Type = "Wrap" },
        ["Hidden Wrap"] = { Type = "Wrap", Hidden = true },
        ["Visible Charm"] = { Type = "Charm" },
        ["Visible Finisher"] = { Type = "Finisher" },
        Emote = { Type = "Emote" },
    },
}
function cosmeticLibrary.OwnsCosmetic(_, inventory, name, weapon)
    local owned = inventory and inventory[name]
    return owned == true or type(owned) == "table" and owned[weapon] == true
end
local originalOwnsCosmetic = cosmeticLibrary.OwnsCosmetic

local cosmeticInventory = {
    ["Owned Skin"] = { ["Assault Rifle"] = true },
    ["Owned Wrap"] = { ["Assault Rifle"] = true },
}
local weaponInventory = {
    {
        Name = "Assault Rifle",
        Skin = { Name = "Owned Skin" },
        Wrap = { Name = "Owned Wrap" },
    },
    { Name = "Handgun", Skin = { Name = "Unowned Skin" } },
    { Name = "Bow" },
}
local refreshes = {}
local weaponInventoryListeners = {}
local weaponInventorySignal = {}
function weaponInventorySignal:Connect(listener)
    weaponInventoryListeners[listener] = true
    return {
        Disconnect = function()
            weaponInventoryListeners[listener] = nil
        end,
    }
end
function weaponInventorySignal:Fire()
    for listener in pairs(weaponInventoryListeners) do
        listener()
    end
end
local playerDataController = {
    CurrentData = {
        Replicate = function(_, name)
            refreshes[name] = (refreshes[name] or 0) + 1
            if name == "WeaponInventory" then
                weaponInventorySignal:Fire()
            end
        end,
    },
}
function playerDataController:Get(name)
    if name == "CosmeticInventory" then
        return cosmeticInventory
    end
    if name == "WeaponInventory" then
        return weaponInventory
    end
    error("Unexpected player data key: " .. tostring(name))
end
function playerDataController:GetDataChangedSignal(name)
    assert(name == "WeaponInventory")
    return weaponInventorySignal
end
function playerDataController:GetWeaponData(name)
    for _, weapon in ipairs(weaponInventory) do
        if weapon.Name == name then
            return weapon
        end
    end
    return nil
end

local equipmentState = {
    SelectedWeapon = "Assault Rifle",
    CustomizingType = "Skin",
    CosmeticInverted = nil,
}
local equipmentStateLibrary = {}
function equipmentStateLibrary.SelectCosmetic(state, cosmetic)
    state.SelectedCosmetic = cosmetic ~= NONE and cosmetic or nil
end
local originalSelectCosmetic = equipmentStateLibrary.SelectCosmetic

local equips = {}
local equipCosmetic = {}
function equipCosmetic:FireServer(weapon, cosmeticType, name, options)
    table.insert(equips, {
        weapon = weapon,
        cosmeticType = cosmeticType,
        name = name,
        options = options,
    })
end

local restoreWrites = {}
local equippedWrites = {}
local function runtime()
    return SkinUnlock.new({
        cosmeticLibrary = cosmeticLibrary,
        equipmentState = equipmentState,
        equipmentStateLibrary = equipmentStateLibrary,
        equipCosmetic = equipCosmetic,
        onEquippedChanged = function(cosmetics)
            table.insert(equippedWrites, SkinUnlock.encodeRestore(cosmetics))
        end,
        onRestoreChanged = function(cosmetics)
            table.insert(restoreWrites, SkinUnlock.encodeRestore(cosmetics))
        end,
        playerDataController = playerDataController,
    })
end

local unlock = runtime()
unlock:update({
    unlockAllSkins = true,
    unlockAllSkinsRestore = {},
    unlockAllCosmeticsEquipped = {},
})
local saved = restoreWrites[#restoreWrites]
assert(findEntry(saved, "Assault Rifle", "Skin").name == "Owned Skin")
assert(findEntry(saved, "Assault Rifle", "Wrap").name == "Owned Wrap")
assert(findEntry(saved, "Assault Rifle", "Charm").name == NONE)
assert(findEntry(saved, "Assault Rifle", "Finisher").name == NONE)
assert(findEntry(saved, "Handgun", "Skin").name == NONE)
assert(cosmeticLibrary:OwnsCosmetic(cosmeticInventory, "Visible Skin", "Assault Rifle"))
assert(cosmeticLibrary:OwnsCosmetic(cosmeticInventory, "Visible Wrap", "Assault Rifle"))
assert(cosmeticLibrary:OwnsCosmetic(cosmeticInventory, "Visible Charm", "Assault Rifle"))
assert(cosmeticLibrary:OwnsCosmetic(cosmeticInventory, "Visible Finisher", "Assault Rifle"))
assert(not cosmeticLibrary:OwnsCosmetic(cosmeticInventory, "Hidden Skin", "Assault Rifle"))
assert(not cosmeticLibrary:OwnsCosmetic(cosmeticInventory, "Hidden Wrap", "Assault Rifle"))
assert(not cosmeticLibrary:OwnsCosmetic(cosmeticInventory, "Emote", "Assault Rifle"))
assert(equipmentStateLibrary.SelectCosmetic ~= originalSelectCosmetic)

for cosmeticType, name in pairs({
    Skin = "Visible Skin",
    Wrap = "Visible Wrap",
    Charm = "Visible Charm",
    Finisher = "Visible Finisher",
}) do
    equipmentState.CustomizingType = cosmeticType
    equipmentState.CosmeticInverted = cosmeticType == "Wrap" and true or nil
    equipmentStateLibrary.SelectCosmetic(equipmentState, name)
    assert(weaponInventory[1][cosmeticType].Name == name)
end
assert(weaponInventory[1].Wrap.Inverted == true)
local locallyEquipped = equippedWrites[#equippedWrites]
assert(findEntry(locallyEquipped, "Assault Rifle", "Skin").name == "Visible Skin")
assert(findEntry(locallyEquipped, "Assault Rifle", "Wrap").inverted == true)
assert(findEntry(locallyEquipped, "Assault Rifle", "Charm").name == "Visible Charm")
assert(findEntry(locallyEquipped, "Assault Rifle", "Finisher").name == "Visible Finisher")
assert((refreshes.WeaponInventory or 0) >= 5, "local selections must refresh equipped state")
weaponInventory[1].Skin = { Name = "Owned Skin" }
weaponInventorySignal:Fire()
assert(
    weaponInventory[1].Skin.Name == "Visible Skin",
    "server inventory refreshes must reapply the persisted local selection"
)

unlock:update({
    unlockAllSkins = false,
    unlockAllSkinsRestore = saved,
    unlockAllCosmeticsEquipped = locallyEquipped,
})
assert(cosmeticLibrary.OwnsCosmetic == originalOwnsCosmetic)
assert(equipmentStateLibrary.SelectCosmetic == originalSelectCosmetic)
assert(weaponInventory[1].Skin.Name == "Owned Skin")
assert(weaponInventory[1].Wrap.Name == "Owned Wrap")
assert(weaponInventory[1].Charm == nil and weaponInventory[1].Finisher == nil)
assert(weaponInventory[2].Skin == nil, "legacy unowned equipment must safely restore to none")
assert(next(restoreWrites[#restoreWrites]) == nil)
assert(next(equippedWrites[#equippedWrites]) == nil)
local restoredTypes = {}
for _, call in ipairs(equips) do
    if call.weapon == "Assault Rifle" then
        restoredTypes[call.cosmeticType] = call.name
    end
end
assert(restoredTypes.Skin == "Owned Skin" and restoredTypes.Wrap == "Owned Wrap")
assert(restoredTypes.Charm == NONE and restoredTypes.Finisher == NONE)

local localReload = runtime()
localReload:update({
    unlockAllSkins = true,
    unlockAllSkinsRestore = saved,
    unlockAllCosmeticsEquipped = locallyEquipped,
})
assert(weaponInventory[1].Skin.Name == "Visible Skin")
assert(weaponInventory[1].Wrap.Name == "Visible Wrap")
local writesBeforeStop = #equippedWrites
localReload:stop()
assert(equipmentStateLibrary.SelectCosmetic == originalSelectCosmetic)
assert(weaponInventory[1].Skin.Name == "Visible Skin", "hot reload must preserve local equipment")
assert(#equippedWrites == writesBeforeStop, "hot reload must preserve local config")
weaponInventory[1].Skin = { Name = "Owned Skin" }
weaponInventory[1].Wrap = { Name = "Owned Wrap" }
weaponInventory[1].Charm = nil
weaponInventory[1].Finisher = nil

local legacyRestore = { ["Assault Rifle"] = "Owned Skin" }
local migration = runtime()
migration:update({
    unlockAllSkins = true,
    unlockAllSkinsRestore = legacyRestore,
    unlockAllCosmeticsEquipped = {},
})
local migrated = restoreWrites[#restoreWrites]
assert(findEntry(migrated, "Assault Rifle", "Skin").name == "Owned Skin")
assert(findEntry(migrated, "Assault Rifle", "Wrap").name == "Owned Wrap")
migration:stop()

local disabledStore = Store.new({
    settings = {
        unlockAllSkins = false,
        unlockAllSkinsRestore = legacyRestore,
        unlockAllCosmeticsEquipped = locallyEquipped,
    },
})
local function persistDisabledSetting(name, cosmetics)
    local state = disabledStore:Get()
    local updated = table.clone(state.settings)
    updated[name] = SkinUnlock.encodeRestore(cosmetics)
    disabledStore:Patch({ settings = updated })
end
local disabledCleanup = SkinUnlock.new({
    cosmeticLibrary = cosmeticLibrary,
    equipmentState = equipmentState,
    equipmentStateLibrary = equipmentStateLibrary,
    equipCosmetic = equipCosmetic,
    onEquippedChanged = function(cosmetics)
        persistDisabledSetting("unlockAllCosmeticsEquipped", cosmetics)
    end,
    onRestoreChanged = function(cosmetics)
        persistDisabledSetting("unlockAllSkinsRestore", cosmetics)
    end,
    playerDataController = playerDataController,
})
disabledCleanup:update(disabledStore:Get().settings)
assert(next(disabledStore:Get().settings.unlockAllSkinsRestore) == nil)
assert(next(disabledStore:Get().settings.unlockAllCosmeticsEquipped) == nil)
disabledCleanup:stop()

assert(Definition.defaults.unlockAllSkins == false)
assert(type(Definition.defaults.unlockAllSkinsRestore) == "table")
assert(type(Definition.defaults.unlockAllCosmeticsEquipped) == "table")
assert(table.find(Definition.features.capabilities, "unlockAllSkins"))
assert(table.find(Definition.sources, "games/rivals/features/SkinUnlock"))

local adapterSource = fs.readFile("games/rivals/Adapter.lua")
assert(adapterSource:find('require("./features/SkinUnlock")', 1, true))
assert(adapterSource:find("skinUnlock:update(settings)", 1, true))
assert(adapterSource:find('persistCosmeticSetting("unlockAllCosmeticsEquipped"', 1, true))
assert(adapterSource:find("skinUnlock:stop()", 1, true))

print("rivals-skin-unlock-contracts-ok")
