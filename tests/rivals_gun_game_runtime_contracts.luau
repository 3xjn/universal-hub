local GunGameRuntime = require("../games/rivals/features/GunGameRuntime")

local function signal()
    local callbacks = {}
    local value = {}
    function value:Connect(callback)
        table.insert(callbacks, callback)
        local connection = { connected = true }
        function connection:Disconnect()
            if not self.connected then
                return
            end
            self.connected = false
            for index, registered in ipairs(callbacks) do
                if registered == callback then
                    table.remove(callbacks, index)
                    break
                end
            end
        end
        return connection
    end
    function value:Fire(child)
        local snapshot = table.clone(callbacks)
        for _, callback in ipairs(snapshot) do
            callback(child)
        end
    end
    function value:count()
        return #callbacks
    end
    return value
end

local function drop(kind)
    return {
        Name = "_drop",
        Parent = nil,
        FindFirstChild = function(_self, name)
            return name == kind and {} or nil
        end,
        IsA = function(_self, name)
            return name == "BasePart"
        end,
    }
end

local touches = {}
local now = 10
local enabled = false
local nativeGunGame = true
local healthDrop = drop("Health")
local childAdded = signal()
local childRemoved = signal()
local getChildrenCalls = 0
local workspace = {
    ChildAdded = childAdded,
    ChildRemoved = childRemoved,
    GetChildren = function()
        getChildrenCalls += 1
        return { healthDrop }
    end,
}
healthDrop.Parent = workspace
local store = {
    Get = function()
        return { settings = { autoPickup = enabled } }
    end,
}
local fighter = {
    Entity = { Humanoid = { Health = 50, MaxHealth = 100 }, RootPart = {} },
}
local runtime = GunGameRuntime.new({
    clock = function()
        return now
    end,
    fireTouchInterest = function(part, target, toggle)
        table.insert(touches, { part = part, target = target, toggle = toggle })
    end,
    getFighter = function()
        return fighter
    end,
    isActive = function()
        return true
    end,
    isGunGame = function()
        return nativeGunGame
    end,
    isInCombat = function()
        return true
    end,
    spawn = function(callback)
        callback()
    end,
    store = store,
    wait = function() end,
    workspace = workspace,
})
assert(getChildrenCalls == 1, "runtime must seed candidates exactly once")
runtime:update()
runtime:update()
assert(#touches == 0, "disabled runtime must do zero pickup work")
assert(getChildrenCalls == 1, "disabled updates must not rescan Workspace")
enabled = true
nativeGunGame = false
runtime:update()
assert(#touches == 0, "non-Gun-Game native state must do zero pickup work")
nativeGunGame = true
runtime:update()
assert(#touches == 2 and touches[1].toggle == 0 and touches[2].toggle == 1)
runtime:update()
assert(#touches == 2, "pickup attempts must be throttled")
assert(getChildrenCalls == 1, "enabled updates must use the maintained registry")

local addedDrop = drop("Health")
addedDrop.Parent = workspace
childAdded:Fire(addedDrop)
now += 1
runtime:update()
assert(#touches == 6, "ChildAdded pickups must join the registry")

local lateMarker
local lateMarkerAdded = signal()
local lateDrop = {
    Name = "_drop",
    Parent = workspace,
    ChildAdded = lateMarkerAdded,
    FindFirstChild = function(_self, name)
        return name == lateMarker and {} or nil
    end,
    IsA = function(_self, name)
        return name == "BasePart"
    end,
}
childAdded:Fire(lateDrop)
assert(lateMarkerAdded:count() == 1, "an incomplete drop must wait for its marker")
lateMarker = "Health"
lateMarkerAdded:Fire({ Name = "Health" })
assert(lateMarkerAdded:count() == 0, "classification must release the per-drop listener")
now += 0.1
runtime:update()
assert(#touches == 8, "a marker replicated after its parent must still classify the drop")

addedDrop.Parent = nil
lateDrop.Parent = nil
childRemoved:Fire(addedDrop)
childRemoved:Fire(lateDrop)
now += 1
runtime:update()
assert(#touches == 10, "ChildRemoved pickups must leave the registry")

assert(childAdded:count() == 1 and childRemoved:count() == 1)
runtime:stop()
assert(
    childAdded:count() == 0 and childRemoved:count() == 0,
    "stop must disconnect registry listeners"
)
local afterStop = drop("Health")
afterStop.Parent = workspace
childAdded:Fire(afterStop)
now += 1
runtime:update()
assert(#touches == 10, "stopped runtime must remain inert")

print("rivals-gun-game-runtime-contracts-ok")
