local AutoReload = {}
AutoReload.__index = AutoReload

function AutoReload.new()
    return setmetatable({ requested = false }, AutoReload)
end

function AutoReload:update(enabled, reload, weapon)
    local stats = weapon and weapon:FindFirstChild("Stats")
    local clip = stats and stats:FindFirstChild("ClipSize")
    if enabled and reload and clip and clip.Value <= 0 then
        if not self.requested then
            self.requested = true
            task.spawn(function()
                pcall(reload)
                self.requested = false
            end)
        end
    elseif not clip or clip.Value > 0 then
        self.requested = false
    end
end

return AutoReload
