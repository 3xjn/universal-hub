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

local limnUrl = configuration.LimnSourceUrl or sourceBaseUrl .. "vendor/Limn.lua"
local limnSource = httpGame:HttpGet(limnUrl, true)
local limnChunk, limnError = loadstring(limnSource, "vendor/Limn.lua")
local Limn = assert(limnChunk, limnError)()
assert(type(Limn.new) == "function", "Universal Hub requires a valid Limn runtime artifact")
configuration.Limn = Limn

local helpers = type(environment.oh) == "table" and environment.oh or {}
if not helpers.targeting or type(helpers.targeting.nearestPlayer) ~= "function" then
    local targetingUrl = configuration.HydroxideTargetingUrl
        or "https://raw.githubusercontent.com/3xjn/hydroxide/dev/modules/Targeting.lua"
    local targetingSource = httpGame:HttpGet(targetingUrl, true)
    local targetingChunk, targetingError =
        loadstring(targetingSource, "hydroxide/modules/Targeting.lua")
    local targeting = assert(targetingChunk, targetingError)()
    assert(
        type(targeting) == "table" and type(targeting.nearestPlayer) == "function",
        "Universal Hub requires the Hydroxide targeting helper"
    )
    helpers.targeting = targeting
    environment.oh = helpers
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
