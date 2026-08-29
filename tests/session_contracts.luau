local Store = require("../modules/Store")
local Session = require("../modules/Session")

local previousStops = 0
local legacySession = {
    stop = function()
        previousStops += 1
    end,
}
local unrelatedHydroxideExits = 0
local environment = {
    UniversalHubSession = legacySession,
    oh = {
        Exit = function()
            unrelatedHydroxideExits += 1
        end,
        Resources = {
            legacySession,
        },
    },
}
assert(type(Session.stopPrevious) == "function", "Session must expose staged previous-session cleanup")
local stoppedPrevious = Session.stopPrevious(environment)
assert(stoppedPrevious == legacySession and previousStops == 1)
assert(environment.UniversalHubSession == nil)
assert(#environment.oh.Resources == 0, "Exact legacy Universal Hub resource must be detached")
assert(unrelatedHydroxideExits == 0, "Matching legacy cleanup must never exit the Hydroxide application")

local unrelatedEnvironment = {
    oh = {
        Exit = function()
            unrelatedHydroxideExits += 1
        end,
        Resources = {
            {
                stop = function()
                    error("Unrelated Hydroxide resources must not stop")
                end,
            },
        },
    },
}
assert(Session.stopPrevious(unrelatedEnvironment) == nil)
assert(unrelatedHydroxideExits == 0, "An unrelated oh namespace must remain untouched")
local failedPrevious = {
    stop = function()
        error("simulated legacy cleanup failure")
    end,
}
local failedEnvironment = { UniversalHubSession = failedPrevious }
assert(Session.stopPrevious(failedEnvironment) == failedPrevious)
assert(failedEnvironment.UniversalHubSession == nil, "Failed legacy cleanup must not block replacement")

local adapterStops = 0
local inputStops = 0
local overlayStops = 0
local cleanupOrder = {}
local savedSettings = {}
local store = Store.new({
    cosmeticsOpen = false,
    menuVisible = true,
    settings = {
        aimAssistStrength = 60,
        aimSmoothness = 0,
        cameraFov = 100,
        enabled = false,
        fov = 100,
        headshotRate = 0,
        minimumFov = 40,
        maximumFov = 200,
        missRate = 0,
        teleportBehind = false,
        worldRenderer = "limn",
    },
})
local session = Session.new({
    adapter = {
        stop = function()
            adapterStops += 1
            table.insert(cleanupOrder, "adapter")
        end,
    },
    environment = environment,
    inputCapture = {
        Destroy = function()
            inputStops += 1
            table.insert(cleanupOrder, "input")
        end,
    },
    overlay = {
        destroy = function()
            overlayStops += 1
            table.insert(cleanupOrder, "overlay")
        end,
    },
    settingsChanged = function(settings)
        table.insert(savedSettings, settings)
    end,
    store = store,
})

assert(previousStops == 1 and environment.UniversalHubSession == session)
session:setOption("enabled", true)
session:setRate("aimSmoothness", 42)
session:setRate("headshotRate", 74.6)
session:setRate("missRate", -10)
session:setSetting("worldRenderer", "native")
session:toggleMenu()
assert(store:Get().settings.enabled == true)
assert(store:Get().settings.worldRenderer == "native", "Typed settings must preserve non-boolean values")
assert(
    store:Get().settings.aimSmoothness == 42
        and store:Get().settings.headshotRate == 75
        and store:Get().settings.missRate == 0,
    "Accuracy rates must round and clamp to percentages"
)
assert(store:Get().menuVisible == false, "Menu visibility must toggle through reactive state")
session:setMenuVisible(true)
assert(store:Get().menuVisible == true)
session:setCosmeticsOpen(true)
assert(store:Get().cosmeticsOpen == true, "Cosmetics disclosure must be reactive UI state")
assert(#savedSettings == 5, "Only persistent settings changes should request a config save")
session:setRate("aimAssistStrength", 85, false)
assert(
    store:Get().settings.aimAssistStrength == 85 and #savedSettings == 5,
    "Assist Strength must update live without persisting until slider release"
)
session:setRate("aimSmoothness", 55, false)
assert(
    store:Get().settings.aimSmoothness == 55 and #savedSettings == 5,
    "Live slider updates must not write configuration before pointer release"
)
session:setRate("aimSmoothness", 55, true)
assert(#savedSettings == 6, "Slider release must persist its final value exactly once")
session:setOption("teleportBehind", true, false)
assert(
    store:Get().settings.teleportBehind == true and #savedSettings == 6,
    "Ephemeral options must update live without requesting a config save"
)
session:setOption("enabled", false)
assert(#savedSettings == 7, "Existing setOption callers must continue to persist by default")

session:Add(function()
    table.insert(cleanupOrder, "first")
end)
session:Add(function()
    table.insert(cleanupOrder, "second")
end)
session:stop()
session:stop()

assert(
    cleanupOrder[1] == "second"
        and cleanupOrder[2] == "first"
        and cleanupOrder[3] == "adapter"
        and cleanupOrder[4] == "overlay"
        and cleanupOrder[5] == "input",
    "Session resources must unwind in reverse construction order"
)
assert(
    adapterStops == 1 and overlayStops == 1 and inputStops == 1,
    "Session teardown must be idempotent"
)
assert(environment.UniversalHubSession == nil)
print("session-contracts-ok")
