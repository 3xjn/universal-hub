local environment = assert(getgenv, "<UH> ~ Your executor is not supported")()
local configuration = environment.UniversalHubConfig or {}
local sourceRoot = configuration.SourceBaseUrl
    or "https://raw.githubusercontent.com/3xjn/universal-hub/refs/heads/main/"
local localRoot = configuration.LocalRoot
local localLoaderPath = type(localRoot) == "string" and localRoot .. "/local.lua" or nil
local localLoaderSource
if localLoaderPath and type(readfile) == "function" then
    local succeeded, source = pcall(readfile, localLoaderPath)
    if succeeded then
        localLoaderSource = source
    end
end
type HttpGame = typeof(game) & {
    HttpGet: (self: typeof(game), url: string) -> string,
}
local httpGame = game :: HttpGame

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

    if localLoaderSource then
        queue(([[loadstring(readfile(%q), "universal-hub/local.lua")()]]):format(localLoaderPath))
        return
    end

    queue(([[
local environment = getgenv()
environment.UniversalHubConfig = environment.UniversalHubConfig or {}
environment.UniversalHubConfig.SourceBaseUrl = %q
loadstring(game:HttpGet(%q), "universal-hub/loader.lua")()
]]):format(sourceRoot, sourceRoot .. "loader.lua"))
end

local function loadHub()
    if localLoaderSource then
        local chunk, compileError = loadstring(localLoaderSource, "universal-hub/local.lua")
        return assert(chunk, compileError)()
    end

    configuration.SourceBaseUrl = sourceRoot
    environment.UniversalHubConfig = configuration

    local source = httpGame:HttpGet(sourceRoot .. "hub.lua")
    local chunk, compileError = loadstring(source, "universal-hub/hub.lua")
    return assert(chunk, compileError)()
end

queueNextPlace()
if not game:IsLoaded() then
    task.spawn(function()
        game.Loaded:Wait()
        return loadHub()
    end)
    return
end

return loadHub()
