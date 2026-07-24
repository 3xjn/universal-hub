local fs = require("@lune/fs")
local source = fs.readFile("loader.lua")
local environment = {}
local requestedUrl

function getgenv()
    return environment
end

game = {}
function game:HttpGet(url)
    requestedUrl = url
    return [[return "remote-loader-ok"]]
end

local chunk, compileError = loadstring(source, "loader.lua")
local result = assert(chunk, compileError)()
assert(result == "remote-loader-ok")
assert(
    requestedUrl == "https://raw.githubusercontent.com/3xjn/universal-hub/refs/heads/main/hub.lua",
    "Remote loader must use GitHub's canonical branch-ref URL"
)
print("remote-loader-contracts-ok")
