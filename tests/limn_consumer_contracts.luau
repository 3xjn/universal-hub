local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

Color3 = roblox.Color3
Vector2 = roblox.Vector2
Drawing = {
    Fonts = {
        Plex = 2,
    },
}

local limnRoot = assert(process.env.LIMN_ROOT, "LIMN_ROOT must point to the Limn repository")
local limnPath = limnRoot .. "/dist/Limn.lua"
local limnChunk, limnError = loadstring(fs.readFile(limnPath), limnPath)
local Limn = assert(limnChunk, limnError)()
local initSource = fs.readFile("init.lua")
assert(
    initSource:find("MapPosition", 1, true)
        and initSource:find("return position + topLeftInset", 1, true),
    "Universal Hub must add the GUI inset to executor input before Limn hit-testing"
)
local Store = require("../modules/Store")
local Overlay = require("../modules/Overlay")

local function newSignal()
    local listeners = {}
    local signal = {}
    function signal:Connect(callback)
        table.insert(listeners, callback)
        local connection = {
            Connected = true,
        }
        function connection:Disconnect()
            if not self.Connected then
                return
            end
            self.Connected = false
            local index = table.find(listeners, callback)
            if index then
                table.remove(listeners, index)
            end
        end
        return connection
    end
    function signal:Fire(...)
        for _, callback in ipairs(table.clone(listeners)) do
            callback(...)
        end
    end
    function signal:count()
        return #listeners
    end
    return signal
end

local objects = {}
local drawing = {
    new = function(kind)
        local object = {
            Kind = kind,
            Removed = false,
            TextBounds = Vector2.new(80, 14),
        }
        function object:Remove()
            self.Removed = true
        end
        table.insert(objects, object)
        return object
    end,
}
local input = {
    InputBegan = newSignal(),
    InputChanged = newSignal(),
    InputEnded = newSignal(),
}
local paintSignals = {}
local immediateDraws = {}
local drawingImmediate = {
    FilledCircle = function(position, radius)
        table.insert(immediateDraws, {
            kind = "circle",
            position = position,
            radius = radius,
        })
    end,
    FilledRectangle = function(position, size)
        table.insert(immediateDraws, {
            kind = "rectangle",
            position = position,
            size = size,
        })
    end,
    GetPaint = function(zIndex)
        paintSignals[zIndex] = paintSignals[zIndex] or newSignal()
        return paintSignals[zIndex]
    end,
}
local guiInset = Vector2.new(0, 58)
local runtime = Limn.new({
    Drawing = drawing,
    DrawingImmediate = drawingImmediate,
    Vector2 = Vector2,
    Input = {
        MapPosition = function(position)
            return position + guiInset
        end,
        Processed = "allow",
    },
})
local store = Store.new({
    activeWeapon = "Test Rifle",
    cosmeticsOpen = false,
    menuVisible = true,
    observations = {},
    settings = {
        aimSmoothness = 0,
        chams = false,
        fov = 180,
        fovCircle = true,
        fullScreenAim = false,
        headshotRate = 0,
        maximumFov = 500,
        minimumFov = 40,
        missRate = 0,
        silentAim = false,
        triggerBot = false,
    },
    status = "Ready",
    utilityObservations = {},
})
local menuChanges = {}
local captures = {}
local optionChanges = {}
local overlay = Overlay.new({
    capabilities = {
        "aimSmoothness",
        "silentAim",
        "triggerBot",
    },
    cosmetics = false,
    gameLabel = "Limn Contract",
    getCamera = function()
        return {
            ViewportSize = Vector2.new(1280, 720),
        }
    end,
    inputService = input,
    limn = runtime,
    setFov = function() end,
    setInputCaptured = function(captured)
        table.insert(captures, captured)
    end,
    setMenuVisible = function(visible)
        table.insert(menuChanges, visible)
    end,
    setOption = function(name, value)
        table.insert(optionChanges, {
            name = name,
            value = value,
        })
    end,
    setRate = function(name, value)
        store:Patch({
            settings = {
                [name] = value,
            },
        })
    end,
    store = store,
})

assert(overlay.available == true)
assert(captures[1] == true)
local triggerRow = overlay.controls.options.triggerBot.row
local triggerScreenPosition = triggerRow.Position + triggerRow.Size / 2
local triggerInputPosition = triggerScreenPosition - guiInset
local panelPosition = overlay.controls.panel.Position
local triggerMouse = {
    Position = triggerInputPosition,
    UserInputType = "MouseButton1",
}
input.InputBegan:Fire(triggerMouse, true)
input.InputChanged:Fire({
    Position = triggerInputPosition + Vector2.new(8, 0),
    UserInputType = "MouseMovement",
}, true)
input.InputEnded:Fire(triggerMouse, true)
assert(
    optionChanges[1] and optionChanges[1].name == "triggerBot",
    "Clicking the rendered Trigger Bot row must not select the control one GUI inset above it"
)
assert(
    overlay.controls.panel.Position == panelPosition,
    "Dragging a rendered option must not capture or move the full panel"
)
local smoothness = overlay.controls.rates.aimSmoothness
local smoothnessStart = smoothness.hit.Position + Vector2.new(24, smoothness.hit.Size.Y / 2)
local smoothnessEnd = smoothness.hit.Position + Vector2.new(232, smoothness.hit.Size.Y / 2)
local smoothnessMouse = {
    Position = smoothnessStart - guiInset,
    UserInputType = "MouseButton1",
}
input.InputBegan:Fire(smoothnessMouse, true)
input.InputChanged:Fire({
    Position = smoothnessEnd - guiInset,
    UserInputType = "MouseMovement",
}, true)
assert(
    smoothness.fill.Visible == false and smoothness.knob.Visible == false,
    "Captured slider must hide only its retained fill/thumb while immediate paint is active"
)
store:Patch({ status = "Live telemetry update" })
assert(
    smoothness.fill.Visible == false and smoothness.knob.Visible == false,
    "Frame-driven store patches must not reveal stale retained visuals during captured paint"
)
paintSignals[206]:Fire()
assert(
    immediateDraws[#immediateDraws - 1].kind == "rectangle"
        and immediateDraws[#immediateDraws].kind == "circle"
        and immediateDraws[#immediateDraws].position.X > smoothness.track.Position.X + 200,
    "Bundled Limn must paint the active slider from the latest mapped pointer event"
)
local activeDrawCount = #immediateDraws
input.InputEnded:Fire({
    Position = smoothnessEnd - guiInset,
    UserInputType = "MouseButton1",
}, true)
paintSignals[206]:Fire()
assert(
    #immediateDraws == activeDrawCount
        and smoothness.fill.Visible == true
        and smoothness.knob.Visible == true,
    "Slider release must stop immediate paint and restore the current retained fill/thumb"
)
local hideButton = overlay.controls.hideButton
local clickPosition = hideButton.Position + Vector2.new(4, 4) - guiInset
local mouse = {
    Position = clickPosition,
    UserInputType = "MouseButton1",
}
input.InputBegan:Fire(mouse, true)
input.InputEnded:Fire(mouse, true)
assert(menuChanges[1] == false, "Processed menu input must reach Limn after Universal Hub sinks it")
assert(
    hideButton.Position.X > 1000,
    "Universal Hub must retain physical-screen Drawing coordinates while mapping input"
)

overlay:destroy()
assert(captures[#captures] == false)
assert(input.InputBegan:count() == 0 and input.InputChanged:count() == 0 and input.InputEnded:count() == 0)
for _, object in ipairs(objects) do
    assert(object.Removed == true, "Destroying the overlay must remove every Limn-owned drawing")
end

local unavailableRuntime = Limn.new({
    Drawing = {
        new = function(kind)
            if kind == "Circle" then
                error("unsupported Circle")
            end
            local object = {}
            function object:Remove() end
            return object
        end,
    },
    Vector2 = Vector2,
})
local unavailableOverlay = Overlay.new({
    capabilities = {},
    cosmetics = false,
    gameLabel = "Unavailable",
    getCamera = function()
        return {
            ViewportSize = Vector2.new(1280, 720),
        }
    end,
    limn = unavailableRuntime,
    store = store,
})
assert(unavailableOverlay.available == false)
assert(table.find(unavailableOverlay.missingPrimitives, "Circle") ~= nil)
unavailableOverlay:render({}, Vector2.new(0, 0), {})
unavailableOverlay:destroy()

store:Destroy()
print("limn-consumer-contracts-ok")
