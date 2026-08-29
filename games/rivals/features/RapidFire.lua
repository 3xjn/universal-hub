local RapidFire = {}
RapidFire.__index = RapidFire

function RapidFire.new(weaponPolicy)
    return setmetatable({
        item = nil,
        cooldownKey = nil,
        originalCooldown = nil,
        weaponPolicy = weaponPolicy,
    }, RapidFire)
end

function RapidFire:restore()
    if self.item and self.cooldownKey and self.originalCooldown then
        self.item.Info[self.cooldownKey] = self.originalCooldown
    end
    self.item = nil
    self.cooldownKey = nil
    self.originalCooldown = nil
end

function RapidFire:update(settings, item, canFire, fireHeld, fire)
    local info = item and item.Info
    local cooldownKey = type(info) == "table"
            and type(info.ShootCooldown) == "number"
            and "ShootCooldown"
        or type(info) == "table" and type(info.AttackCooldown) == "number" and "AttackCooldown"
        or nil
    local cooldown = cooldownKey and info[cooldownKey]
    if settings.rapidFire ~= true or type(cooldown) ~= "number" or cooldown <= 0 then
        self:restore()
        return
    end

    if self.item ~= item then
        self:restore()
        self.item = item
        self.cooldownKey = cooldownKey
        self.originalCooldown = cooldown
    end

    local rate =
        math.clamp(type(settings.fireRate) == "number" and settings.fireRate or 200, 100, 1000)
    info[self.cooldownKey] = self.originalCooldown * 100 / rate

    if
        canFire
        and fireHeld
        and not self.weaponPolicy.holdToFire(item)
        and type(fire) == "function"
    then
        fire()
    end
end

function RapidFire:stop()
    self:restore()
end

return RapidFire
