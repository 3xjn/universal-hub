local fs = require("@lune/fs")

local bootstrap = fs.readFile("site/beta/bootstrap.lua")
local readme = fs.readFile("README.md")
local betaOneLiner = [[loadstring(game:HttpGet("https://3xjn.github.io/universal-hub/beta/bootstrap.lua?v="..tick()))()]]

assert(
    string.find(bootstrap, "refs/heads/beta/loader.lua", 1, true) ~= nil,
    "Beta bootstrap must fetch the beta loader"
)
assert(
    string.find(bootstrap, "refs/heads/main/loader.lua", 1, true) == nil,
    "Beta bootstrap must not fetch the main loader"
)
assert(string.find(bootstrap, "assert(request", 1, true) ~= nil, "Beta bootstrap must require request")
assert(string.find(bootstrap, "game:HttpGet", 1, true) == nil, "Beta bootstrap must bypass executor HttpGet caching")
assert(
    string.find(bootstrap, "UniversalHubConfig = nil", 1, true) ~= nil,
    "Beta bootstrap must clear leftover tester configuration"
)
assert(
    string.find(bootstrap, "UniversalHubLoaderFlight = nil", 1, true) ~= nil,
    "Beta bootstrap must clear leftover loader flight state"
)
assert(string.find(readme, betaOneLiner, 1, true) ~= nil, "README must document the Pages beta one-liner")
assert(
    string.find(readme, "raw.githubusercontent.com/3xjn/universal-hub/refs/heads/beta/loader.lua", 1, true) == nil
        and string.find(readme, "loadstring(request({", 1, true) == nil,
    "README must not document the old raw-GitHub request beta snippet"
)

print("beta-bootstrap-contracts-ok")
