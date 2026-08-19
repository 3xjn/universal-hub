local FastReload = {}
FastReload.__index = FastReload

function FastReload.new()
    return setmetatable({
        animations = {},
        reloadTimes = {},
    }, FastReload)
end

function FastReload:update(enabled, weapon)
    local stats = weapon and weapon:FindFirstChild("Stats")
    local reloadTime = stats and stats:FindFirstChild("ReloadTime")
    local handle = weapon and weapon:FindFirstChild("Handle")
    local sound = handle and handle:FindFirstChild("Reload")

    if enabled and weapon and reloadTime then
        if not self.reloadTimes[reloadTime] then
            self.reloadTimes[reloadTime] = reloadTime.Value
        end
        reloadTime.Value = math.min(self.reloadTimes[reloadTime], 0.1)
        if sound then
            if not self.animations[sound] then
                self.animations[sound] = sound.PlaybackSpeed
            end
            sound.PlaybackSpeed = math.max(self.animations[sound], 10)
        end
        return
    end

    self:restoreWeapon(weapon)
end

function FastReload:restoreWeapon(weapon)
    local stats = weapon and weapon:FindFirstChild("Stats")
    local reloadTime = stats and stats:FindFirstChild("ReloadTime")
    if reloadTime and self.reloadTimes[reloadTime] then
        reloadTime.Value = self.reloadTimes[reloadTime]
        self.reloadTimes[reloadTime] = nil
    end
    local handle = weapon and weapon:FindFirstChild("Handle")
    local sound = handle and handle:FindFirstChild("Reload")
    if sound and self.animations[sound] then
        sound.PlaybackSpeed = self.animations[sound]
        self.animations[sound] = nil
    end
end

function FastReload:stop()
    for reloadTime, original in pairs(self.reloadTimes) do
        if reloadTime.Parent then reloadTime.Value = original end
    end
    for sound, original in pairs(self.animations) do
        if sound.Parent then sound.PlaybackSpeed = original end
    end
    table.clear(self.reloadTimes)
    table.clear(self.animations)
end

return FastReload
