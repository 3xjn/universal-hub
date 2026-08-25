local SkinUnlock = {}
SkinUnlock.__index = SkinUnlock

local NONE_COSMETIC = "NONE_COSMETIC"

local function copyMap(source)
    local result = {}
    for key, value in pairs(source or {}) do
        if type(key) == "string" and type(value) == "string" then
            result[key] = value
        elseif
            type(key) == "number"
            and type(value) == "table"
            and type(value.weapon) == "string"
            and type(value.skin) == "string"
        then
            result[value.weapon] = value.skin
        end
    end
    return result
end

function SkinUnlock.encodeRestore(restore)
    local result = {}
    for weapon, skin in pairs(copyMap(restore)) do
        table.insert(result, { weapon = weapon, skin = skin })
    end
    table.sort(result, function(left, right)
        return left.weapon < right.weapon
    end)
    return result
end

local function isLegacyMap(restore)
    for key in pairs(restore or {}) do
        if type(key) == "string" then
            return true
        end
    end
    return false
end

function SkinUnlock.new(options)
    assert(options and type(options.cosmeticLibrary) == "table")
    assert(type(options.cosmeticLibrary.OwnsCosmetic) == "function")
    assert(options.playerDataController)
    assert(options.equipCosmetic and type(options.equipCosmetic.FireServer) == "function")

    local self = setmetatable({
        cosmeticLibrary = options.cosmeticLibrary,
        enabled = nil,
        equipCosmetic = options.equipCosmetic,
        onRestoreChanged = options.onRestoreChanged or function() end,
        originalOwnsCosmetic = options.cosmeticLibrary.OwnsCosmetic,
        playerDataController = options.playerDataController,
        restore = {},
    }, SkinUnlock)

    self.unlockOwnsCosmetic = function(library, inventory, name, weapon)
        local info = self.cosmeticLibrary.Cosmetics[name]
        if info and info.Type == "Skin" and info.Hidden ~= true then
            return true
        end
        return self.originalOwnsCosmetic(library, inventory, name, weapon)
    end

    return self
end

function SkinUnlock:_waitUntilLoaded()
    local waitUntilLoaded = self.playerDataController.WaitUntilLoaded
    if type(waitUntilLoaded) == "function" then
        waitUntilLoaded(self.playerDataController)
    end
end

function SkinUnlock:_get(name)
    self:_waitUntilLoaded()
    return self.playerDataController:Get(name)
end

function SkinUnlock:_nativeOwns(inventory, name, weapon)
    local success, owned =
        pcall(self.originalOwnsCosmetic, self.cosmeticLibrary, inventory, name, weapon)
    return success and owned and true or false
end

function SkinUnlock:_snapshotOwnedSkins()
    local cosmeticInventory = self:_get("CosmeticInventory") or {}
    local restore = {}
    for _, weapon in pairs(self:_get("WeaponInventory") or {}) do
        if type(weapon) == "table" and type(weapon.Name) == "string" then
            local skin = type(weapon.Skin) == "table" and weapon.Skin.Name or nil
            restore[weapon.Name] = type(skin) == "string"
                    and self:_nativeOwns(cosmeticInventory, skin, weapon.Name)
                    and skin
                or NONE_COSMETIC
        end
    end
    return restore
end

function SkinUnlock:_refreshCosmetics()
    local data = self.playerDataController.CurrentData
    if data and type(data.Replicate) == "function" then
        pcall(data.Replicate, data, "CosmeticInventory")
    end
end

function SkinUnlock:_restoreSkins(restore)
    local cosmeticInventory = self:_get("CosmeticInventory") or {}
    for _, weapon in pairs(self:_get("WeaponInventory") or {}) do
        local weaponName = type(weapon) == "table" and weapon.Name or nil
        local saved = type(weaponName) == "string" and restore[weaponName] or nil
        if type(saved) == "string" then
            if
                saved ~= NONE_COSMETIC
                and not self:_nativeOwns(cosmeticInventory, saved, weaponName)
            then
                saved = NONE_COSMETIC
            end
            local current = type(weapon.Skin) == "table" and weapon.Skin.Name or NONE_COSMETIC
            if current ~= saved then
                pcall(
                    self.equipCosmetic.FireServer,
                    self.equipCosmetic,
                    weaponName,
                    "Skin",
                    saved,
                    {}
                )
            end
        end
    end
end

function SkinUnlock:_restoreOwnership()
    if self.cosmeticLibrary.OwnsCosmetic == self.unlockOwnsCosmetic then
        self.cosmeticLibrary.OwnsCosmetic = self.originalOwnsCosmetic
    end
end

function SkinUnlock:update(settings)
    settings = settings or {}
    local enabled = settings.unlockAllSkins == true
    if enabled == self.enabled then
        return false
    end

    local persisted = copyMap(settings.unlockAllSkinsRestore)
    if enabled then
        self.enabled = true
        if next(persisted) == nil then
            persisted = self:_snapshotOwnedSkins()
            self.onRestoreChanged(copyMap(persisted))
        elseif isLegacyMap(settings.unlockAllSkinsRestore) then
            self.onRestoreChanged(copyMap(persisted))
        end
        self.restore = persisted
        self.cosmeticLibrary.OwnsCosmetic = self.unlockOwnsCosmetic
    else
        local shouldRestore = self.enabled == true or next(persisted) ~= nil
        self.enabled = false
        self:_restoreOwnership()
        if shouldRestore then
            local restore = next(persisted) ~= nil and persisted or self.restore
            self:_restoreSkins(restore)
            self.restore = {}
            self.onRestoreChanged({})
        end
    end

    self:_refreshCosmetics()
    return true
end

function SkinUnlock:stop()
    self:_restoreOwnership()
    self.enabled = false
    self:_refreshCosmetics()
end

return SkinUnlock
