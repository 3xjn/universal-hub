local environment = assert(getgenv, "<UH> ~ Your executor is not supported")()
local configuration = environment.UniversalHubConfig or {}
local sourceBaseUrl = assert(
    configuration.SourceBaseUrl,
    "Set UniversalHubConfig.SourceBaseUrl to the raw universal-hub source root"
)
type HttpGame = typeof(game) & {
    HttpGet: (self: typeof(game), url: string, noCache: boolean?) -> string,
}
local httpGame = game :: HttpGame

if not environment.oh or not environment.oh.drawing or not environment.oh.targeting then
    local hydroxideConfiguration = environment.HydroxideConfig or {}
    hydroxideConfiguration.Owner = configuration.HydroxideOwner or "3xjn"
    hydroxideConfiguration.Branch = configuration.HydroxideBranch or "dev"
    hydroxideConfiguration.Web = true
    environment.HydroxideConfig = hydroxideConfiguration

    local hydroxideUrl = configuration.HydroxideUrl
        or "https://raw.githubusercontent.com/3xjn/hydroxide/dev/init.lua"
    local hydroxideSource = httpGame:HttpGet(hydroxideUrl, true)
    local hydroxideChunk, hydroxideError = loadstring(hydroxideSource, "hydroxide/init.lua")
    assert(hydroxideChunk, hydroxideError)()
end

local sources = {}
for _, path in ipairs({
    "modules/Store.lua",
    "modules/Config.lua",
    "modules/InputCapture.lua",
    "modules/MenuToggle.lua",
    "modules/Registry.lua",
    "modules/Session.lua",
    "modules/Overlay.lua",
    "games/town/Canonical.lua",
    "games/town/CheckpointStore.lua",
    "games/town/CopyEngine.lua",
    "games/town/CopyPlan.lua",
    "games/town/ExecutionPlan.lua",
    "games/Counterblox.lua",
    "games/Town.lua",
    "games/rivals/Adapter.lua",
    "games/rivals/Targeting.lua",
    "games/rivals/ProjectileAim.lua",
    "games/rivals/ShotPresentation.lua",
    "games/rivals/ScopedAccuracy.lua",
    "games/rivals/WeaponPolicy.lua",
    "games/rivals/Effects.lua",
    "games/rivals/Movement.lua",
    "games/rivals/CombatState.lua",
}) do
    sources[path] = httpGame:HttpGet(sourceBaseUrl .. path, true)
end
environment.UniversalHubConfig = configuration
configuration.Import = function(path)
    local file = path .. ".lua"
    local chunk, compileError = loadstring(assert(sources[file], "Unknown hub module: " .. path), file)
    return assert(chunk, compileError)()
end

local initSource = httpGame:HttpGet(sourceBaseUrl .. "init.lua", true)
local initChunk, initError = loadstring(initSource, "init.lua")
return assert(initChunk, initError)()
