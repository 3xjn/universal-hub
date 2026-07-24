local fs = require("@lune/fs")
local source = fs.readFile("hub.lua")
local environment = {}
local requested = {}

function getgenv()
    return environment
end

game = {}
function game:HttpGet(url)
    table.insert(requested, url)

    if url == "https://raw.githubusercontent.com/3xjn/hydroxide/dev/init.lua" then
        return [[
local environment = getgenv()
assert(environment.HydroxideConfig ~= nil, "Universal Hub must configure Hydroxide before loading it")
assert(environment.HydroxideConfig.Owner == "3xjn", "Hydroxide owner must match the downloaded source")
assert(environment.HydroxideConfig.Branch == "dev", "Hydroxide source and module branches must match")
assert(environment.HydroxideConfig.Web == true, "The remote hub must keep Hydroxide imports on the web")
environment.oh = {
    drawing = {},
    targeting = {},
}
]]
    end

    if url == "https://raw.githubusercontent.com/3xjn/universal-hub/main/init.lua" then
        return [[return "hub-loader-ok"]]
    end

    return [[return {}]]
end

environment.UniversalHubConfig = {
    SourceBaseUrl = "https://raw.githubusercontent.com/3xjn/universal-hub/main/",
}

local chunk, compileError = loadstring(source, "hub.lua")
local result = assert(chunk, compileError)()
assert(result == "hub-loader-ok")
assert(#requested == 10, "Hub loader must fetch Hydroxide and its nine source files")
print("hub-loader-contracts-ok")
