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

local function omitKeys(settings, omittedKeys)
    if type(settings) ~= "table" then
        return settings
    end
    local result = copy(settings)
    for key in pairs(omittedKeys or {}) do
        result[key] = nil
    end
    return result
end

local function prettifyJson(source)
    if type(source) ~= "string" or not source:match("^%s*[%[{]") then
        return source
    end

    local result = {}
    local depth = 0
    local inString = false
    local escaped = false

    for index = 1, #source do
        local character = source:sub(index, index)
        if inString then
            table.insert(result, character)
            if escaped then
                escaped = false
            elseif character == "\\" then
                escaped = true
            elseif character == '"' then
                inString = false
            end
        elseif character == '"' then
            inString = true
            table.insert(result, character)
        elseif character == "{" or character == "[" then
            depth += 1
            table.insert(result, character .. "\n" .. string.rep("    ", depth))
        elseif character == "}" or character == "]" then
            depth -= 1
            table.insert(result, "\n" .. string.rep("    ", depth) .. character)
        elseif character == "," then
            table.insert(result, ",\n" .. string.rep("    ", depth))
        elseif character == ":" then
            table.insert(result, ": ")
        elseif not character:match("%s") then
            table.insert(result, character)
        end
    end

    return table.concat(result)
end

function Config.new(options)
    assert(options and options.path, "Config requires a workspace path")
    return setmetatable({
        decode = options.decode,
        encode = options.encode,
        isFile = options.isFile,
        omittedKeys = options.omittedKeys or {},
        path = options.path,
        readFile = options.readFile,
        writeFile = options.writeFile,
    }, Config)
end

function Config:load(defaults)
    local result = copy(defaults)
    if
        type(self.isFile) ~= "function"
        or type(self.readFile) ~= "function"
        or type(self.decode) ~= "function"
        or not self.isFile(self.path)
    then
        return result
    end

    local success, decoded = pcall(self.decode, self.readFile(self.path))
    if success then
        if type(decoded) == "table" then
            if
                decoded.taskAutomationEnabled == nil
                and type(decoded.taskAutomationPaused) == "boolean"
            then
                decoded.taskAutomationEnabled = not decoded.taskAutomationPaused
            end
            decoded.taskAutomationPaused = nil
            if decoded.cameraFov == nil then
                decoded.cameraFov = decoded.fov
            end
            if decoded.shotFov == nil then
                decoded.shotFov = decoded.fov
            end
            if decoded.cameraFullScreenAim == nil then
                decoded.cameraFullScreenAim = decoded.fullScreenAim
            end
            if decoded.shotFullScreenAim == nil then
                decoded.shotFullScreenAim = decoded.fullScreenAim
            end
            if decoded.cameraTargetMode == nil then
                decoded.cameraTargetMode = decoded.cameraFullScreenAim == true and "fullscreen"
                    or "radius"
            end
            if decoded.shotTargetMode == nil then
                decoded.shotTargetMode = decoded.shotFullScreenAim == true and "fullscreen"
                    or "radius"
            end
        end
        mergeKnown(result, omitKeys(decoded, self.omittedKeys))
    end
    return result
end

function Config:save(settings)
    if type(self.writeFile) ~= "function" or type(self.encode) ~= "function" then
        return false
    end

    local encoded = self.encode(omitKeys(settings, self.omittedKeys))
    local success = pcall(self.writeFile, self.path, prettifyJson(encoded))
    return success
end

return Config
