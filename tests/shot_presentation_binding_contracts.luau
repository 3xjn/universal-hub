local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

Enum = roblox.Enum
CFrame = roblox.CFrame
Vector2 = roblox.Vector2

local source = fs.readFile("games/rivals/features/ShotPresentation.lua")

local function loadCopy(name)
    local chunk, compileError = loadstring(source, name)
    return assert(chunk, compileError)()
end

local bindings = {}
local RunService = {
    BindToRenderStep = function(_service, name, priority, callback)
        bindings[name] = {
            callback = callback,
            priority = priority,
        }
    end,
    UnbindFromRenderStep = function(_service, name)
        bindings[name] = nil
    end,
}

local function options()
    local controller = {
        Rotation = Vector2.zero,
        SetRotation = function(self, rotation)
            self.Rotation = rotation
        end,
    }
    return {
        cameraController = controller,
        getFighter = function()
            return nil
        end,
        hookFunction = function(target)
            return target
        end,
        restoreFunction = function() end,
        runService = RunService,
        workspace = {
            CurrentCamera = {
                CFrame = CFrame.new(10, 20, 30),
            },
        },
    },
        controller
end

local firstOptions = options()
firstOptions.isEnabled = function()
    return true
end
local first = loadCopy("ShotPresentation.copy1").new(firstOptions)
first:refreshHook()
local secondOptions, secondController = options()
secondOptions.isEnabled = function()
    return true
end
local second = loadCopy("ShotPresentation.copy2").new(secondOptions)
second:refreshHook()

assert(
    first.preBinding ~= second.preBinding and first.postBinding ~= second.postBinding,
    "separate ShotPresentation module copies must bind unique render-step names"
)
assert(bindings[first.preBinding] and bindings[first.postBinding])
assert(bindings[second.preBinding] and bindings[second.postBinding])

first:stop()
assert(
    bindings[second.preBinding] and bindings[second.postBinding],
    "stopping an older ShotPresentation must not unbind a newer instance"
)

local rotation = Vector2.new(0.2, -0.4)
local target = { Name = "second-target" }
assert(second:update(rotation, target))
local callbacks = {
    bindings[second.preBinding],
    bindings[second.postBinding],
}
table.sort(callbacks, function(left, right)
    return left.priority < right.priority
end)
for _, binding in ipairs(callbacks) do
    binding.callback()
end
assert(second:getPresentedTarget() == target)
assert(secondController.Rotation == rotation)

second:stop()
assert(not bindings[second.preBinding] and not bindings[second.postBinding])

local hookTarget = function() end
local hookEnabled = false
local hookCalls = 0
local restoreCalls = 0
local lazyOptions = options()
lazyOptions.getFighter = function()
    return { GetCameraData = hookTarget }
end
lazyOptions.isEnabled = function()
    return hookEnabled
end
lazyOptions.hookFunction = function(target)
    hookCalls += 1
    return target
end
lazyOptions.restoreFunction = function(target)
    assert(target == hookTarget)
    restoreCalls += 1
end
local lazy = loadCopy("ShotPresentation.lazy").new(lazyOptions)
lazy:refreshHook()
assert(hookCalls == 0, "disabled Shot Aim must not install a camera-data hook")
hookEnabled = true
lazy:refreshHook()
assert(hookCalls == 1, "enabling Shot Aim must install its camera-data hook")
hookEnabled = false
lazy:refreshHook()
assert(restoreCalls == 1, "disabling Shot Aim must restore its camera-data hook")
lazy:stop()

local observedCameraData = 0
local originalCameraDataCalls = 0
local observeEnabled = true
local observedHook
local observedRestoreCalls = 0
local observedFighter = {}
local observedController
local observedOptions
local originalCameraRotation
local originalCameraLook
local observedTarget = function()
    originalCameraDataCalls += 1
    originalCameraRotation = observedController.Rotation
    originalCameraLook = observedOptions.workspace.CurrentCamera.CFrame.LookVector
    return "camera-data"
end
observedFighter.GetCameraData = observedTarget
observedOptions, observedController = options()
observedOptions.getFighter = function()
    return observedFighter
end
observedOptions.isEnabled = function()
    return false
end
observedOptions.shouldObserve = function()
    return observeEnabled
end
observedOptions.onCameraData = function()
    observedCameraData += 1
end
observedOptions.hookFunction = function(target, replacement)
    assert(target == observedTarget)
    observedHook = replacement
    return target
end
observedOptions.restoreFunction = function(target)
    assert(target == observedTarget)
    observedRestoreCalls += 1
end
local observed = loadCopy("ShotPresentation.observed").new(observedOptions)
observed:refreshHook()
assert(observedHook, "Camera Aim rates must observe the native camera-data shot seam")
assert(observedHook(observedFighter) == "camera-data")
assert(
    originalCameraDataCalls == 1 and observedCameraData == 1,
    "A Camera Aim shot must advance its rate plan without masking the visible camera"
)
local flickRotation = Vector2.new(0.25, -0.5)
assert(observed:stageFlick(flickRotation))
assert(observedHook(observedFighter) == "camera-data")
local expectedFlickFrame = CFrame.new(observedOptions.workspace.CurrentCamera.CFrame.Position)
    * CFrame.Angles(0, flickRotation.Y, 0)
    * CFrame.Angles(flickRotation.X, 0, 0)
assert(
    originalCameraRotation == flickRotation
        and (originalCameraLook - expectedFlickFrame.LookVector).Magnitude < 1e-6
        and (
            observedOptions.workspace.CurrentCamera.CFrame.LookVector
            - expectedFlickFrame.LookVector
        ).Magnitude < 1e-6,
    "Flick Projectiles must commit its visible rotation before native camera data is captured"
)
observeEnabled = false
observed:refreshHook()
assert(observedRestoreCalls == 1, "disabling shot observation must restore the camera-data hook")
observed:stop()

print("shot-presentation-binding-contracts-ok")
