local Registry = {}
Registry.__index = Registry

local function matchManifest(manifest, context)
    local score = 0

    for _, placeId in ipairs(manifest.placeIds or {}) do
        if placeId == context.placeId then
            score = math.max(score, 200)
        end
    end

    for _, gameId in ipairs(manifest.gameIds or {}) do
        if gameId == context.gameId then
            score = math.max(score, 100)
        end
    end

    return score
end

function Registry.new()
    return setmetatable({
        adapters = {},
    }, Registry)
end

function Registry:Register(adapter)
    assert(type(adapter) == "table", "Hub adapter must be a table")
    assert(type(adapter.id) == "string", "Hub adapter requires an id")
    assert(type(adapter.new) == "function", "Hub adapter requires new(context)")

    self.adapters[adapter.id] = adapter
    return adapter
end

function Registry:Resolve(context)
    local selected
    local selectedScore = 0

    for _, adapter in pairs(self.adapters) do
        local score
        if type(adapter.match) == "function" then
            score = adapter.match(context)
            if score == true then
                score = 1
            elseif score == false or score == nil then
                score = 0
            end
        else
            score = matchManifest(adapter.manifest or {}, context)
        end

        if type(score) == "number" and score > selectedScore then
            selected = adapter
            selectedScore = score
        end
    end

    return selected, selectedScore
end

function Registry:List()
    local adapters = {}
    for _, adapter in pairs(self.adapters) do
        table.insert(adapters, adapter)
    end
    table.sort(adapters, function(left, right)
        return left.id < right.id
    end)
    return adapters
end

return Registry
