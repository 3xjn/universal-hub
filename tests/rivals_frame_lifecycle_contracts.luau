local fs = require("@lune/fs")
local source = fs.readFile("games/rivals/Adapter.lua")
local function contains(needle, message)
    assert(string.find(source, needle, 1, true), message or ("missing: " .. needle))
end
contains("local function frameWorkEnabled(state)")
contains("settingsSubscription = store:Subscribe(reconcileFrameLifecycle)")
contains('TaskFarmRuntime = require("./tasks/TaskFarmRuntime")')
contains('PracticeTaskDriver = require("./tasks/PracticeTaskDriver")')
contains("ShootingRangeController:Enter()")
contains("fighter:GetItem(name)")
contains("fighter:EquipItem(item)")
contains("MechanicsController:Slide()")
contains("taskFarmRuntime:isCombatActive() == true")
contains("onActivityChanged = taskActivityChanged")
contains(
    'playerGui:FindFirstChild("LoadingScreen")',
    "RIVALS must wait for native controller bootstrap before requiring match controllers"
)
contains(
    "reconcileFrameLifecycle(store:Get())",
    "frame lifecycle must initialize without waiting for a patch"
)
contains(
    'settings.worldRenderer ~= "native" or state.menuVisible ~= false',
    "hidden Native ESP must remain event-driven"
)
contains("disconnectFrame()")
contains("effects:renderTrajectory(nil)")
contains("runTriggerBot(nil, false)")
local firstObservation = assert(
    string.find(source, "observations, visualObservations = observationRuntime:update", 1, true)
)
local cameraAim = assert(
    string.find(
        source,
        "alignedTarget = alignCamera(false, taskCombatActive)",
        firstObservation,
        true
    )
)
local visualRefresh = assert(
    string.find(source, "local _, refreshedVisuals = observationRuntime:update", cameraAim, true)
)
local overlayRender =
    assert(string.find(source, "context.render(visualObservations", visualRefresh, true))
assert(
    firstObservation < cameraAim and cameraAim < visualRefresh and visualRefresh < overlayRender,
    "Drawing ESP must reproject observations after Camera Aim commits the final camera frame"
)
local frameStart = assert(string.find(source, "local function frameWorkEnabled(state)", 1, true))
local frameEnd = assert(string.find(source, "local function connectFrame()", frameStart, true))
local frameBlock = string.sub(source, frameStart, frameEnd - 1)
assert(not string.find(frameBlock, "noSmoke", 1, true), "No Smoke must not own frame work")
assert(not string.find(frameBlock, "noFlash", 1, true), "No Flash must not own frame work")
print("rivals-frame-lifecycle-contracts-ok")
