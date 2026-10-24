local Clearance = {}

local MAX_SPAN = 4.5
local CENTER_DEADZONE = 0.15
local FIT_MARGIN = 0.15

function Clearance.centerOffset(leftDistance, rightDistance, bodyWidth)
    if type(leftDistance) ~= "number" or type(rightDistance) ~= "number" then
        return 0
    end
    local width = type(bodyWidth) == "number" and bodyWidth or 2
    local span = leftDistance + rightDistance
    if span < width + FIT_MARGIN or span >= MAX_SPAN then
        return 0
    end
    local center = (rightDistance - leftDistance) * 0.5
    if math.abs(center) < CENTER_DEADZONE then
        return 0
    end
    return math.clamp(center * 1.5, -0.75, 0.75)
end

function Clearance.passageFits(span, bodyWidth)
    if type(span) ~= "number" then
        return false
    end
    local width = type(bodyWidth) == "number" and bodyWidth or 2
    return span >= width + FIT_MARGIN
end

function Clearance.applyOffset(forward, side, offset)
    if typeof(forward) ~= "Vector3" or forward.Magnitude < 0.1 or type(offset) ~= "number" or math.abs(offset) < 1e-3 then
        return forward
    end
    if typeof(side) ~= "Vector3" or side.Magnitude < 0.1 then
        return forward.Unit
    end
    local direction = forward.Unit + side.Unit * offset
    if direction.Magnitude < 1e-3 then
        return forward.Unit
    end
    return direction.Unit
end

return Clearance
