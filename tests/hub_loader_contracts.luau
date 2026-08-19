local fs = require("@lune/fs")
local source = fs.readFile("hub.lua")
local oldHydroxideCommit = "8e2d4a84ddb4b7ef901af170966a43b3b35fbaa7"
local hydroxideCommit = "cb1e184c27ffc7639b26cefd55e7f25978b9dcf7"
local sourceBaseUrl = "https://raw.githubusercontent.com/3xjn/universal-hub/main/"
local Catalog = require("../games/Catalog")
local Sources = require("../modules/Sources")
local expectedHubPaths = {
    "init.lua",
}
for _, path in ipairs(Sources.Core()) do
    table.insert(expectedHubPaths, path .. ".lua")
end
local firstDeclaredSource
for _, definitionPath in ipairs(Catalog) do
    table.insert(expectedHubPaths, definitionPath .. ".lua")
    local definition = require("../" .. definitionPath)
    for _, modulePath in ipairs(definition.sources) do
        local file = modulePath .. ".lua"
        firstDeclaredSource = firstDeclaredSource or file
        table.insert(expectedHubPaths, file)
        assert(
            not source:find('"' .. file .. '"', 1, true),
            "Packaged game sources must come from definitions, not hub.lua: " .. file
        )
    end
end
assert(
    source:find("Registry.Validate", 1, true),
    "Packaged bootstrap must validate definitions before fetching their declared sources"
)
assert(
    source:find("vendor/Limn.lua", 1, true)
        and source:find(hydroxideCommit, 1, true)
        and source:find("modules/Helpers.lua", 1, true)
        and source:find("modules/Closure.lua", 1, true)
        and source:find("modules/Lifecycle.lua", 1, true)
        and source:find("modules/Targeting.lua", 1, true),
    "Packaged bootstrap must pin Limn and the stable Hydroxide helper source set"
)
assert(
    not source:find(oldHydroxideCommit, 1, true),
    "Packaged bootstrap must not retain the pre-raycastIgnore Hydroxide pin"
)
assert(
    not source:find("/hydroxide/dev/init.lua", 1, true)
        and not source:find("environment.HydroxideConfig", 1, true),
    "Packaged bootstrap must not execute or configure the Hydroxide application"
)
local environment = {
    oh = {
        unrelated = true,
    },
}
environment.OriginalOh = environment.oh
local requested = {}
local invalidDefinitionPath

function getgenv()
    return environment
end

game = {
    GameId = 7633926880,
    PlaceId = 114234929420007,
}
function game:HttpGet(url, noCache)
    assert(noCache == true, "Hub loader must bypass the executor HTTP cache")
    table.insert(requested, url)
    environment.RequestCount = #requested

    if url == sourceBaseUrl .. "vendor/Limn.lua" then
        return [[return { new = function() end }]]
    end
    if url == sourceBaseUrl .. "ui/dist/Menu.lua" then
        return [[return { mountUniversalHubMenu = function() end }]]
    end

    local hydroxideRoot =
        "https://raw.githubusercontent.com/3xjn/hydroxide/"
        .. hydroxideCommit
        .. "/"
    if url == hydroxideRoot .. "modules/Helpers.lua" then
        return [[
return {
    load = function(options)
        local files = {
            closure = "modules/Closure",
            lifecycle = "modules/Lifecycle",
            targeting = "modules/Targeting",
        }
        local namespace = {}
        for _, name in ipairs(options.modules or {}) do
            namespace[name] = options.import(files[name])
        end
        return namespace
    end,
}
]]
    end
    if url == hydroxideRoot .. "modules/Targeting.lua" then
        return [[return { nearestPlayer = function() end }]]
    end
    if url == hydroxideRoot .. "modules/Closure.lua"
        or url == hydroxideRoot .. "modules/Lifecycle.lua"
    then
        return [[return {}]]
    end

    if url:sub(1, #sourceBaseUrl) == sourceBaseUrl then
        local path = url:sub(#sourceBaseUrl + 1)
        if path == invalidDefinitionPath then
            return [[return {}]]
        end
        if path ~= "init.lua" and path ~= "modules/Store.lua" and fs.isFile(path) then
            return fs.readFile(path)
        end
    end

    if url == sourceBaseUrl .. "init.lua" then
        return [[
local configuration = getgenv().UniversalHubConfig
assert(type(configuration.Limn.new) == "function", "Hub loader must stage vendored Limn")
assert(type(configuration.Import) == "function", "Hub loader must install its own importer")
local first = configuration.Import("modules/Store")
local second = configuration.Import("modules/Store")
assert(first == second, "Hub importer must cache Universal Hub modules")
local requestCount = getgenv().RequestCount
configuration.Import("games/Counterblox")
assert(
    getgenv().RequestCount == requestCount,
    "Selected imports must execute already-prefetched bytes without lazy requests"
)
assert(
    not pcall(configuration.Import, "games/rivals/Adapter")
        and not pcall(configuration.Import, "games/town/Presentation"),
    "Selected runtime importer must reject sources owned only by other definitions"
)
assert(not pcall(configuration.Import, "../modules/Store"), "Hub importer must validate paths")
local helpers = configuration.HydroxideHelpers.load({
    import = configuration.HydroxideImport,
    modules = { "targeting" },
})
assert(type(helpers.targeting.nearestPlayer) == "function")
assert(
    not pcall(configuration.HydroxideImport, "modules/Store"),
    "Hydroxide importer must not resolve Universal Hub modules"
)
assert(getgenv().oh == getgenv().OriginalOh, "Hub loader must not replace environment.oh")
return "hub-loader-ok"
]]
    end

    if url == sourceBaseUrl .. "modules/Store.lua" then
        return [[
local environment = getgenv()
environment.StoreExecutions = (environment.StoreExecutions or 0) + 1
return {}
]]
    end

    return [[return {}]]
end

environment.UniversalHubConfig = {
    SourceBaseUrl = sourceBaseUrl,
}

local chunk, compileError = loadstring(source, "hub.lua")
local result = assert(chunk, compileError)()
assert(result == "hub-loader-ok")
assert(environment.StoreExecutions == 1, "Hub importer must execute a fetched module once")
local expectedUrls = {
    [sourceBaseUrl .. "vendor/Limn.lua"] = true,
    [sourceBaseUrl .. "ui/dist/Menu.lua"] = true,
    [sourceBaseUrl .. "changelog.json"] = true,
}
local hydroxideRoot =
    "https://raw.githubusercontent.com/3xjn/hydroxide/"
    .. hydroxideCommit
    .. "/"
for _, path in ipairs({
    "modules/Helpers.lua",
    "modules/Closure.lua",
    "modules/Lifecycle.lua",
    "modules/Targeting.lua",
}) do
    expectedUrls[hydroxideRoot .. path] = true
end
for _, path in ipairs(expectedHubPaths) do
    expectedUrls[sourceBaseUrl .. path] = true
end

local seen = {}
local requestedAt = {}
for index, url in ipairs(requested) do
    assert(not seen[url], "Hub loader must fetch each pinned source exactly once: " .. url)
    assert(expectedUrls[url], "Hub loader fetched an undeclared source: " .. url)
    seen[url] = true
    requestedAt[url] = index
    assert(not url:find("/hydroxide/dev/init.lua", 1, true))
    assert(not url:find("/modules/Drawing", 1, true))
    assert(not url:find("/modules/DrawingControls", 1, true))
    assert(not url:find("/modules/Remote.lua", 1, true))
    assert(not url:find(oldHydroxideCommit, 1, true))
end
for url in pairs(expectedUrls) do
    assert(seen[url], "Hub loader did not fetch declared source: " .. url)
end
local hydroxideRequestCount = 0
for url in pairs(seen) do
    if url:find("https://raw.githubusercontent.com/3xjn/hydroxide/", 1, true) == 1 then
        hydroxideRequestCount += 1
        assert(
            url:find(hydroxideRoot, 1, true) == 1,
            "Every Hydroxide helper request must use the immutable raycastIgnore pin"
        )
    end
end
assert(hydroxideRequestCount == 4, "Packaged bootstrap must fetch only Helpers and three stable leaves")
local lastDefinitionAt = 0
for _, path in ipairs(Catalog) do
    lastDefinitionAt = math.max(lastDefinitionAt, assert(requestedAt[sourceBaseUrl .. path .. ".lua"]))
end
assert(
    lastDefinitionAt < assert(requestedAt[sourceBaseUrl .. firstDeclaredSource]),
    "Catalog definitions must be fetched before their declared game sources"
)

invalidDefinitionPath = "games/rivals/Definition.lua"
requested = {}
environment.UniversalHubConfig = {
    SourceBaseUrl = sourceBaseUrl,
}
local invalidSucceeded, invalidMessage = pcall(function()
    local invalidChunk, invalidCompileError = loadstring(source, "hub-invalid-definition.lua")
    assert(invalidChunk, invalidCompileError)()
end)
assert(
    not invalidSucceeded and tostring(invalidMessage):find("non-empty id", 1, true),
    "Packaged bootstrap must reject an invalid catalog definition"
)
for _, url in ipairs(requested) do
    for _, definitionPath in ipairs(Catalog) do
        local definition = require("../" .. definitionPath)
        for _, modulePath in ipairs(definition.sources) do
            assert(
                url ~= sourceBaseUrl .. modulePath .. ".lua",
                "Packaged bootstrap must validate every definition before fetching game sources"
            )
        end
    end
end
invalidDefinitionPath = nil

local originalHttpGet = game.HttpGet
function game:HttpGet(url, noCache)
    local result = originalHttpGet(self, url, noCache)
    if url == sourceBaseUrl .. "games/rivals/Definition.lua" then
        return result:gsub(
            'sources = {',
            'sources = {\n        "games/Town",',
            1
        )
    end
    return result
end
requested = {}
environment.UniversalHubConfig = {
    SourceBaseUrl = sourceBaseUrl,
}
local duplicateSucceeded, duplicateMessage = pcall(function()
    local duplicateChunk, duplicateCompileError = loadstring(source, "hub-duplicate-owner.lua")
    assert(duplicateChunk, duplicateCompileError)()
end)
assert(
    not duplicateSucceeded
        and tostring(duplicateMessage):find(
            "Source path owned by multiple game definitions: games/Town (rivals, town)",
            1,
            true
        ),
    "Packaged bootstrap must reject cross-definition source ownership deterministically"
)
for _, url in ipairs(requested) do
    assert(
        url ~= sourceBaseUrl .. "games/Town.lua"
            and url ~= sourceBaseUrl .. "games/rivals/Adapter.lua"
            and url ~= sourceBaseUrl .. "games/Town.lua",
        "Source ownership must validate globally before any game source fetch"
    )
end
print("hub-loader-contracts-ok")
