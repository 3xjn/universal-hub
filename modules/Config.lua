local Config = {}
Config.__index = Config

local function copy(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}
    for key, child in pairs(value) do
        result[key] = copy(child)
    end
    return result
end

local function mergeKnown(target, source)
    if type(source) ~= "table" then
        return target
    end

    for key, existing in pairs(target) do
        local value = source[key]
        if value ~= nil then
            if type(existing) == "table" and type(value) == "table" then
                if next(existing) == nil then
                    target[key] = copy(value)
                else
                    mergeKnown(existing, value)
                end
            elseif existing == false and type(value) == "table" then
                target[key] = copy(value)
            elseif type(existing) == type(value) then
                target[key] = value
            end
        end
    end
    return target
end

function Config.new(options)
    assert(options and options.path, "Config requires a workspace path")
    return setmetatable({
        decode = options.decode,
        encode = options.encode,
        isFile = options.isFile,
        path = options.path,
        readFile = options.readFile,
        writeFile = options.writeFile,
    }, Config)
end

function Config:load(defaults)
    local result = copy(defaults)
    if type(self.isFile) ~= "function"
        or type(self.readFile) ~= "function"
        or type(self.decode) ~= "function"
        or not self.isFile(self.path)
    then
        return result
    end

    local success, decoded = pcall(self.decode, self.readFile(self.path))
    if success then
        mergeKnown(result, decoded)
    end
    return result
end

function Config:save(settings)
    if type(self.writeFile) ~= "function" or type(self.encode) ~= "function" then
        return false
    end

    local success = pcall(self.writeFile, self.path, self.encode(copy(settings)))
    return success
end

return Config
