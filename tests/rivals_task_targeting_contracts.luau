local Targeting = require("../games/rivals/libraries/Targeting")

local visibleThreat = { visible = true, posture = "aware" }
local blockedThreat = { visible = false, posture = "aware" }
local afkFinish = { visible = true, posture = "afk", finishable = true }
local afkPressure = { visible = true, posture = "afk", finishable = false }
local blockedAfkFinish = { visible = false, posture = "afk", finishable = true }
local function classify(value)
    return value.posture == "aware", value.posture == "afk", value.finishable == true
end

assert(
    Targeting.taskPriority({ blockedThreat, visibleThreat }, classify)[1] == visibleThreat,
    "task targeting must never abandon a visible threat for a target behind a wall"
)
assert(
    Targeting.taskPriority({ visibleThreat, blockedAfkFinish }, classify)[1] == visibleThreat,
    "a finishable AFK target behind a wall must not override a visible active threat"
)
assert(
    Targeting.taskPriority({ visibleThreat, afkFinish }, classify)[1] == afkFinish,
    "task targeting must take a verified finish on an AFK target"
)
assert(
    Targeting.taskPriority({ visibleThreat, afkPressure }, classify)[1] == visibleThreat,
    "an active threat must outrank a non-finishable AFK target"
)

print("rivals-task-targeting-contracts-ok")
