local environment = assert(getgenv, "<UH> ~ Your executor is not supported")()
local configuration = environment.UniversalHubConfig or {}
local sourceBaseUrl = assert(
    configuration.SourceBaseUrl,
    "Set UniversalHubConfig.SourceBaseUrl to the raw universal-hub source root"
)
type HttpGame = typeof(game) & {
    HttpGet: (self: typeof(game), url: string) -> string,
}
local httpGame = game :: HttpGame

if not environment.oh or not environment.oh.drawing or not environment.oh.targeting then
    local hydroxideUrl = configuration.HydroxideUrl
        or "https://raw.githubusercontent.com/3xjn/hydroxide/dev/init.lua"
    local hydroxideSource = httpGame:HttpGet(hydroxideUrl)
    local hydroxideChunk, hydroxideError = loadstring(hydroxideSource, "hydroxide/init.lua")
    assert(hydroxideChunk, hydroxideError)()
end

local sources = {}
for _, path in ipairs({
    "modules/Store.lua",
    "modules/Config.lua",
    "modules/InputCapture.lua",
    "modules/Registry.lua",
    "modules/Session.lua",
    "modules/Overlay.lua",
    "games/Counterblox.lua",
}) do
    sources[path] = httpGame:HttpGet(sourceBaseUrl .. path)
end
environment.UniversalHubConfig = configuration
configuration.Import = function(path)
    local file = path .. ".lua"
    local chunk, compileError = loadstring(assert(sources[file], "Unknown hub module: " .. path), file)
    return assert(chunk, compileError)()
end

local initSource = httpGame:HttpGet(sourceBaseUrl .. "init.lua")
local initChunk, initError = loadstring(initSource, "init.lua")
return assert(initChunk, initError)()
