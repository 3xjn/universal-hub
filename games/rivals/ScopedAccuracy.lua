local ScopedAccuracy = {}
ScopedAccuracy.__index = ScopedAccuracy

local function eligibleItem(item)
    local info = item and item.Info
    return type(info) == "table"
        and type(info.AimScopePercent) == "number"
        and info.AimScopePercent > 0
        and type(item.IsFullyAiming) == "function"
end

function ScopedAccuracy.new(options)
    assert(options and options.getFighter, "RIVALS Scoped Accuracy requires a fighter getter")
    assert(options.hookFunction, "RIVALS Scoped Accuracy requires hookfunction")
    assert(options.isEnabled, "RIVALS Scoped Accuracy requires an enabled predicate")
    assert(options.restoreFunction, "RIVALS Scoped Accuracy requires restorefunction")

    return setmetatable({
        getFighter = options.getFighter,
        hookFunction = options.hookFunction,
        hookTarget = nil,
        isEnabled = options.isEnabled,
        restoreFunction = options.restoreFunction,
        stopped = false,
    }, ScopedAccuracy)
end

function ScopedAccuracy:_restoreHook()
    if not self.hookTarget then
        return
    end
    self.restoreFunction(self.hookTarget)
    self.hookTarget = nil
end

function ScopedAccuracy:refreshHook()
    if self.stopped then
        return
    end

    local fighter = self.getFighter()
    local item = fighter and fighter.EquippedItem
    local target = eligibleItem(item) and item.IsFullyAiming or nil
    if target == self.hookTarget then
        return
    end

    self:_restoreHook()
    if not target then
        return
    end

    self.hookTarget = target
    local original
    original = self.hookFunction(target, function(itemSelf, ...)
        local currentFighter = self.getFighter()
        if not self.stopped
            and self.isEnabled()
            and currentFighter
            and itemSelf == currentFighter.EquippedItem
            and eligibleItem(itemSelf)
        then
            return true
        end
        return original(itemSelf, ...)
    end)
end

function ScopedAccuracy:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    self:_restoreHook()
end

return ScopedAccuracy
