local InputCapture = require("../modules/InputCapture")

Enum = {
    ContextActionPriority = {
        High = { Value = 2000 },
    },
    ContextActionResult = {
        Sink = "Sink",
    },
    MouseBehavior = {
        Default = "Default",
        LockCenter = "LockCenter",
    },
    CameraMode = {
        Classic = "Classic",
        LockFirstPerson = "LockFirstPerson",
    },
    OverrideMouseIconBehavior = {
        ForceShow = "ForceShow",
        None = "None",
    },
    RenderPriority = {
        Last = { Value = 2000 },
    },
    UserInputType = {
        MouseButton1 = "MouseButton1",
        MouseButton2 = "MouseButton2",
        MouseMovement = "MouseMovement",
        MouseWheel = "MouseWheel",
        Touch = "Touch",
    },
}

local action
local actionInputs
local actionPriority
local heartbeatCallback
local contextActionService = {}
function contextActionService:BindActionAtPriority(name, callback, _touchButton, priority, ...)
    action = {
        callback = callback,
        name = name,
    }
    actionInputs = { ... }
    actionPriority = priority
end
function contextActionService:UnbindAction(name)
    assert(action and action.name == name)
    action = nil
end

local runService = {}
runService.Heartbeat = {
    Connect = function(_, callback)
        heartbeatCallback = callback
        return {
            Disconnect = function()
                heartbeatCallback = nil
            end,
        }
    end,
}

local userInputService = {
    MouseBehavior = Enum.MouseBehavior.LockCenter,
    MouseIconEnabled = false,
    OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.None,
}
local inputPropertyCallbacks = {}
function userInputService:GetPropertyChangedSignal(propertyName)
    return {
        Connect = function(_, callback)
            inputPropertyCallbacks[propertyName] = callback
            return {
                Disconnect = function()
                    inputPropertyCallbacks[propertyName] = nil
                end,
            }
        end,
    }
end
local menuClosedCallback
local guiService = {
    MenuClosed = {
        Connect = function(_, callback)
            menuClosedCallback = callback
            return {
                Disconnect = function()
                    menuClosedCallback = nil
                end,
            }
        end,
    },
}
local localPlayer = {
    CameraMode = Enum.CameraMode.LockFirstPerson,
}
local playerPropertyCallbacks = {}
function localPlayer:GetPropertyChangedSignal(propertyName)
    return {
        Connect = function(_, callback)
            playerPropertyCallbacks[propertyName] = callback
            return {
                Disconnect = function()
                    playerPropertyCallbacks[propertyName] = nil
                end,
            }
        end,
    }
end
local capture = InputCapture.new({
    contextActionService = contextActionService,
    guiService = guiService,
    localPlayer = localPlayer,
    runService = runService,
    userInputService = userInputService,
})

capture:SetEnabled(true)
assert(capture:IsEnabled() == true)
assert(action and action.callback() == Enum.ContextActionResult.Sink)
assert(actionPriority > Enum.ContextActionPriority.High.Value)
assert(#actionInputs == 5, "Menu capture must sink mouse buttons, movement, wheel, and touch")
assert(heartbeatCallback, "Cursor release must run after the game's render-phase camera lock")
assert(userInputService.MouseBehavior == Enum.MouseBehavior.Default)
assert(userInputService.MouseIconEnabled == true)
assert(userInputService.OverrideMouseIconBehavior == Enum.OverrideMouseIconBehavior.ForceShow)
assert(localPlayer.CameraMode == Enum.CameraMode.Classic)
assert(menuClosedCallback ~= nil)

userInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
userInputService.MouseIconEnabled = false
userInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.None
localPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
inputPropertyCallbacks.MouseBehavior()
assert(
    userInputService.MouseBehavior == Enum.MouseBehavior.Default and userInputService.MouseIconEnabled == true,
    "Visible menu must win against games that relock the cursor every frame"
)
assert(userInputService.OverrideMouseIconBehavior == Enum.OverrideMouseIconBehavior.ForceShow)
assert(localPlayer.CameraMode == Enum.CameraMode.Classic)
assert(playerPropertyCallbacks.CameraMode ~= nil)

userInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
menuClosedCallback()
assert(userInputService.MouseBehavior == Enum.MouseBehavior.Default)

capture:SetEnabled(true)
capture:SetEnabled(false)
assert(capture:IsEnabled() == false)
assert(action == nil and heartbeatCallback == nil)
assert(userInputService.MouseBehavior == Enum.MouseBehavior.LockCenter)
assert(userInputService.MouseIconEnabled == false)
assert(userInputService.OverrideMouseIconBehavior == Enum.OverrideMouseIconBehavior.None)
assert(localPlayer.CameraMode == Enum.CameraMode.LockFirstPerson)

capture:Destroy()
capture:Destroy()
print("input-capture-contracts-ok")
