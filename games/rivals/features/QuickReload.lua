local QuickReload = {}
QuickReload.__index = QuickReload

local RELOADS = {
    { "ReloadLength", "ReloadActionTimestamp" },
    { "EmptyReloadLength", "EmptyReloadActionTimestamp" },
}

function QuickReload.new()
    return setmetatable({
        item = nil,
        originals = {},
    }, QuickReload)
end

function QuickReload:restore()
    local info = self.item and self.item.Info
    if type(info) == "table" then
        for key, value in pairs(self.originals) do
            info[key] = value
        end
    end
    self.item = nil
    table.clear(self.originals)
end

function QuickReload:update(settings, item)
    local info = item and item.Info
    if settings.quickReload ~= true or type(info) ~= "table" then
        self:restore()
        return
    end
    if self.item ~= item then
        self:restore()
        self.item = item
    end

    for _, keys in ipairs(RELOADS) do
        local lengthKey, actionKey = keys[1], keys[2]
        local length = self.originals[lengthKey] or info[lengthKey]
        local actionAt = info[actionKey]
        if
            type(length) == "number"
            and type(actionAt) == "number"
            and actionAt > 0
            and length > actionAt
        then
            self.originals[lengthKey] = length
            info[lengthKey] = actionAt
        end
    end
end

function QuickReload:stop()
    self:restore()
end

return QuickReload
