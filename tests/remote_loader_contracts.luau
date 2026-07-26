local fs = require("@lune/fs")
local source = fs.readFile("loader.lua")
local queuedTeleportSource
local environment = {
    queue_on_teleport = function(source)
        queuedTeleportSource = source
    end,
}
local requestedUrl
local loaded = false
local waitedForLoad = false
local pendingBootstrap

function getgenv()
    return environment
end

task = {
    spawn = function(callback)
        pendingBootstrap = callback
    end,
}
game = {
    Loaded = {
        Wait = function()
            waitedForLoad = true
            loaded = true
        end,
    },
}
function game:IsLoaded()
    return loaded
end
function game:HttpGet(url)
    assert(loaded, "Remote loader must not start network bootstrap before Roblox finishes loading")
    requestedUrl = url
    return [[return "remote-loader-ok"]]
end

local chunk, compileError = loadstring(source, "loader.lua")
local result = assert(chunk, compileError)()
assert(result == nil, "Early autoexec must return immediately instead of blocking game startup")
assert(requestedUrl == nil, "Early autoexec must not bootstrap before Roblox finishes loading")
assert(type(pendingBootstrap) == "function", "Early autoexec must schedule a deferred bootstrap")
assert(
    type(queuedTeleportSource) == "string"
        and string.find(queuedTeleportSource, "universal%-hub/loader%.lua") ~= nil
        and string.find(
            queuedTeleportSource,
            "https://raw%.githubusercontent%.com/3xjn/universal%-hub/refs/heads/main/"
        ) ~= nil,
    "Remote loader must queue itself so game-to-game teleports refresh the selected adapter"
)
local deferredResult = pendingBootstrap()
assert(deferredResult == "remote-loader-ok")
assert(waitedForLoad, "Remote loader must yield to Roblox startup when launched from autoexec")
assert(
    requestedUrl == "https://raw.githubusercontent.com/3xjn/universal-hub/refs/heads/main/hub.lua",
    "Remote loader must use GitHub's canonical branch-ref URL"
)

waitedForLoad = false
pendingBootstrap = nil
game.Loaded.Wait = function()
    error("Remote loader must not wait again after Roblox is already loaded")
end
task.spawn = function()
    error("Remote loader must not defer after Roblox is already loaded")
end
local immediateChunk, immediateCompileError = loadstring(source, "loader.lua")
local immediateResult = assert(immediateChunk, immediateCompileError)()
assert(immediateResult == "remote-loader-ok")
assert(not waitedForLoad, "Manual execution in a loaded game must start immediately")

environment.UniversalHubConfig = {
    LocalRoot = "universal-hub/local",
}
requestedUrl = nil
queuedTeleportSource = nil
function readfile(path)
    assert(path == "universal-hub/local/local.lua")
    return [[return "local-loader-from-remote-entry-ok"]]
end
local localChunk, localCompileError = loadstring(source, "loader.lua")
local localResult = assert(localChunk, localCompileError)()
assert(localResult == "local-loader-from-remote-entry-ok")
assert(requestedUrl == nil, "An explicitly configured local version must not fall back to GitHub")
assert(
    type(queuedTeleportSource) == "string"
        and string.find(queuedTeleportSource, "universal%-hub/local/local%.lua") ~= nil,
    "A local version entered through loader.lua must queue the local version for the next place"
)

environment.UniversalHubConfig = {
    SourceBaseUrl = "https://example.invalid/custom/",
}
readfile = nil
requestedUrl = nil
queuedTeleportSource = nil
local customChunk, customCompileError = loadstring(source, "loader.lua")
local customResult = assert(customChunk, customCompileError)()
assert(customResult == "remote-loader-ok")
assert(
    requestedUrl == "https://example.invalid/custom/hub.lua",
    "An explicit custom source may be used for the current session"
)
assert(
    queuedTeleportSource == nil,
    "A custom remote source must not become persistent cross-teleport code execution"
)

print("remote-loader-contracts-ok")
