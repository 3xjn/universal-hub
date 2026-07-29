local environment = assert(getgenv, "<UH> ~ Your executor is not supported")()
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

local configuration

local function loadTargeting()
    local helpers = type(environment.oh) == "table" and environment.oh or {}
    if helpers.targeting and type(helpers.targeting.nearestPlayer) == "function" then
        return
    end

    local targetingChunk, targetingError = loadstring(
        readfile(configuration.HydroxideRoot .. "/modules/Targeting.lua"),
        "hydroxide/modules/Targeting.lua"
    )
    local targeting = assert(targetingChunk, targetingError)()
    assert(
        type(targeting) == "table" and type(targeting.nearestPlayer) == "function",
        "Universal Hub requires the Hydroxide targeting helper"
    )
    helpers.targeting = targeting
    environment.oh = helpers
end

local function loadHub()
    loadTargeting()
    if not ownsFlight() then
        return
    end

    local hubChunk, hubError = loadstring(readfile(configuration.LocalRoot .. "/init.lua"), "universal-hub/init.lua")
    return assert(hubChunk, hubError)()
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
    configuration = environment.UniversalHubConfig or {}
    configuration.LocalRoot = configuration.LocalRoot or "universal-hub/local"
    configuration.HydroxideRoot = configuration.HydroxideRoot or "hydroxide/local"
    configuration.LimnPath = configuration.LimnPath or "limn/dist/Limn.lua"
    configuration.Import = nil
    environment.UniversalHubConfig = configuration

    local synapse = environment.syn
    local queue = type(environment.queue_on_teleport) == "function"
            and environment.queue_on_teleport
        or type(environment.queueonteleport) == "function" and environment.queueonteleport
        or type(synapse) == "table" and type(synapse.queue_on_teleport) == "function"
            and synapse.queue_on_teleport
    if queue then
        queue(([[
loadstring(readfile(%q), "universal-hub/local.lua")()
]]):format(configuration.LocalRoot .. "/local.lua"))
    end

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
