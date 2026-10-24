local Slopes = {}

local FLAT_NORMAL = 0.92
local STEP_RISE = 1.15
local MIN_CHANGE = 0.08

function Slopes.minNormalY(maxSlopeAngle)
    local angle = math.clamp(type(maxSlopeAngle) == "number" and maxSlopeAngle or 89, 0, 89)
    return math.cos(math.rad(angle))
end

function Slopes.walkable(normalY, maxSlopeAngle)
    return type(normalY) == "number" and normalY >= Slopes.minNormalY(maxSlopeAngle)
end

-- A forward probe that hits the ramp itself is not a wall.
function Slopes.blocksProbe(normalY, maxSlopeAngle)
    return not Slopes.walkable(normalY, maxSlopeAngle)
end

-- samples are ground hits along the move: { normalY, y } at `spacing` studs.
-- A continuous incline the humanoid can walk is a ramp, including slopes
-- steeper than the old fixed 53-degree cutoff. A flat lip with a sudden
-- rise is a box, not a ramp, so the jump step can take it.
function Slopes.classify(samples, maxSlopeAngle, spacing)
    spacing = type(spacing) == "number" and spacing > 0 and spacing or 0.6
    if type(samples) ~= "table" or #samples == 0 then
        return "blocked"
    end
    local minNormal = Slopes.minNormalY(maxSlopeAngle)
    local maxAngle = math.clamp(type(maxSlopeAngle) == "number" and maxSlopeAngle or 89, 0, 89)
    local changed = false
    local ramp = false
    local previousY = nil
    for _, sample in ipairs(samples) do
        if type(sample) ~= "table"
            or type(sample.normalY) ~= "number"
            or type(sample.y) ~= "number"
            or sample.normalY < minNormal
        then
            return "blocked"
        end
        if previousY ~= nil then
            local rise = sample.y - previousY
            if math.abs(rise) > MIN_CHANGE then
                changed = true
            end
            if math.abs(rise) > STEP_RISE then
                local implied = math.deg(math.atan(math.abs(rise) / spacing))
                local slanted = sample.normalY <= FLAT_NORMAL
                if slanted and implied <= maxAngle + 0.01 then
                    ramp = true
                else
                    return "blocked"
                end
            elseif sample.normalY <= FLAT_NORMAL and math.abs(rise) > MIN_CHANGE then
                ramp = true
            end
        end
        previousY = sample.y
    end
    if ramp then
        return "ramp"
    end
    if changed then
        return "stairs"
    end
    return "flat"
end

return Slopes
