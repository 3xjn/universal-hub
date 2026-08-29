local ItemPolicy = require("../libraries/ItemPolicy")
local TaskCounterPolicy = {}
TaskCounterPolicy.__index = TaskCounterPolicy

function TaskCounterPolicy.isDefensiveItem(item)
    return ItemPolicy.isDeflector(item) or ItemPolicy.isAbsorber(item)
end

function TaskCounterPolicy.hasShieldOrKatana(items)
    for key, value in pairs(items or {}) do
        local item = type(value) == "table" and value or type(key) == "table" and key or nil
        if TaskCounterPolicy.isDefensiveItem(item) then
            return true
        end
    end
    return false
end

function TaskCounterPolicy.shouldSelectSpray(items)
    return TaskCounterPolicy.hasShieldOrKatana(items)
end

function TaskCounterPolicy.shouldForceSpray(item, opponentEquippedItem)
    return ItemPolicy.capabilities(item).bypassesDeflection
        and TaskCounterPolicy.isDefensiveItem(opponentEquippedItem)
end

function TaskCounterPolicy.new(options)
    return setmetatable({
        clock = options and options.clock or os.clock,
        candidate = false,
        candidateAt = 0,
        active = false,
        targetKey = nil,
    }, TaskCounterPolicy)
end

function TaskCounterPolicy:reset()
    self.candidate = false
    self.candidateAt = 0
    self.active = false
    self.targetKey = nil
end

function TaskCounterPolicy:update(equippedItem, targetKey)
    local now = self.clock()
    if targetKey ~= self.targetKey then
        self.candidate = false
        self.candidateAt = now
        self.active = false
        self.targetKey = targetKey
    end
    local candidate = TaskCounterPolicy.isDefensiveItem(equippedItem)
    if candidate ~= self.candidate then
        self.candidate = candidate
        self.candidateAt = now
    end
    local hold = candidate and 1.25 or 0.75
    if candidate ~= self.active and now - self.candidateAt >= hold then
        self.active = candidate
    end
    return self.active
end

return TaskCounterPolicy
