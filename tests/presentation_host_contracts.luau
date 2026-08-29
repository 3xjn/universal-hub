local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
Vector2 = roblox.Vector2

local expectedPresentations = {
    counterblox = "games/counterblox/Presentation",
    rivals = "games/rivals/Presentation",
    town = "games/town/Presentation",
}

local function recorder(capabilities)
    local calls = {}
    local available = {}
    for _, capability in ipairs(capabilities) do
        available[capability] = true
    end
    local host = {}
    function host:supports(name)
        return available[name] == true
    end
    for _, method in ipairs({
        "aim",
        "cosmetics",
        "option",
        "plotCopy",
        "rate",
        "section",
        "segmented",
        "slider",
    }) do
        host[method] = function(_, ...)
            local values = { method }
            for _, value in ipairs({ ... }) do
                if type(value) == "string" or type(value) == "number" then
                    table.insert(values, value)
                end
            end
            table.insert(calls, table.concat(values, ":"))
        end
    end
    return host, calls
end

local function mount(path, capabilities)
    local host, calls = recorder(capabilities)
    local presentation = require("../" .. path)
    assert(type(presentation) == "table" and type(presentation.mount) == "function")
    presentation.mount(host)
    return calls
end

local function assertSequence(actual, expected, label)
    assert(#actual == #expected, label .. " call count changed")
    for index, value in ipairs(expected) do
        assert(
            actual[index] == value,
            ("%s call %d changed: expected %q, got %q"):format(
                label,
                index,
                value,
                tostring(actual[index])
            )
        )
    end
end

local CounterbloxDefinition = require("../games/counterblox/Definition")
local RivalsDefinition = require("../games/rivals/Definition")
local TownDefinition = require("../games/town/Definition")
for id, definition in pairs({
    counterblox = CounterbloxDefinition,
    rivals = RivalsDefinition,
    town = TownDefinition,
}) do
    assert(definition.presentation == expectedPresentations[id])
    assert(table.find(definition.sources, definition.presentation))
    local presentationSource = fs.readFile(definition.presentation .. ".lua")
    for _, forbidden in ipairs({
        "Drawing",
        "DrawingImmediate",
        "Limn",
        "Canvas",
        "Element",
        "surface",
    }) do
        assert(
            not presentationSource:find(forbidden, 1, true),
            definition.presentation
                .. " must not access presentation runtime internals: "
                .. forbidden
        )
    end
end

assertSequence(mount(expectedPresentations.rivals, RivalsDefinition.features.capabilities), {
    "aim",
    "rate:aimSmoothness:Aim Smoothness",
    "rate:headshotRate:Headshot Rate",
    "rate:missRate:Miss Rate",
    "segmented:Visuals",
    "segmented:Combat",
    "section:Combat:trigger:Trigger Bot:64",
    "option:trigger:1:triggerBot:Trigger Bot",
    "slider:trigger:triggerDelay:Delay",
    "option:trigger:3:quickReload:Quick Reload",
    "option:trigger:4:skipDeflect:Katana Stop",
    "option:trigger:4:autoDeflect:Auto Katana",
    "option:trigger:5:alwaysScoped:Always Scoped",
    "section:Rage:rage:RAGE:70",
    "option:rage:1:teleportBehind:Warp",
    "option:rage:2:rapidFire:Rapid Fire",
    "slider:rage:fireRate:Fire Rate",
    "section:Movement:movement:MOVEMENT:70",
    "option:movement:1:bhop:Bunny Hop",
    "option:movement:2:infiniteJump:Infinite Jump",
    "option:movement:3:wallNoclip:Wall Noclip",
    "option:movement:4:redLightSafety:Red Light Safety",
    "section:Tools:taskFarming:TASK FARMING:70",
    "option:taskFarming:1:taskAutomationEnabled:Task Farming",
    "section:Tools:world:WORLD:70",
    "option:world:1:autoPickup:Auto Pickup",
    "section:Visuals:visuals:VISUALS:70:1",
    "option:visuals:1:boxes:Hitboxes",
    "option:visuals:1:chams:Chams",
    "option:visuals:2:chamsExcludeAccessories:Ignore Accessories:chams",
    "option:visuals:2:chamsPerPart:Part Highlights:chams",
    "option:visuals:3:names:Names",
    "option:visuals:3:health:Health",
    "option:visuals:4:weapon:Weapons",
    "option:visuals:20:showEnemies:Enemies:audience",
    "option:visuals:21:showTeammates:Allies:audience",
    "option:visuals:4:noFlash:No Flash",
    "option:visuals:5:noSmoke:No Smoke",
    "option:visuals:6:unlockAllSkins:Unlock All Cosmetics",
    "option:visuals:7:utilityEsp:Utility ESP",
    "cosmetics",
}, "RIVALS presentation")

assertSequence(
    mount(expectedPresentations.counterblox, CounterbloxDefinition.features.capabilities),
    {
        "aim",
        "rate:headshotRate:Headshot Rate",
        "rate:missRate:Miss Rate",
        "section:Combat:rage:AIM:64:2",
        "option:rage:1:silentAim:Silent Aim",
        "option:rage:1:wallbang:Wallbang:silentAim",
        "option:rage:2:rapidFire:Rapid Fire",
        "option:rage:3:triggerBot:Trigger Bot",
        "option:rage:3:noSpread:No Spread",
        "option:rage:4:noRecoil:No Recoil",
        "option:rage:4:noWeaponSlow:No Weapon Slow",
        "section:Combat:melee:MELEE:70:2",
        "option:melee:1:knifeAura:Knife Aura",
        "option:melee:1:microStep:Micro Step:knifeAura",
        "section:Movement:movement:MOVEMENT:70",
        "option:movement:1:spinBot:Spin Bot",
        "option:movement:1:bhop:Bunny Hop",
        "section:Visuals:visuals:VISUALS:70:1",
        "option:visuals:1:boxes:Hitboxes",
        "option:visuals:1:chams:Chams",
        "option:visuals:2:names:Names",
        "option:visuals:2:health:Health",
        "option:visuals:3:weapon:Weapons",
        "option:visuals:20:showEnemies:Enemies:audience",
        "option:visuals:21:showTeammates:Allies:audience",
        "option:visuals:4:bombTimer:Bomb Timer",
        "option:visuals:5:utilityEsp:Utility ESP",
        "cosmetics",
    },
    "Counterblox presentation"
)

local hostSource = fs.readFile("ui/PresentationHost.lua")
for _, forbidden in ipairs({
    "Drawing",
    "Limn",
    "Canvas",
    "Element",
    "surface",
    ":create(",
    "PLOT COPY",
    "Copy & Save",
    "COSMETICS",
    "cosmetics",
    "Town",
    "layout",
}) do
    assert(
        not hostSource:find(forbidden, 1, true),
        "PresentationHost must be a thin generic facade: " .. forbidden
    )
end
local _, hostLineCount = hostSource:gsub("\n", "\n")
assert(hostLineCount < 80, "PresentationHost must not hide presentation construction")
for _, path in ipairs({
    "ui/presentation/Runtime.lua",
    "ui/presentation/StandardPanels.lua",
    "ui/presentation/CosmeticsPanel.lua",
}) do
    local source = fs.readFile(path)
    for _, forbidden in ipairs({
        "Drawing",
        "DrawingImmediate",
        "Limn",
        "Canvas",
        "Element",
        "surface",
    }) do
        assert(
            not source:find(forbidden, 1, true),
            path .. " must stay above Limn internals: " .. forbidden
        )
    end
end
local standardPanelsSource = fs.readFile("ui/presentation/StandardPanels.lua")
assert(
    not standardPanelsSource:find("SECTION_PAGES", 1, true),
    "StandardPanels must not assign a game section to a page"
)
local townPresentationSource = fs.readFile("games/town/Presentation.lua")
assert(
    not townPresentationSource:find("host:aim()", 1, true),
    "Town must not mount unsupported aim controls"
)
assert(
    not townPresentationSource:find("host:cosmetics()", 1, true),
    "Town must not mount unsupported cosmetics controls"
)
for _, ownedContent in ipairs({
    "PLOT COPY",
    "Copy & Save",
    "No player plots",
    "Enter save name",
}) do
    assert(
        townPresentationSource:find(ownedContent, 1, true),
        "Town presentation must own its visible panel content: " .. ownedContent
    )
end
for _, action in ipairs({
    "cancelPlotCopy",
    "cleanupPlotCopyCheckpoint",
    "confirmPlotCopy",
    "copyPlot",
    "discardPlotCopy",
    "resumePlotCopy",
    "retryPlotCopyCleanup",
}) do
    assert(
        townPresentationSource:find(action, 1, true),
        "Town presentation must own its custom action: " .. action
    )
    assert(
        not hostSource:find('"' .. action .. '"', 1, true),
        "PresentationHost must not own Town action selection: " .. action
    )
end

local overlaySource = fs.readFile("ui/esp/DrawingRenderer.lua")
for _, forbidden in ipairs({
    "OPTION_GROUPS",
    "OPTION_LABELS",
    "OPTION_PARENTS",
    "RATE_CONTROLS",
    "PLOT COPY",
    "Copy & Save",
    "COSMETICS",
    "Auto Pickup",
    "Always Scoped",
    "Knife Aura",
    "No Weapon Slow",
}) do
    assert(
        not overlaySource:find(forbidden, 1, true),
        "Overlay must not own game presentation content: " .. forbidden
    )
end
assert(
    overlaySource:find(
        "context.presentationHost.mount(presentationRuntime, context.presentation)",
        1,
        true
    ),
    "Overlay must give PresentationHost only the generic presentation runtime"
)

local initSource = fs.readFile("init.lua")
assert(
    initSource:find("import(adapterDefinition.presentation)", 1, true),
    "Init must import only the selected definition's presentation"
)
for _, path in pairs(expectedPresentations) do
    assert(
        not initSource:find('"' .. path .. '"', 1, true),
        "Init must not hand-maintain presentation imports"
    )
end

local PresentationHost = require("../ui/PresentationHost")
local PresentationRuntime = require("../ui/presentation/Runtime")
local lifecycle = {}
local MinimalPresentation = {}
function MinimalPresentation.mount(host)
    host:register({
        destroy = function()
            table.insert(lifecycle, "destroy")
        end,
        layout = function(_, _x, _y, cursor)
            table.insert(lifecycle, "layout")
            return cursor + 20
        end,
        render = function()
            table.insert(lifecycle, "render")
        end,
        setVisible = function()
            table.insert(lifecycle, "visible")
        end,
    })
end
local unavailablePart = {
    new = function()
        error("Minimal presentation must not construct optional control parts")
    end,
}
for _ = 1, 2 do
    local controls = {
        panel = {},
        panelBorder = {},
        panelShadow = {},
    }
    local state = {
        menuVisible = true,
        settings = {},
    }
    local runtime = PresentationRuntime.new({
        activeSliderVisuals = {},
        capabilities = {},
        cosmeticsSupported = false,
        context = {
            store = {
                Get = function()
                    return state
                end,
                Patch = function(_, patch)
                    return patch
                end,
            },
        },
        controls = controls,
        interactive = function(node)
            return node
        end,
        node = function()
            error("Minimal presentation must not construct hidden controls")
        end,
        refreshVisibility = function() end,
        requestLayout = function() end,
        setControlColor = function() end,
        text = function()
            error("Minimal presentation must not construct hidden labels")
        end,
        theme = {
            tokens = {
                layout = {
                    contentTopWithTabs = 112,
                    contentTopWithoutTabs = 72,
                    initialHeight = 596,
                    shellWidth = 390,
                },
            },
        },
    }, {
        cosmetics = unavailablePart,
        standard = unavailablePart,
    })
    local mounted = PresentationHost.mount(runtime, MinimalPresentation)
    assert(mounted == runtime)
    local minimalHeight = runtime:layout(10, 20)
    assert(minimalHeight == 104, "Unexpected minimal shell height: " .. tostring(minimalHeight))
    runtime:render(state)
    runtime:setVisible(true)
    runtime:setMousePosition(Vector2.zero)
    assert(next(controls.rates) == nil)
    assert(next(controls.sections) == nil)
    assert(next(controls.options) == nil)
    assert(next(controls.cosmetics) == nil)
    runtime:destroy()
    runtime:destroy()
end
assertSequence(lifecycle, {
    "layout",
    "render",
    "visible",
    "destroy",
    "layout",
    "render",
    "visible",
    "destroy",
}, "Minimal presentation lifecycle")

print("presentation-host-contracts-ok")
