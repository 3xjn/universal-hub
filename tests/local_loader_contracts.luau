local fs = require("@lune/fs")
local source = fs.readFile("local.lua")
local exited = false
local loaded = {}
local queuedTeleportSource
local queueCount = 0
local pendingBootstrap
local spawnCount = 0
local waitedForLoad = false
local gameLoaded = false
local duplicateDuringLoadResult
local attemptedDuplicateDuringLoad = false
local failTargeting = false
local environment = {
    queue_on_teleport = function(source)
        queueCount += 1
        queuedTeleportSource = source
    end,
    UniversalHubConfig = {
        Import = function()
            error("stale remote import must not run")
        end,
    },
    oh = {
        targeting = {
            stale = true,
        },
        Exit = function()
            exited = true
        end,
    },
}

function getgenv()
    return environment
end

task = {
    spawn = function(callback)
        spawnCount += 1
        pendingBootstrap = callback
    end,
}
game = {
    JobId = "local-job",
    Loaded = {
        Wait = function()
            waitedForLoad = true
            gameLoaded = true
        end,
    },
}
function game:IsLoaded()
    return gameLoaded
end

function readfile(path)
    table.insert(loaded, path)
    if path == "hydroxide/local/init.lua" then
        return [[getgenv().oh = { core = true }]]
    end
    if path == "hydroxide/local/modules/Targeting.lua" then
        if failTargeting then
            error("intentional targeting failure")
        end
        if not attemptedDuplicateDuringLoad then
            attemptedDuplicateDuringLoad = true
            local duplicateChunk, duplicateCompileError = loadstring(source, "local.lua")
            duplicateDuringLoadResult = assert(duplicateChunk, duplicateCompileError)()
        end
        return [[
return {
    nearestPlayer = function() end,
    observeCharacter = function() end,
}
]]
    end
    assert(path == "universal-hub/local/init.lua")
    return [[
assert(getgenv().UniversalHubConfig.Import == nil, "Local loader must clear a stale remote Import seam")
assert(
    getgenv().UniversalHubConfig.LimnPath == "limn/dist/Limn.lua",
    "Local loader must default to Limn's published build artifact"
)
assert(
    type(getgenv().oh.targeting.nearestPlayer) == "function",
    "Local loader must initialize generic targeting before loading a targeting-dependent adapter"
)
return "local-loader-ok"
]]
end

local chunk, compileError = loadstring(source, "local.lua")
local result = assert(chunk, compileError)()
assert(result == nil, "Early local loader execution must return before Roblox finishes loading")
assert(#loaded == 0, "Early local loader execution must not initialize Hydroxide or the hub")
assert(type(pendingBootstrap) == "function", "Early local loader execution must schedule a deferred bootstrap")
local duplicateEarlyChunk, duplicateEarlyCompileError = loadstring(source, "local.lua")
local duplicateEarlyResult = assert(duplicateEarlyChunk, duplicateEarlyCompileError)()
assert(duplicateEarlyResult == nil, "A duplicate early local bootstrap in the same job must coalesce")
assert(spawnCount == 1, "A duplicate early local bootstrap must not schedule a second deferred task")
assert(queueCount == 1, "A duplicate early local bootstrap must queue teleport code once")
assert(
    type(queuedTeleportSource) == "string"
        and string.find(queuedTeleportSource, "universal%-hub/local/local%.lua") ~= nil,
    "Local loader must queue itself so game-to-game teleports refresh the selected adapter"
)
local deferredResult = pendingBootstrap()
assert(deferredResult == "local-loader-ok")
assert(waitedForLoad, "Local loader must yield to Roblox startup when launched from autoexec")
assert(exited == false, "Loading generic targeting must not replace or exit an existing Hydroxide session")
assert(
    loaded[1] == "hydroxide/local/modules/Targeting.lua"
        and loaded[2] == "universal-hub/local/init.lua",
    "Local bootstrap must load only generic targeting before Universal Hub"
)
assert(#loaded == 2, "A duplicate local bootstrap must not initialize targeting or the hub twice")
assert(duplicateDuringLoadResult == nil, "A duplicate local bootstrap during targeting init must coalesce")

waitedForLoad = false
pendingBootstrap = nil
game.Loaded.Wait = function()
    error("Local loader must not wait again after Roblox is already loaded")
end
task.spawn = function()
    error("Local loader must not defer after Roblox is already loaded")
end
local immediateChunk, immediateCompileError = loadstring(source, "local.lua")
local immediateResult = assert(immediateChunk, immediateCompileError)()
assert(immediateResult == "local-loader-ok")
assert(not waitedForLoad, "Manual execution in a loaded game must start immediately")
assert(queueCount == 2, "Manual reexecution after a completed flight must start a fresh bootstrap")

game.JobId = "local-error-job"
environment.oh = {}
failTargeting = true
local errorChunk, errorCompileError = loadstring(source, "local.lua")
assert(not pcall(assert(errorChunk, errorCompileError)), "A failed local flight must surface its initialization error")
failTargeting = false
local retryChunk, retryCompileError = loadstring(source, "local.lua")
local retryResult = assert(retryChunk, retryCompileError)()
assert(retryResult == "local-loader-ok", "A failed local flight must release ownership for a retry")

print("local-loader-contracts-ok")
