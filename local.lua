local environment = assert(getgenv, "<UH> ~ Your executor is not supported")()
local configuration = environment.UniversalHubConfig or {}

configuration.LocalRoot = configuration.LocalRoot or "universal-hub/local"
configuration.HydroxideRoot = configuration.HydroxideRoot or "hydroxide/local"
configuration.Import = nil
environment.UniversalHubConfig = configuration

local hydroxideConfiguration = environment.HydroxideConfig or {}
hydroxideConfiguration.Web = false
hydroxideConfiguration.LocalRoot = configuration.HydroxideRoot
hydroxideConfiguration.Branch = hydroxideConfiguration.Branch or "dev"
environment.HydroxideConfig = hydroxideConfiguration

local synapse = environment.syn
local queue = type(environment.queue_on_teleport) == "function"
        and environment.queue_on_teleport
    or type(environment.queueonteleport) == "function" and environment.queueonteleport
    or type(synapse) == "table" and type(synapse.queue_on_teleport) == "function"
        and synapse.queue_on_teleport
if queue then
    queue(([[
loadstring(readfile(%q), "universal-hub/local.lua")()
]]):format(configuration.LocalRoot .. "/local.lua"))
end

local hydroxideChunk, hydroxideError =
    loadstring(readfile(configuration.HydroxideRoot .. "/init.lua"), "hydroxide/init.lua")
assert(hydroxideChunk, hydroxideError)()

local hubChunk, hubError = loadstring(readfile(configuration.LocalRoot .. "/init.lua"), "universal-hub/init.lua")
return assert(hubChunk, hubError)()
