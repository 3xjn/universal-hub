local environment = assert(getgenv, "<UH> ~ Your executor is not supported")()
local officialSourceRoot = "https://raw.githubusercontent.com/3xjn/universal-hub/refs/heads/main/"
local sourceRoot = officialSourceRoot
local configuration = {
    SourceBaseUrl = sourceRoot,
}
type HttpGame = typeof(game) & {
    HttpGet: (self: typeof(game), url: string, noCache: boolean?) -> string,
}
local httpGame = game :: HttpGame

local jobId = game.JobId
local activeFlight = environment.UniversalHubLoaderFlight
if type(activeFlight) == "table" and activeFlight.jobId == jobId then
    return
end

local owner = {}
environment.UniversalHubLoaderFlight = {
    jobId = jobId,
    owner = owner,
}

local function ownsFlight()
    local current = environment.UniversalHubLoaderFlight
    return type(current) == "table" and current.owner == owner
end

local function releaseFlight()
    if ownsFlight() then
        environment.UniversalHubLoaderFlight = nil
    end
end

local function queueNextPlace()
    local synapse = environment.syn
    local queue = type(environment.queue_on_teleport) == "function"
            and environment.queue_on_teleport
        or type(environment.queueonteleport) == "function" and environment.queueonteleport
        or type(synapse) == "table" and type(synapse.queue_on_teleport) == "function"
            and synapse.queue_on_teleport
    if not queue then
        return
    end

    if sourceRoot ~= officialSourceRoot then
        return
    end

    queue(([[
loadstring(game:HttpGet(%q, true), "universal-hub/loader.lua")()
]]):format(sourceRoot .. "loader.lua"))
end

local function loadHub()
    environment.UniversalHubConfig = configuration

    local source = httpGame:HttpGet(sourceRoot .. "hub.lua", true)
    if not ownsFlight() then
        return
    end
    local chunk, compileError = loadstring(source, "universal-hub/hub.lua")
    return assert(chunk, compileError)()
end

local function completeBootstrap()
    if not ownsFlight() then
        return
    end

    local succeeded, result = pcall(loadHub)
    releaseFlight()
    if not succeeded then
        error(result, 0)
    end
    return result
end

local function startBootstrap()
    queueNextPlace()
    if not game:IsLoaded() then
        task.spawn(function()
            local succeeded, result = pcall(function()
                game.Loaded:Wait()
                return completeBootstrap()
            end)
            if not succeeded then
                releaseFlight()
                error(result, 0)
            end
            return result
        end)
        return
    end

    return completeBootstrap()
end

local succeeded, result = pcall(startBootstrap)
if not succeeded then
    releaseFlight()
    error(result, 0)
end
return result
