local RapidFire = {}
RapidFire.__index = RapidFire

function RapidFire.new()
    return setmetatable({
        weapons = {},
    }, RapidFire)
end

function RapidFire:update(settings, weapon)
    local stats = weapon and weapon:FindFirstChild("Stats")
    local fireRate = stats and stats:FindFirstChild("FireRate")
    local gunType = stats and stats:FindFirstChild("GunType")

    if settings.rapidFire == true and fireRate and gunType then
        if not self.weapons[weapon] then
            self.weapons[weapon] = {
                fireRate = fireRate.Value,
                gunType = gunType.Value,
            }
        end
        local delay = math.clamp(
            type(settings.rapidFireDelay) == "number" and settings.rapidFireDelay or 40,
            10,
            200
        ) / 1000
        fireRate.Value = math.min(self.weapons[weapon].fireRate, delay)
        gunType.Value = "Auto"
        return
    end

    self:restore(weapon)
end

function RapidFire:restore(weapon)
    local original = self.weapons[weapon]
    if not original then
        return
    end

    local stats = weapon.Parent and weapon:FindFirstChild("Stats")
    local fireRate = stats and stats:FindFirstChild("FireRate")
    local gunType = stats and stats:FindFirstChild("GunType")
    if fireRate then
        fireRate.Value = original.fireRate
    end
    if gunType then
        gunType.Value = original.gunType
    end
    self.weapons[weapon] = nil
end

function RapidFire:stop()
    local weapons = {}
    for weapon in pairs(self.weapons) do
        table.insert(weapons, weapon)
    end
    for _, weapon in ipairs(weapons) do
        self:restore(weapon)
    end
end

return RapidFire

