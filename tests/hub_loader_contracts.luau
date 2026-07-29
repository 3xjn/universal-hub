local fs = require("@lune/fs")
local source = fs.readFile("hub.lua")
local environment = {}
local requested = {}

function getgenv()
    return environment
end

game = {}
function game:HttpGet(url, noCache)
    assert(noCache == true, "Hub loader must bypass the executor HTTP cache")
    table.insert(requested, url)

    if url == "https://raw.githubusercontent.com/3xjn/universal-hub/main/vendor/Limn.lua" then
        return [[return { new = function() end }]]
    end

    if url == "https://raw.githubusercontent.com/3xjn/hydroxide/dev/modules/Targeting.lua" then
        return [[return { nearestPlayer = function() end }]]
    end

    if url == "https://raw.githubusercontent.com/3xjn/universal-hub/main/init.lua" then
        return [[
assert(type(getgenv().UniversalHubConfig.Limn.new) == "function", "Hub loader must provide Limn to init")
assert(type(getgenv().oh.targeting.nearestPlayer) == "function", "Hub loader must provide targeting to init")
return "hub-loader-ok"
]]
    end

    return [[return {}]]
end

environment.UniversalHubConfig = {
    SourceBaseUrl = "https://raw.githubusercontent.com/3xjn/universal-hub/main/",
}

local chunk, compileError = loadstring(source, "hub.lua")
local result = assert(chunk, compileError)()
assert(result == "hub-loader-ok")
assert(
    #requested == 21,
    "Hub loader must fetch packaged Limn, targeting, init.lua, and its eighteen module source files"
)
print("hub-loader-contracts-ok")
