local TaskCounterPolicy = require("./TaskCounterPolicy")

local TaskWeaponSwap = {}
TaskWeaponSwap.__index = TaskWeaponSwap

local SLOT_ORDER = {
    Primary = 1,
    Secondary = 2,
    Utility = 3,
    Melee = 4,
}

local function reloading(item)
    if type(item) ~= "table" then
        return false
    end
    local data = item.Data
    return item.IsEquipping == true
        or type(data) == "table" and (data.IsReloading == true or data.Reloading == true)
end

local function candidates(fighter)
    local source = fighter.Items
    if
        (type(source) ~= "table" or next(source) == nil)
        and type(fighter.GetEquippedItems) == "function"
    then
        local succeeded, equipped = pcall(fighter.GetEquippedItems, fighter)
        if succeeded and type(equipped) == "table" then
            source = equipped
        end
    end
    if type(source) ~= "table" then
        return {}
    end

    local result = {}
    local seen = {}
    for key, value in pairs(source) do
        local item = type(value) == "table" and value or type(key) == "table" and key or nil
        if not item and type(fighter.GetItem) == "function" then
            local identifier = value ~= true and value or key
            local succeeded, resolved = pcall(fighter.GetItem, fighter, identifier)
            item = succeeded and resolved or nil
        end
        if type(item) == "table" and not seen[item] then
            seen[item] = true
            table.insert(result, item)
        end
    end
    return result
end

function TaskWeaponSwap.new(options)
    return setmetatable({
        clock = options.clock or os.clock,
        counterPolicy = options.counterPolicy or TaskCounterPolicy,
        equip = options.equip or function(fighter, item)
            return fighter:EquipItem(item)
        end,
        nextAt = 0,
        pendingItem = nil,
        pendingAttempts = 0,
        pendingAt = 0,
        pendingFighter = nil,
        pendingMobility = false,
        pendingTargetKey = nil,
        release = options.release or function() end,
        weaponPolicy = assert(options.weaponPolicy),
    }, TaskWeaponSwap)
end

function TaskWeaponSwap:reset()
    self.pendingItem = nil
    self.pendingAttempts = 0
    self.pendingAt = 0
    self.pendingFighter = nil
    self.pendingMobility = false
    self.pendingTargetKey = nil
    self.nextAt = 0
end

function TaskWeaponSwap:_ready(item, distance)
    local policy = self.weaponPolicy
    local info = item and item.Info
    local capability = policy.capabilities(item)
    if
        type(info) ~= "table"
        or policy.automationPolicy(item).triggerBot ~= true
        or reloading(item)
    then
        return false
    end
    if capability.attack == "melee" then
        return policy.taskMeleeInRange(item, distance)
    end
    local ammo = policy.ammo(item)
    return capability.attack == "gun" and type(ammo) == "number" and ammo > 0
end

function TaskWeaponSwap:update(active, fighter, target, distance, context)
    context = context or {}
    if active ~= true or context.fighterActive == false then
        self:reset()
        return false
    end
    local now = self.clock()
    local current = fighter and fighter.EquippedItem
    local targetKey = target and (target.character or target.player or target.part)
    if self.pendingItem then
        if current == self.pendingItem then
            self.pendingItem = nil
            self.pendingAttempts = 0
            self.pendingFighter = nil
            self.pendingMobility = false
            self.pendingTargetKey = nil
        elseif
            self.pendingFighter ~= fighter
            or not self.pendingMobility and self.pendingTargetKey ~= targetKey
        then
            self:reset()
            return false
        elseif fighter and now >= self.pendingAt then
            local attempts = self.pendingAttempts
            self:reset()
            local retried = self:update(active, fighter, target, distance, context)
            if self.pendingItem then
                self.pendingAttempts = attempts + 1
                if self.pendingAttempts >= 6 then
                    self:reset()
                end
            end
            return retried
        else
            return true
        end
    end
    if now < self.nextAt or not fighter or type(fighter.EquipItem) ~= "function" then
        return false
    end

    local policy = self.weaponPolicy
    local targetHealth = target and target.health
    local currentCapability = policy.capabilities(current)
    local currentAmmo = policy.ammo(current)
    local currentDamage = policy.finishingDamage(current, target, distance)
    local currentCapacity = currentCapability.attack == "melee" and currentDamage
        or type(currentAmmo) == "number" and type(currentDamage) == "number" and currentAmmo * currentDamage
        or nil
    local maximumAmmo = current and current.Info and current.Info.MaxAmmo
    local lowMagazine = type(currentAmmo) == "number"
        and type(maximumAmmo) == "number"
        and currentAmmo <= math.max(2, math.floor(maximumAmmo * 0.3))
    local currentLethal = self:_ready(current, distance)
        and type(targetHealth) == "number"
        and type(currentDamage) == "number"
        and currentDamage >= targetHealth
    local currentCounters = context.counterActive == true
        and self.counterPolicy.shouldForceSpray(current, context.opponentItem)
    local needsMobility = context.mobilityNeedsDoubleJump == true
    local currentHasMobility = type(currentCapability.maxDoubleJumps) == "number"
        and currentCapability.maxDoubleJumps > 0
    if currentHasMobility and needsMobility then
        return false
    end
    if currentCounters or currentLethal and context.counterActive ~= true and not needsMobility then
        return false
    end

    local currentStalled = current == nil
        or reloading(current)
        or currentAmmo == 0
        or currentCapability.attack == "melee" and not policy.taskMeleeInRange(current, distance)
        or lowMagazine and type(targetHealth) == "number" and (type(currentCapacity) ~= "number" or currentCapacity < targetHealth)
        or current ~= nil and policy.triggerDamageReady(current, target, distance) == false

    local selected
    local selectedTier = 0
    local selectedValue = -math.huge
    local selectedSlot = math.huge
    local ambiguous = false
    for _, candidate in ipairs(candidates(fighter)) do
        local capability = policy.capabilities(candidate)
        local mobility = needsMobility
            and type(capability.maxDoubleJumps) == "number"
            and capability.maxDoubleJumps > 0
            and not reloading(candidate)
        local ready = self:_ready(candidate, distance)
        local damageReady = ready
            and policy.triggerDamageReady(candidate, target, distance) ~= false
        local counters = ready
            and context.counterActive == true
            and self.counterPolicy.shouldForceSpray(candidate, context.opponentItem)
        if candidate ~= current and (damageReady or mobility or counters) then
            local hitDamage = policy.finishingDamage(candidate, target, distance)
            local candidateAmmo = policy.ammo(candidate)
            local capacity = capability.attack == "melee" and hitDamage
                or type(candidateAmmo) == "number" and type(hitDamage) == "number" and candidateAmmo * hitDamage
                or nil
            local lethal = type(targetHealth) == "number"
                and type(hitDamage) == "number"
                and hitDamage >= targetHealth
            local tier = mobility and 4
                or counters and 3
                or lethal and 2
                or currentStalled and 1
                or 0
            local value = tier == 2 and hitDamage or capacity or hitDamage or 0
            local slot = SLOT_ORDER[candidate.Info.Class] or 5
            if
                tier > selectedTier
                or tier == selectedTier and value > selectedValue
                or tier == selectedTier and value == selectedValue and slot < selectedSlot
            then
                selected = tier > 0 and candidate or nil
                selectedTier = tier
                selectedValue = value
                selectedSlot = slot
                ambiguous = false
            elseif
                tier > 0
                and tier == selectedTier
                and value == selectedValue
                and slot == selectedSlot
            then
                ambiguous = true
            end
        end
    end
    if not selected or ambiguous then
        self.nextAt = now + 0.25
        return false
    end

    self.release()
    self.pendingItem = selected
    self.pendingAttempts = 1
    self.pendingAt = now + 0.12
    self.pendingFighter = fighter
    self.pendingMobility = selectedTier == 4
    self.pendingTargetKey = targetKey
    self.nextAt = self.pendingAt
    pcall(self.equip, fighter, selected)
    if fighter.EquippedItem == selected then
        self.pendingItem = nil
        self.pendingAttempts = 0
        self.pendingFighter = nil
        self.pendingMobility = false
        self.pendingTargetKey = nil
    end
    return true
end

return TaskWeaponSwap
