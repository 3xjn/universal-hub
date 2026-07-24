local Store = require("../modules/Store")
local Session = require("../modules/Session")

local previousStops = 0
local environment = {
    UniversalHubSession = {
        stop = function()
            previousStops += 1
        end,
    },
}
local adapterStops = 0
local overlayStops = 0
local cleanupOrder = {}
local savedSettings = {}
local store = Store.new({
    cosmeticsOpen = false,
    menuVisible = true,
    settings = {
        enabled = false,
        fov = 100,
        minimumFov = 40,
        maximumFov = 200,
    },
})
local session = Session.new({
    adapter = {
        stop = function()
            adapterStops += 1
        end,
    },
    environment = environment,
    overlay = {
        destroy = function()
            overlayStops += 1
        end,
    },
    settingsChanged = function(settings)
        table.insert(savedSettings, settings)
    end,
    store = store,
})

assert(previousStops == 1 and environment.UniversalHubSession == session)
session:setOption("enabled", true)
session:setFov(999)
session:toggleMenu()
assert(store:Get().settings.enabled == true)
assert(store:Get().settings.fov == 200, "FOV must clamp to the configured maximum")
assert(store:Get().menuVisible == false, "Menu visibility must toggle through reactive state")
session:setMenuVisible(true)
assert(store:Get().menuVisible == true)
session:setCosmeticsOpen(true)
assert(store:Get().cosmeticsOpen == true, "Cosmetics disclosure must be reactive UI state")
assert(#savedSettings == 2, "Only persistent settings changes should request a config save")

session:Add(function()
    table.insert(cleanupOrder, "first")
end)
session:Add(function()
    table.insert(cleanupOrder, "second")
end)
session:stop()
session:stop()

assert(cleanupOrder[1] == "second" and cleanupOrder[2] == "first", "Cleanup must run in reverse order")
assert(adapterStops == 1 and overlayStops == 1, "Session teardown must be idempotent")
assert(environment.UniversalHubSession == nil)
print("session-contracts-ok")
