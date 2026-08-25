local fs = require("@lune/fs")
local Definition = require("../games/rivals/Definition")
local SkinUnlock = require("../games/rivals/features/SkinUnlock")
local Store = require("../modules/Store")

local NONE = "NONE_COSMETIC"

local function copyMap(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[key] = value
    end
    return result
end

local cosmeticLibrary = {
    Cosmetics = {
        ["Owned Skin"] = { Type = "Skin", ItemName = "Assault Rifle" },
        ["Visible Skin"] = { Type = "Skin", ItemName = "Assault Rifle" },
        ["Unowned Skin"] = { Type = "Skin", ItemName = "Handgun" },
        ["Hidden Skin"] = { Type = "Skin", ItemName = "Assault Rifle", Hidden = true },
        Wrap = { Type = "Wrap" },
    },
}
function cosmeticLibrary.OwnsCosmetic(_, inventory, name, weapon)
    local owned = inventory and inventory[name]
    return owned == true or type(owned) == "table" and owned[weapon] == true
end
local originalOwnsCosmetic = cosmeticLibrary.OwnsCosmetic

local cosmeticInventory = {
    ["Owned Skin"] = { ["Assault Rifle"] = true },
}
local weaponInventory = {
    { Name = "Assault Rifle", Skin = { Name = "Owned Skin" } },
    { Name = "Handgun", Skin = { Name = "Unowned Skin" } },
    { Name = "Bow" },
}
local refreshes = 0
local playerDataController = {
    CurrentData = {
        Replicate = function(_, name)
            assert(name == "CosmeticInventory")
            refreshes += 1
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

local equips = {}
local equipCosmetic = {}
function equipCosmetic:FireServer(weapon, cosmeticType, skin, options)
    table.insert(equips, {
        weapon = weapon,
        cosmeticType = cosmeticType,
        skin = skin,
        options = options,
    })
end

local persisted = {}
local function runtime()
    return SkinUnlock.new({
        cosmeticLibrary = cosmeticLibrary,
        equipCosmetic = equipCosmetic,
        onRestoreChanged = function(snapshot)
            table.insert(persisted, copyMap(snapshot))
        end,
        playerDataController = playerDataController,
    })
end

local unlock = runtime()
unlock:update({ unlockAllSkins = true, unlockAllSkinsRestore = {} })
local saved = persisted[#persisted]
assert(saved["Assault Rifle"] == "Owned Skin", "enable must remember an equipped owned skin")
assert(saved.Handgun == NONE, "legacy unowned equipped skins must safely restore to none")
assert(saved.Bow == NONE, "weapons without a skin must restore to none")
assert(cosmeticLibrary:OwnsCosmetic(cosmeticInventory, "Visible Skin", "Assault Rifle") == true)
assert(
    cosmeticLibrary:OwnsCosmetic(cosmeticInventory, "Hidden Skin", "Assault Rifle") == false,
    "hidden skins must remain unavailable"
)
assert(
    cosmeticLibrary:OwnsCosmetic(cosmeticInventory, "Wrap", "Assault Rifle") == false,
    "the override must not unlock non-skin cosmetics"
)
assert(cosmeticLibrary:OwnsCosmetic(cosmeticInventory, "Owned Skin", "Assault Rifle") == true)
assert(refreshes == 1, "enabling must refresh the native cosmetics UI")

weaponInventory[1].Skin = { Name = "Visible Skin" }
unlock:update({ unlockAllSkins = false, unlockAllSkinsRestore = saved })
assert(
    cosmeticLibrary.OwnsCosmetic == originalOwnsCosmetic,
    "disable must restore native ownership"
)
assert(#equips == 2, "disable must restore changed equipped skins")
assert(equips[1].weapon == "Assault Rifle" and equips[1].skin == "Owned Skin")
assert(equips[1].cosmeticType == "Skin" and type(equips[1].options) == "table")
assert(equips[2].weapon == "Handgun" and equips[2].skin == NONE)
assert(next(persisted[#persisted]) == nil, "disable must clear the persisted restore snapshot")
assert(refreshes == 2, "disabling must refresh the native cosmetics UI")

local existingSnapshot = { ["Assault Rifle"] = "Owned Skin" }
local encodedSnapshot = SkinUnlock.encodeRestore(existingSnapshot)
assert(
    #encodedSnapshot == 1
        and encodedSnapshot[1].weapon == "Assault Rifle"
        and encodedSnapshot[1].skin == "Owned Skin"
)
local persistedBeforeReload = #persisted
local reload = runtime()
reload:update({ unlockAllSkins = true, unlockAllSkinsRestore = encodedSnapshot })
assert(
    #persisted == persistedBeforeReload,
    "hub reload must reuse an existing restore snapshot instead of replacing it"
)
local equipsBeforeStop = #equips
reload:stop()
assert(cosmeticLibrary.OwnsCosmetic == originalOwnsCosmetic)
assert(#equips == equipsBeforeStop, "hot reload must not change equipped skins")
assert(#persisted == persistedBeforeReload, "hot reload must preserve the restore snapshot")

local persistedBeforeMigration = #persisted
local legacyReload = runtime()
legacyReload:update({ unlockAllSkins = true, unlockAllSkinsRestore = existingSnapshot })
assert(
    #persisted == persistedBeforeMigration + 1
        and persisted[#persisted]["Assault Rifle"] == "Owned Skin",
    "hub load must migrate a legacy restore map without changing its saved skin"
)
legacyReload:stop()

weaponInventory[1].Skin = { Name = "Visible Skin" }
local cleanup = runtime()
cleanup:update({ unlockAllSkins = false, unlockAllSkinsRestore = encodedSnapshot })
assert(equips[#equips].weapon == "Assault Rifle" and equips[#equips].skin == "Owned Skin")
assert(next(persisted[#persisted]) == nil, "disabled legacy config must clear a stale snapshot")

local store = Store.new({ settings = { unlockAllSkinsRestore = existingSnapshot } })
local state = store:Get()
local updated = table.clone(state.settings)
updated.unlockAllSkinsRestore = encodedSnapshot
store:Patch({ settings = updated })
assert(
    store:Get().settings.unlockAllSkinsRestore[1].skin == "Owned Skin",
    "migration must replace the legacy map with the persisted list shape"
)
state = store:Get()
updated = table.clone(state.settings)
updated.unlockAllSkinsRestore = SkinUnlock.encodeRestore({})
store:Patch({ settings = updated })
assert(
    next(store:Get().settings.unlockAllSkinsRestore) == nil,
    "the persisted list shape must replace a stale Store snapshot when disabled"
)

assert(Definition.defaults.unlockAllSkins == false)
assert(type(Definition.defaults.unlockAllSkinsRestore) == "table")
assert(table.find(Definition.features.capabilities, "unlockAllSkins"))
assert(table.find(Definition.sources, "games/rivals/features/SkinUnlock"))

local adapterSource = fs.readFile("games/rivals/Adapter.lua")
assert(adapterSource:find('require("./features/SkinUnlock")', 1, true))
assert(adapterSource:find("skinUnlock:update(settings)", 1, true))
assert(adapterSource:find("SkinUnlock.encodeRestore(snapshot)", 1, true))
assert(adapterSource:find("skinUnlock:stop()", 1, true))

print("rivals-skin-unlock-contracts-ok")
