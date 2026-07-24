local environment = assert(getgenv, "<UH> ~ Your executor is not supported")()
local configuration = environment.UniversalHubConfig or {}
local sourceRoot = configuration.SourceBaseUrl
    or "https://raw.githubusercontent.com/3xjn/universal-hub/refs/heads/main/"
type HttpGame = typeof(game) & {
    HttpGet: (self: typeof(game), url: string) -> string,
}
local httpGame = game :: HttpGame

configuration.SourceBaseUrl = sourceRoot
environment.UniversalHubConfig = configuration

local source = httpGame:HttpGet(sourceRoot .. "hub.lua")
local chunk, compileError = loadstring(source, "universal-hub/hub.lua")
return assert(chunk, compileError)()
