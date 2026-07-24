local environment = assert(getgenv, "<UH> ~ Your executor is not supported")()
local configuration = environment.UniversalHubConfig or {}

configuration.LocalRoot = configuration.LocalRoot or "universal-hub/local"
configuration.HydroxideRoot = configuration.HydroxideRoot or "hydroxide/local"
environment.UniversalHubConfig = configuration

local oh = environment.oh
if not oh or not oh.drawing or not oh.targeting then
    local hydroxideConfiguration = environment.HydroxideConfig or {}
    hydroxideConfiguration.Web = false
    hydroxideConfiguration.LocalRoot = configuration.HydroxideRoot
    hydroxideConfiguration.Branch = hydroxideConfiguration.Branch or "dev"
    environment.HydroxideConfig = hydroxideConfiguration

    local hydroxideChunk, hydroxideError =
        loadstring(readfile(configuration.HydroxideRoot .. "/init.lua"), "hydroxide/init.lua")
    assert(hydroxideChunk, hydroxideError)()
end

local hubChunk, hubError = loadstring(readfile(configuration.LocalRoot .. "/init.lua"), "universal-hub/init.lua")
return assert(hubChunk, hubError)()
