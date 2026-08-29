local SkinUnlock = {}
SkinUnlock.__index = SkinUnlock

local NONE_COSMETIC = "NONE_COSMETIC"
local RANDOM_COSMETIC = "RANDOM_COSMETIC"
local COSMETIC_TYPES = { "Skin", "Wrap", "Charm", "Finisher" }
local SET_THREAD_IDENTITY = setthreadidentity or setidentity or setthreadcontext
local GET_THREAD_IDENTITY = getthreadidentity or getidentity or getthreadcontext
local SUPPORTED_TYPES = {}
for _, cosmeticType in ipairs(COSMETIC_TYPES) do
    SUPPORTED_TYPES[cosmeticType] = true
end

local function booleanField(value, key)
    if type(value) == "table" and type(value[key]) == "boolean" then
        return value[key]
    end
    return nil
end

local function copyEntry(value)
    if type(value) == "string" then
        return { name = value }
    end
    if type(value) ~= "table" or type(value.name) ~= "string" then
        return nil
    end
    return {
        name = value.name,
        inverted = booleanField(value, "inverted"),
        onlyUseFavorites = booleanField(value, "onlyUseFavorites"),
    }
end

local function put(result, weapon, cosmeticType, value)
    local entry = copyEntry(value)
    if type(weapon) ~= "string" or not SUPPORTED_TYPES[cosmeticType] or not entry then
        return
    end
    result[weapon] = result[weapon] or {}
    result[weapon][cosmeticType] = entry
end

local function copyCosmetics(source)
    local result = {}
    for key, value in pairs(source or {}) do
        if type(key) == "string" then
            if type(value) == "string" then
                put(result, key, "Skin", value)
            elseif type(value) == "table" then
                for cosmeticType, entry in pairs(value) do
                    put(result, key, cosmeticType, entry)
                end
            end
        elseif type(key) == "number" and type(value) == "table" then
            put(
                result,
                value.weapon,
                value.cosmeticType or (value.skin and "Skin"),
                value.name
                        and {
                            name = value.name,
                            inverted = value.inverted,
                            onlyUseFavorites = value.onlyUseFavorites,
                        }
                    or value.skin
            )
        end
    end
    return result
end

function SkinUnlock.encodeRestore(restore)
    local result = {}
    for weapon, cosmetics in pairs(copyCosmetics(restore)) do
        for cosmeticType, entry in pairs(cosmetics) do
            local encoded = {
                weapon = weapon,
                cosmeticType = cosmeticType,
                name = entry.name,
            }
            if type(entry.inverted) == "boolean" then
                encoded.inverted = entry.inverted
            end
            if type(entry.onlyUseFavorites) == "boolean" then
                encoded.onlyUseFavorites = entry.onlyUseFavorites
            end
            table.insert(result, encoded)
        end
    end
    table.sort(result, function(left, right)
        return left.weapon == right.weapon and left.cosmeticType < right.cosmeticType
            or left.weapon < right.weapon
    end)
    return result
end

local function sameEntry(value, entry)
    local name = type(value) == "table" and value.Name or NONE_COSMETIC
    return name == entry.name
        and (entry.inverted == nil or booleanField(value, "Inverted") == entry.inverted)
        and (
            entry.onlyUseFavorites == nil
            or booleanField(value, "OnlyUseFavorites") == entry.onlyUseFavorites
        )
end

local function applyEntry(weaponData, cosmeticType, entry)
    if entry.name == NONE_COSMETIC then
        weaponData[cosmeticType] = nil
        return
    end
    weaponData[cosmeticType] = { Name = entry.name }
    if cosmeticType == "Wrap" and type(entry.inverted) == "boolean" then
        weaponData[cosmeticType].Inverted = entry.inverted
    end
    if type(entry.onlyUseFavorites) == "boolean" then
        weaponData[cosmeticType].OnlyUseFavorites = entry.onlyUseFavorites
    end
end

local function viewModelFingerprint(cosmetics)
    local parts = {}
    for _, cosmeticType in ipairs({ "Skin", "Wrap", "Charm" }) do
        local entry = cosmetics and cosmetics[cosmeticType]
        table.insert(
            parts,
            entry and table.concat({ cosmeticType, entry.name, tostring(entry.inverted) }, ":")
                or ""
        )
    end
    return table.concat(parts, "|")
end

function SkinUnlock.new(options)
    assert(options and type(options.cosmeticLibrary) == "table")
    assert(type(options.cosmeticLibrary.OwnsCosmetic) == "function")
    assert(options.playerDataController)
    assert(options.equipCosmetic and type(options.equipCosmetic.FireServer) == "function")
    assert(type(options.equipmentStateLibrary) == "table")
    assert(type(options.equipmentStateLibrary.SelectCosmetic) == "function")
    assert(type(options.equipmentStateLibrary.SetCosmeticInvertedState) == "function")
    assert(type(options.equipmentState) == "table")
    assert(type(options.clientViewModelLibrary) == "table")
    assert(type(options.clientViewModelLibrary.new) == "function")
    assert(type(options.fighterController) == "table")

    local self = setmetatable({
        applying = false,
        clientViewModelLibrary = options.clientViewModelLibrary,
        cosmeticLibrary = options.cosmeticLibrary,
        enabled = nil,
        equipmentState = options.equipmentState,
        equipmentStateLibrary = options.equipmentStateLibrary,
        equipCosmetic = options.equipCosmetic,
        equipped = {},
        fighterController = options.fighterController,
        getThreadIdentity = options.getThreadIdentity or GET_THREAD_IDENTITY,
        lastViewModel = nil,
        lastViewModelFingerprint = nil,
        onEquippedChanged = options.onEquippedChanged or function() end,
        setThreadIdentity = options.setThreadIdentity or SET_THREAD_IDENTITY,
        onRestoreChanged = options.onRestoreChanged or function() end,
        viewModelClassFor = options.viewModelClassFor or function()
            return nil
        end,
        originalOwnsCosmetic = options.cosmeticLibrary.OwnsCosmetic,
        originalSelectCosmetic = options.equipmentStateLibrary.SelectCosmetic,
        originalSetCosmeticInvertedState = options.equipmentStateLibrary.SetCosmeticInvertedState,
        playerDataController = options.playerDataController,
        restore = {},
    }, SkinUnlock)

    self.unlockOwnsCosmetic = function(library, inventory, name, weapon)
        local info = self.cosmeticLibrary.Cosmetics[name]
        if info and SUPPORTED_TYPES[info.Type] and info.Hidden ~= true then
            return true
        end
        return self.originalOwnsCosmetic(library, inventory, name, weapon)
    end
    self.selectCosmetic = function(state, cosmetic)
        local result = self.originalSelectCosmetic(state, cosmetic)
        if self.enabled and state == self.equipmentState then
            self:_selectLocalCosmetic(state, cosmetic)
        end
        return result
    end
    self.setCosmeticInvertedState = function(state, inverted)
        local result = self.originalSetCosmeticInvertedState(state, inverted)
        if self.enabled and state == self.equipmentState then
            self:_setLocalWrapInverted(state, inverted)
        end
        return result
    end
    if type(self.playerDataController.GetDataChangedSignal) == "function" then
        local success, signal = pcall(
            self.playerDataController.GetDataChangedSignal,
            self.playerDataController,
            "WeaponInventory"
        )
        if success and signal and type(signal.Connect) == "function" then
            self.weaponInventoryConnection = signal:Connect(function()
                if self.enabled and not self.applying then
                    self:_applyLocalCosmetics()
                end
            end)
        end
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

function SkinUnlock:_getWeaponData(name)
    for _, weapon in pairs(self:_get("WeaponInventory") or {}) do
        if type(weapon) == "table" and weapon.Name == name then
            return weapon
        end
    end
    return nil
end

function SkinUnlock:_resolveEntry(weaponName, cosmeticType, entry)
    if not entry or entry.name ~= RANDOM_COSMETIC then
        return entry
    end
    local candidates = {}
    for name, info in pairs(self.cosmeticLibrary.Cosmetics) do
        if
            info.Type == cosmeticType
            and info.Hidden ~= true
            and (cosmeticType ~= "Skin" or info.ItemName == weaponName)
        then
            table.insert(candidates, name)
        end
    end
    if #candidates == 0 then
        return { name = NONE_COSMETIC }
    end
    local resolved = copyEntry(entry)
    resolved.name = candidates[math.random(#candidates)]
    return resolved
end

function SkinUnlock:_updateHud(fighter, item, viewModel)
    local interface = fighter.FighterInterface
    if not interface then
        return
    end
    local image = viewModel:GetImage()
    for _, slots in ipairs({
        interface.Hotbar and interface.Hotbar._hotbar_slots,
        interface.EquippedDisplays and interface.EquippedDisplays._equipped_displays,
    }) do
        for _, slot in pairs(slots or {}) do
            if slot.ClientItem == item then
                local icon = slot.Icon or slot.WeaponIcon
                if icon then
                    icon.Image = image
                end
            end
        end
    end
end

function SkinUnlock:_applyViewModelForWeapon(weaponName, cosmetics, force)
    local fighter = self.fighterController.LocalFighter
    local item = fighter and fighter.EquippedItem
    local old = item and item.ViewModel
    if not old or item.Name ~= weaponName or type(self.setThreadIdentity) ~= "function" then
        return false
    end

    local fingerprint = viewModelFingerprint(cosmetics)
    if not force and old == self.lastViewModel and fingerprint == self.lastViewModelFingerprint then
        return false
    end

    local previousIdentity = 8
    if type(self.getThreadIdentity) == "function" then
        local success, identity = pcall(self.getThreadIdentity)
        if success and type(identity) == "number" then
            previousIdentity = identity
        end
    end
    if not pcall(self.setThreadIdentity, 2) then
        return false
    end

    local replacement
    local wasEquipped = old._is_equipped == true
    local success = pcall(function()
        local serial = old:Serialize()
        local data = serial[old:ToEnum("Data")]
        local skin = self:_resolveEntry(weaponName, "Skin", cosmetics and cosmetics.Skin)
        local wrap = self:_resolveEntry(weaponName, "Wrap", cosmetics and cosmetics.Wrap)
        local charm = self:_resolveEntry(weaponName, "Charm", cosmetics and cosmetics.Charm)

        if skin then
            data[old:ToEnum("Name")] = skin.name == NONE_COSMETIC and weaponName or skin.name
        end
        for cosmeticType, entry in pairs({ Wrap = wrap, Charm = charm }) do
            if entry then
                local value
                if entry.name ~= NONE_COSMETIC then
                    value = { Name = entry.name }
                    if cosmeticType == "Wrap" and type(entry.inverted) == "boolean" then
                        value.Inverted = entry.inverted
                    end
                end
                data[old:ToEnum(cosmeticType)] = value
            end
        end

        local viewModelClass = self.viewModelClassFor(weaponName) or getmetatable(old)
        local constructor = type(viewModelClass) == "table" and viewModelClass.new
            or self.clientViewModelLibrary.new
        replacement = constructor(serial, item)
        local parent = old.Model and old.Model.Parent
        local pivot = old.Model and old.Model:GetPivot()
        if wasEquipped then
            old:Unequip()
        end
        item.ViewModel = replacement
        replacement:SetArmsData(old._shirt_id, old._left_arm_color, old._right_arm_color)
        replacement:SetParent(parent)
        if pivot then
            replacement:SetCFrame(pivot)
        end
        self:_updateHud(fighter, item, replacement)
        if wasEquipped then
            replacement:Equip(true)
        end
        old:Destroy()
    end)
    pcall(self.setThreadIdentity, previousIdentity)

    if not success or not replacement then
        item.ViewModel = old
        if replacement then
            pcall(replacement.Destroy, replacement)
        end
        if wasEquipped then
            pcall(old.Equip, old, true)
        end
        return false
    end

    self.lastViewModel = replacement
    self.lastViewModelFingerprint = fingerprint
    return true
end

function SkinUnlock:step()
    if not self.enabled then
        return false
    end
    local fighter = self.fighterController.LocalFighter
    local item = fighter and fighter.EquippedItem
    local cosmetics = item and self.equipped[item.Name]
    if not cosmetics or not (cosmetics.Skin or cosmetics.Wrap or cosmetics.Charm) then
        return false
    end
    return self:_applyViewModelForWeapon(item.Name, cosmetics, false)
end

function SkinUnlock:_nativeOwns(inventory, name, weapon)
    local success, owned =
        pcall(self.originalOwnsCosmetic, self.cosmeticLibrary, inventory, name, weapon)
    return success and owned and true or false
end

function SkinUnlock:_snapshotOwnedCosmetics()
    local cosmeticInventory = self:_get("CosmeticInventory") or {}
    local restore = {}
    for _, weapon in pairs(self:_get("WeaponInventory") or {}) do
        if type(weapon) == "table" and type(weapon.Name) == "string" then
            restore[weapon.Name] = {}
            for _, cosmeticType in ipairs(COSMETIC_TYPES) do
                local value = weapon[cosmeticType]
                local name = type(value) == "table" and value.Name or nil
                local canRestore = name == RANDOM_COSMETIC
                    or type(name) == "string"
                        and self:_nativeOwns(cosmeticInventory, name, weapon.Name)
                restore[weapon.Name][cosmeticType] = {
                    name = canRestore and name or NONE_COSMETIC,
                    inverted = booleanField(value, "Inverted"),
                    onlyUseFavorites = booleanField(value, "OnlyUseFavorites"),
                }
            end
        end
    end
    return restore
end

function SkinUnlock:_refresh(name)
    local data = self.playerDataController.CurrentData
    if data and type(data.Replicate) == "function" then
        pcall(data.Replicate, data, name)
    end
end

function SkinUnlock:_applyLocalCosmetics()
    if self.applying then
        return
    end
    self.applying = true
    for weaponName, cosmetics in pairs(self.equipped) do
        local weaponData = self:_getWeaponData(weaponName)
        if weaponData then
            for cosmeticType, entry in pairs(cosmetics) do
                applyEntry(weaponData, cosmeticType, entry)
            end
        end
    end
    self:_refresh("WeaponInventory")
    self.applying = false
end

function SkinUnlock:_selectLocalCosmetic(state, cosmetic)
    local weaponName = state.SelectedWeapon
    local cosmeticType = state.CustomizingType
    if type(weaponName) ~= "string" or not SUPPORTED_TYPES[cosmeticType] or cosmetic == nil then
        return
    end
    if cosmetic ~= NONE_COSMETIC and cosmetic ~= RANDOM_COSMETIC then
        local info = self.cosmeticLibrary.Cosmetics[cosmetic]
        if not info or info.Type ~= cosmeticType or info.Hidden == true then
            return
        end
    end

    local weaponData = self:_getWeaponData(weaponName)
    local current = weaponData and weaponData[cosmeticType] or nil
    local inverted
    local onlyUseFavorites
    if cosmeticType == "Wrap" then
        inverted = booleanField(state, "CosmeticInverted")
    end
    if cosmetic == RANDOM_COSMETIC then
        onlyUseFavorites = booleanField(current, "OnlyUseFavorites")
    end
    local entry = {
        name = cosmetic,
        inverted = inverted,
        onlyUseFavorites = onlyUseFavorites,
    }
    self.equipped[weaponName] = self.equipped[weaponName] or {}
    self.equipped[weaponName][cosmeticType] = entry
    self:_applyLocalCosmetics()
    if cosmeticType ~= "Finisher" then
        self:_applyViewModelForWeapon(weaponName, self.equipped[weaponName], true)
    end
    self.onEquippedChanged(copyCosmetics(self.equipped))
end

function SkinUnlock:_setLocalWrapInverted(state, inverted)
    local weaponName = state.SelectedWeapon
    if
        type(weaponName) ~= "string"
        or state.CustomizingType ~= "Wrap"
        or type(inverted) ~= "boolean"
    then
        return
    end
    local weaponCosmetics = self.equipped[weaponName]
    local entry = weaponCosmetics and weaponCosmetics.Wrap or nil
    if not entry then
        local weaponData = self:_getWeaponData(weaponName)
        local current = weaponData and weaponData.Wrap or nil
        if type(current) ~= "table" or type(current.Name) ~= "string" then
            return
        end
        self.equipped[weaponName] = weaponCosmetics or {}
        entry = {
            name = current.Name,
            onlyUseFavorites = booleanField(current, "OnlyUseFavorites"),
        }
        self.equipped[weaponName].Wrap = entry
    end
    if entry.name == NONE_COSMETIC then
        return
    end
    entry.inverted = inverted
    self:_applyLocalCosmetics()
    self:_applyViewModelForWeapon(weaponName, self.equipped[weaponName], true)
    self.onEquippedChanged(copyCosmetics(self.equipped))
end

function SkinUnlock:_restoreCosmetics(restore)
    local cosmeticInventory = self:_get("CosmeticInventory") or {}
    for weaponName, cosmetics in pairs(restore) do
        local weaponData = self:_getWeaponData(weaponName)
        local applied = {}
        if weaponData then
            for cosmeticType, saved in pairs(cosmetics) do
                local entry = copyEntry(saved)
                if entry then
                    if
                        entry.name ~= NONE_COSMETIC
                        and entry.name ~= RANDOM_COSMETIC
                        and not self:_nativeOwns(cosmeticInventory, entry.name, weaponName)
                    then
                        entry = { name = NONE_COSMETIC }
                    end
                    applied[cosmeticType] = entry
                    if not sameEntry(weaponData[cosmeticType], entry) then
                        pcall(
                            self.equipCosmetic.FireServer,
                            self.equipCosmetic,
                            weaponName,
                            cosmeticType,
                            entry.name,
                            {
                                IsInverted = entry.inverted,
                                OnlyUseFavorites = entry.onlyUseFavorites,
                            }
                        )
                        applyEntry(weaponData, cosmeticType, entry)
                    end
                end
            end
            self:_applyViewModelForWeapon(weaponName, applied, true)
        end
    end
    self:_refresh("WeaponInventory")
end

function SkinUnlock:_restoreNativeMethods()
    if self.cosmeticLibrary.OwnsCosmetic == self.unlockOwnsCosmetic then
        self.cosmeticLibrary.OwnsCosmetic = self.originalOwnsCosmetic
    end
    if self.equipmentStateLibrary.SelectCosmetic == self.selectCosmetic then
        self.equipmentStateLibrary.SelectCosmetic = self.originalSelectCosmetic
    end
    if self.equipmentStateLibrary.SetCosmeticInvertedState == self.setCosmeticInvertedState then
        self.equipmentStateLibrary.SetCosmeticInvertedState = self.originalSetCosmeticInvertedState
    end
end

function SkinUnlock:update(settings)
    settings = settings or {}
    local enabled = settings.unlockAllSkins == true
    if enabled == self.enabled then
        return false
    end

    local persistedRestore = copyCosmetics(settings.unlockAllSkinsRestore)
    local persistedEquipped = copyCosmetics(settings.unlockAllCosmeticsEquipped)
    if enabled then
        self.enabled = true
        local snapshot = self:_snapshotOwnedCosmetics()
        for weapon, cosmetics in pairs(snapshot) do
            persistedRestore[weapon] = persistedRestore[weapon] or {}
            for cosmeticType, entry in pairs(cosmetics) do
                if persistedRestore[weapon][cosmeticType] == nil then
                    persistedRestore[weapon][cosmeticType] = copyEntry(entry)
                end
            end
        end
        self.restore = persistedRestore
        self.equipped = persistedEquipped
        self.onRestoreChanged(copyCosmetics(self.restore))
        self.cosmeticLibrary.OwnsCosmetic = self.unlockOwnsCosmetic
        self.equipmentStateLibrary.SelectCosmetic = self.selectCosmetic
        self.equipmentStateLibrary.SetCosmeticInvertedState = self.setCosmeticInvertedState
        self:_applyLocalCosmetics()
    else
        local shouldRestore = self.enabled == true
            or next(persistedRestore) ~= nil
            or next(persistedEquipped) ~= nil
        self.enabled = false
        self:_restoreNativeMethods()
        if shouldRestore then
            if next(persistedRestore) ~= nil then
                self.onRestoreChanged(copyCosmetics(persistedRestore))
            end
            if next(persistedEquipped) ~= nil then
                self.onEquippedChanged(copyCosmetics(persistedEquipped))
            end
            local restore = next(persistedRestore) ~= nil and persistedRestore or self.restore
            self:_restoreCosmetics(restore)
            self.restore = {}
            self.equipped = {}
            self.onRestoreChanged({})
            self.onEquippedChanged({})
        end
    end

    self:_refresh("CosmeticInventory")
    return true
end

function SkinUnlock:stop()
    self:_restoreNativeMethods()
    self.enabled = false
    if self.weaponInventoryConnection then
        self.weaponInventoryConnection:Disconnect()
        self.weaponInventoryConnection = nil
    end
    self:_refresh("CosmeticInventory")
end

return SkinUnlock
