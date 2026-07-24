local Store = {}
Store.__index = Store

local function copy(source)
    local result = {}
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            result[key] = copy(value)
        else
            result[key] = value
        end
    end
    return result
end

local function merge(target, patch)
    for key, value in pairs(patch) do
        if type(value) == "table" and type(target[key]) == "table" then
            merge(target[key], value)
        else
            target[key] = value
        end
    end
end

function Store.new(initial)
    return setmetatable({
        listeners = {},
        state = copy(initial),
        stopped = false,
    }, Store)
end

function Store:Get()
    return self.state
end

function Store:Patch(patch)
    if self.stopped then
        return self.state
    end

    merge(self.state, patch)
    for listener in pairs(self.listeners) do
        listener(self.state)
    end
    return self.state
end

function Store:Subscribe(listener, emitCurrent)
    assert(type(listener) == "function", "Store subscriber must be a function")
    if self.stopped then
        return function() end
    end

    self.listeners[listener] = true
    if emitCurrent ~= false then
        listener(self.state)
    end

    local connected = true
    return function()
        if connected then
            connected = false
            self.listeners[listener] = nil
        end
    end
end

function Store:Destroy()
    if self.stopped then
        return
    end
    self.stopped = true
    table.clear(self.listeners)
end

return Store
