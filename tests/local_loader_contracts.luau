local fs = require("@lune/fs")
local source = fs.readFile("local.lua")
local exited = false
local loaded = {}
local queuedTeleportSource
local environment = {
    queue_on_teleport = function(source)
        queuedTeleportSource = source
    end,
    UniversalHubConfig = {
        Import = function()
            error("stale remote import must not run")
        end,
    },
    oh = {
        drawing = {},
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

function readfile(path)
    table.insert(loaded, path)
    if path == "hydroxide/local/init.lua" then
        return [[
local previous = getgenv().oh
if previous and previous.Exit then
    previous.Exit()
end
getgenv().oh = {
    drawing = {},
    targeting = {
        observeCharacter = function() end,
    },
}
]]
    end
    assert(path == "universal-hub/local/init.lua")
    return [[
assert(getgenv().UniversalHubConfig.Import == nil, "Local loader must clear a stale remote Import seam")
assert(
    type(getgenv().oh.targeting.observeCharacter) == "function",
    "Local loader must refresh Hydroxide helpers before loading a game adapter"
)
return "local-loader-ok"
]]
end

local chunk, compileError = loadstring(source, "local.lua")
local result = assert(chunk, compileError)()
assert(result == "local-loader-ok")
assert(exited == true, "Refreshing Hydroxide must let its initializer clean up the previous session")
assert(loaded[1] == "hydroxide/local/init.lua" and loaded[2] == "universal-hub/local/init.lua")
assert(
    type(queuedTeleportSource) == "string"
        and string.find(queuedTeleportSource, "universal%-hub/local/local%.lua") ~= nil,
    "Local loader must queue itself so game-to-game teleports refresh the selected adapter"
)
print("local-loader-contracts-ok")
